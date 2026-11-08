import Foundation

public struct VolumeMetrics: Sendable, Equatable {
    public let totalBytes: Int64
    public let rawAvailableBytes: Int64
    public let importantAvailableBytes: Int64
    public let opportunisticAvailableBytes: Int64
    public let purgeableBytes: Int64
    public let dataVolumeUsedBytes: Int64
    public let systemVolumeBytes: Int64
    public let vmSwapBytes: Int64
    public let prebootAndRecoveryBytes: Int64
    public let localSnapshots: [String]
    public let tccUnscannedBytesEstimate: Int64?

    public init(
        totalBytes: Int64,
        rawAvailableBytes: Int64,
        importantAvailableBytes: Int64,
        opportunisticAvailableBytes: Int64,
        dataVolumeUsedBytes: Int64,
        systemVolumeBytes: Int64,
        vmSwapBytes: Int64,
        prebootAndRecoveryBytes: Int64,
        localSnapshots: [String] = [],
        tccUnscannedBytesEstimate: Int64? = nil
    ) {
        self.totalBytes = max(1, totalBytes)
        self.rawAvailableBytes = max(0, rawAvailableBytes)
        self.importantAvailableBytes = max(self.rawAvailableBytes, importantAvailableBytes)
        self.opportunisticAvailableBytes = max(0, opportunisticAvailableBytes)
        self.purgeableBytes = max(0, self.importantAvailableBytes - self.rawAvailableBytes)
        self.dataVolumeUsedBytes = max(0, dataVolumeUsedBytes)
        self.systemVolumeBytes = max(0, systemVolumeBytes)
        self.vmSwapBytes = max(0, vmSwapBytes)
        self.prebootAndRecoveryBytes = max(0, prebootAndRecoveryBytes)
        self.localSnapshots = localSnapshots
        self.tccUnscannedBytesEstimate = tccUnscannedBytesEstimate
    }

    public var containerUsedBytes: Int64 {
        max(0, totalBytes - rawAvailableBytes)
    }

    public var usedFraction: Double {
        min(1.0, max(0.0, Double(containerUsedBytes) / Double(totalBytes)))
    }

    public var isCriticallyConstrained: Bool {
        opportunisticAvailableBytes == 0 || (Double(rawAvailableBytes) / Double(totalBytes)) < 0.08
    }

    public func withTCCUnscannedEstimate(scannedHomeAndSystemBytes: Int64, hadPermissionDenials: Bool) -> VolumeMetrics {
        guard hadPermissionDenials, dataVolumeUsedBytes > 0 else {
            return self
        }
        let delta = max(0, dataVolumeUsedBytes - scannedHomeAndSystemBytes)
        guard delta > 500_000_000 else {
            return self
        }
        return VolumeMetrics(
            totalBytes: totalBytes,
            rawAvailableBytes: rawAvailableBytes,
            importantAvailableBytes: importantAvailableBytes,
            opportunisticAvailableBytes: opportunisticAvailableBytes,
            dataVolumeUsedBytes: dataVolumeUsedBytes,
            systemVolumeBytes: systemVolumeBytes,
            vmSwapBytes: vmSwapBytes,
            prebootAndRecoveryBytes: prebootAndRecoveryBytes,
            localSnapshots: localSnapshots,
            tccUnscannedBytesEstimate: delta
        )
    }
}
