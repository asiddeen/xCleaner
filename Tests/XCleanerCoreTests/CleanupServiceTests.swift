import Foundation
import Testing
@testable import XCleanerCore

private struct MockRunningAppChecker: RunningAppChecking {
    let apps: [RunningApplicationSnapshot]
    func activeApplications() async -> [RunningApplicationSnapshot] { apps }
    func requestGracefulTermination(bundleID: String?, appName: String?) async -> Bool { true }
}

private final class MockTrashBackend: FileRecyclingBackend, @unchecked Sendable {
    let trashDir: URL

    init(trashDir: URL) {
        self.trashDir = trashDir
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
    }

    func recycleToTrash(_ urls: [URL]) async throws -> [URL] {
        var moved: [URL] = []
        for url in urls {
            let dest = trashDir.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
            try FileManager.default.moveItem(at: url, to: dest)
            moved.append(url)
        }
        return moved
    }

    func permanentlyRemove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }
}

@Suite("Cleanup Execution Service, TOCTOU Re-validation & JSONL Audit Log")
struct CleanupServiceTests {
    @Test("Cleans approved targets while strictly blocking protected, pinned, and running-locked items at execution time")
    func enforcesPreflightSafetyAndRecordsHistory() async throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcleaner-cleanup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let safeCache = tempHome.appendingPathComponent("Library/Caches/bruno-updater", isDirectory: true)
        let pinnedCache = tempHome.appendingPathComponent("Library/Application Support/Spotify/PersistentCache", isDirectory: true)
        let runningCache = tempHome.appendingPathComponent("Library/Caches/com.google.Chrome", isDirectory: true)
        let protectedSSH = tempHome.appendingPathComponent(".ssh", isDirectory: true)

        for dir in [safeCache, pinnedCache, runningCache, protectedSSH] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 0x77, count: 32_768).write(to: dir.appendingPathComponent("payload.dat"))
        }

        let keepStore = KeepListStore(storageURL: tempHome.appendingPathComponent("keep.json"))
        keepStore.pin(url: pinnedCache, label: "Spotify")

        let historyStore = CleanupHistoryStore(logFileURL: tempHome.appendingPathComponent("history.jsonl"))
        let backend = MockTrashBackend(trashDir: tempHome.appendingPathComponent(".MockTrash"))
        let runningChecker = MockRunningAppChecker(apps: [
            RunningApplicationSnapshot(bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome")
        ])

        let service = CleanupService(
            safetyPolicy: SafetyPolicyEngine(homeDirectory: tempHome),
            runningAppGuard: runningChecker,
            historyStore: historyStore,
            backend: backend
        )

        let dummyAdv = ItemAdvisory(level: .safe, badgeTitle: "Safe", whatIsThis: "Test", consequenceIfRemoved: "None")
        let targets: [CleanupStageTarget] = [
            CleanupStageTarget(id: "1", title: "Bruno Updater", subtitle: safeCache.path, urls: [safeCache], allocatedBytes: 32_768, sourceLabel: "Smart Scan", advisory: dummyAdv),
            CleanupStageTarget(id: "2", title: "Spotify", subtitle: pinnedCache.path, urls: [pinnedCache], allocatedBytes: 32_768, sourceLabel: "Smart Scan", advisory: dummyAdv),
            CleanupStageTarget(id: "3", title: "Chrome Cache", subtitle: runningCache.path, urls: [runningCache], allocatedBytes: 32_768, sourceLabel: "Smart Scan", associatedBundleID: "com.google.Chrome", associatedAppName: "Google Chrome", advisory: dummyAdv),
            CleanupStageTarget(id: "4", title: "SSH", subtitle: protectedSSH.path, urls: [protectedSSH], allocatedBytes: 32_768, sourceLabel: "Manual", advisory: dummyAdv)
        ]

        let result = await service.executeCleanup(targets: targets, mode: .moveToTrash, keepList: keepStore)

        // Only safeCache should be moved to Trash; the other 3 must still exist untouched!
        #expect(result.cleanedPaths == [safeCache.standardizedFileURL.path])
        #expect(result.freedBytes >= 32_768)
        #expect(result.skippedReasons.count == 3)
        #expect(!FileManager.default.fileExists(atPath: safeCache.path))
        #expect(FileManager.default.fileExists(atPath: pinnedCache.path))
        #expect(FileManager.default.fileExists(atPath: runningCache.path))
        #expect(FileManager.default.fileExists(atPath: protectedSSH.path))

        // History JSONL persisted accurately
        let records = historyStore.loadAll()
        #expect(records.count == 1)
        #expect(records.first?.itemsCleanedCount == 1)
        #expect(records.first?.skippedItems.count == 3)
    }
}
