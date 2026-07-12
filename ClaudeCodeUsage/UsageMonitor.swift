import Combine
import Foundation

@MainActor
final class UsageMonitor: ObservableObject {
    @Published var sessionPercent: String = "--"
    @Published var sessionReset: String = "--"
    @Published var weeklyPercent: String = "--"
    @Published var weeklyReset: String = "--"
    @Published var enterprisePercent: String = "--"
    @Published var enterpriseReset: String = "--"
    @Published var litellmPercent: String = "--"
    @Published var litellmReset: String = "--"

    var onChange: (() -> Void)?

    private let refreshInterval: TimeInterval = 300
    private var timer: Timer?

    private static let enterpriseExpiry: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 27
        return Calendar.current.date(from: components) ?? Date()
    }()

    func start() {
        refresh()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        enterpriseReset = "\(Self.daysUntil(Self.enterpriseExpiry))d"
        litellmReset = "\(Self.daysUntil(Self.startOfNextMonth()))d"

        Task { [weak self] in
            guard let self else { return }
            async let personalOutput = self.runScript(named: "usage-personal")
            async let enterpriseOutput = self.runScript(named: "usage-enterprise")
            async let litellmOutput = self.runScript(named: "usage-litellm")

            if let output = await personalOutput { self.applyPersonal(output) }
            if let output = await enterpriseOutput { self.applyEnterprise(output) }
            if let output = await litellmOutput { self.applyLitellm(output) }

            self.onChange?()
        }
    }

    // MARK: - Script execution

    private func runScript(named name: String) async -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "sh") else { return nil }

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [url.path]

            let stdout = Pipe()
            process.standardOutput = stdout
            process.standardError = Pipe()

            process.terminationHandler = { _ in
                let data = stdout.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: String(data: data, encoding: .utf8))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Parsing

    private func applyPersonal(_ output: String) {
        var headers: [String: String] = [:]
        for line in output.split(separator: "\n") {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }

        let now = Date().timeIntervalSince1970

        if let utilization = headers["anthropic-ratelimit-unified-5h-utilization"].flatMap(Double.init),
           let reset = headers["anthropic-ratelimit-unified-5h-reset"].flatMap(Double.init) {
            sessionPercent = "\(Int((utilization * 100).rounded()))%"
            sessionReset = "\(max(0, Int(((reset - now) / 3600).rounded(.up))))h"
        }

        if let utilization = headers["anthropic-ratelimit-unified-7d-utilization"].flatMap(Double.init),
           let reset = headers["anthropic-ratelimit-unified-7d-reset"].flatMap(Double.init) {
            weeklyPercent = "\(Int((utilization * 100).rounded()))%"
            weeklyReset = "\(max(0, Int(((reset - now) / 86400).rounded(.up))))d"
        }
    }

    private func applyEnterprise(_ output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "^\\d+%$", options: .regularExpression) != nil else { return }
        enterprisePercent = trimmed
    }

    private func applyLitellm(_ output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Int(trimmed) != nil else { return }
        litellmPercent = "\(trimmed)%"
    }

    // MARK: - Date helpers

    private static func daysUntil(_ date: Date) -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: date)
        let days = Calendar.current.dateComponents([.day], from: start, to: target).day ?? 0
        return max(0, days)
    }

    private static func startOfNextMonth() -> Date {
        let now = Date()
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month], from: now)
        let startOfMonth = calendar.date(from: components) ?? now
        return calendar.date(byAdding: .month, value: 1, to: startOfMonth) ?? now
    }
}
