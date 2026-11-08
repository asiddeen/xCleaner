import Foundation

public enum ToolchainEcosystem: String, Codable, Sendable, CaseIterable, Identifiable {
    case gradle = "Gradle Build System"
    case androidSDK = "Android SDK & NDK"
    case nodeNVM = "Node.js Runtimes (nvm)"
    case headlessBrowsers = "Headless Testing Browsers"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .gradle: return "shippingbox"
        case .androidSDK: return "iphone.gen3"
        case .nodeNVM: return "terminal"
        case .headlessBrowsers: return "safari"
        }
    }
}

public enum ToolchainVersionStatus: String, Codable, Sendable, Equatable {
    case referencedByProject = "Referenced by Project"
    case activeOrLatest = "Active / Latest"
    case sharedCoreCache = "Shared Core Cache"
    case releaseCandidateOrPreview = "Preview / Release Candidate"
    case superseded = "Older / Unreferenced"
    case leftoverArchive = "Leftover Installer Archive"
}

public struct ToolchainItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let ecosystem: ToolchainEcosystem
    public let componentKind: String
    public let version: String
    public let urls: [URL]
    public let allocatedBytes: Int64
    public let lastModified: Date?
    public let status: ToolchainVersionStatus
    public let advisory: ItemAdvisory

    public init(
        id: String? = nil,
        ecosystem: ToolchainEcosystem,
        componentKind: String,
        version: String,
        urls: [URL],
        allocatedBytes: Int64,
        lastModified: Date? = nil,
        status: ToolchainVersionStatus,
        advisory: ItemAdvisory
    ) {
        let normalized = urls.map(\.standardizedFileURL)
        self.id = id ?? (normalized.first?.path ?? "\(ecosystem.rawValue):\(componentKind):\(version)")
        self.ecosystem = ecosystem
        self.componentKind = componentKind
        self.version = version
        self.urls = normalized
        self.allocatedBytes = allocatedBytes
        self.lastModified = lastModified
        self.status = status
        self.advisory = advisory
    }

    public var primaryURL: URL {
        urls.first ?? URL(fileURLWithPath: "/")
    }
}
