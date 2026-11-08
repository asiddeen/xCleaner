import Foundation
import Testing
@testable import XCleanerCore

@Suite("Safety Policy & 4-Tier Advisory Engine")
struct SafetyAndAdvisoryEngineTests {
    @Test("Blocks macOS system roots, credentials, .git repos, cloud mounts, browser logins, and raw VM disks")
    func blocksHardProtectedPaths() throws {
        let fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcleaner-safety-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: fakeHome) }
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)

        let engine = SafetyPolicyEngine(homeDirectory: fakeHome)

        let protectedURLs: [URL] = [
            URL(fileURLWithPath: "/"),
            URL(fileURLWithPath: "/System/Library/Kernels"),
            URL(fileURLWithPath: "/Applications/Safari.app"),
            URL(fileURLWithPath: "/private/var/vm/sleepimage"),
            fakeHome,
            fakeHome.appendingPathComponent("Documents"),
            fakeHome.appendingPathComponent("Projects"),
            fakeHome.appendingPathComponent(".ssh/id_ed25519"),
            fakeHome.appendingPathComponent(".gnupg/secring.gpg"),
            fakeHome.appendingPathComponent(".aws/credentials"),
            fakeHome.appendingPathComponent(".kube/config"),
            fakeHome.appendingPathComponent(".gemini/oauth_creds.json"),
            fakeHome.appendingPathComponent("Projects/MamaCare/.git/objects"),
            fakeHome.appendingPathComponent("Keys/prod-server.pem"),
            fakeHome.appendingPathComponent("Keys/signing.keystore"),
            fakeHome.appendingPathComponent("Library/Keychains/login.keychain-db"),
            fakeHome.appendingPathComponent("Library/Preferences/com.apple.Finder.plist"),
            fakeHome.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Contract.pdf"),
            fakeHome.appendingPathComponent("Library/CloudStorage/GoogleDrive-user@gmail.com/My Drive/Tax.xlsx"),
            fakeHome.appendingPathComponent("Library/Application Support/MobileSync/Backup/device1"),
            fakeHome.appendingPathComponent("Library/Application Support/Comet/Default/Cookies"),
            fakeHome.appendingPathComponent("Library/Application Support/Comet/Default/Login Data"),
            fakeHome.appendingPathComponent("Library/Application Support/Google/Chrome/Default/Local Storage/leveldb"),
            fakeHome.appendingPathComponent("Library/Application Support/Google/Chrome/Default/IndexedDB"),
            fakeHome.appendingPathComponent("Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw"),
            fakeHome.appendingPathComponent("Library/Application Support/xCleaner/keep-list.json")
        ]

        for url in protectedURLs {
            let verdict = engine.evaluateProtection(for: url)
            #expect(verdict.isProtected, "Expected \(url.path) to be strictly protected")
        }

        // Allowed cache & artifact paths
        let allowedURLs: [URL] = [
            fakeHome.appendingPathComponent("Library/Caches/com.github.GitHubClient.ShipIt"),
            fakeHome.appendingPathComponent("Library/Application Support/Comet/Default/Service Worker/CacheStorage"),
            fakeHome.appendingPathComponent("Library/Application Support/Spotify/PersistentCache"),
            fakeHome.appendingPathComponent("Projects/MamaCare/node_modules"),
            fakeHome.appendingPathComponent(".gradle/caches/8.10.2"),
            fakeHome.appendingPathComponent(".npm/_cacache")
        ]

        for url in allowedURLs {
            let verdict = engine.evaluateProtection(for: url)
            #expect(!verdict.isProtected, "Expected \(url.path) to be user-reviewable, not hard-blocked")
        }
    }

    @Test("Blocks symlink inside cache directory pointing to protected ~/.ssh")
    func blocksSymlinkEscapingToProtectedTarget() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcleaner-symlink-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let sshDir = tempRoot.appendingPathComponent(".ssh", isDirectory: true)
        let cachesDir = tempRoot.appendingPathComponent("Library/Caches/EvilCache", isDirectory: true)
        try FileManager.default.createDirectory(at: sshDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cachesDir.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: cachesDir, withDestinationURL: sshDir)

        let engine = SafetyPolicyEngine(homeDirectory: tempRoot)
        let verdict = engine.evaluateProtection(for: cachesDir)
        #expect(verdict.isProtected)
    }

    @Test("KeepListStore pinning, Select-Safe invariants, Warning explicit-ack, and Running-App lock")
    func advisoryTiersPinningAndRunningLocks() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcleaner-advisory-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)

        let keepURL = tempRoot.appendingPathComponent("keep-list.json")
        let keepStore = KeepListStore(storageURL: keepURL)
        let safety = SafetyPolicyEngine(homeDirectory: tempRoot)
        let advisoryEngine = AdvisoryEngine(safetyPolicy: safety)

        // 1. Safe item is auto-safe candidate until pinned or locked
        let shipItURL = tempRoot.appendingPathComponent("Library/Caches/com.github.GitHubClient.ShipIt")
        let safeAdv = advisoryEngine.assessPath(url: shipItURL, keepList: keepStore)
        #expect(safeAdv.level == .safe)
        #expect(safeAdv.isAutoSafeCandidate)
        #expect(!safeAdv.requiresExplicitAck)

        // 2. Caution item (Spotify offline cache) is NOT an auto-safe candidate, and can be pinned by user
        let spotifyURL = tempRoot.appendingPathComponent("Library/Application Support/Spotify/PersistentCache")
        let spotifyUnpinned = advisoryEngine.assessPath(url: spotifyURL, keepList: keepStore)
        #expect(spotifyUnpinned.level == .caution)
        #expect(!spotifyUnpinned.isAutoSafeCandidate)
        #expect(spotifyUnpinned.canBeStaged)

        keepStore.pin(url: spotifyURL, label: "Spotify Offline Songs")
        // Reload from disk to verify persistence
        let reloadedKeepStore = KeepListStore(storageURL: keepURL)
        #expect(reloadedKeepStore.isPinned(url: spotifyURL))

        let spotifyPinned = advisoryEngine.assessPath(url: spotifyURL, keepList: reloadedKeepStore)
        #expect(spotifyPinned.isPinnedByUser)
        #expect(!spotifyPinned.canBeStaged)
        #expect(!spotifyPinned.isAutoSafeCandidate)

        // 3. Warning item (Gradle version referenced by active project) requires explicit user acknowledgment
        let gradleRefURL = tempRoot.appendingPathComponent(".gradle/caches/8.14.5")
        let warnAdv = advisoryEngine.assessPath(
            url: gradleRefURL,
            keepList: reloadedKeepStore,
            projectGradleRefs: ["8.14.5": ["ComBIP"]]
        )
        #expect(warnAdv.level == .warning)
        #expect(warnAdv.requiresExplicitAck)
        #expect(warnAdv.referencedByProjects == ["ComBIP"])
        #expect(!warnAdv.isAutoSafeCandidate)

        // 4. Running app lock prevents staging
        let chromeCacheURL = tempRoot.appendingPathComponent("Library/Caches/com.google.Chrome")
        let runningChrome = [RunningApplicationSnapshot(bundleIdentifier: "com.google.Chrome", localizedName: "Google Chrome")]
        let lockedAdv = advisoryEngine.assessPath(url: chromeCacheURL, runningApps: runningChrome)
        #expect(lockedAdv.isLockedByRunningApp)
        #expect(lockedAdv.lockedByAppName == "Google Chrome")
        #expect(!lockedAdv.canBeStaged)
        #expect(!lockedAdv.isAutoSafeCandidate)
    }
}
