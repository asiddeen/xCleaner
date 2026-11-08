import Foundation
import Testing
@testable import XCleanerCore

@Suite("App Uninstaller & Associated Library Scanner Tests")
struct AppUninstallerScannerTests {
    @Test("Discovers installed app bundles and pairs them with caches, support, and preference plists")
    func scansInstalledAppAndAssociatesLibraryFolders() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcleaner-app-uninstaller-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appRoot = tempDir.appendingPathComponent("Applications", isDirectory: true)
        let homeDir = tempDir.appendingPathComponent("Home", isDirectory: true)

        let testAppBundle = appRoot.appendingPathComponent("MockBrowser.app", isDirectory: true)
        let testContents = testAppBundle.appendingPathComponent("Contents", isDirectory: true)
        let testMacOS = testContents.appendingPathComponent("MacOS", isDirectory: true)

        try FileManager.default.createDirectory(at: testMacOS, withIntermediateDirectories: true)

        // Write Info.plist
        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.mock.browser",
            "CFBundleName": "MockBrowser",
            "CFBundleDisplayName": "Mock Browser",
            "CFBundleShortVersionString": "2.4.1"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: testContents.appendingPathComponent("Info.plist"))
        try Data(repeating: 0x01, count: 50_000).write(to: testMacOS.appendingPathComponent("MockBrowser"))

        // Create associated ~/Library folders
        let appSupport = homeDir.appendingPathComponent("Library/Application Support/Mock Browser", isDirectory: true)
        let appCaches = homeDir.appendingPathComponent("Library/Caches/com.mock.browser", isDirectory: true)
        let appPrefs = homeDir.appendingPathComponent("Library/Preferences", isDirectory: true)

        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appCaches, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: appPrefs, withIntermediateDirectories: true)

        try Data(repeating: 0x02, count: 20_000).write(to: appSupport.appendingPathComponent("state.db"))
        try Data(repeating: 0x03, count: 80_000).write(to: appCaches.appendingPathComponent("cache.data"))
        try Data(repeating: 0x04, count: 2_000).write(to: appPrefs.appendingPathComponent("com.mock.browser.plist"))

        let policy = SafetyPolicyEngine(homeDirectory: homeDir)
        let scanner = AppUninstallerScanner(safetyPolicy: policy)

        let apps = scanner.scanInstalledApps(
            applicationRoots: [appRoot],
            runningApps: [],
            keepList: nil
        )

        let browser = try #require(apps.first { $0.bundleID == "com.mock.browser" })
        #expect(browser.displayName == "Mock Browser")
        #expect(browser.version == "2.4.1")
        #expect(browser.isSystemProtected == false)
        #expect(browser.locations.count >= 4) // Bundle + Support + Caches + Prefs

        let safeCaches = browser.locations.filter { $0.category == .safeCacheOrLog }
        #expect(safeCaches.count >= 1)
        #expect(safeCaches.first?.advisory.level == .safe)

        let supportLocations = browser.locations.filter { $0.category == .supportAndContainers }
        #expect(supportLocations.count >= 1)
        #expect(supportLocations.first?.advisory.level == .warning)

        let prefsLocations = browser.locations.filter { $0.category == .preferences }
        #expect(prefsLocations.count >= 1)
        #expect(prefsLocations.first?.advisory.level == .warning)
    }

    @Test("Guards system and Apple bundles from being flagged as uninstallation candidates")
    func protectsSystemAndAppleBundles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcleaner-sys-protect-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let sysApps = tempDir.appendingPathComponent("System/Applications", isDirectory: true)
        let safariBundle = sysApps.appendingPathComponent("Safari.app/Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: safariBundle, withIntermediateDirectories: true)

        let infoPlist: [String: Any] = [
            "CFBundleIdentifier": "com.apple.Safari",
            "CFBundleName": "Safari"
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: infoPlist, format: .xml, options: 0)
        try plistData.write(to: safariBundle.appendingPathComponent("Info.plist"))

        let policy = SafetyPolicyEngine(homeDirectory: tempDir)
        let scanner = AppUninstallerScanner(safetyPolicy: policy)
        let apps = scanner.scanInstalledApps(applicationRoots: [sysApps], runningApps: [], keepList: nil)

        let safari = try #require(apps.first { $0.bundleID == "com.apple.Safari" })
        #expect(safari.isSystemProtected == true)
        #expect(safari.locations.first?.advisory.level == .protected)
    }
}
