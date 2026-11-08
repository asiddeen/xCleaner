import Foundation

public struct JunkRuleRegistry: Sendable {
    public let safetyPolicy: SafetyPolicyEngine

    public init(safetyPolicy: SafetyPolicyEngine = SafetyPolicyEngine()) {
        self.safetyPolicy = safetyPolicy
    }

    private struct StaticCacheRule {
        let id: String
        let title: String
        let relativeHomePath: String
        let domain: JunkDomain
        let level: AdvisoryLevel
        let badgeTitle: String
        let whatIsThis: String
        let consequence: String
        let appName: String?
        let bundleID: String?
    }

    private static let developerAndToolRules: [StaticCacheRule] = [
        StaticCacheRule(
            id: "dev:npm-cacache",
            title: "npm Package Tarball Cache (_cacache)",
            relativeHomePath: ".npm/_cacache",
            domain: .developerCaches,
            level: .caution,
            badgeTitle: "Caution • Historical npm Tarballs",
            whatIsThis: "npm's global archive of previously downloaded package tarballs (~/.npm/_cacache).",
            consequence: "Existing project node_modules continue working normally. Future npm installs will fetch fresh tarballs online.",
            appName: nil,
            bundleID: nil
        ),
        StaticCacheRule(
            id: "dev:npm-npx",
            title: "npm Ephemeral npx Cache (_npx)",
            relativeHomePath: ".npm/_npx",
            domain: .developerCaches,
            level: .safe,
            badgeTitle: "Safe • Ephemeral npx Runs",
            whatIsThis: "Temporary environments created by one-off npx commands (~/.npm/_npx).",
            consequence: "Safe to remove; npx automatically re-downloads CLI tools on next invocation.",
            appName: nil,
            bundleID: nil
        ),
        StaticCacheRule(
            id: "dev:pnpm-store",
            title: "pnpm Content-Addressable Store",
            relativeHomePath: "Library/pnpm/store",
            domain: .developerCaches,
            level: .warning,
            badgeTitle: "Warning • Hard-Linked pnpm Store",
            whatIsThis: "pnpm global package store.",
            consequence: "Prefer running 'pnpm store prune' so unreferenced packages are trimmed without breaking hard-linked node_modules.",
            appName: nil,
            bundleID: nil
        ),
        StaticCacheRule(
            id: "dev:yarn-cache",
            title: "Yarn Package Cache",
            relativeHomePath: "Library/Caches/Yarn",
            domain: .developerCaches,
            level: .caution,
            badgeTitle: "Caution • Yarn Download Cache",
            whatIsThis: "Global Yarn offline tarball cache.",
            consequence: "Existing projects stay intact; future yarn installs fetch online.",
            appName: nil,
            bundleID: nil
        ),
        StaticCacheRule(
            id: "dev:homebrew-cache",
            title: "Homebrew Bottle Download Cache",
            relativeHomePath: "Library/Caches/Homebrew",
            domain: .developerCaches,
            level: .safe,
            badgeTitle: "Safe • Downloaded Brew Bottles",
            whatIsThis: "Already-installed Homebrew formula and cask installer downloads.",
            consequence: "Installed CLI tools and apps are unaffected.",
            appName: nil,
            bundleID: nil
        ),
        StaticCacheRule(
            id: "dev:pip-cache",
            title: "Python pip Wheel Cache",
            relativeHomePath: "Library/Caches/pip",
            domain: .developerCaches,
            level: .safe,
            badgeTitle: "Safe • Python Wheel Cache",
            whatIsThis: "Cached wheel and source archives from pip installs.",
            consequence: "Active virtual environments remain untouched.",
            appName: nil,
            bundleID: nil
        ),
        StaticCacheRule(
            id: "dev:uv-cache",
            title: "Astral uv Package Cache",
            relativeHomePath: ".cache/uv",
            domain: .developerCaches,
            level: .caution,
            badgeTitle: "Caution • uv Wheel & Env Cache",
            whatIsThis: "Global wheel and environment cache for the uv Python manager.",
            consequence: "Future uv runs or tool invocations re-fetch packages if needed.",
            appName: nil,
            bundleID: nil
        ),
        StaticCacheRule(
            id: "dev:cocoapods-cache",
            title: "CocoaPods Spec & Pod Cache",
            relativeHomePath: "Library/Caches/CocoaPods",
            domain: .developerCaches,
            level: .safe,
            badgeTitle: "Safe • CocoaPods Download Cache",
            whatIsThis: "Cached iOS/macOS Pod tarballs.",
            consequence: "Project Pods/ directories are untouched; future pod installs re-download as needed.",
            appName: nil,
            bundleID: nil
        ),
        StaticCacheRule(
            id: "dev:swiftpm-cache",
            title: "Swift Package Manager Cache",
            relativeHomePath: "Library/Caches/org.swift.swiftpm",
            domain: .developerCaches,
            level: .safe,
            badgeTitle: "Safe • SwiftPM Repository Cache",
            whatIsThis: "Cloned git mirrors for Swift Package Manager dependencies.",
            consequence: "Re-fetched automatically on next swift package resolve.",
            appName: nil,
            bundleID: nil
        ),
        StaticCacheRule(
            id: "dev:go-build-cache",
            title: "Go Compiler Build Cache",
            relativeHomePath: "Library/Caches/go-build",
            domain: .developerCaches,
            level: .safe,
            badgeTitle: "Safe • Go Incremental Build Cache",
            whatIsThis: "Compiled Go object cache.",
            consequence: "Next go build takes slightly longer while rebuilding object files.",
            appName: nil,
            bundleID: nil
        ),
        StaticCacheRule(
            id: "dev:xcode-deriveddata",
            title: "Xcode DerivedData",
            relativeHomePath: "Library/Developer/Xcode/DerivedData",
            domain: .developerCaches,
            level: .safe,
            badgeTitle: "Safe • Xcode Build & Index Cache",
            whatIsThis: "Intermediate Xcode build products and symbol indexes.",
            consequence: "Safe when Xcode is closed; Xcode re-indexes on next project open.",
            appName: "Xcode",
            bundleID: "com.apple.dt.Xcode"
        ),
        StaticCacheRule(
            id: "dev:pub-cache",
            title: "Dart / Flutter Pub Cache",
            relativeHomePath: ".pub-cache",
            domain: .developerCaches,
            level: .caution,
            badgeTitle: "Caution • Flutter Pub Packages",
            whatIsThis: "Shared Dart and Flutter package cache (~/.pub-cache).",
            consequence: "Flutter projects require running 'flutter pub get' after removal.",
            appName: nil,
            bundleID: nil
        ),
        StaticCacheRule(
            id: "dev:huggingface-cache",
            title: "HuggingFace Local Model Weights",
            relativeHomePath: ".cache/huggingface",
            domain: .developerCaches,
            level: .warning,
            badgeTitle: "Warning • Large AI Model Weights",
            whatIsThis: "Downloaded HuggingFace Hub ML models and datasets.",
            consequence: "Re-downloading multi-gigabyte LLM/diffusion weights can take substantial bandwidth.",
            appName: nil,
            bundleID: nil
        ),
        StaticCacheRule(
            id: "dev:ollama-models",
            title: "Ollama Local LLM Models",
            relativeHomePath: ".ollama/models",
            domain: .developerCaches,
            level: .warning,
            badgeTitle: "Warning • Local Ollama LLMs",
            whatIsThis: "Downloaded local Large Language Model weights for Ollama.",
            consequence: "Removes pulled Ollama models; requires 'ollama pull' to restore.",
            appName: "Ollama",
            bundleID: "com.electron.ollama"
        ),
        StaticCacheRule(
            id: "dev:antigravity-backup",
            title: "Antigravity Legacy Migration Backup",
            relativeHomePath: ".gemini/antigravity-backup",
            domain: .developerCaches,
            level: .caution,
            badgeTitle: "Caution • Old Migration Backup",
            whatIsThis: "Historical backup snapshot directory (~/.gemini/antigravity-backup), separate from active ~/.gemini/antigravity.",
            consequence: "Removes the old migration backup folder; active Antigravity configuration and brain stay intact.",
            appName: nil,
            bundleID: nil
        )
    ]

