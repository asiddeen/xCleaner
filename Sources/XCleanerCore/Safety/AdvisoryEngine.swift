import Foundation

public struct AdvisoryEngine: Sendable {
    public let safetyPolicy: SafetyPolicyEngine

    public init(safetyPolicy: SafetyPolicyEngine = SafetyPolicyEngine()) {
        self.safetyPolicy = safetyPolicy
    }

    public func assessPath(
        url: URL,
        runningApps: [RunningApplicationSnapshot] = [],
        keepList: KeepListStore? = nil,
        projectGradleRefs: [String: [String]] = [:]
    ) -> ItemAdvisory {
        let standardized = url.standardizedFileURL
        let path = standardized.path
        let lowerPath = path.lowercased()
        let name = standardized.lastPathComponent
        let isPinned = keepList?.isPinned(url: standardized) ?? false

        // 1. Hard Protection Check
        let verdict = safetyPolicy.evaluateProtection(for: standardized)
        if verdict.isProtected {
            return ItemAdvisory(
                level: .protected,
                badgeTitle: verdict.reasonTitle ?? "Protected",
                whatIsThis: verdict.explanation ?? "Protected system or user data path.",
                consequenceIfRemoved: "Blocked by xCleaner safety guardrails so macOS, repositories, and credentials stay intact.",
                requiresExplicitAck: false,
                isPinnedByUser: isPinned
            )
        }

        // 2. Knowledge-base heuristics for arbitrary directories/files (used in Visual Explorer & Large Files)
        var baseAdvisory: ItemAdvisory

        if lowerPath.contains("/spotify/persistentcache") || lowerPath.hasSuffix("/application support/spotify") {
            baseAdvisory = ItemAdvisory(
                level: .caution,
                badgeTitle: "Caution • Offline Audio Cache",
                whatIsThis: "Spotify local streaming and downloaded offline music/podcast storage.",
                consequenceIfRemoved: "Removes downloaded offline songs and cached audio streams in Spotify. Pin to Keep if you rely on offline playback."
            )
        } else if lowerPath.contains("/service worker") {
            baseAdvisory = ItemAdvisory(
                level: .caution,
                badgeTitle: "Caution • PWA Service Worker Cache",
                whatIsThis: "Browser Progressive Web App (CacheStorage) offline asset cache.",
                consequenceIfRemoved: "Cookies, logins, bookmarks, and tabs stay untouched, though offline-enabled web apps (e.g. Docs/Canva) will re-sync cached assets."
            )
        } else if name.hasSuffix(".ShipIt") || name.hasSuffix("-updater") {
            baseAdvisory = ItemAdvisory(
                level: .safe,
                badgeTitle: "Safe • Abandoned Auto-Updater",
                whatIsThis: "Leftover Squirrel.Mac or Electron auto-updater staging bundle.",
                consequenceIfRemoved: "Completely safe to remove; does not affect the installed application."
            )
        } else if lowerPath.contains("/.gradle/caches/modules-2") || lowerPath.contains("/.gradle/caches/jars-") {
            baseAdvisory = ItemAdvisory(
                level: .warning,
                badgeTitle: "Warning • Shared Maven Dependencies",
                whatIsThis: "Shared Maven/Gradle dependency JARs and AARs used across all Android & JVM builds.",
                consequenceIfRemoved: "Forces Gradle and Android Studio to re-download gigabytes of Maven dependencies on your next build.",
                requiresExplicitAck: true
            )
        } else if lowerPath.contains("/.gradle/caches/") {
            let ver = extractGradleVersion(from: path)
            if let ver, let projects = projectGradleRefs[ver], !projects.isEmpty {
                let list = projects.joined(separator: ", ")
                baseAdvisory = ItemAdvisory(
                    level: .warning,
                    badgeTitle: "Warning • Used by \(list)",
                    whatIsThis: "Gradle \(ver) build cache actively referenced in gradle-wrapper.properties.",
                    consequenceIfRemoved: "Rebuilding \(list) will re-initialize Gradle \(ver) caches.",
                    requiresExplicitAck: true,
                    referencedByProjects: projects
                )
            } else {
                baseAdvisory = ItemAdvisory(
                    level: .caution,
                    badgeTitle: "Caution • Gradle Build Cache",
                    whatIsThis: "Versioned Gradle build & transform cache.",
                    consequenceIfRemoved: "Safe if this Gradle version is no longer used; otherwise Gradle regenerates it on next build."
                )
            }
        } else if lowerPath.contains("/.npm/_cacache") {
            baseAdvisory = ItemAdvisory(
                level: .caution,
                badgeTitle: "Caution • npm Tarball Cache",
                whatIsThis: "Historical npm package download cache (~/.npm/_cacache).",
                consequenceIfRemoved: "Existing project node_modules are unaffected, though future npm installs will fetch fresh tarballs online."
            )
        } else if lowerPath.contains("/.npm/_npx") {
            baseAdvisory = ItemAdvisory(
                level: .safe,
                badgeTitle: "Safe • Ephemeral npx Cache",
                whatIsThis: "Temporary sandboxes created by one-off npx CLI executions.",
                consequenceIfRemoved: "Safe to remove; npx automatically re-fetches active CLI tools when invoked."
            )
        } else if name == "node_modules" {
            baseAdvisory = ItemAdvisory(
                level: .caution,
                badgeTitle: "Caution • Node Dependencies",
                whatIsThis: "Installed JavaScript/TypeScript project dependencies.",
                consequenceIfRemoved: "Source code is untouched, but you must run npm/pnpm/yarn install before running this project again."
            )
        } else if name == "renv" || lowerPath.contains("/renv/library") {
            baseAdvisory = ItemAdvisory(
                level: .warning,
                badgeTitle: "Warning • R renv Environment",
                whatIsThis: "Project-local R package library managed by renv.",
                consequenceIfRemoved: "Requires running renv::restore(), which may recompile C/C++/Fortran R packages from source.",
                requiresExplicitAck: true
            )
        } else if lowerPath.contains("/library/android/sdk/ndk/") {
            baseAdvisory = ItemAdvisory(
                level: .caution,
                badgeTitle: "Caution • Android NDK Toolchain",
                whatIsThis: "Side-by-side C/C++ Native Development Kit for Android builds.",
                consequenceIfRemoved: "If an Android project pins this exact ndkVersion, Android Studio will need to re-download ~2.4 GB."
            )
        } else if lowerPath.contains("/library/caches/") || lowerPath.contains("/library/logs/") {
            baseAdvisory = ItemAdvisory(
                level: .safe,
                badgeTitle: "Safe • Regenerable Cache / Log",
                whatIsThis: "Application cache or diagnostic log directory.",
                consequenceIfRemoved: "Automatically recreated by the application as needed."
            )
        } else if lowerPath.contains("/downloads/") || lowerPath.contains("/movies/") || lowerPath.contains("/documents/") || lowerPath.contains("/desktop/") {
            baseAdvisory = ItemAdvisory(
                level: .warning,
                badgeTitle: "Warning • Personal User File",
                whatIsThis: "Personal file or folder inside your user workspace.",
                consequenceIfRemoved: "Review carefully before moving to Trash; xCleaner never auto-selects personal files.",
                requiresExplicitAck: true
            )
        } else {
            baseAdvisory = ItemAdvisory(
                level: .caution,
                badgeTitle: "Caution • Manual Review",
                whatIsThis: "User-writable directory or file.",
                consequenceIfRemoved: "Verify whether an application or workflow depends on this item before removing."
            )
        }

        // 3. Running-App Lock Check
        if let lockingApp = RunningLockMatcher.findLockingApp(
            for: standardized,
            runningApps: runningApps,
            homeDirectory: safetyPolicy.homeDirectory
        ) {
            baseAdvisory = baseAdvisory.withRunningLock(
                appName: lockingApp.localizedName,
                bundleID: lockingApp.bundleIdentifier
            )
        }

        // 4. User Pin State
        if isPinned {
            baseAdvisory = baseAdvisory.withPinState(true)
        }

        return baseAdvisory
    }

    private func extractGradleVersion(from path: String) -> String? {
        guard let range = path.range(of: "/.gradle/caches/") else { return nil }
        let suffix = path[range.upperBound...]
        let firstSeg = suffix.split(separator: "/").first.map(String.init) ?? ""
        guard let firstChar = firstSeg.first, firstChar.isNumber else { return nil }
        return firstSeg
    }
}
