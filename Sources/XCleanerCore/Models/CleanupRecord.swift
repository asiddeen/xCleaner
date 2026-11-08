import Foundation

public enum DeletionMode: String, Codable, Sendable, CaseIterable {
    case moveToTrash = "Move to Trash"
    case permanentDelete = "Permanent Delete"
}

public struct CleanupStageTarget: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let urls: [URL]
    public let allocatedBytes: Int64
    public let sourceLabel: String
    public let associatedBundleID: String?
    public let associatedAppName: String?
    public let advisory: ItemAdvisory

    public init(
        id: String,
        title: String,
        subtitle: String,
        urls: [URL],
        allocatedBytes: Int64,
        sourceLabel: String,
        associatedBundleID: String? = nil,
        associatedAppName: String? = nil,
        advisory: ItemAdvisory
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.urls = urls.map(\.standardizedFileURL)
        self.allocatedBytes = allocatedBytes
        self.sourceLabel = sourceLabel
        self.associatedBundleID = associatedBundleID
        self.associatedAppName = associatedAppName
        self.advisory = advisory
    }
}

public struct CleanupRecord: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let actionKind: String
    public let itemsCleanedCount: Int
    public let freedBytes: Int64
    public let cleanedPaths: [String]
    public let skippedItems: [String]
    public let notes: String?

    public init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        actionKind: String,
        itemsCleanedCount: Int,
        freedBytes: Int64,
        cleanedPaths: [String],
        skippedItems: [String] = [],
        notes: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.actionKind = actionKind
        self.itemsCleanedCount = itemsCleanedCount
        self.freedBytes = freedBytes
        self.cleanedPaths = cleanedPaths
        self.skippedItems = skippedItems
        self.notes = notes
    }
}