    /// Cache folders inside ~/Library/Caches already covered by dedicated developer rules so they are never double-listed.
    private static let dedicatedCacheSubfolders: Set<String> = [
        "Yarn", "Homebrew", "pip", "CocoaPods", "org.swift.swiftpm", "go-build",
        "ms-playwright", "puppeteer", "Cypress",
        "CloudKit", "FamilyCircle", "com.apple.Safari", "com.apple.Safari.SafeBrowsing",
        "com.apple.HomeKit", "com.apple.containermanagerd", "com.apple.homed",
        "com.apple.ap.adprivacyd", "familycircled"
    ]

    public func scanStandardAndDevCaches(
        runningApps: [RunningApplicationSnapshot],
        keepList: KeepListStore?
    ) -> [ScannableItem] {
        let home = safetyPolicy.homeDirectory
        let fm = FileManager.default
        var items: [ScannableItem] = []

        // 1. Evaluate Declarative Developer & AI Rules
        for rule in Self.developerAndToolRules {
            if Task.isCancelled { break }
            let target = home.appendingPathComponent(rule.relativeHomePath).standardizedFileURL
            guard fm.fileExists(atPath: target.path),
                  !safetyPolicy.evaluateProtection(for: target).isProtected else {
                continue
            }
            let fp = ConcurrentDiskScanner.measureFootprint(at: target)
            guard fp.allocatedBytes >= 2_000_000 else { continue }

            let pinned = keepList?.isPinned(url: target) ?? false
            var adv = ItemAdvisory(
                level: rule.level,
                badgeTitle: rule.badgeTitle,
                whatIsThis: rule.whatIsThis,
                consequenceIfRemoved: rule.consequence,
                requiresExplicitAck: rule.level == .warning
            )
            if let lock = RunningLockMatcher.findLockingApp(
                for: target,
                explicitBundleID: rule.bundleID,
                explicitAppName: rule.appName,
                runningApps: runningApps,
                homeDirectory: home
            ) {
                adv = adv.withRunningLock(appName: lock.localizedName, bundleID: lock.bundleIdentifier)
            }
            if pinned { adv = adv.withPinState(true) }

            items.append(
                ScannableItem(
                    id: rule.id,
                    url: target,
                    title: rule.title,
                    subtitle: target.path,
                    domain: rule.domain,
                    allocatedBytes: fp.allocatedBytes,
                    itemCount: fp.itemCount,
                    lastModified: fp.lastModified,
                    associatedAppName: rule.appName,
                    associatedBundleID: rule.bundleID,
                    advisory: adv
                )
            )
        }

        // 2. Scan ~/Library/Caches/* dynamically (surfacing *.ShipIt / *-updater & sizable app caches >= 5 MB)
        let cachesRoot = home.appendingPathComponent("Library/Caches").standardizedFileURL
        if let entries = try? fm.contentsOfDirectory(at: cachesRoot, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            for entry in entries {
                if Task.isCancelled { break }
                let standardized = entry.standardizedFileURL
                let folderName = standardized.lastPathComponent
                if Self.dedicatedCacheSubfolders.contains(folderName) { continue }
                if folderName.hasPrefix("com.apple.") && !folderName.contains("Xcode") {
                    // Skip tiny internal macOS daemon caches so system services never hiccup
                    continue
                }
                if safetyPolicy.evaluateProtection(for: standardized).isProtected { continue }

                let fp = ConcurrentDiskScanner.measureFootprint(at: standardized)
                guard fp.allocatedBytes >= 5_000_000 else { continue }

                let isDeadUpdater = folderName.hasSuffix(".ShipIt") || folderName.hasSuffix("-updater") || folderName.lowercased().contains("updater")
                let pinned = keepList?.isPinned(url: standardized) ?? false

                var adv: ItemAdvisory
                let displayTitle: String
                if isDeadUpdater {
                    displayTitle = "\(folderName) (Abandoned Auto-Updater Staging)"
                    adv = ItemAdvisory(
                        level: .safe,
                        badgeTitle: "Safe • Abandoned Auto-Updater",
                        whatIsThis: "Leftover update staging archive downloaded by Squirrel.Mac / electron-updater.",
                        consequenceIfRemoved: "Completely safe to remove; does not touch your installed application."
                    )
                } else {
                    displayTitle = "\(folderName) Cache"
                    adv = ItemAdvisory(
                        level: .safe,
                        badgeTitle: "Safe • Application Cache",
                        whatIsThis: "Standard macOS user cache folder (~/Library/Caches/\(folderName)).",
                        consequenceIfRemoved: "Recreated automatically by the app; logins and preferences live elsewhere."
                    )
                }

                if !isDeadUpdater, let lock = RunningLockMatcher.findLockingApp(
                    for: standardized,
                    runningApps: runningApps,
                    homeDirectory: home
                ) {
                    adv = adv.withRunningLock(appName: lock.localizedName, bundleID: lock.bundleIdentifier)
                }
                if pinned { adv = adv.withPinState(true) }

                items.append(
                    ScannableItem(
                        url: standardized,
                        title: displayTitle,
                        subtitle: standardized.path,
                        domain: .systemAndAppCaches,
                        allocatedBytes: fp.allocatedBytes,
                        itemCount: fp.itemCount,
                        lastModified: fp.lastModified,
                        advisory: adv
                    )
                )
            }
        }

        // 3. Scan ~/Library/Logs/* (>= 5 MB)
        let logsRoot = home.appendingPathComponent("Library/Logs").standardizedFileURL
        if let logEntries = try? fm.contentsOfDirectory(at: logsRoot, includingPropertiesForKeys: nil, options: []) {
            for entry in logEntries {
                if Task.isCancelled { break }
                let standardized = entry.standardizedFileURL
                if safetyPolicy.evaluateProtection(for: standardized).isProtected { continue }
                let fp = ConcurrentDiskScanner.measureFootprint(at: standardized)
                guard fp.allocatedBytes >= 5_000_000 else { continue }
                let pinned = keepList?.isPinned(url: standardized) ?? false
                let adv = ItemAdvisory(
                    level: .safe,
                    badgeTitle: "Safe • Diagnostic Logs",
                    whatIsThis: "Historical text logs and crash diagnostics in ~/Library/Logs/\(standardized.lastPathComponent).",
                    consequenceIfRemoved: "Safe to clear unless you are actively debugging an old crash."
                ).withPinState(pinned)

                items.append(
                    ScannableItem(
                        url: standardized,
                        title: "\(standardized.lastPathComponent) Logs",
                        subtitle: standardized.path,
                        domain: .systemAndAppCaches,
                        allocatedBytes: fp.allocatedBytes,
                        itemCount: fp.itemCount,
                        lastModified: fp.lastModified,
                        advisory: adv
                    )
                )
            }
        }

        return items.sorted { $0.allocatedBytes > $1.allocatedBytes }
    }
}
