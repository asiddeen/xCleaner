import Foundation

public struct DockerSpaceRow: Codable, Sendable, Equatable, Identifiable {
    public var id: String { type }
    public let type: String
    public let totalCount: String
    public let activeCount: String
    public let sizeText: String
    public let reclaimableText: String

    public init(
        type: String,
        totalCount: String,
        activeCount: String,
        sizeText: String,
        reclaimableText: String
    ) {
        self.type = type
        self.totalCount = totalCount
        self.activeCount = activeCount
        self.sizeText = sizeText
        self.reclaimableText = reclaimableText
    }
}

public struct LocalDockerStatus: Sendable, Equatable {
    public let isCLIAvailable: Bool
    public let cliPath: String?
    public let isDaemonRunning: Bool
    public let vmDiskURL: URL?
    public let vmDiskAllocatedBytes: Int64
    public let rows: [DockerSpaceRow]
    public let statusMessage: String

    public init(
        isCLIAvailable: Bool,
        cliPath: String?,
        isDaemonRunning: Bool,
        vmDiskURL: URL?,
        vmDiskAllocatedBytes: Int64,
        rows: [DockerSpaceRow],
        statusMessage: String
    ) {
        self.isCLIAvailable = isCLIAvailable
        self.cliPath = cliPath
        self.isDaemonRunning = isDaemonRunning
        self.vmDiskURL = vmDiskURL
        self.vmDiskAllocatedBytes = vmDiskAllocatedBytes
        self.rows = rows
        self.statusMessage = statusMessage
    }
}

public struct SSHServerTarget: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let alias: String
    public let host: String
    public let user: String?
    public let port: Int?
    public let source: String

    public init(
        id: String? = nil,
        alias: String,
        host: String,
        user: String? = nil,
        port: Int? = nil,
        source: String = "Custom"
    ) {
        self.alias = alias
        self.host = host
        self.user = user
        self.port = port
        self.source = source
        self.id = id ?? "\(user ?? "")@\(host):\(port ?? 22)#\(alias)"
    }

    public var sshDestination: String {
        if source == "~/.ssh/config" {
            return alias
        }
        if let user, !user.isEmpty {
            return "\(user)@\(host)"
        }
        return host
    }

    public var displayLabel: String {
        if let user, !user.isEmpty {
            if alias != host {
                return "\(alias) (\(user)@\(host))"
            }
            return "\(user)@\(host)"
        }
        return alias == host ? host : "\(alias) (\(host))"
    }
}

public struct RemoteServerStatus: Sendable, Equatable, Identifiable {
    public var id: String { target.id }
    public let target: SSHServerTarget
    public let isReachable: Bool
    public let rootTotalBytes: Int64?
    public let rootUsedBytes: Int64?
    public let rootAvailBytes: Int64?
    public let dockerRows: [DockerSpaceRow]
    public let statusMessage: String
    public let checkedAt: Date

    public init(
        target: SSHServerTarget,
        isReachable: Bool,
        rootTotalBytes: Int64? = nil,
        rootUsedBytes: Int64? = nil,
        rootAvailBytes: Int64? = nil,
        dockerRows: [DockerSpaceRow] = [],
        statusMessage: String,
        checkedAt: Date = Date()
    ) {
        self.target = target
        self.isReachable = isReachable
        self.rootTotalBytes = rootTotalBytes
        self.rootUsedBytes = rootUsedBytes
        self.rootAvailBytes = rootAvailBytes
        self.dockerRows = dockerRows
        self.statusMessage = statusMessage
        self.checkedAt = checkedAt
    }
}
