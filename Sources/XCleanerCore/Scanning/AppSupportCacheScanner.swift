import Foundation

public struct AppSupportCacheScanner: Sendable {
    public let safetyPolicy: SafetyPolicyEngine

    public init(safetyPolicy: SafetyPolicyEngine = SafetyPolicyEngine()) {
        self.safetyPolicy = safetyPolicy
    }

    private struct BrowserTarget {
        let appName: String
        let bundleID: String
        let relativeAppSupportPath: String
    }

    private static let chromiumBrowsers: [BrowserTarget] = [
        BrowserTarget(appName: "Comet", bundleID: "ai.perplexity.comet", relativeAppSupportPath: "Comet"),
        BrowserTarget(appName: "Google Chrome", bundleID: "com.google.Chrome", relativeAppSupportPath: "Google/Chrome"),
        BrowserTarget(appName: "Brave Browser", bundleID: "com.brave.Browser", relativeAppSupportPath: "BraveSoftware/Brave-Browser"),
        BrowserTarget(appName: "Microsoft Edge", bundleID: "com.microsoft.edgemac", relativeAppSupportPath: "Microsoft Edge"),
        BrowserTarget(appName: "Arc", bundleID: "company.thebrowser.Browser", relativeAppSupportPath: "Arc/User Data")
    ]

    private static let activeIDETargets: [BrowserTarget] = [
        BrowserTarget(appName: "Antigravity", bundleID: "com.google.antigravity", relativeAppSupportPath: "Antigravity"),
        BrowserTarget(appName: "Antigravity IDE", bundleID: "com.google.antigravity-ide", relativeAppSupportPath: "Antigravity IDE"),
        BrowserTarget(appName: "Visual Studio Code", bundleID: "com.microsoft.VSCode", relativeAppSupportPath: "Code"),
        BrowserTarget(appName: "Cursor", bundleID: "com.todesktop.230313mzl4w4u92", relativeAppSupportPath: "Cursor"),
        BrowserTarget(appName: "Windsurf", bundleID: "com.exafunction.windsurf", relativeAppSupportPath: "Windsurf")
    ]

