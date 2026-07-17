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
    @Published var workPercent: String = "--"
    @Published var workReset: String = "--"
    @Published var activeProfile: AccountProfile?

    var onChange: (() -> Void)?

    private var timer: Timer?
    private var fileWatcher: DispatchSourceFileSystemObject?
    private var lastProfileCheck: AccountProfile?

    private var sessionResetDeadline: TimeInterval?
    private var weeklyResetDeadline: TimeInterval?
    private var workResetDeadline: TimeInterval?

    init() {
    }

    private static let workExpiry: Date = {
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

            let isHomeActive = activeProfile == .home
            let isWorkActive = activeProfile == .work

            async let homeOutput = isHomeActive ? self.runScript(named: "usage-home") : .init(stdout: nil, stderr: nil, exitCode: 0)
            async let workOutput = isWorkActive ? self.runScript(named: "usage-work") : .init(stdout: nil, stderr: nil, exitCode: 0)

            if let output = await homeOutput.stdout { self.applyHome(output) }
            if let output = await workOutput.stdout { self.applyWork(output) }

            self.onChange?()
        }
    }

    private func updateAllResetTimes(now: TimeInterval) {
        if let deadline = sessionResetDeadline {
            let hours = max(0, Int(((deadline - now) / 3600).rounded(.up)))
            sessionReset = "\(min(hours, 5))h"
        }
        if let deadline = weeklyResetDeadline {
            weeklyReset = "\(max(0, Int(((deadline - now) / 86400).rounded(.up))))d"
        }

        let workDaysUntil = Self.daysUntil(Self.workExpiry)
        workResetDeadline = Date().addingTimeInterval(TimeInterval(workDaysUntil * 86400)).timeIntervalSince1970
        workReset = "\(workDaysUntil)d"
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

    private func applyHome(_ output: String) {
        var fields: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            guard let equalsIndex = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<equalsIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = line[line.index(after: equalsIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            fields[key] = value
        }

        let now = Date().timeIntervalSince1970

        if let percent = fields["SESSION_PERCENT"], let reset = fields["SESSION_RESET_EPOCH"].flatMap(Double.init) {
            sessionPercent = "\(percent)%"
            sessionResetDeadline = reset
            let hours = max(0, Int(((reset - now) / 3600).rounded(.up)))
            sessionReset = "\(min(hours, 5))h"
        }

        if let percent = fields["WEEKLY_PERCENT"], let reset = fields["WEEKLY_RESET_EPOCH"].flatMap(Double.init) {
            weeklyPercent = "\(percent)%"
            weeklyResetDeadline = reset
            weeklyReset = "\(max(0, Int(((reset - now) / 86400).rounded(.up))))d"
        }
    }

    private func applyWork(_ output: String) {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: "^\\d+%$", options: .regularExpression) != nil else { return }
        workPercent = trimmed
    }

    // MARK: - Date helpers

    private static func daysUntil(_ date: Date) -> Int {
        let start = Calendar.current.startOfDay(for: Date())
        let target = Calendar.current.startOfDay(for: date)
        let days = Calendar.current.dateComponents([.day], from: start, to: target).day ?? 0
        return max(0, days)
    }
}
