import Foundation

public enum DockerPruneError: LocalizedError, Sendable {
    case cliNotFound
    case daemonNotRunning
    case nothingSelected
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "Docker CLI was not found on this Mac."
        case .daemonNotRunning:
            return "Local Docker daemon is not running. Start Docker Desktop first to run safe CLI pruning."
        case .nothingSelected:
            return "Select at least one Docker target (Build Cache or Dangling Images) to prune."
        case .commandFailed(let message):
            return message
        }
    }
}

public struct DockerAndSSHService: Sendable {
    public let homeDirectory: URL

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    // MARK: - Local Docker Discovery & Safe Prune

    public static func locateDockerCLI(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> String? {
        let candidates = [
            "/opt/homebrew/bin/docker",
            "/usr/local/bin/docker",
            homeDirectory.appendingPathComponent(".docker/bin/docker").path,
            homeDirectory.appendingPathComponent(".orbstack/bin/docker").path
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return path
        }
        return nil
    }

    public func inspectLocalDocker() async -> LocalDockerStatus {
        let cliPath = Self.locateDockerCLI(homeDirectory: homeDirectory)
        let vmsDir = homeDirectory.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms").standardizedFileURL
        let rawFile = vmsDir.appendingPathComponent("0/data/Docker.raw").standardizedFileURL

        let fm = FileManager.default
        let diskURL: URL?
        let vmBytes: Int64
        if fm.fileExists(atPath: rawFile.path) {
            diskURL = rawFile
            vmBytes = ConcurrentDiskScanner.measureFootprint(at: rawFile).allocatedBytes
        } else if fm.fileExists(atPath: vmsDir.path) {
            diskURL = vmsDir
            vmBytes = ConcurrentDiskScanner.measureFootprint(at: vmsDir).allocatedBytes
        } else {
            diskURL = nil
            vmBytes = 0
        }

        guard let cliPath else {
            let msg = vmBytes > 0
                ? "Docker CLI not found, though Docker VM disk occupies \(ByteFormatting.string(from: vmBytes))."
                : "Docker is not installed on this Mac."
            return LocalDockerStatus(
                isCLIAvailable: false,
                cliPath: nil,
                isDaemonRunning: false,
                vmDiskURL: diskURL,
                vmDiskAllocatedBytes: vmBytes,
                rows: [],
                statusMessage: msg
            )
        }

        let res = Self.runCommandWithTimeout(
            executable: cliPath,
            arguments: ["system", "df", "--format", "{{json .}}"],
            timeoutSeconds: 6.0
        )

        if res.exitCode == 0 {
            let rows = Self.parseDockerSystemDFJSONLines(res.stdout)
            return LocalDockerStatus(
                isCLIAvailable: true,
                cliPath: cliPath,
                isDaemonRunning: true,
                vmDiskURL: diskURL,
                vmDiskAllocatedBytes: vmBytes,
                rows: rows,
                statusMessage: "Local Docker daemon is active."
            )
        } else {
            let offlineNote = vmBytes > 0
                ? "Docker Desktop daemon is offline.Docker.raw occupies \(ByteFormatting.string(from: vmBytes)) on disk (protected against raw file deletion — start Docker Desktop if you wish to prune internal images/build cache)."
                : "Local Docker daemon is currently stopped."
            return LocalDockerStatus(
                isCLIAvailable: true,
                cliPath: cliPath,
                isDaemonRunning: false,
                vmDiskURL: diskURL,
                vmDiskAllocatedBytes: vmBytes,
                rows: [],
                statusMessage: offlineNote.replacingOccurrences(of: "offline.Docker", with: "offline. Docker")
            )
        }
    }

    public func pruneLocalDocker(
        pruneBuilderCache: Bool,
        pruneDanglingImages: Bool
    ) async throws -> String {
        guard pruneBuilderCache || pruneDanglingImages else {
            throw DockerPruneError.nothingSelected
        }
        guard let cliPath = Self.locateDockerCLI(homeDirectory: homeDirectory) else {
            throw DockerPruneError.cliNotFound
        }

        var outputs: [String] = []
        if pruneBuilderCache {
            let res = Self.runCommandWithTimeout(
                executable: cliPath,
                arguments: ["builder", "prune", "-f"],
                timeoutSeconds: 120.0
            )
            if res.exitCode != 0 {
                throw DockerPruneError.commandFailed(res.stderr.isEmpty ? "docker builder prune failed." : res.stderr)
            }
            outputs.append("[Build Cache]\n\(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        if pruneDanglingImages {
            let res = Self.runCommandWithTimeout(
                executable: cliPath,
                arguments: ["image", "prune", "-f"],
                timeoutSeconds: 120.0
            )
            if res.exitCode != 0 {
                throw DockerPruneError.commandFailed(res.stderr.isEmpty ? "docker image prune failed." : res.stderr)
            }
            outputs.append("[Dangling Images]\n\(res.stdout.trimmingCharacters(in: .whitespacesAndNewlines))")
        }

        return outputs.joined(separator: "\n\n")
    }

    // MARK: - Remote SSH Server Discovery, Probe & Safe Docker Prune

    public func discoverSSHServers(customTargets: [SSHServerTarget] = []) -> [SSHServerTarget] {
        let sshConfigURL = homeDirectory.appendingPathComponent(".ssh/config")
        var discovered: [SSHServerTarget] = []
        if let content = try? String(contentsOf: sshConfigURL, encoding: .utf8) {
            discovered.append(contentsOf: Self.parseSSHConfig(content))
        }

        var seen = Set(discovered.map(\.id))
        for custom in customTargets {
            if seen.insert(custom.id).inserted {
                discovered.append(custom)
            }
        }
        return discovered
    }

    public func probeRemoteServer(_ target: SSHServerTarget) async -> RemoteServerStatus {
        let sshBinary = "/usr/bin/ssh"
        guard FileManager.default.isExecutableFile(atPath: sshBinary) else {
            return RemoteServerStatus(
                target: target,
                isReachable: false,
                statusMessage: "/usr/bin/ssh is unavailable."
            )
        }

        var args = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=6"
        ]
        if target.source != "~/.ssh/config", let port = target.port {
            args.append(contentsOf: ["-p", "\(port)"])
        }
        let remoteScript = "df -Pk / 2>/dev/null; echo '---XCLEANER_DOCKER---'; (docker system df --format '{{json .}}' 2>/dev/null || sudo -n docker system df --format '{{json .}}' 2>/dev/null || true)"
        args.append(target.sshDestination)
        args.append(remoteScript)

        let res = Self.runCommandWithTimeout(
            executable: sshBinary,
            arguments: args,
            timeoutSeconds: 10.0
        )

        guard res.exitCode == 0 else {
            let errText = res.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let friendly = errText.isEmpty
                ? "Host unreachable or requires interactive SSH key unlock."
                : "SSH unreachable: \(errText.split(whereSeparator: \.isNewline).first.map(String.init) ?? errText)"
            return RemoteServerStatus(
                target: target,
                isReachable: false,
                statusMessage: friendly
            )
        }

        let parts = res.stdout.components(separatedBy: "---XCLEANER_DOCKER---")
        let dfPart = parts.first ?? ""
        let dockerPart = parts.count > 1 ? parts[1] : ""

        let rootMetrics = Self.parsePOSIXDFRootLine(dfPart)
        let dockerRows = Self.parseDockerSystemDFJSONLines(dockerPart)

        let message: String
        if !dockerRows.isEmpty {
            message = "Connected via SSH • Docker daemon inspected."
        } else {
            message = "Connected via SSH • No accessible Docker daemon output."
        }

        return RemoteServerStatus(
            target: target,
            isReachable: true,
            rootTotalBytes: rootMetrics?.totalBytes,
            rootUsedBytes: rootMetrics?.usedBytes,
            rootAvailBytes: rootMetrics?.availBytes,
            dockerRows: dockerRows,
            statusMessage: message
        )
    }

    public func pruneRemoteDocker(
        target: SSHServerTarget,
        pruneBuilderCache: Bool,
        pruneDanglingImages: Bool
    ) async throws -> String {
        guard pruneBuilderCache || pruneDanglingImages else {
            throw DockerPruneError.nothingSelected
        }
        let sshBinary = "/usr/bin/ssh"
        var commands: [String] = []
        if pruneBuilderCache {
            commands.append("(docker builder prune -f 2>&1 || sudo -n docker builder prune -f 2>&1)")
        }
        if pruneDanglingImages {
            commands.append("(docker image prune -f 2>&1 || sudo -n docker image prune -f 2>&1)")
        }

        var args = [
            "-o", "BatchMode=yes",
            "-o", "ConnectTimeout=8"
        ]
        if target.source != "~/.ssh/config", let port = target.port {
            args.append(contentsOf: ["-p", "\(port)"])
        }
        args.append(target.sshDestination)
        args.append(commands.joined(separator: " && "))

        let res = Self.runCommandWithTimeout(
            executable: sshBinary,
            arguments: args,
            timeoutSeconds: 180.0
        )
        if res.exitCode != 0 {
            let msg = res.stderr.isEmpty ? res.stdout : res.stderr
            throw DockerPruneError.commandFailed(
                msg.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "Remote Docker prune failed on \(target.displayLabel)."
                    : msg.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return res.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Pure Parsers (Unit-Testable)

    public static func parseSSHConfig(_ content: String) -> [SSHServerTarget] {
        struct PendingHost {
            var aliases: [String]
            var hostName: String?
            var user: String?
            var port: Int?
        }

        var results: [SSHServerTarget] = []
        var current: PendingHost?

        func flushCurrent() {
            guard let block = current else { return }
            let ConcreteAliases = block.aliases.filter { alias in
                !alias.isEmpty && !alias.contains("*") && !alias.contains("?") && !alias.hasPrefix("!")
            }
            for alias in ConcreteAliases {
                // Skip git forges that aren't SSH Docker servers
                let resolvedHost = block.hostName ?? alias
                let lowerHost = resolvedHost.lowercased()
                if lowerHost == "github.com" || lowerHost == "gitlab.com" || lowerHost == "bitbucket.org" || lowerHost == "ssh.github.com" {
                    continue
                }
                results.append(
                    SSHServerTarget(
                        alias: alias,
                        host: resolvedHost,
                        user: block.user,
                        port: block.port,
                        source: "~/.ssh/config"
                    )
                )
            }
        }

        for rawLine in content.split(whereSeparator: \.isNewline) {
            let strippedComment = rawLine.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
            let trimmed = strippedComment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            // Split key and value by whitespace or "="
            let key: String
            let value: String
            if let eqIdx = trimmed.firstIndex(of: "="),
               let wsIdx = trimmed.firstIndex(where: \.isWhitespace) {
                let splitIdx = min(eqIdx, wsIdx)
                key = String(trimmed[..<splitIdx]).trimmingCharacters(in: .whitespaces)
                value = String(trimmed[trimmed.index(after: splitIdx)...])
                    .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "=\"")))
            } else if let eqIdx = trimmed.firstIndex(of: "=") {
                key = String(trimmed[..<eqIdx]).trimmingCharacters(in: .whitespaces)
                value = String(trimmed[trimmed.index(after: eqIdx)...])
                    .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
            } else if let wsIdx = trimmed.firstIndex(where: \.isWhitespace) {
                key = String(trimmed[..<wsIdx])
                value = String(trimmed[wsIdx...]).trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
            } else {
                continue
            }

            switch key.lowercased() {
            case "host":
                flushCurrent()
                let aliases = value.split(whereSeparator: \.isWhitespace).map(String.init)
                current = PendingHost(aliases: aliases)
            case "hostname":
                current?.hostName = value
            case "user":
                current?.user = value
            case "port":
                current?.port = Int(value)
            default:
                break
            }
        }
        flushCurrent()

        return results
    }

    public static func parseDockerSystemDFJSONLines(_ output: String) -> [DockerSpaceRow] {
        var rows: [DockerSpaceRow] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}"),
                  let data = trimmed.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            guard let type = obj["Type"] as? String else { continue }
            let total = "\(obj["TotalCount"] ?? "0")"
            let active = "\(obj["Active"] ?? "0")"
            let size = "\(obj["Size"] ?? "0B")"
            let reclaimable = "\(obj["Reclaimable"] ?? "0B")"
            rows.append(
                DockerSpaceRow(
                    type: type,
                    totalCount: total,
                    activeCount: active,
                    sizeText: size,
                    reclaimableText: reclaimable
                )
            )
        }
        return rows
    }

    public static func parsePOSIXDFRootLine(_ output: String) -> (totalBytes: Int64, usedBytes: Int64, availBytes: Int64)? {
        // POSIX `df -Pk /` outputs header on line 1 and 1024-byte block counts on line 2:
        // Filesystem 1024-blocks Used Available Capacity Mounted on
        let lines = output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.lowercased().hasPrefix("filesystem") }

        for line in lines {
            let cols = line.split(whereSeparator: \.isWhitespace).map(String.init)
            // Standard POSIX columns: [fs, blocks, used, avail, pct, mount]; handle wrapped fs name too
            if cols.count >= 5 {
                let numericCandidates = cols.dropFirst().compactMap(Int64.init)
                if numericCandidates.count >= 3 {
                    let total = numericCandidates[0] * 1024
                    let used = numericCandidates[1] * 1024
                    let avail = numericCandidates[2] * 1024
                    if total > 0 {
                        return (total, used, avail)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Subprocess Helper with Timeout

    private struct CommandOutput {
        let exitCode: Int32
        let stdout: String
        let stderr: String
    }

    private static func runCommandWithTimeout(
        executable: String,
        arguments: [String],
        timeoutSeconds: TimeInterval
    ) -> CommandOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            return CommandOutput(exitCode: -1, stdout: "", stderr: error.localizedDescription)
        }

        let semaphore = DispatchSemaphore(value: 0)
        final class OutputBox: @unchecked Sendable {
            var outData = Data()
            var errData = Data()
        }
        let box = OutputBox()
        let readGroup = DispatchGroup()

        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        readGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            box.errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            readGroup.leave()
        }

        DispatchQueue.global(qos: .utility).async {
            process.waitUntilExit()
            semaphore.signal()
        }

        let waitResult = semaphore.wait(timeout: .now() + timeoutSeconds)
        if waitResult == .timedOut {
            process.terminate()
            return CommandOutput(exitCode: -124, stdout: "", stderr: "Timed out after \(Int(timeoutSeconds))s.")
        }

        _ = readGroup.wait(timeout: .now() + 2.0)
        return CommandOutput(
            exitCode: process.terminationStatus,
            stdout: String(data: box.outData, encoding: .utf8) ?? "",
            stderr: String(data: box.errData, encoding: .utf8) ?? ""
        )
    }
}