    public func scanAppSupportCaches(
        installedIndex: InstalledAppsIndex,
        runningApps: [RunningApplicationSnapshot],
        keepList: KeepListStore?
    ) -> [ScannableItem] {
        let appSupport = safetyPolicy.homeDirectory.appendingPathComponent("Library/Application Support")
        let fm = FileManager.default
        var results: [ScannableItem] = []

        // 1. Chromium Browsers: Service Worker CacheStorage + GPU/Shader caches (Logins/Cookies/History untouched!)
        for browser in Self.chromiumBrowsers {
            if Task.isCancelled { break }
            let browserRoot = appSupport.appendingPathComponent(browser.relativeAppSupportPath).standardizedFileURL
            guard fm.fileExists(atPath: browserRoot.path) else { continue }

            let lockingApp = RunningLockMatcher.findLockingApp(
                for: browserRoot,
                explicitBundleID: browser.bundleID,
                explicitAppName: browser.appName,
                runningApps: runningApps,
                homeDirectory: safetyPolicy.homeDirectory
            )

            // Discover profiles: Default, Profile 1, Profile 2, ...
            let entries = (try? fm.contentsOfDirectory(at: browserRoot, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []
            let profileDirs = entries.filter { url in
                let name = url.lastPathComponent
                return name == "Default" || name.hasPrefix("Profile ")
            }

            // A) Service Worker CacheStorage & ScriptCache (.caution so user explicitly opts in)
            var swURLs: [URL] = []
            var swBytes: Int64 = 0
            var swCount = 0
            var swMod: Date?

            for profile in profileDirs {
                let swDir = profile.appendingPathComponent("Service Worker")
                for subName in ["CacheStorage", "ScriptCache"] {
                    let subURL = swDir.appendingPathComponent(subName).standardizedFileURL
                    if fm.fileExists(atPath: subURL.path), !safetyPolicy.evaluateProtection(for: subURL).isProtected {
                        let fp = ConcurrentDiskScanner.measureFootprint(at: subURL)
                        if fp.allocatedBytes > 0 {
                            swURLs.append(subURL)
                            swBytes += fp.allocatedBytes
                            swCount += fp.itemCount
                            if let m = fp.lastModified, (swMod == nil || m > swMod!) { swMod = m }
                        }
                    }
                }
                // Fallback if Service Worker itself holds direct cache blobs without CacheStorage subdir
                if swURLs.isEmpty, fm.fileExists(atPath: swDir.path), !safetyPolicy.evaluateProtection(for: swDir).isProtected {
                    let fp = ConcurrentDiskScanner.measureFootprint(at: swDir)
                    if fp.allocatedBytes >= 5_000_000 {
                        swURLs.append(swDir.standardizedFileURL)
                        swBytes += fp.allocatedBytes
                        swCount += fp.itemCount
                        swMod = fp.lastModified
                    }
                }
            }

            if swBytes >= 5_000_000, let primarySW = swURLs.first {
                let pinned = keepList?.isPinned(urls: swURLs) ?? keepList?.isPinned(url: browserRoot) ?? false
                var adv = ItemAdvisory(
                    level: .caution,
                    badgeTitle: "Caution • PWA Service Worker Cache",
                    whatIsThis: "\(browser.appName) Progressive Web App (Service Worker) HTTP asset cache inside Application Support.",
                    consequenceIfRemoved: "Saved passwords, cookies, open tabs, bookmarks, and history are NOT touched. Offline web-app assets will re-sync when visited."
                )
                if let lockingApp {
                    adv = adv.withRunningLock(appName: lockingApp.localizedName, bundleID: lockingApp.bundleIdentifier)
                }
                if pinned { adv = adv.withPinState(true) }

                results.append(
                    ScannableItem(
                        id: "appsupport:sw:\(browser.bundleID)",
                        url: primarySW,
                        additionalURLs: Array(swURLs.dropFirst()),
                        title: "\(browser.appName) — Service Worker Web Cache",
                        subtitle: primarySW.path,
                        domain: .browserAndAppSupport,
                        allocatedBytes: swBytes,
                        itemCount: swCount,
                        lastModified: swMod,
                        associatedAppName: browser.appName,
                        associatedBundleID: browser.bundleID,
                        advisory: adv
                    )
                )
            }

            // B) Pure Shader / GPU / Crashpad / CRX caches (.safe)
            var gpuURLs: [URL] = []
            var gpuBytes: Int64 = 0
            var gpuCount = 0
            var gpuMod: Date?

            let topSafeDirs = ["ShaderCache", "GrShaderCache", "GraphiteDawnCache", "BrowserMetrics", "component_crx_cache", "Crashpad/completed"]
            for rel in topSafeDirs {
                let candidate = browserRoot.appendingPathComponent(rel).standardizedFileURL
                if fm.fileExists(atPath: candidate.path), !safetyPolicy.evaluateProtection(for: candidate).isProtected {
                    let fp = ConcurrentDiskScanner.measureFootprint(at: candidate)
                    if fp.allocatedBytes > 0 {
                        gpuURLs.append(candidate)
                        gpuBytes += fp.allocatedBytes
                        gpuCount += fp.itemCount
                        if let m = fp.lastModified, (gpuMod == nil || m > gpuMod!) { gpuMod = m }
                    }
                }
            }
            for profile in profileDirs {
                for rel in ["GPUCache", "Code Cache", "DawnGraphiteCache", "DawnWebGPUCache"] {
                    let candidate = profile.appendingPathComponent(rel).standardizedFileURL
                    if fm.fileExists(atPath: candidate.path), !safetyPolicy.evaluateProtection(for: candidate).isProtected {
                        let fp = ConcurrentDiskScanner.measureFootprint(at: candidate)
                        if fp.allocatedBytes > 0 {
                            gpuURLs.append(candidate)
                            gpuBytes += fp.allocatedBytes
                            gpuCount += fp.itemCount
                            if let m = fp.lastModified, (gpuMod == nil || m > gpuMod!) { gpuMod = m }
                        }
                    }
                }
            }

            if gpuBytes >= 10_000_000, let primaryGPU = gpuURLs.first {
                let pinned = keepList?.isPinned(urls: gpuURLs) ?? keepList?.isPinned(url: browserRoot) ?? false
                var adv = ItemAdvisory(
                    level: .safe,
                    badgeTitle: "Safe • Browser GPU & Shader Caches",
                    whatIsThis: "Compiled WebGL/Metal shaders, V8 bytecode cache, and completed crash dumps for \(browser.appName).",
                    consequenceIfRemoved: "Safely regenerated automatically as pages render; zero impact on logins or browsing data."
                )
                if let lockingApp {
                    adv = adv.withRunningLock(appName: lockingApp.localizedName, bundleID: lockingApp.bundleIdentifier)
                }
                if pinned { adv = adv.withPinState(true) }

                results.append(
                    ScannableItem(
                        id: "appsupport:gpu:\(browser.bundleID)",
                        url: primaryGPU,
                        additionalURLs: Array(gpuURLs.dropFirst()),
                        title: "\(browser.appName) — GPU, Shader & Crashpad Caches",
                        subtitle: browserRoot.path,
                        domain: .browserAndAppSupport,
                        allocatedBytes: gpuBytes,
                        itemCount: gpuCount,
                        lastModified: gpuMod,
                        associatedAppName: browser.appName,
                        associatedBundleID: browser.bundleID,
                        advisory: adv
                    )
                )
            }
        }

        // 2. Installed Electron IDEs (only when installed, avoiding overlap with OrphanedAppDetector!)
        for ide in Self.activeIDETargets {
            if Task.isCancelled { break }
            guard installedIndex.isInstalled(bundleIDs: [ide.bundleID], appNames: [ide.appName]) else {
                continue
            }
            let ideRoot = appSupport.appendingPathComponent(ide.relativeAppSupportPath).standardizedFileURL
            guard fm.fileExists(atPath: ideRoot.path) else { continue }

            let lockingApp = RunningLockMatcher.findLockingApp(
                for: ideRoot,
                explicitBundleID: ide.bundleID,
                explicitAppName: ide.appName,
                runningApps: runningApps,
                homeDirectory: safetyPolicy.homeDirectory
            )

            let cacheSubdirs = ["CachedExtensionVSIXs", "logs", "Cache", "Code Cache", "GPUCache", "Crashpad/completed"]
            var urls: [URL] = []
            var bytes: Int64 = 0
            var count = 0
            var mod: Date?

            for sub in cacheSubdirs {
                let u = ideRoot.appendingPathComponent(sub).standardizedFileURL
                if fm.fileExists(atPath: u.path), !safetyPolicy.evaluateProtection(for: u).isProtected {
                    let fp = ConcurrentDiskScanner.measureFootprint(at: u)
                    if fp.allocatedBytes > 0 {
                        urls.append(u)
                        bytes += fp.allocatedBytes
                        count += fp.itemCount
                        if let m = fp.lastModified, (mod == nil || m > mod!) { mod = m }
                    }
                }
            }

            if bytes >= 10_000_000, let primary = urls.first {
                let pinned = keepList?.isPinned(urls: urls) ?? keepList?.isPinned(url: ideRoot) ?? false
                var adv = ItemAdvisory(
                    level: .safe,
                    badgeTitle: "Safe • IDE .vsix & Log Caches",
                    whatIsThis: "Downloaded extension installer packages (CachedExtensionVSIXs), old extension logs, and GPU caches for \(ide.appName).",
                    consequenceIfRemoved: "Installed extensions, settings, and conversations remain completely untouched."
                )
                if let lockingApp {
                    adv = adv.withRunningLock(appName: lockingApp.localizedName, bundleID: lockingApp.bundleIdentifier)
                }
                if pinned { adv = adv.withPinState(true) }

                results.append(
                    ScannableItem(
                        id: "appsupport:ide:\(ide.bundleID)",
                        url: primary,
                        additionalURLs: Array(urls.dropFirst()),
                        title: "\(ide.appName) — Cached .vsix Installers & Logs",
                        subtitle: ideRoot.path,
                        domain: .browserAndAppSupport,
                        allocatedBytes: bytes,
                        itemCount: count,
                        lastModified: mod,
                        associatedAppName: ide.appName,
                        associatedBundleID: ide.bundleID,
                        advisory: adv
                    )
                )
            }
        }

        // 3. Spotify Offline / Streaming Audio Cache (Caution advisory + Pin prompt!)
        let spotifyRoot = appSupport.appendingPathComponent("Spotify").standardizedFileURL
        let spotifyCache = spotifyRoot.appendingPathComponent("PersistentCache").standardizedFileURL
        let targetSpotify = fm.fileExists(atPath: spotifyCache.path) ? spotifyCache : spotifyRoot
        if fm.fileExists(atPath: targetSpotify.path), !safetyPolicy.evaluateProtection(for: targetSpotify).isProtected {
            let fp = ConcurrentDiskScanner.measureFootprint(at: targetSpotify)
            if fp.allocatedBytes >= 10_000_000 {
                let lockingApp = RunningLockMatcher.findLockingApp(
                    for: spotifyRoot,
                    explicitBundleID: "com.spotify.client",
                    explicitAppName: "Spotify",
                    runningApps: runningApps,
                    homeDirectory: safetyPolicy.homeDirectory
                )
                let pinned = keepList?.isPinned(url: targetSpotify) ?? keepList?.isPinned(url: spotifyRoot) ?? false
                var adv = ItemAdvisory(
                    level: .caution,
                    badgeTitle: "Caution • Offline Music & Audio Cache",
                    whatIsThis: "Spotify local audio streaming cache and downloaded offline playlists/podcasts.",
                    consequenceIfRemoved: "Removes downloaded offline songs in Spotify (playlists stay in your account, but offline tracks must re-download). Click Pin to Keep if you want to keep offline songs."
                )
                if let lockingApp {
                    adv = adv.withRunningLock(appName: lockingApp.localizedName, bundleID: lockingApp.bundleIdentifier)
                }
                if pinned { adv = adv.withPinState(true) }

                results.append(
                    ScannableItem(
                        id: "appsupport:spotify",
                        url: targetSpotify,
                        title: "Spotify — Offline & Streaming Audio Cache",
                        subtitle: targetSpotify.path,
                        domain: .browserAndAppSupport,
                        allocatedBytes: fp.allocatedBytes,
                        itemCount: fp.itemCount,
                        lastModified: fp.lastModified,
                        associatedAppName: "Spotify",
                        associatedBundleID: "com.spotify.client",
                        advisory: adv
                    )
                )
            }
        }

        return results.sorted { $0.allocatedBytes > $1.allocatedBytes }
    }
}
