import AppKit
import Foundation

public struct CleanupExecutionResult: Sendable, Equatable {
    public let mode: DeletionMode
    public let freedBytes: Int64
    public let cleanedPaths: [String]
    public let skippedReasons: [String]
    public let record: CleanupRecord?

    public init(
        mode: DeletionMode,
        freedBytes: Int64,
        cleanedPaths: [String],
        skippedReasons: [String],
        record: CleanupRecord?
    ) {
        self.mode = mode
        self.freedBytes = freedBytes
        self.cleanedPaths = cleanedPaths
        self.skippedReasons = skippedReasons
        self.record = record
    }
}

public protocol FileRecyclingBackend: Sendable {
    func recycleToTrash(_ urls: [URL]) async throws -> [URL]
    func permanentlyRemove(_ url: URL) throws
}

public struct LiveFileRecyclingBackend: FileRecyclingBackend {
    public init() {}

    public func recycleToTrash(_ urls: [URL]) async throws -> [URL] {
        try await withCheckedThrowingContinuation { continuation in
            NSWorkspace.shared.recycle(urls) { recycledMap, error in
                let recycledOriginals = Array(recycledMap.keys)
                if !recycledOriginals.isEmpty {
                    continuation.resume(returning: recycledOriginals)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: [])
                }
            }
        }
    }

    public func permanentlyRemove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

public struct CleanupService: Sendable {
    public let safetyPolicy: SafetyPolicyEngine
    public let runningAppGuard: any RunningAppChecking
    public let historyStore: CleanupHistoryStore
    public let backend: any FileRecyclingBackend

    public init(
        safetyPolicy: SafetyPolicyEngine = SafetyPolicyEngine(),
        runningAppGuard: any RunningAppChecking = LiveRunningAppGuard(),
        historyStore: CleanupHistoryStore = CleanupHistoryStore(),
        backend: any FileRecyclingBackend = LiveFileRecyclingBackend()
    ) {
        self.safetyPolicy = safetyPolicy
        self.runningAppGuard = runningAppGuard
        self.historyStore = historyStore
        self.backend = backend
    }

    public func executeCleanup(
        targets: [CleanupStageTarget],
        mode: DeletionMode,
        keepList: KeepListStore?
    ) async -> CleanupExecutionResult {
        guard !targets.isEmpty else {
            return CleanupExecutionResult(
                mode: mode,
                freedBytes: 0,
                cleanedPaths: [],
                skippedReasons: [],
                record: nil
            )
        }

        let liveRunningApps = await runningAppGuard.activeApplications()
        let fm = FileManager.default

        struct ValidatedURL {
            let url: URL
            let measuredBytes: Int64
        }

        var approvedURLs: [ValidatedURL] = []
        var seenPaths = Set<String>()
        var skippedReasons: [String] = []

        // Pre-flight TOCTOU Re-validation on every individual URL
        for target in targets {
            for rawURL in target.urls {
                let standardized = rawURL.standardizedFileURL
                guard seenPaths.insert(standardized.path).inserted else { continue }

                // 1. Hard Protection Blocklist & Symlink Target Check
                let verdict = safetyPolicy.evaluateProtection(for: standardized)
                if verdict.isProtected {
                    skippedReasons.append("\(standardized.lastPathComponent): Blocked (\(verdict.reasonTitle ?? "Protected"))")
                    continue
                }

                // 2. User Pin Check
                if keepList?.isPinned(url: standardized) == true {
                    skippedReasons.append("\(standardized.lastPathComponent): Skipped (Pinned to Keep)")
                    continue
                }

                // 3. Live Running Application Lock Check
                if let lockingApp = RunningLockMatcher.findLockingApp(
                    for: standardized,
                    explicitBundleID: target.associatedBundleID,
                    explicitAppName: target.associatedAppName,
                    runningApps: liveRunningApps,
                    homeDirectory: safetyPolicy.homeDirectory
                ) {
                    skippedReasons.append("\(standardized.lastPathComponent): Skipped (\(lockingApp.localizedName) is currently running)")
                    continue
                }

                // 4. Verify existence without following symlinks
                guard (try? fm.attributesOfItem(atPath: standardized.path)) != nil else {
                    skippedReasons.append("\(standardized.lastPathComponent): Already removed")
                    continue
                }

                let measured = ConcurrentDiskScanner.measureFootprint(at: standardized).allocatedBytes
                approvedURLs.append(ValidatedURL(url: standardized, measuredBytes: measured))
            }
        }

        // Remove descendant URLs if their parent directory is also in approvedURLs
        let sortedApproved = approvedURLs.sorted { $0.url.path.count < $1.url.path.count }
        var deduplicatedApproved: [ValidatedURL] = []
        for candidate in sortedApproved {
            let coveredByAncestor = deduplicatedApproved.contains {
                candidate.url.path.hasPrefix($0.url.path + "/")
            }
            if !coveredByAncestor {
                deduplicatedApproved.append(candidate)
            }
        }

        var cleanedPaths: [String] = []
        var freedBytes: Int64 = 0

        switch mode {
        case .moveToTrash:
            // Process in batches of 25 URLs so Finder / NSWorkspace stays responsive
            let batchSize = 25
            var index = 0
            while index < deduplicatedApproved.count {
                let end = min(index + batchSize, deduplicatedApproved.count)
                let slice = Array(deduplicatedApproved[index..<end])
                let batchURLs = slice.map(\.url)
                do {
                    let recycled = try await backend.recycleToTrash(batchURLs)
                    let recycledSet = Set(recycled.map { $0.standardizedFileURL.path })
                    for entry in slice {
                        if recycledSet.contains(entry.url.path) || !fm.fileExists(atPath: entry.url.path) {
                            cleanedPaths.append(entry.url.path)
                            freedBytes += entry.measuredBytes
                        } else {
                            skippedReasons.append("\(entry.url.lastPathComponent): Could not move to Trash")
                        }
                    }
                } catch {
                    // Fallback per-item recycle so one locked file does not abort the rest of the batch
                    for entry in slice {
                        if let singleRecycled = try? await backend.recycleToTrash([entry.url]),
                           !singleRecycled.isEmpty || !fm.fileExists(atPath: entry.url.path) {
                            cleanedPaths.append(entry.url.path)
                            freedBytes += entry.measuredBytes
                        } else {
                            skippedReasons.append("\(entry.url.lastPathComponent): \(error.localizedDescription)")
                        }
                    }
                }
                index = end
            }

        case .permanentDelete:
            for entry in deduplicatedApproved {
                do {
                    try backend.permanentlyRemove(entry.url)
                    cleanedPaths.append(entry.url.path)
                    freedBytes += entry.measuredBytes
                } catch {
                    skippedReasons.append("\(entry.url.lastPathComponent): \(error.localizedDescription)")
                }
            }
        }

        let record: CleanupRecord?
        if !cleanedPaths.isEmpty || !skippedReasons.isEmpty {
            let newRecord = CleanupRecord(
                actionKind: mode.rawValue,
                itemsCleanedCount: cleanedPaths.count,
                freedBytes: freedBytes,
                cleanedPaths: cleanedPaths,
                skippedItems: skippedReasons
            )
            historyStore.append(newRecord)
            record = newRecord
        } else {
            record = nil
        }

        return CleanupExecutionResult(
            mode: mode,
            freedBytes: freedBytes,
            cleanedPaths: cleanedPaths,
            skippedReasons: skippedReasons,
            record: record
        )
    }
}
