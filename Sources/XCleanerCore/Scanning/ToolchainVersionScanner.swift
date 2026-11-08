import Foundation

public struct SemanticVersionKey: Comparable, Sendable, Equatable {
    public let numbers: [Int]
    public let prereleaseTag: String?
    public let raw: String

    public init(_ raw: String) {
        self.raw = raw
        // Strip leading non-digits like "v" or "android-" or "mac_arm-"
        var cleaned = raw
        if let firstDigitIdx = cleaned.firstIndex(where: \.isNumber) {
            cleaned = String(cleaned[firstDigitIdx...])
        }
        let parts = cleaned.split(separator: "-", maxSplits: 1).map(String.init)
        let numericPart = parts.first ?? ""
        self.numbers = numericPart
            .split(whereSeparator: { $0 == "." || $0 == "_" })
            .map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        self.prereleaseTag = parts.count > 1 ? parts[1].lowercased() : nil
    }

    public var isPrereleaseOrPreview: Bool {
        let lower = raw.lowercased()
        if lower.contains("-rc") || lower.contains("-alpha") || lower.contains("-beta") ||
            lower.contains("preview") || lower.contains("privacysandbox") || lower.contains("canary") {
            return true
        }
        if let tag = prereleaseTag, !tag.isEmpty {
            return true
        }
        return false
    }

    public static func < (lhs: SemanticVersionKey, rhs: SemanticVersionKey) -> Bool {
        let maxCount = max(lhs.numbers.count, rhs.numbers.count)
        for idx in 0..<maxCount {
            let lVal = idx < lhs.numbers.count ? lhs.numbers[idx] : 0
            let rVal = idx < rhs.numbers.count ? rhs.numbers[idx] : 0
            if lVal != rVal {
                return lVal < rVal
            }
        }
        // Stable > prerelease for identical numeric tuple
        switch (lhs.prereleaseTag, rhs.prereleaseTag) {
        case (nil, nil):
            return lhs.raw < rhs.raw
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case let (.some(lTag), .some(rTag)):
            return lTag < rTag
        }
    }
}

public struct ToolchainVersionScanner: Sendable {
    public let safetyPolicy: SafetyPolicyEngine
    public let environment: [String: String]

    public init(
        safetyPolicy: SafetyPolicyEngine = SafetyPolicyEngine(),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.safetyPolicy = safetyPolicy
        self.environment = environment
    }

    public func scanAllToolchains(
        projectReferences: ProjectToolchainReferences = ProjectToolchainReferences(),
        keepList: KeepListStore? = nil
    ) -> [ToolchainItem] {
        var items: [ToolchainItem] = []
        items.append(contentsOf: scanGradle(projectReferences: projectReferences, keepList: keepList))
        items.append(contentsOf: scanAndroidSDK(keepList: keepList))
        items.append(contentsOf: scanNodeNVM(projectReferences: projectReferences, keepList: keepList))
        items.append(contentsOf: scanPuppeteerBrowsers(keepList: keepList))
        return items
    }

    // MARK: - Defense-in-Depth Default/Current Version Guard (Shared with SafetyPolicyEngine)

