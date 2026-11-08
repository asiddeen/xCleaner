import Foundation

public enum AdvisoryLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case safe
    case caution
    case warning
    case protected

    private var rank: Int {
        switch self {
        case .safe: return 0
        case .caution: return 1
        case .warning: return 2
        case .protected: return 3
        }
    }

    public static func < (lhs: AdvisoryLevel, rhs: AdvisoryLevel) -> Bool {
        lhs.rank < rhs.rank
    }

    public var displayName: String {
        switch self {
        case .safe: return "Safe"
        case .caution: return "Caution"
        case .warning: return "Warning"
        case .protected: return "Protected"
        }
    }

    public var symbolName: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .protected: return "lock.shield.fill"
        }
    }
}

public struct ItemAdvisory: Codable, Sendable, Equatable {
    public let level: AdvisoryLevel
    public let badgeTitle: String
    public let whatIsThis: String
    public let consequenceIfRemoved: String
    public let requiresExplicitAck: Bool
    public let referencedByProjects: [String]
    public let lockedByAppName: String?
    public let lockedByBundleID: String?
    public let isPinnedByUser: Bool

    public init(
        level: AdvisoryLevel,
        badgeTitle: String,
        whatIsThis: String,
        consequenceIfRemoved: String,
        requiresExplicitAck: Bool? = nil,
        referencedByProjects: [String] = [],
        lockedByAppName: String? = nil,
        lockedByBundleID: String? = nil,
        isPinnedByUser: Bool = false
    ) {
        self.level = level
        self.badgeTitle = badgeTitle
        self.whatIsThis = whatIsThis
        self.consequenceIfRemoved = consequenceIfRemoved
        self.requiresExplicitAck = requiresExplicitAck ?? (level == .warning)
        self.referencedByProjects = referencedByProjects
        self.lockedByAppName = lockedByAppName
        self.lockedByBundleID = lockedByBundleID
        self.isPinnedByUser = isPinnedByUser
    }

    public var isLockedByRunningApp: Bool {
        lockedByAppName != nil
    }

    public var canBeStaged: Bool {
        level != .protected && !isLockedByRunningApp && !isPinnedByUser
    }

    public var isAutoSafeCandidate: Bool {
        level == .safe && canBeStaged
    }

    public func withPinState(_ pinned: Bool) -> ItemAdvisory {
        ItemAdvisory(
            level: level,
            badgeTitle: badgeTitle,
            whatIsThis: whatIsThis,
            consequenceIfRemoved: consequenceIfRemoved,
            requiresExplicitAck: requiresExplicitAck,
            referencedByProjects: referencedByProjects,
            lockedByAppName: lockedByAppName,
            lockedByBundleID: lockedByBundleID,
            isPinnedByUser: pinned
        )
    }

    public func withRunningLock(appName: String, bundleID: String?) -> ItemAdvisory {
        ItemAdvisory(
            level: level,
            badgeTitle: "\(appName) Running",
            whatIsThis: whatIsThis,
            consequenceIfRemoved: "\(appName) is currently open. Quit \(appName) before cleaning to avoid active cache or database corruption.",
            requiresExplicitAck: requiresExplicitAck,
            referencedByProjects: referencedByProjects,
            lockedByAppName: appName,
            lockedByBundleID: bundleID,
            isPinnedByUser: isPinnedByUser
        )
    }
}
