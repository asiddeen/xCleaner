import Foundation

public struct SmartJunkScanReport: Sendable, Equatable {
    public let items: [ScannableItem]
    public let projectReferences: ProjectToolchainReferences
    public let scannedAt: Date

    public init(
        items: [ScannableItem],
        projectReferences: ProjectToolchainReferences,
        scannedAt: Date = Date()
    ) {
        self.items = items
        self.projectReferences = projectReferences
        self.scannedAt = scannedAt
    }

    public var totalFoundBytes: Int64 {
        items.reduce(0) { $0 + $1.allocatedBytes }
    }

    public var autoSafeBytes: Int64 {
        items.filter { $0.advisory.isAutoSafeCandidate }.reduce(0) { $0 + $1.allocatedBytes }
    }

    public func items(in domain: JunkDomain) -> [ScannableItem] {
        items.filter { $0.domain == domain }
    }
}

public struct SmartJunkScanner: Sendable {
    public let safetyPolicy: SafetyPolicyEngine
    public let orphanDetector: OrphanedAppDetector
    public let appSupportScanner: AppSupportCacheScanner
    public let ruleRegistry: JunkRuleRegistry
    public let projectArtifactScanner: ProjectArtifactScanner
    public let projectReferenceScanner: ProjectReferenceScanner

    public init(safetyPolicy: SafetyPolicyEngine = SafetyPolicyEngine()) {
        self.safetyPolicy = safetyPolicy
        self.orphanDetector = OrphanedAppDetector(safetyPolicy: safetyPolicy)
        self.appSupportScanner = AppSupportCacheScanner(safetyPolicy: safetyPolicy)
        self.ruleRegistry = JunkRuleRegistry(safetyPolicy: safetyPolicy)
        self.projectArtifactScanner = ProjectArtifactScanner(safetyPolicy: safetyPolicy)
        self.projectReferenceScanner = ProjectReferenceScanner()
    }

    public func runSmartScan(
        projectRoots: [URL],
        installedAppsIndex: InstalledAppsIndex? = nil,
        runningApps: [RunningApplicationSnapshot],
        keepList: KeepListStore?,
        minimumProjectStalenessDays: Int = 0
    ) async throws -> SmartJunkScanReport {
        try Task.checkCancellation()
        let home = safetyPolicy.homeDirectory
        let resolvedIndex = installedAppsIndex ?? InstalledAppsIndex.buildFromSystem(homeDirectory: home)

        async let orphanTask = orphanDetector.scanOrphans(
            installedIndex: resolvedIndex,
            runningApps: runningApps,
            keepList: keepList
        )
        async let appSupportTask = appSupportScanner.scanAppSupportCaches(
            installedIndex: resolvedIndex,
            runningApps: runningApps,
            keepList: keepList
        )
        async let standardAndDevTask = ruleRegistry.scanStandardAndDevCaches(
            runningApps: runningApps,
            keepList: keepList
        )
        async let projectArtifactsTask = projectArtifactScanner.scanProjectArtifacts(
            in: projectRoots,
            minimumStalenessDays: minimumProjectStalenessDays,
            keepList: keepList
        )
        async let referencesTask = projectReferenceScanner.scanReferences(in: projectRoots)

        let (orphans, appSupport, standardAndDev, projectArtifacts, references) = await (
            orphanTask,
            appSupportTask,
            standardAndDevTask,
            projectArtifactsTask,
            referencesTask
        )

        try Task.checkCancellation()

        // Priority order prevents double-counting when an uninstalled app claims its ShipIt cache or Application Support dir
        let orderedCandidates = orphans + appSupport + standardAndDev + projectArtifacts
        let deduplicated = Self.deduplicateOverlappingItems(orderedCandidates)

        return SmartJunkScanReport(
            items: deduplicated.sorted { $0.allocatedBytes > $1.allocatedBytes },
            projectReferences: references
        )
    }

    public static func deduplicateOverlappingItems(_ candidates: [ScannableItem]) -> [ScannableItem] {
        var claimedPaths: [String] = []
        var kept: [ScannableItem] = []

        for item in candidates {
            let itemPaths = item.allTargetURLs.map { $0.standardizedFileURL.path }
            let overlaps = itemPaths.contains { candidatePath in
                claimedPaths.contains { existingPath in
                    candidatePath == existingPath ||
                    candidatePath.hasPrefix(existingPath + "/") ||
                    existingPath.hasPrefix(candidatePath + "/")
                }
            }
            if !overlaps {
                kept.append(item)
                claimedPaths.append(contentsOf: itemPaths)
            }
        }
        return kept
    }
}