    public static func evaluateDefaultToolchainProtection(
        for standardizedPath: String,
        homeDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> ProtectionVerdict? {
        let homePath = homeDirectory.standardizedFileURL.path

        // Prevent whole-container deletion of active toolchain roots in Visual Explorer
        let protectedToolchainContainers: Set<String> = [
            "\(homePath)/.nvm",
            "\(homePath)/.nvm/versions",
            "\(homePath)/.nvm/versions/node",
            "\(homePath)/.gradle",
            "\(homePath)/.gradle/caches",
            "\(homePath)/.gradle/wrapper",
            "\(homePath)/.gradle/wrapper/dists",
            "\(homePath)/Library/Android/sdk",
            "\(homePath)/Library/Android/sdk/ndk",
            "\(homePath)/Library/Android/sdk/build-tools",
            "\(homePath)/Library/Android/sdk/platforms",
            "\(homePath)/Library/Android/sdk/system-images",
            "\(homePath)/.cache/puppeteer",
            "\(homePath)/Library/Caches/ms-playwright"
        ]
        if protectedToolchainContainers.contains(standardizedPath) {
            return .blocked(
                title: "Toolchain Root Directory Protected",
                explanation: "Contains active/default SDK or runtime versions. Drill inside or use Toolchains & Docker to remove older side-by-side versions."
            )
        }

        let prefixes = [
            "\(homePath)/.gradle/caches/",
            "\(homePath)/.gradle/wrapper/dists/",
            "\(homePath)/Library/Android/sdk/",
            "\(homePath)/.nvm/versions/node/",
            "\(homePath)/.cache/puppeteer/",
            "\(homePath)/Library/Caches/ms-playwright/"
        ]
        guard prefixes.contains(where: { standardizedPath.hasPrefix($0) }) else {
            return nil
        }

        let lockedPaths = lockedDefaultOrCurrentPaths(homeDirectory: homeDirectory, environment: environment)
        for locked in lockedPaths {
            if standardizedPath == locked || standardizedPath.hasPrefix(locked + "/") {
                return .blocked(
                    title: "Current / Default Version Locked",
                    explanation: "Removal of your default or current toolchain/runtime version is disabled so active builds and CLI tools never break."
                )
            }
        }
        return nil
    }

    public static func lockedDefaultOrCurrentPaths(
        homeDirectory: URL,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Set<String> {
        let home = homeDirectory.standardizedFileURL
        let fm = FileManager.default
        var locked = Set<String>()

        // 1. Gradle current / latest stable
        let gradleMap = discoverGradleVersionURLs(home: home, fm: fm)
        let sortedGradle = gradleMap.keys.sorted { SemanticVersionKey($0) > SemanticVersionKey($1) }
        let lockedGradleVers = resolveLockedGradleVersions(
            sortedVersions: sortedGradle,
            home: home,
            environment: environment
        )
        for ver in lockedGradleVers {
            for u in gradleMap[ver] ?? [] {
                locked.insert(u.standardizedFileURL.path)
            }
        }

        // 2. Android SDK latest stable per family
        let sdkRoot = home.appendingPathComponent("Library/Android/sdk").standardizedFileURL
        for subdir in ["ndk", "build-tools", "platforms", "system-images"] {
            let dir = sdkRoot.appendingPathComponent(subdir)
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
                continue
            }
            let validDirs = entries.filter {
                !$0.lastPathComponent.hasPrefix(".") &&
                ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
            }
            let sorted = validDirs.sorted {
                SemanticVersionKey($0.lastPathComponent) > SemanticVersionKey($1.lastPathComponent)
            }
            if let latestStable = sorted.first(where: { !SemanticVersionKey($0.lastPathComponent).isPrereleaseOrPreview }) ?? sorted.first {
                locked.insert(latestStable.standardizedFileURL.path)
            }
        }

        // 3. Node.js (nvm) default alias / current active / fallback latest stable
        let nvmRoot = home.appendingPathComponent(".nvm").standardizedFileURL
        let nvmVersionsDir = nvmRoot.appendingPathComponent("versions/node")
        if let entries = try? fm.contentsOfDirectory(at: nvmVersionsDir, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            let dirs = entries.filter { !$0.lastPathComponent.hasPrefix(".") }
            let sortedNames = dirs
                .map(\.lastPathComponent)
                .sorted { SemanticVersionKey($0) > SemanticVersionKey($1) }
            let nodeLocks = resolveLockedNodeVersions(
                nvmRoot: nvmRoot,
                sortedInstalledVersions: sortedNames,
                environment: environment
            )
            for ver in nodeLocks.allLocked {
                locked.insert(nvmVersionsDir.appendingPathComponent(ver).standardizedFileURL.path)
            }
        }

        // 4. Puppeteer latest installed revision
        let puppeteerRoot = home.appendingPathComponent(".cache/puppeteer").standardizedFileURL
        var puppeteerByVer: [String: [URL]] = [:]
        for channel in ["chrome", "chrome-headless-shell"] {
            let chanDir = puppeteerRoot.appendingPathComponent(channel)
            if let entries = try? fm.contentsOfDirectory(at: chanDir, includingPropertiesForKeys: nil, options: []) {
                for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
                    puppeteerByVer[entry.lastPathComponent, default: []].append(entry.standardizedFileURL)
                }
            }
        }
        let sortedPup = puppeteerByVer.keys.sorted { SemanticVersionKey($0) > SemanticVersionKey($1) }
        if let latestPup = sortedPup.first {
            for u in puppeteerByVer[latestPup] ?? [] {
                locked.insert(u.path)
            }
        }

        // 5. Playwright latest revision per browser family
        let playwrightRoot = home.appendingPathComponent("Library/Caches/ms-playwright").standardizedFileURL
        if let entries = try? fm.contentsOfDirectory(at: playwrightRoot, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            var byFamily: [String: [URL]] = [:]
            for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
                let (family, _) = parsePlaywrightFamilyAndRevision(entry.lastPathComponent)
                byFamily[family, default: []].append(entry.standardizedFileURL)
            }
            for (_, familyURLs) in byFamily {
                let sortedFam = familyURLs.sorted {
                    SemanticVersionKey(parsePlaywrightFamilyAndRevision($0.lastPathComponent).revision) >
                    SemanticVersionKey(parsePlaywrightFamilyAndRevision($1.lastPathComponent).revision)
                }
                if let latestFam = sortedFam.first {
                    locked.insert(latestFam.path)
                }
            }
        }

