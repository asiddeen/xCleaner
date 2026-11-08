import Foundation

public enum JunkDomain: String, Codable, Sendable, CaseIterable, Identifiable {
    case systemAndAppCaches = "macOS Caches & Auto-Updaters"
    case browserAndAppSupport = "Browser & App Support Caches"
    case developerCaches = "Global Developer & AI Caches"
    case projectArtifacts = "Project Build & Dependency Folders"
    case orphanedApps = "Uninstalled App Leftovers"

    public var id: String { rawValue }

    public var symbolName: String {
        switch self {
        case .systemAndAppCaches: return "internaldrive"
        case .browserAndAppSupport: return "globe"
        case .developerCaches: return "hammer"
        case .projectArtifacts: return "folder.badge.gearshape"
        case .orphanedApps: return "puzzlepiece.extension"
        }
    }

    public var summaryDescription: String {
        switch self {
        case .systemAndAppCaches:
            return "Application caches in ~/Library/Caches, logs, crash reports, and abandoned auto-updater bundles (.ShipIt, *-updater)."
        case .browserAndAppSupport:
            return "Web PWA Service Worker caches, GPU/shader caches, IDE extension .vsix caches, and offline media caches inside Application Support."
        case .developerCaches:
            return "Global package manager caches (npm, npx, CocoaPods, Homebrew, pip, uv), Go/SwiftPM caches, and old IDE backups."
        case .projectArtifacts:
            return "Regenerable build and dependency folders (node_modules, dist, android/app/build, .next, .build, target, venv, R renv) across your workspaces."
        case .orphanedApps:
            return "Support folders, caches, and paired hidden dotfiles (~/.vscode, ~/.cursor) left behind after an application was removed from /Applications."
        }
    }
}

public struct ScannableItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let url: URL
    public let additionalURLs: [URL]
    public let title: String
    public let subtitle: String
    public let domain: JunkDomain
    public let allocatedBytes: Int64
    public let itemCount: Int
    public let lastModified: Date?
    public let stalenessDays: Int?
    public let associatedAppName: String?
    public let associatedBundleID: String?
    public let advisory: ItemAdvisory
    public let subItems: [ScannableItem]

    public init(
        id: String? = nil,
        url: URL,
        additionalURLs: [URL] = [],
        title: String,
        subtitle: String,
        domain: JunkDomain,
        allocatedBytes: Int64,
        itemCount: Int = 1,
        lastModified: Date? = nil,
        stalenessDays: Int? = nil,
        associatedAppName: String? = nil,
        associatedBundleID: String? = nil,
        advisory: ItemAdvisory,
        subItems: [ScannableItem] = []
    ) {
        let standardized = url.standardizedFileURL
        self.id = id ?? standardized.path
        self.url = standardized
        self.additionalURLs = additionalURLs.map(\.standardizedFileURL)
        self.title = title
        self.subtitle = subtitle
        self.domain = domain
        self.allocatedBytes = allocatedBytes
        self.itemCount = itemCount
        self.lastModified = lastModified
        self.stalenessDays = stalenessDays ?? ByteFormatting.daysBetween(lastModified)
        self.associatedAppName = associatedAppName
        self.associatedBundleID = associatedBundleID
        self.advisory = advisory
        self.subItems = subItems
    }

    public var allTargetURLs: [URL] {
        [url] + additionalURLs
    }
}
