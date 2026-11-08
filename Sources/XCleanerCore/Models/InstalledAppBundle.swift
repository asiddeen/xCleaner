import Foundation

public enum AppLocationCategory: String, Codable, Sendable, CaseIterable {
    case appBundle = "Application Bundle"
    case safeCacheOrLog = "Caches & Diagnostic Logs"
    case supportAndContainers = "Application Support & Containers"
    case preferences = "Preferences & Saved State"

    public var symbolName: String {
        switch self {
        case .appBundle: return "app.badge"
        case .safeCacheOrLog: return "sparkles"
        case .supportAndContainers: return "folder.badge.gearshape"
        case .preferences: return "slider.horizontal.3"
        }
    }

    public var advisoryLevel: AdvisoryLevel {
        switch self {
        case .safeCacheOrLog: return .safe
        case .appBundle, .supportAndContainers, .preferences: return .warning
        }
    }
}

public struct AppAssociatedLocation: Identifiable, Sendable, Equatable {
    public let id: String
    public let url: URL
    public let category: AppLocationCategory
    public let allocatedBytes: Int64
    public let itemCount: Int
    public let lastModified: Date?
    public let advisory: ItemAdvisory

    public init(
        url: URL,
        category: AppLocationCategory,
        allocatedBytes: Int64,
        itemCount: Int,
        lastModified: Date? = nil,
        advisory: ItemAdvisory
    ) {
        let norm = url.standardizedFileURL
        self.id = norm.path
        self.url = norm
        self.category = category
        self.allocatedBytes = allocatedBytes
        self.itemCount = itemCount
        self.lastModified = lastModified
        self.advisory = advisory
    }
}

public struct InstalledAppBundle: Identifiable, Sendable, Equatable {
    public let id: String
    public let appURL: URL
    public let bundleID: String?
    public let displayName: String
    public let version: String?
    public let isSystemProtected: Bool
    public let isRunning: Bool
    public let locations: [AppAssociatedLocation]

    public init(
        appURL: URL,
        bundleID: String?,
        displayName: String,
        version: String?,
        isSystemProtected: Bool,
        isRunning: Bool,
        locations: [AppAssociatedLocation]
    ) {
        let norm = appURL.standardizedFileURL
        self.id = bundleID ?? norm.path
        self.appURL = norm
        self.bundleID = bundleID
        self.displayName = displayName
        self.version = version
        self.isSystemProtected = isSystemProtected
        self.isRunning = isRunning
        self.locations = locations
    }

    public var appBinaryBytes: Int64 {
        locations.first(where: { $0.category == .appBundle })?.allocatedBytes ?? 0
    }

    public var safeCacheBytes: Int64 {
        locations.filter { $0.category == .safeCacheOrLog }.reduce(0) { $0 + $1.allocatedBytes }
    }

    public var supportAndPrefsBytes: Int64 {
        locations.filter { $0.category == .supportAndContainers || $0.category == .preferences }.reduce(0) { $0 + $1.allocatedBytes }
    }

    public var totalFootprintBytes: Int64 {
        locations.reduce(0) { $0 + $1.allocatedBytes }
    }
}
