import Foundation

public struct APFSVolumeMonitor: Sendable {
    public init() {}

    public func fetchMetrics(rootURL: URL = URL(fileURLWithPath: "/")) async -> VolumeMetrics {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey
        ]
        let values = try? rootURL.resourceValues(forKeys: keys)
        var totalBytes = Int64(values?.volumeTotalCapacity ?? 0)
        var rawAvail = Int64(values?.volumeAvailableCapacity ?? 0)
        let importantAvail = Int64(values?.volumeAvailableCapacityForImportantUsage ?? rawAvail)
        let opportunisticAvail = Int64(values?.volumeAvailableCapacityForOpportunisticUsage ?? 0)

        var dataUsed: Int64 = 0
        var systemUsed: Int64 = 0
        var vmUsed: Int64 = 0
        var prebootRecoveryUsed: Int64 = 0

        if let apfsInfo = Self.queryDiskutilAPFS() {
            if apfsInfo.containerCeiling > 0 {
                totalBytes = apfsInfo.containerCeiling
            }
            if apfsInfo.containerFree > 0 {
                rawAvail = apfsInfo.containerFree
            }
            dataUsed = apfsInfo.dataBytes
            systemUsed = apfsInfo.systemBytes
            vmUsed = apfsInfo.vmBytes
            prebootRecoveryUsed = apfsInfo.prebootAndRecoveryBytes
        } else if totalBytes > 0 {
            dataUsed = max(0, totalBytes - rawAvail)
        }

        let snapshots = Self.queryLocalSnapshots()

        return VolumeMetrics(
            totalBytes: max(1, totalBytes),
            rawAvailableBytes: rawAvail,
            importantAvailableBytes: max(rawAvail, importantAvail),
            opportunisticAvailableBytes: opportunisticAvail,
            dataVolumeUsedBytes: dataUsed,
            systemVolumeBytes: systemUsed,
            vmSwapBytes: vmUsed,
            prebootAndRecoveryBytes: prebootRecoveryUsed,
            localSnapshots: snapshots
        )
    }

    private struct APFSContainerBreakdown {
        var containerCeiling: Int64 = 0
        var containerFree: Int64 = 0
        var dataBytes: Int64 = 0
        var systemBytes: Int64 = 0
        var vmBytes: Int64 = 0
        var prebootAndRecoveryBytes: Int64 = 0
    }

    private static func queryDiskutilAPFS() -> APFSContainerBreakdown? {
        let diskutilPath = "/usr/sbin/diskutil"
        guard FileManager.default.isExecutableFile(atPath: diskutilPath) else { return nil }
        guard let outputData = runProcessData(executable: diskutilPath, arguments: ["apfs", "list", "-plist"]) else {
            return nil
        }
        guard let plist = try? PropertyListSerialization.propertyList(from: outputData, options: [], format: nil) as? [String: Any],
              let containers = plist["Containers"] as? [[String: Any]] else {
            return nil
        }

        // Pick container hosting Macintosh HD / Data (largest or containing System+Data roles)
        let targetContainer = containers.max { lhs, rhs in
            let lSize = (lhs["CapacityCeiling"] as? NSNumber)?.int64Value ?? 0
            let rSize = (rhs["CapacityCeiling"] as? NSNumber)?.int64Value ?? 0
            return lSize < rSize
        }
        guard let container = targetContainer else { return nil }

        var result = APFSContainerBreakdown()
        result.containerCeiling = (container["CapacityCeiling"] as? NSNumber)?.int64Value ?? 0
        result.containerFree = (container["CapacityFree"] as? NSNumber)?.int64Value ?? 0

        if let volumes = container["Volumes"] as? [[String: Any]] {
            for vol in volumes {
                let consumed = (vol["CapacityConsumed"] as? NSNumber)?.int64Value ?? 0
                let roles = (vol["Roles"] as? [String]) ?? []
                if roles.contains("Data") {
                    result.dataBytes += consumed
                } else if roles.contains("System") {
                    result.systemBytes += consumed
                } else if roles.contains("VM") {
                    result.vmBytes += consumed
                } else if roles.contains("Preboot") || roles.contains("Recovery") {
                    result.prebootAndRecoveryBytes += consumed
                } else {
                    result.prebootAndRecoveryBytes += consumed
                }
            }
        }
        return result
    }

    private static func queryLocalSnapshots() -> [String] {
        let tmutilPath = "/usr/bin/tmutil"
        guard FileManager.default.isExecutableFile(atPath: tmutilPath),
              let data = runProcessData(executable: tmutilPath, arguments: ["listlocalsnapshots", "/"]),
              let text = String(data: data, encoding: .utf8) else {
            return []
        }
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.contains("com.apple.") }
    }

    private static func runProcessData(executable: String, arguments: [String]) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()
        do {
            try process.run()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return data
        } catch {
            return nil
        }
    }
}
