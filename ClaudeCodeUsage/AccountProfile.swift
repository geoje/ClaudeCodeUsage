import Foundation

enum AccountProfile: CaseIterable {
    case home, work

    var title: String {
        switch self {
        case .home: return "Home"
        case .work: return "Work"
        }
    }

    var argument: String {
        switch self {
        case .home: return "1"
        case .work: return "2"
        }
    }

    static func detectActive() -> AccountProfile? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: "\(home)/.claude") else {
            return nil
        }

        switch (target as NSString).lastPathComponent {
        case ".claude-home":
            return .home
        case ".claude-work":
            return .work
        default:
            return nil
        }
    }

    func run() async -> Result<Void, ScriptRunError> {
        guard let url = Bundle.main.url(forResource: "cc", withExtension: "sh") else {
            return .failure(ScriptRunError(message: "cc.sh not found in app bundle"))
        }

        return await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/bash")
            process.arguments = [url.path, argument]

            let stderr = Pipe()
            process.standardOutput = Pipe()
            process.standardError = stderr

            process.terminationHandler = { process in
                if process.terminationStatus == 0 {
                    continuation.resume(returning: .success(()))
                } else {
                    let data = stderr.fileHandleForReading.readDataToEndOfFile()
                    let message = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: .failure(ScriptRunError(message: message?.isEmpty == false ? message! : "cc.sh exited with status \(process.terminationStatus)")))
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(returning: .failure(ScriptRunError(message: error.localizedDescription)))
            }
        }
    }
}

struct ScriptRunError: Error {
    let message: String
}
