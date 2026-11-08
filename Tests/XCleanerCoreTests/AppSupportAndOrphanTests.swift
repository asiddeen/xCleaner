import Foundation
import Testing
@testable import XCleanerCore

@Suite("Application Support Browser Caches & Orphaned Apps")
struct AppSupportAndOrphanTests {
    @Test("Surgically isolates Chromium Service Worker cache while leaving Cookies untouched and respecting SingletonLock")
    func isolatesBrowserServiceWorkerAndHonorsSingletonLock() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcleaner-appsupport-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let cometRoot = tempHome.appendingPathComponent("Library/Application Support/Comet", isDirectory: true)
        let defaultProfile = cometRoot.appendingPathComponent("Default", isDirectory: true)
        let swCache = defaultProfile.appendingPathComponent("Service Worker/CacheStorage", isDirectory: true)
        try FileManager.default.createDirectory(at: swCache, withIntermediateDirectories: true)

        // Write 6 MB into Service Worker CacheStorage and sensitive Cookies file alongside it
        try Data(repeating: 0x55, count: 6_000_000).write(to: swCache.appendingPathComponent("pwa-blob.bin"))
        let cookiesFile = defaultProfile.appendingPathComponent("Cookies")
        try Data(repeating: 0x99, count: 64_000).write(to: cookiesFile)

        // Simulate active Chromium SingletonLock
        try "127.0.0.1-12345".write(
            to: cometRoot.appendingPathComponent("SingletonLock"),
            atomically: true,
            encoding: .utf8
        )

        let safety = SafetyPolicyEngine(homeDirectory: tempHome)
        let scanner = AppSupportCacheScanner(safetyPolicy: safety)
        let index = InstalledAppsIndex(bundleIDs: ["ai.perplexity.comet"], normalizedNames: ["comet"])

        let lockedItems = scanner.scanAppSupportCaches(installedIndex: index, runningApps: [], keepList: nil)
        #expect(lockedItems.count == 1)
        let swItem = try #require(lockedItems.first)
        #expect(swItem.url.path == swCache.standardizedFileURL.path)
        #expect(!swItem.allTargetURLs.contains { $0.lastPathComponent == "Cookies" })
        #expect(swItem.advisory.level == .caution)
        #expect(swItem.advisory.isLockedByRunningApp)
        #expect(!swItem.advisory.canBeStaged)

        // Remove SingletonLock -> item becomes stageable by user
        try FileManager.default.removeItem(at: cometRoot.appendingPathComponent("SingletonLock"))
        let unlockedItems = scanner.scanAppSupportCaches(installedIndex: index, runningApps: [], keepList: nil)
        #expect(unlockedItems.first?.advisory.isLockedByRunningApp == false)
        #expect(unlockedItems.first?.advisory.canBeStaged == true)
    }

    @Test("Pairs uninstalled VS Code Application Support + ~/.vscode with granular Safe (.vsix/logs) vs Warning (extensions/User) sub-items")
    func buildsGranularUninstalledIDEOrphanBreakdown() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcleaner-orphan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let codeSupport = tempHome.appendingPathComponent("Library/Application Support/Code", isDirectory: true)
        let vsixCache = codeSupport.appendingPathComponent("CachedExtensionVSIXs", isDirectory: true)
        let userDir = codeSupport.appendingPathComponent("User", isDirectory: true)
        let dotVSCodeExt = tempHome.appendingPathComponent(".vscode/extensions", isDirectory: true)

        try FileManager.default.createDirectory(at: vsixCache, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: userDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dotVSCodeExt, withIntermediateDirectories: true)

        try Data(repeating: 0x11, count: 2_000_000).write(to: vsixCache.appendingPathComponent("ext.vsix"))
        try Data(repeating: 0x22, count: 1_500_000).write(to: userDir.appendingPathComponent("state.vscdb"))
        try Data(repeating: 0x33, count: 2_500_000).write(to: dotVSCodeExt.appendingPathComponent("python.bin"))

        // Antigravity IS installed, VS Code is NOT installed
        let installed = InstalledAppsIndex(
            bundleIDs: ["com.google.antigravity"],
            normalizedNames: ["antigravity"]
        )
        let detector = OrphanedAppDetector(safetyPolicy: SafetyPolicyEngine(homeDirectory: tempHome))
        let orphans = detector.scanOrphans(installedIndex: installed, runningApps: [], keepList: nil)

        #expect(orphans.count == 1)
        let vscodeOrphan = try #require(orphans.first)
        #expect(vscodeOrphan.advisory.level == .warning)
        #expect(vscodeOrphan.subItems.count == 3)

        let vsixSub = try #require(vscodeOrphan.subItems.first { $0.url.lastPathComponent == "CachedExtensionVSIXs" })
        let userSub = try #require(vscodeOrphan.subItems.first { $0.url.lastPathComponent == "User" })
        let extSub = try #require(vscodeOrphan.subItems.first { $0.url.lastPathComponent == "extensions" })

        #expect(vsixSub.advisory.level == .safe)
        #expect(userSub.advisory.level == .warning)
        #expect(userSub.advisory.requiresExplicitAck)
        #expect(extSub.advisory.level == .warning)
        #expect(extSub.advisory.requiresExplicitAck)
    }
}
