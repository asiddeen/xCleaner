import Foundation

public enum SafeToolPrunerError: LocalizedError, Sendable {
    case toolNotAvailable(String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .toolNotAvailable(let msg): return msg
        case .executionFailed(let msg): return msg
        }
    }
}

public struct SafeToolPruner: Sendable {
    public init() {}

    public static func locateHomebrew() -> String? {
        for candidate in ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    public static func isSimctlAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: "/usr/bin/xcrun")
    }

    public func runHomebrewCleanup(historyStore: CleanupHistoryStore? = nil) async throws -> String {
        guard let brewPath = Self.locateHomebrew() else {
            throw SafeToolPrunerError.toolNotAvailable("Homebrew is not installed on this Mac.")
        }
        let output = try Self.runProcess(executable: brewPath, arguments: ["cleanup", "--prune=all"])
        historyStore?.append(
            CleanupRecord(
                actionKind: "Homebrew Cache Prune (brew cleanup --prune=all)",
                itemsCleanedCount: 1,
                freedBytes: 0,
                cleanedPaths: ["~/Library/Caches/Homebrew"],
                notes: output.isEmpty ? "Homebrew cache is already clean." : String(output.prefix(500))
            )
        )
        return output.isEmpty ? "Homebrew download cache is already clean." : output
    }

    public func deleteUnavailableSimulators(historyStore: CleanupHistoryStore? = nil) async throws -> String {
        guard Self.isSimctlAvailable() else {
            throw SafeToolPrunerError.toolNotAvailable("xcrun is not available on this Mac.")
        }
        let output = try Self.runProcess(
            executable: "/usr/bin/xcrun",
            arguments: ["simctl", "delete", "unavailable"]
        )
        historyStore?.append(
            CleanupRecord(
                actionKind: "Xcode Unavailable Simulators Prune",
                itemsCleanedCount: 1,
                freedBytes: 0,
                cleanedPaths: ["~/Library/Developer/CoreSimulator/Devices (unavailable)"],
                notes: output.isEmpty ? "Removed unavailable simulator runtimes." : String(output.prefix(500))
            )
        )
        return output.isEmpty ? "Unavailable simulator devices cleaned." : output
    }

    /// Invokes Apple's official `/usr/bin/tmutil thinlocalsnapshots / <bytes> 4` via standard macOS admin prompt.
    public func thinLocalTimeMachineSnapshots(
        targetBytes: Int64 = 10_000_000_000,
        historyStore: CleanupHistoryStore? = nil
    ) async throws -> String {
        let clampedBytes = min(max(targetBytes, 1_000_000_000), 100_000_000_000)
        let tmutilCmd = "/usr/bin/tmutil thinlocalsnapshots / \(clampedBytes) 4"
        let appleScript = "do shell script \"\(tmutilCmd)\" with administrator privileges"

        let output = try Self.runProcess(
            executable: "/usr/bin/osascript",
            arguments: ["-e", appleScript]
        )
        historyStore?.append(
            CleanupRecord(
                actionKind: "Time Machine Local Snapshot Thinning (tmutil)",
                itemsCleanedCount: 1,
                freedBytes: 0,
                cleanedPaths: ["APFS Local Snapshots (/)"],
                notes: output.isEmpty ? "Completed tmutil thinlocalsnapshots." : String(output.prefix(500))
            )
        )
        return output.isEmpty ? "APFS local snapshot thinning completed." : output
    }

    private static func runProcess(executable: String, arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        try process.run()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let stdout = (String(data: outData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = (String(data: errData, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else {
            throw SafeToolPrunerError.executionFailed(stderr.isEmpty ? stdout : stderr)
        }
        return stdout.isEmpty ? stderr : stdout
    }
}