        return locked
    }

    // MARK: - 1. Gradle (~/.gradle)

    private static func discoverGradleVersionURLs(home: URL, fm: FileManager) -> [String: [URL]] {
        let gradleRoot = home.appendingPathComponent(".gradle").standardizedFileURL
        guard fm.fileExists(atPath: gradleRoot.path) else { return [:] }

        let cachesDir = gradleRoot.appendingPathComponent("caches")
        let distsDir = gradleRoot.appendingPathComponent("wrapper/dists")

        var wrapperByVersion: [String: [URL]] = [:]
        if let distEntries = try? fm.contentsOfDirectory(at: distsDir, includingPropertiesForKeys: nil, options: []) {
            for entry in distEntries {
                let name = entry.lastPathComponent
                guard name.hasPrefix("gradle-") else { continue }
                let afterPrefix = String(name.dropFirst("gradle-".count))
                let ver: String
                if let r = afterPrefix.range(of: "-bin") ?? afterPrefix.range(of: "-all") {
                    ver = String(afterPrefix[..<r.lowerBound])
                } else {
                    ver = afterPrefix
                }
                if ver.first?.isNumber == true {
                    wrapperByVersion[ver, default: []].append(entry.standardizedFileURL)
                }
            }
        }

        var versionURLs: [String: [URL]] = wrapperByVersion
        if let cacheEntries = try? fm.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            for entry in cacheEntries {
                let name = entry.lastPathComponent
                if let first = name.first, first.isNumber {
                    versionURLs[name, default: []].insert(entry.standardizedFileURL, at: 0)
                }
            }
        }
        return versionURLs
    }

    private static func resolveLockedGradleVersions(
        sortedVersions: [String],
        home: URL,
        environment: [String: String]
    ) -> Set<String> {
        var locked = Set<String>()
        if let latestStable = sortedVersions.first(where: { !SemanticVersionKey($0).isPrereleaseOrPreview }) ?? sortedVersions.first {
            locked.insert(latestStable)
        }
        // Check SDKMAN ~/.sdkman/candidates/gradle/current symlink if present
        let sdkmanCurrent = home.appendingPathComponent(".sdkman/candidates/gradle/current")
        if FileManager.default.fileExists(atPath: sdkmanCurrent.path) {
            let resolvedVer = sdkmanCurrent.resolvingSymlinksInPath().lastPathComponent
            if sortedVersions.contains(resolvedVer) {
                locked.insert(resolvedVer)
            }
        }
        if let gradleHome = environment["GRADLE_HOME"], !gradleHome.isEmpty {
            let candidate = URL(fileURLWithPath: gradleHome).resolvingSymlinksInPath().lastPathComponent
                .replacingOccurrences(of: "gradle-", with: "")
            if sortedVersions.contains(candidate) {
                locked.insert(candidate)
            }
        }
        return locked
    }

    public func scanGradle(
        projectReferences: ProjectToolchainReferences,
        keepList: KeepListStore?
    ) -> [ToolchainItem] {
        let home = safetyPolicy.homeDirectory
        let gradleRoot = home.appendingPathComponent(".gradle").standardizedFileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: gradleRoot.path) else { return [] }

        var results: [ToolchainItem] = []
        let cachesDir = gradleRoot.appendingPathComponent("caches")
        let versionURLs = Self.discoverGradleVersionURLs(home: home, fm: fm)

        let sortedVersions = versionURLs.keys.sorted { SemanticVersionKey($0) > SemanticVersionKey($1) }
        let lockedVersions = Self.resolveLockedGradleVersions(
            sortedVersions: sortedVersions,
            home: home,
            environment: environment
        )

        for ver in sortedVersions {
            guard let urls = versionURLs[ver], !urls.isEmpty else { continue }
            var totalBytes: Int64 = 0
            var latestMod: Date?
            for u in urls {
                let fp = ConcurrentDiskScanner.measureFootprint(at: u)
                totalBytes += fp.allocatedBytes
                if let m = fp.lastModified, (latestMod == nil || m > latestMod!) { latestMod = m }
            }
            guard totalBytes > 0 else { continue }

            let pinned = keepList?.isPinned(urls: urls) ?? false
            let referencingProjects = projectReferences.gradleVersionsToProjects[ver] ?? []

            let status: ToolchainVersionStatus
            let advisory: ItemAdvisory

            if lockedVersions.contains(ver) {
                status = .activeOrLatest
                advisory = ItemAdvisory(
                    level: .protected,
                    badgeTitle: "Current / Default • Locked",
                    whatIsThis: "Current / latest installed Gradle runtime & cache (\(ver)).",
                    consequenceIfRemoved: "Removal of your current/default Gradle version is disabled so active builds never break.",
                    requiresExplicitAck: false,
                    referencedByProjects: referencingProjects,
                    isPinnedByUser: false
                )
            } else if !referencingProjects.isEmpty {
                let projList = referencingProjects.joined(separator: ", ")
                status = .referencedByProject
                advisory = ItemAdvisory(
                    level: .warning,
                    badgeTitle: "Warning • Used by \(projList)",
                    whatIsThis: "Gradle \(ver) distribution and task cache actively referenced in gradle-wrapper.properties (\(projList)).",
                    consequenceIfRemoved: "Next build of \(projList) will re-download Gradle \(ver) and rebuild transform caches.",
                    requiresExplicitAck: true,
                    referencedByProjects: referencingProjects,
                    isPinnedByUser: pinned
                ).withPinState(pinned)
            } else {
                status = .superseded
                advisory = ItemAdvisory(
                    level: .caution,
                    badgeTitle: "Caution • Older Unreferenced Version",
                    whatIsThis: "Gradle \(ver) cache & wrapper distribution not referenced by scanned project wrappers.",
                    consequenceIfRemoved: "Safe to remove if you upgraded past Gradle \(ver); automatically re-downloaded if an older repo requests it.",
                    isPinnedByUser: pinned
                ).withPinState(pinned)
            }

            results.append(
                ToolchainItem(
                    id: "gradle:ver:\(ver)",
                    ecosystem: .gradle,
                    componentKind: "Gradle Version Cache + Wrapper",
                    version: ver,
                    urls: urls,
                    allocatedBytes: totalBytes,
                    lastModified: latestMod,
                    status: status,
                    advisory: advisory
                )
            )
        }

        // Shared Gradle Dependency Caches (modules-2, jars-9, transforms-*)
        let sharedCacheNames = ["modules-2", "jars-9", "transforms-3", "transforms-4"]
        var sharedURLs: [URL] = []
        var sharedBytes: Int64 = 0
        var sharedMod: Date?
        for name in sharedCacheNames {
            let u = cachesDir.appendingPathComponent(name).standardizedFileURL
            if fm.fileExists(atPath: u.path) {
                let fp = ConcurrentDiskScanner.measureFootprint(at: u)
                if fp.allocatedBytes > 0 {
                    sharedURLs.append(u)
                    sharedBytes += fp.allocatedBytes
                    if let m = fp.lastModified, (sharedMod == nil || m > sharedMod!) { sharedMod = m }
                }
            }
        }
        if sharedBytes >= 5_000_000 {
            let pinned = keepList?.isPinned(urls: sharedURLs) ?? false
            let adv = ItemAdvisory(
                level: .warning,
                badgeTitle: "Warning • Shared Maven/Android JARs",
                whatIsThis: "Shared Maven artifact cache (modules-2 & jars-9) used across all Gradle versions.",
                consequenceIfRemoved: "Every Android/JVM project will re-download gigabytes of Maven dependencies on next build.",
                requiresExplicitAck: true,
                isPinnedByUser: pinned
            ).withPinState(pinned)
            results.append(
                ToolchainItem(
                    id: "gradle:shared-modules",
                    ecosystem: .gradle,
                    componentKind: "Shared Maven Artifacts",
                    version: "modules-2 & jars",
                    urls: sharedURLs,
                    allocatedBytes: sharedBytes,
                    lastModified: sharedMod,
                    status: .sharedCoreCache,
                    advisory: adv
                )
            )
        }

        // Leftover JDK archives (*.tar.gz, *.zip, *.part) inside ~/.gradle/jdks & daemon logs
        let jdksDir = gradleRoot.appendingPathComponent("jdks")
        var archiveURLs: [URL] = []
        var archiveBytes: Int64 = 0
        var archiveMod: Date?
        if let jdkEntries = try? fm.contentsOfDirectory(at: jdksDir, includingPropertiesForKeys: nil, options: []) {
            for entry in jdkEntries {
                let name = entry.lastPathComponent.lowercased()
                if name.hasSuffix(".tar.gz") || name.hasSuffix(".zip") || name.hasSuffix(".part") || name.hasSuffix(".lock") {
                    if name.hasSuffix(".lock") { continue }
                    let fp = ConcurrentDiskScanner.measureFootprint(at: entry)
                    if fp.allocatedBytes > 0 {
                        archiveURLs.append(entry.standardizedFileURL)
                        archiveBytes += fp.allocatedBytes
                        if let m = fp.lastModified, (archiveMod == nil || m > archiveMod!) { archiveMod = m }
                    }
                }
            }
        }
        if archiveBytes >= 1_000_000 {
            let pinned = keepList?.isPinned(urls: archiveURLs) ?? false
            let adv = ItemAdvisory(
                level: .safe,
                badgeTitle: "Safe • Leftover JDK Tarballs & .part Files",
                whatIsThis: "Uncleaned .tar.gz archives and interrupted .part downloads in ~/.gradle/jdks (extracted JDK folders are untouched).",
                consequenceIfRemoved: "Completely safe to remove; extracted JDK toolchains continue working normally.",
                isPinnedByUser: pinned
            ).withPinState(pinned)
            results.append(
                ToolchainItem(
                    id: "gradle:jdk-archives",
                    ecosystem: .gradle,
                    componentKind: "Leftover JDK Archives",
                    version: "\(archiveURLs.count) archive(s)",
                    urls: archiveURLs,
                    allocatedBytes: archiveBytes,
                    lastModified: archiveMod,
                    status: .leftoverArchive,
                    advisory: adv
                )
            )
        }

        let daemonDir = gradleRoot.appendingPathComponent("daemon").standardizedFileURL
        if fm.fileExists(atPath: daemonDir.path) {
            let fp = ConcurrentDiskScanner.measureFootprint(at: daemonDir)
            if fp.allocatedBytes >= 5_000_000 {
                let pinned = keepList?.isPinned(url: daemonDir) ?? false
                let adv = ItemAdvisory(
                    level: .safe,
                    badgeTitle: "Safe • Historical Daemon Logs",
                    whatIsThis: "Old Gradle daemon stdout/stderr log files (~/.gradle/daemon).",
                    consequenceIfRemoved: "Safe to remove when no Gradle build is actively running.",
                    isPinnedByUser: pinned
                ).withPinState(pinned)
                results.append(
                    ToolchainItem(
                        id: "gradle:daemon-logs",
                        ecosystem: .gradle,
                        componentKind: "Daemon Logs",
                        version: "daemon",
                        urls: [daemonDir],
                        allocatedBytes: fp.allocatedBytes,
                        lastModified: fp.lastModified,
                        status: .leftoverArchive,
                        advisory: adv
                    )
                )
            }
        }

        return results.sorted { $0.allocatedBytes > $1.allocatedBytes }
    }

    // MARK: - 2. Android SDK (~/Library/Android/sdk)

    public func scanAndroidSDK(keepList: KeepListStore?) -> [ToolchainItem] {
        let sdkRoot = safetyPolicy.homeDirectory.appendingPathComponent("Library/Android/sdk").standardizedFileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: sdkRoot.path) else { return [] }

        var results: [ToolchainItem] = []
        let families: [(subdir: String, label: String)] = [
            ("ndk", "Android NDK (C++/Rust Native Kit)"),
            ("build-tools", "Android SDK Build-Tools"),
            ("platforms", "Android API Platform"),
            ("system-images", "Emulator System Image")
        ]

        for family in families {
            let dir = sdkRoot.appendingPathComponent(family.subdir)
            guard let entries = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
                continue
            }
            let validDirs = entries.filter {
                !$0.lastPathComponent.hasPrefix(".") &&
                ((try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true)
            }
            guard !validDirs.isEmpty else { continue }

            let sorted = validDirs.sorted {
                SemanticVersionKey($0.lastPathComponent) > SemanticVersionKey($1.lastPathComponent)
            }
            let latestStable = sorted.first { !SemanticVersionKey($0.lastPathComponent).isPrereleaseOrPreview } ?? sorted.first

            for entry in sorted {
                let standardized = entry.standardizedFileURL
                let verName = standardized.lastPathComponent
                let verKey = SemanticVersionKey(verName)
                let fp = ConcurrentDiskScanner.measureFootprint(at: standardized)
                guard fp.allocatedBytes >= 1_000_000 else { continue }

                let pinned = keepList?.isPinned(url: standardized) ?? false
                let status: ToolchainVersionStatus
                let adv: ItemAdvisory

                if standardized == latestStable?.standardizedFileURL {
                    status = .activeOrLatest
                    adv = ItemAdvisory(
                        level: .protected,
                        badgeTitle: "Current Stable • Locked",
                        whatIsThis: "Current/latest installed stable \(family.label) (\(verName)).",
                        consequenceIfRemoved: "Removal of the current stable \(family.subdir) version is disabled to protect active Android builds.",
                        requiresExplicitAck: false,
                        isPinnedByUser: false
                    )
                } else if verKey.isPrereleaseOrPreview {
                    status = .releaseCandidateOrPreview
                    adv = ItemAdvisory(
                        level: .caution,
                        badgeTitle: "Caution • Preview / RC Build",
                        whatIsThis: "\(family.label) (\(verName)) is a pre-release, release candidate, or preview SDK.",
                        consequenceIfRemoved: "Safe to remove once stable SDK versions are installed, unless testing preview APIs.",
                        isPinnedByUser: pinned
                    ).withPinState(pinned)
                } else {
                    status = .superseded
                    adv = ItemAdvisory(
                        level: .caution,
                        badgeTitle: "Caution • Side-by-Side Older Version",
                        whatIsThis: "Older \(family.label) (\(verName)) installed alongside current \(latestStable?.lastPathComponent ?? "version").",
                        consequenceIfRemoved: "Check build.gradle (ndkVersion / compileSdk) first; Android Studio re-downloads automatically if a project pins \(verName).",
                        isPinnedByUser: pinned
                    ).withPinState(pinned)
                }

                results.append(
                    ToolchainItem(
                        id: "android:\(family.subdir):\(verName)",
                        ecosystem: .androidSDK,
                        componentKind: family.label,
                        version: verName,
                        urls: [standardized],
                        allocatedBytes: fp.allocatedBytes,
                        lastModified: fp.lastModified,
                        status: status,
                        advisory: adv
                    )
                )
            }
        }

        return results.sorted { $0.allocatedBytes > $1.allocatedBytes }
    }

    // MARK: - 3. Node.js via nvm (~/.nvm/versions/node)

    public struct NodeLockResolution: Sendable, Equatable {
        public let defaultAliasVersion: String?
        public let currentActiveVersion: String?
        public let fallbackLatestVersion: String?

        public var allLocked: Set<String> {
            var set = Set<String>()
            if let d = defaultAliasVersion { set.insert(d) }
            if let c = currentActiveVersion { set.insert(c) }
            if set.isEmpty, let f = fallbackLatestVersion { set.insert(f) }
            return set
        }
    }

    public static func resolveLockedNodeVersions(
        nvmRoot: URL,
        sortedInstalledVersions: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> NodeLockResolution {
        guard !sortedInstalledVersions.isEmpty else {
            return NodeLockResolution(defaultAliasVersion: nil, currentActiveVersion: nil, fallbackLatestVersion: nil)
        }

        let latestStable = sortedInstalledVersions.first { !SemanticVersionKey($0).isPrereleaseOrPreview } ?? sortedInstalledVersions.first

        // 1. Resolve ~/.nvm/alias/default (supports direct prefixes like "22", "v20.17.0", and indirect alias chains like "lts/*" -> "lts/jod" -> "v22.14.0")
        let defaultResolved = resolveNVMAliasChain(
            nvmRoot: nvmRoot,
            initialAliasName: "default",
            sortedInstalledVersions: sortedInstalledVersions,
            latestStable: latestStable
        )

        // 2. Resolve active current runtime from NVM_BIN or ~/.nvm/current symlink
        var currentActive: String?
        if let nvmBin = environment["NVM_BIN"], !nvmBin.isEmpty {
            let candidate = URL(fileURLWithPath: nvmBin).deletingLastPathComponent().lastPathComponent
            if sortedInstalledVersions.contains(candidate) {
                currentActive = candidate
            }
        }
        if currentActive == nil {
            let currentSymlink = nvmRoot.appendingPathComponent("current")
            if FileManager.default.fileExists(atPath: currentSymlink.path) {
                let candidate = currentSymlink.resolvingSymlinksInPath().lastPathComponent
                if sortedInstalledVersions.contains(candidate) {
                    currentActive = candidate
                }
            }
        }

        return NodeLockResolution(
            defaultAliasVersion: defaultResolved,
            currentActiveVersion: currentActive,
            fallbackLatestVersion: latestStable
        )
    }

    public static func resolveNVMAliasChain(
        nvmRoot: URL,
        initialAliasName: String,
        sortedInstalledVersions: [String],
        latestStable: String?
    ) -> String? {
        let aliasRoot = nvmRoot.appendingPathComponent("alias")
        var token = initialAliasName
        var visited = Set<String>()

        for _ in 0..<6 {
            guard visited.insert(token).inserted else { break }
            let aliasFile = aliasRoot.appendingPathComponent(token)
            if let contents = try? String(contentsOf: aliasFile, encoding: .utf8) {
                let next = contents.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !next.isEmpty else { return nil }
                token = next
                continue
            }
            break
        }

        // If alias/default did not exist at all, token is still initialAliasName ("default")
        if token == initialAliasName {
            return nil
        }
        if token == "node" || token == "stable" || token.hasPrefix("lts/") {
            return latestStable
        }

        let cleanToken = token.hasPrefix("v") ? String(token.dropFirst()) : token
        guard cleanToken.first?.isNumber == true else { return nil }

        return sortedInstalledVersions.first { installed in
            let cleanInstalled = installed.hasPrefix("v") ? String(installed.dropFirst()) : installed
            return cleanInstalled == cleanToken || cleanInstalled.hasPrefix(cleanToken + ".")
        }
    }

    public func scanNodeNVM(
        projectReferences: ProjectToolchainReferences,
        keepList: KeepListStore?
    ) -> [ToolchainItem] {
        let home = safetyPolicy.homeDirectory
        let nvmRoot = home.appendingPathComponent(".nvm")
        let versionsDir = nvmRoot.appendingPathComponent("versions/node")
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: versionsDir, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
            return []
        }

        let dirs = entries.filter { !$0.lastPathComponent.hasPrefix(".") }
        let sorted = dirs.sorted {
            SemanticVersionKey($0.lastPathComponent) > SemanticVersionKey($1.lastPathComponent)
        }
        let sortedNames = sorted.map(\.lastPathComponent)
        let locks = Self.resolveLockedNodeVersions(
            nvmRoot: nvmRoot,
            sortedInstalledVersions: sortedNames,
            environment: environment
        )
        let latestDir = sorted.first

        var results: [ToolchainItem] = []
        for entry in sorted {
            let standardized = entry.standardizedFileURL
            let verName = standardized.lastPathComponent
            let cleanVer = verName.replacingOccurrences(of: "v", with: "")
            let fp = ConcurrentDiskScanner.measureFootprint(at: standardized)
            guard fp.allocatedBytes >= 1_000_000 else { continue }

            let pinned = keepList?.isPinned(url: standardized) ?? false
            let matchedProjects = matchingNodeProjects(for: cleanVer, references: projectReferences)
            let isDefaultAlias = (verName == locks.defaultAliasVersion)
            let isCurrentActive = (verName == locks.currentActiveVersion)
            let isLockedCurrentOrDefault = locks.allLocked.contains(verName)

            let status: ToolchainVersionStatus
            let adv: ItemAdvisory

            if isLockedCurrentOrDefault {
                status = .activeOrLatest
                let lockBadge: String
                if isDefaultAlias && isCurrentActive {
                    lockBadge = "Default & Current • Locked"
                } else if isDefaultAlias {
                    lockBadge = "Default Runtime • Locked"
                } else {
                    lockBadge = "Current Runtime • Locked"
                }
                adv = ItemAdvisory(
                    level: .protected,
                    badgeTitle: lockBadge,
                    whatIsThis: "Active/default Node.js \(verName) runtime and global npm CLIs installed under this version.",
                    consequenceIfRemoved: "Removal of your default or current Node.js runtime is disabled. Switch your nvm default ('nvm alias default <other>') first if retiring \(verName).",
                    requiresExplicitAck: false,
                    referencedByProjects: matchedProjects,
                    isPinnedByUser: false
                )
            } else if !matchedProjects.isEmpty {
                let list = matchedProjects.joined(separator: ", ")
                status = .referencedByProject
                adv = ItemAdvisory(
                    level: .warning,
                    badgeTitle: "Warning • Pinned in .nvmrc (\(list))",
                    whatIsThis: "Node.js \(verName) runtime referenced by \(list).",
                    consequenceIfRemoved: "Removing this runtime breaks projects pinning \(verName) until reinstalled via 'nvm install'.",
                    requiresExplicitAck: true,
                    referencedByProjects: matchedProjects,
                    isPinnedByUser: pinned
                ).withPinState(pinned)
            } else {
                status = .superseded
                adv = ItemAdvisory(
                    level: .caution,
                    badgeTitle: "Caution • Non-Default Node Runtime",
                    whatIsThis: "Additional Node.js \(verName) installation under ~/.nvm (including any global packages installed specifically into \(verName)).",
                    consequenceIfRemoved: "Safe if you migrated to \(locks.defaultAliasVersion ?? latestDir?.lastPathComponent ?? "your default Node"); reinstall anytime with 'nvm install \(verName)'.",
                    isPinnedByUser: pinned
                ).withPinState(pinned)
            }

            results.append(
                ToolchainItem(
                    id: "nvm:\(verName)",
                    ecosystem: .nodeNVM,
                    componentKind: "Node.js Runtime",
                    version: verName,
                    urls: [standardized],
                    allocatedBytes: fp.allocatedBytes,
                    lastModified: fp.lastModified,
                    status: status,
                    advisory: adv
                )
            )
        }

        return results
    }

    private func matchingNodeProjects(for cleanVer: String, references: ProjectToolchainReferences) -> [String] {
        var matched = Set<String>()
        for (pin, projects) in references.nodeVersionsToProjects {
            if cleanVer == pin || cleanVer.hasPrefix(pin + ".") {
                matched.formUnion(projects)
            }
        }
        return matched.sorted()
    }

    // MARK: - 4. Headless Testing Browsers (~/.cache/puppeteer & ~/Library/Caches/ms-playwright)

    private static func parsePlaywrightFamilyAndRevision(_ folderName: String) -> (family: String, revision: String) {
        if let dashIndex = folderName.lastIndex(of: "-") {
            let suffix = String(folderName[folderName.index(after: dashIndex)...])
            if suffix.first?.isNumber == true {
                let family = String(folderName[..<dashIndex])
                return (family, suffix)
            }
        }
        return (folderName, "0")
    }

    public func scanPuppeteerBrowsers(keepList: KeepListStore?) -> [ToolchainItem] {
        let home = safetyPolicy.homeDirectory
        let fm = FileManager.default
        var results: [ToolchainItem] = []

        // Group Puppeteer chrome + chrome-headless-shell by build version
        let puppeteerRoot = home.appendingPathComponent(".cache/puppeteer")
        var puppeteerByVer: [String: [URL]] = [:]
        for channel in ["chrome", "chrome-headless-shell"] {
            let chanDir = puppeteerRoot.appendingPathComponent(channel)
            guard let entries = try? fm.contentsOfDirectory(at: chanDir, includingPropertiesForKeys: nil, options: []) else {
                continue
            }
            for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
                puppeteerByVer[entry.lastPathComponent, default: []].append(entry.standardizedFileURL)
            }
        }

        let sortedPup = puppeteerByVer.keys.sorted { SemanticVersionKey($0) > SemanticVersionKey($1) }
        var footprints: [String: (bytes: Int64, mod: Date?)] = [:]
        for ver in sortedPup {
            var b: Int64 = 0
            var m: Date?
            for u in puppeteerByVer[ver] ?? [] {
                let fp = ConcurrentDiskScanner.measureFootprint(at: u)
                b += fp.allocatedBytes
                if let lm = fp.lastModified, (m == nil || lm > m!) { m = lm }
            }
            footprints[ver] = (b, m)
        }

        let latestNonEmpty = sortedPup.first { (footprints[$0]?.bytes ?? 0) > 1_000_000 }
        for ver in sortedPup {
            guard let urls = puppeteerByVer[ver], let fp = footprints[ver], fp.bytes >= 1_000_000 else { continue }
            let pinned = keepList?.isPinned(urls: urls) ?? false
            let isLatest = (ver == latestNonEmpty)
            let status: ToolchainVersionStatus = isLatest ? .activeOrLatest : .superseded
            let adv: ItemAdvisory
            if isLatest {
                adv = ItemAdvisory(
                    level: .protected,
                    badgeTitle: "Current Revision • Locked",
                    whatIsThis: "Current/latest Headless Chrome / Chrome-Headless-Shell (\(ver)) in ~/.cache/puppeteer.",
                    consequenceIfRemoved: "Removal of the current Puppeteer browser revision is disabled so headless browser scripts continue working offline.",
                    requiresExplicitAck: false,
                    isPinnedByUser: false
                )
            } else {
                adv = ItemAdvisory(
                    level: .safe,
                    badgeTitle: "Safe • Superseded Puppeteer Build",
                    whatIsThis: "Older Headless Chrome / Chrome-Headless-Shell (\(ver)) in ~/.cache/puppeteer.",
                    consequenceIfRemoved: "Safe to remove superseded browser revision; current revision \(latestNonEmpty ?? "") remains installed.",
                    isPinnedByUser: pinned
                ).withPinState(pinned)
            }

            results.append(
                ToolchainItem(
                    id: "puppeteer:\(ver)",
                    ecosystem: .headlessBrowsers,
                    componentKind: "Puppeteer Chromium Bundle",
                    version: ver,
                    urls: urls,
                    allocatedBytes: fp.bytes,
                    lastModified: fp.mod,
                    status: status,
                    advisory: adv
                )
            )
        }

        // Playwright browsers (~/Library/Caches/ms-playwright) grouped by engine family
        let playwrightRoot = home.appendingPathComponent("Library/Caches/ms-playwright")
        if let entries = try? fm.contentsOfDirectory(at: playwrightRoot, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            struct PlaywrightCandidate {
                let url: URL
                let family: String
                let revision: String
                let footprint: DirectoryFootprint
            }
            var byFamily: [String: [PlaywrightCandidate]] = [:]
            for entry in entries where !entry.lastPathComponent.hasPrefix(".") {
                let standardized = entry.standardizedFileURL
                let fp = ConcurrentDiskScanner.measureFootprint(at: standardized)
                guard fp.allocatedBytes >= 5_000_000 else { continue }
                let (family, rev) = Self.parsePlaywrightFamilyAndRevision(standardized.lastPathComponent)
                byFamily[family, default: []].append(
                    PlaywrightCandidate(url: standardized, family: family, revision: rev, footprint: fp)
                )
            }

            for (_, candidates) in byFamily {
                let sortedFam = candidates.sorted {
                    SemanticVersionKey($0.revision) > SemanticVersionKey($1.revision)
                }
                let latestURL = sortedFam.first?.url
                for cand in sortedFam {
                    let isLatest = (cand.url == latestURL)
                    let pinned = keepList?.isPinned(url: cand.url) ?? false
                    let adv: ItemAdvisory
                    if isLatest {
                        adv = ItemAdvisory(
                            level: .protected,
                            badgeTitle: "Current Revision • Locked",
                            whatIsThis: "Current installed Playwright \(cand.family) binary (\(cand.url.lastPathComponent)).",
                            consequenceIfRemoved: "Removal of the current Playwright \(cand.family) revision is disabled.",
                            requiresExplicitAck: false,
                            isPinnedByUser: false
                        )
                    } else {
                        adv = ItemAdvisory(
                            level: .safe,
                            badgeTitle: "Safe • Superseded Playwright Build",
                            whatIsThis: "Older Playwright \(cand.family) revision (\(cand.url.lastPathComponent)) superseded by \(latestURL?.lastPathComponent ?? "newer build").",
                            consequenceIfRemoved: "Safe to remove; current \(cand.family) revision stays installed.",
                            isPinnedByUser: pinned
                        ).withPinState(pinned)
                    }
                    results.append(
                        ToolchainItem(
                            id: "playwright:\(cand.url.lastPathComponent)",
                            ecosystem: .headlessBrowsers,
                            componentKind: "Playwright Browser",
                            version: cand.url.lastPathComponent,
                            urls: [cand.url],
                            allocatedBytes: cand.footprint.allocatedBytes,
                            lastModified: cand.footprint.lastModified,
                            status: isLatest ? .activeOrLatest : .superseded,
                            advisory: adv
                        )
                    )
                }
            }
        }

        return results.sorted { $0.allocatedBytes > $1.allocatedBytes }
    }
}
