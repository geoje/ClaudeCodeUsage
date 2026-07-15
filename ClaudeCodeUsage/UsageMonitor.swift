import Combine
import Darwin
import Foundation
import SwiftUI

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
    @Published var activeProfile: AccountProfile?

    var onChange: (() -> Void)?

    private var timer: Timer?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var lastProfileCheck: AccountProfile?

    private var sessionResetDeadline: TimeInterval?
    private var weeklyResetDeadline: TimeInterval?
    private var enterpriseResetDeadline: TimeInterval?
    private var litellmResetDeadline: TimeInterval?

    init() {
    }

    private static let enterpriseExpiry: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 27
        return Calendar.current.date(from: components) ?? Date()
    }()

    func start() {
        refresh()
        startFileWatcher()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.refresh() }
        }
    }

    private func startFileWatcher() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fd = open(home, O_EVTONLY)
        guard fd >= 0 else { return }

        fileWatcher = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .all, queue: .main)
        fileWatcher?.setEventHandler { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                let currentProfile = AccountProfile.detectActive()
                if currentProfile != self.lastProfileCheck {
                    self.lastProfileCheck = currentProfile
                    self.refresh()
                    self.onChange?()
                }
            }
        }
        fileWatcher?.setCancelHandler {
            close(fd)
        }
        fileWatcher?.resume()
    }

    func refresh() {
        let newProfile = AccountProfile.detectActive()
        activeProfile = newProfile

        let now = Date().timeIntervalSince1970

        updateAllResetTimes(now: now)

        Task { [weak self] in
            guard let self else { return }

            let isPersonalActive = activeProfile == .personal
            let isEnterpriseActive = activeProfile == .enterprise
            let isLitellmActive = activeProfile == .litellm

            async let personalOutput = isPersonalActive ? self.runScript(named: "usage-personal") : .init(stdout: nil, stderr: nil, exitCode: 0)
            async let enterpriseOutput = isEnterpriseActive ? self.runScript(named: "usage-enterprise") : .init(stdout: nil, stderr: nil, exitCode: 0)
            async let litellmOutput = isLitellmActive ? self.runScript(named: "usage-litellm") : .init(stdout: nil, stderr: nil, exitCode: 0)

            if let output = await personalOutput.stdout { self.applyPersonal(output) }
            if let output = await enterpriseOutput.stdout { self.applyEnterprise(output) }
            if let output = await litellmOutput.stdout { self.applyLitellm(output) }

            self.onChange?()
        }
    }

    private func updateAllResetTimes(now: TimeInterval) {
        if let deadline = sessionResetDeadline {
            sessionReset = "\(max(0, Int(((deadline - now) / 3600).rounded(.up))))h"
        }
        if let deadline = weeklyResetDeadline {
            weeklyReset = "\(max(0, Int(((deadline - now) / 86400).rounded(.up))))d"
        }

        let enterpriseDaysUntil = Self.daysUntil(Self.enterpriseExpiry)
        enterpriseResetDeadline = Date().addingTimeInterval(TimeInterval(enterpriseDaysUntil * 86400)).timeIntervalSince1970
        enterpriseReset = "\(enterpriseDaysUntil)d"

        let litellmDaysUntil = Self.daysUntil(Self.startOfNextMonth())
        litellmResetDeadline = Date().addingTimeInterval(TimeInterval(litellmDaysUntil * 86400)).timeIntervalSince1970
        litellmReset = "\(litellmDaysUntil)d"
    }

    // MARK: - Script execution

    private struct ScriptResult {
        let stdout: String?
        let stderr: String?
        let exitCode: Int32
    }

    private func runScript(named name: String) async -> ScriptResult {
        guard let url = Bundle.main.url(forResource: name, withExtension: "sh") else {
            return ScriptResult(stdout: nil, stderr: "bundle resource \(name).sh not found", exitCode: -1)
        }

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [url.path]

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            process.terminationHandler = { process in
                let outData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errData = stderr.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: ScriptResult(
                    stdout: String(data: outData, encoding: .utf8),
                    stderr: String(data: errData, encoding: .utf8),
                    exitCode: process.terminationStatus
                ))
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: ScriptResult(stdout: nil, stderr: error.localizedDescription, exitCode: -1))
            }
        }
    }

    // MARK: - Parsing

    private func applyPersonal(_ output: String) {
        var headers: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }

        let now = Date().timeIntervalSince1970

        if let utilization = headers["anthropic-ratelimit-unified-5h-utilization"].flatMap(Double.init),
           let reset = headers["anthropic-ratelimit-unified-5h-reset"].flatMap(Double.init) {
            sessionPercent = "\(Int((utilization * 100).rounded()))%"
            sessionResetDeadline = reset
            sessionReset = "\(max(0, Int(((reset - now) / 3600).rounded(.up))))h"
        }

        if let utilization = headers["anthropic-ratelimit-unified-7d-utilization"].flatMap(Double.init),
           let reset = headers["anthropic-ratelimit-unified-7d-reset"].flatMap(Double.init) {
            weeklyPercent = "\(Int((utilization * 100).rounded()))%"
            weeklyResetDeadline = reset
            weeklyReset = "\(max(0, Int(((reset - now) / 86400).rounded(.up))))d"
        }
    }

    private func applyEnterprise(_ output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "^\\d+%$", options: .regularExpression) != nil else { return }
        enterprisePercent = trimmed
    }

    private func applyLitellm(_ output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")
        guard let value = Double(trimmed) else { return }
        litellmPercent = "\(Int(value))%"
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
