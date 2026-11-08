import Foundation

public struct InstalledAppsIndex: Sendable {
    public let bundleIDs: Set<String>
    public let normalizedNames: Set<String>

    public init(bundleIDs: Set<String>, normalizedNames: Set<String>) {
        self.bundleIDs = bundleIDs
        self.normalizedNames = normalizedNames
    }

    public static func buildFromSystem(
        applicationRoots: [URL]? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> InstalledAppsIndex {
        let roots = applicationRoots ?? [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            homeDirectory.appendingPathComponent("Applications")
        ]

        var ids = Set<String>()
        var names = Set<String>()
        let fm = FileManager.default

        for root in roots {
            guard let level1 = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
                continue
            }
            for item in level1 {
                if item.pathExtension.lowercased() == "app" {
                    recordAppBundle(at: item, ids: &ids, names: &names)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if let level2 = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: []) {
                        for sub in level2 where sub.pathExtension.lowercased() == "app" {
                            recordAppBundle(at: sub, ids: &ids, names: &names)
                        }
                    }
                }
            }
        }

        return InstalledAppsIndex(bundleIDs: ids, normalizedNames: names)
    }

    public func isInstalled(bundleIDs candidateIDs: [String], appNames candidateNames: [String]) -> Bool {
        for bid in candidateIDs where bundleIDs.contains(bid.lowercased()) {
            return true
        }
        for name in candidateNames where normalizedNames.contains(Self.normalize(name)) {
            return true
        }
        return false
    }

    private static func recordAppBundle(at appURL: URL, ids: inout Set<String>, names: inout Set<String>) {
        let baseName = appURL.deletingPathExtension().lastPathComponent
        names.insert(normalize(baseName))

        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        if let data = try? Data(contentsOf: infoPlistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
            if let bid = plist["CFBundleIdentifier"] as? String {
                ids.insert(bid.lowercased())
            }
            if let name = plist["CFBundleName"] as? String {
                names.insert(normalize(name))
            }
            if let display = plist["CFBundleDisplayName"] as? String {
                names.insert(normalize(display))
            }
        }
    }

    public static func normalize(_ raw: String) -> String {
        raw.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

public struct OrphanedAppDetector: Sendable {
    public let safetyPolicy: SafetyPolicyEngine

    public init(safetyPolicy: SafetyPolicyEngine = SafetyPolicyEngine()) {
        self.safetyPolicy = safetyPolicy
    }

    private struct KnownAppProfile {
        let displayName: String
        let bundleIDs: [String]
        let appNames: [String]
        let relativeHomePaths: [String]
        let supportsVSCodeStyleBreakdown: Bool
    }

    private static let knownProfiles: [KnownAppProfile] = [
        KnownAppProfile(
            displayName: "Visual Studio Code",
            bundleIDs: ["com.microsoft.vscode"],
            appNames: ["Visual Studio Code", "VSCode"],
            relativeHomePaths: [
                "Library/Application Support/Code",
                ".vscode",
                "Library/Caches/com.microsoft.VSCode",
                "Library/Caches/com.microsoft.VSCode.ShipIt"
            ],
            supportsVSCodeStyleBreakdown: true
        ),
        KnownAppProfile(
            displayName: "Cursor IDE",
            bundleIDs: ["com.todesktop.230313mzl4w4u92", "com.cursor.cursor"],
            appNames: ["Cursor"],
            relativeHomePaths: [
                "Library/Application Support/Cursor",
                ".cursor"
            ],
            supportsVSCodeStyleBreakdown: true
        ),
        KnownAppProfile(
            displayName: "Windsurf IDE",
            bundleIDs: ["com.exafunction.windsurf"],
            appNames: ["Windsurf"],
            relativeHomePaths: [
                "Library/Application Support/Windsurf",
                ".windsurf"
            ],
            supportsVSCodeStyleBreakdown: true
        ),
        KnownAppProfile(
            displayName: "Wondershare Filmora",
            bundleIDs: ["com.wondershare.filmoramac"],
            appNames: ["Wondershare Filmora", "Wondershare Filmora 10", "Filmora"],
            relativeHomePaths: ["Library/Application Support/Wondershare Filmora 10"],
            supportsVSCodeStyleBreakdown: false
        ),
        KnownAppProfile(
            displayName: "Perplexity Desktop",
            bundleIDs: ["ai.perplexity.mac"],
            appNames: ["Perplexity"],
            relativeHomePaths: ["Library/Application Support/Perplexity"],
            supportsVSCodeStyleBreakdown: false
        ),
        KnownAppProfile(
            displayName: "Canva Desktop",
            bundleIDs: ["com.canva.canvadesktop"],
            appNames: ["Canva"],
            relativeHomePaths: ["Library/Application Support/Canva"],
            supportsVSCodeStyleBreakdown: false
        ),
        KnownAppProfile(
            displayName: "OpenAI Atlas",
            bundleIDs: ["com.openai.atlas"],
            appNames: ["Atlas", "ChatGPT Atlas"],
            relativeHomePaths: ["Library/Application Support/com.openai.atlas"],
            supportsVSCodeStyleBreakdown: false
        ),
        KnownAppProfile(
            displayName: "Epic Games Launcher",
            bundleIDs: ["com.epicgames.epicgameslauncher"],
            appNames: ["Epic Games Launcher"],
            relativeHomePaths: ["Library/Application Support/Epic"],
            supportsVSCodeStyleBreakdown: false
        ),
        KnownAppProfile(
            displayName: "OBS Studio",
            bundleIDs: ["com.obsproject.obs-studio"],
            appNames: ["OBS", "OBS Studio"],
            relativeHomePaths: ["Library/Application Support/obs-studio"],
            supportsVSCodeStyleBreakdown: false
        ),
        KnownAppProfile(
            displayName: "IINA Media Player",
            bundleIDs: ["com.colliderli.iina"],
            appNames: ["IINA"],
            relativeHomePaths: ["Library/Application Support/com.colliderli.iina"],
            supportsVSCodeStyleBreakdown: false
        ),
        KnownAppProfile(
            displayName: "uTorrent Web",
            bundleIDs: ["com.bittorrent.utorrentweb"],
            appNames: ["uTorrent Web"],
            relativeHomePaths: ["Library/Application Support/uTorrent Web"],
            supportsVSCodeStyleBreakdown: false
        ),
        KnownAppProfile(
            displayName: "Grain Recorder",
            bundleIDs: ["com.grain.mac"],
            appNames: ["Grain"],
            relativeHomePaths: ["Library/Application Support/Grain"],
            supportsVSCodeStyleBreakdown: false
        ),
        KnownAppProfile(
            displayName: "GIMP",
            bundleIDs: ["org.gimp.gimp", "org.gimp.gimp-2.10"],
            appNames: ["GIMP"],
            relativeHomePaths: ["Library/Application Support/GIMP"],
            supportsVSCodeStyleBreakdown: false
        ),
        KnownAppProfile(
            displayName: "MongoDB Compass",
            bundleIDs: ["com.mongodb.compass"],
            appNames: ["MongoDB Compass"],
            relativeHomePaths: ["Library/Application Support/MongoDB Compass"],
            supportsVSCodeStyleBreakdown: false
        )
    ]

    private static let nonOrphanVendorAllowlist: Set<String> = [
        "google", "microsoft", "adobe", "apple", "caches", "cef", "crashreporter",
        "antigravity", "antigravityide", "comet", "dockerdesktop", "spotify", "rstudio",
        "zoomus", "bruno", "warp", "devwarpwarpstable", "telegram", "rukeepcodertelegram",
        "whatsapp", "stats", "libreoffice", "githubdesktop", "audacity", "breaktimer",
        "macdroid", "monitorcontrol", "netbird", "coconutbattery", "loop", "maccy",
        "blip", "simplenote", "xcleaner", "cloudcode", "gitkrakencli", "onedrive",
        "jetbrains", "mozilla", "firefox", "go", "kotlin", "vitest", "executorchcoreml"
    ]

    public func scanOrphans(
        installedIndex: InstalledAppsIndex,
        runningApps: [RunningApplicationSnapshot],
        keepList: KeepListStore?
    ) -> [ScannableItem] {
        let home = safetyPolicy.homeDirectory
        let fm = FileManager.default
        var results: [ScannableItem] = []
        var claimedPaths = Set<String>()

        // 1. Evaluate Known Multi-Location Profiles (e.g. VS Code + ~/.vscode)
        for profile in Self.knownProfiles {
            if Task.isCancelled { break }
            guard !installedIndex.isInstalled(bundleIDs: profile.bundleIDs, appNames: profile.appNames) else {
                continue
            }
            // Also skip if currently running from another location (e.g. Downloads/DMG)
            if runningApps.contains(where: { app in
                if let bid = app.bundleIdentifier?.lowercased(), profile.bundleIDs.contains(bid) { return true }
                return profile.appNames.contains { $0.caseInsensitiveCompare(app.localizedName) == .orderedSame }
            }) {
                continue
            }

            let existingURLs = profile.relativeHomePaths
                .map { home.appendingPathComponent($0).standardizedFileURL }
                .filter { fm.fileExists(atPath: $0.path) && !safetyPolicy.evaluateProtection(for: $0).isProtected }

            guard let primary = existingURLs.first else { continue }
            for u in existingURLs { claimedPaths.insert(u.path) }

            if profile.supportsVSCodeStyleBreakdown {
                if let item = buildGranularIDEOrphanItem(
                    profile: profile,
                    existingURLs: existingURLs,
                    keepList: keepList
                ) {
                    results.append(item)
                }
            } else {
                var totalBytes: Int64 = 0
                var totalCount = 0
                var latestMod: Date?
                for url in existingURLs {
                    let fp = ConcurrentDiskScanner.measureFootprint(at: url)
                    totalBytes += fp.allocatedBytes
                    totalCount += fp.itemCount
                    if let m = fp.lastModified, (latestMod == nil || m > latestMod!) {
                        latestMod = m
                    }
                }
                guard totalBytes >= 1_000_000 else { continue }
                let isPinned = keepList?.isPinned(urls: existingURLs) ?? false
                let advisory = ItemAdvisory(
                    level: .warning,
                    badgeTitle: "Warning • Uninstalled App Data",
                    whatIsThis: "\(profile.displayName) is not installed in /Applications, but left behind \(ByteFormatting.string(from: totalBytes)) of support files.",
                    consequenceIfRemoved: "Deletes saved preferences, templates, or cached assets if you reinstall \(profile.displayName) later.",
                    requiresExplicitAck: true,
                    isPinnedByUser: isPinned
                ).withPinState(isPinned)

                results.append(
                    ScannableItem(
                        id: "orphan:\(profile.displayName)",
                        url: primary,
                        additionalURLs: Array(existingURLs.dropFirst()),
                        title: "\(profile.displayName) (Uninstalled Leftovers)",
                        subtitle: existingURLs.map(\.path).joined(separator: " + "),
                        domain: .orphanedApps,
                        allocatedBytes: totalBytes,
                        itemCount: totalCount,
                        lastModified: latestMod,
                        associatedAppName: profile.displayName,
                        associatedBundleID: profile.bundleIDs.first,
                        advisory: advisory
                    )
                )
            }
        }

        // 2. Generic reverse-DNS third-party folders in ~/Library/Application Support >= 20 MB
        let appSupport = home.appendingPathComponent("Library/Application Support")
        if let entries = try? fm.contentsOfDirectory(at: appSupport, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            for entry in entries {
                if Task.isCancelled { break }
                let standardized = entry.standardizedFileURL
                guard !claimedPaths.contains(standardized.path),
                      !safetyPolicy.evaluateProtection(for: standardized).isProtected else {
                    continue
                }
                let name = standardized.lastPathComponent
                let lower = name.lowercased()
                if lower.hasPrefix("com.apple.") || lower.hasPrefix(".") { continue }
                let norm = InstalledAppsIndex.normalize(name)
                if Self.nonOrphanVendorAllowlist.contains(norm) { continue }

                // Only flag clear reverse-DNS bundle directories not matching installed apps
                let parts = name.split(separator: ".")
                guard parts.count >= 3,
                      ["com", "org", "io", "net", "ai", "dev", "app", "us"].contains(parts[0].lowercased()) else {
                    continue
                }
                if installedIndex.isInstalled(bundleIDs: [lower], appNames: [String(parts.last ?? "")]) {
                    continue
                }
                let fp = ConcurrentDiskScanner.measureFootprint(at: standardized)
                guard fp.allocatedBytes >= 20_000_000 else { continue }

                let isPinned = keepList?.isPinned(url: standardized) ?? false
                let advisory = ItemAdvisory(
                    level: .warning,
                    badgeTitle: "Warning • Unmatched App Support",
                    whatIsThis: "Application Support directory (\(name)) with no matching .app bundle in /Applications.",
                    consequenceIfRemoved: "Verify this tool is no longer used via CLI or custom path before removing.",
                    requiresExplicitAck: true,
                    isPinnedByUser: isPinned
                ).withPinState(isPinned)

                results.append(
                    ScannableItem(
                        url: standardized,
                        title: "\(name) (Uninstalled App Support)",
                        subtitle: standardized.path,
                        domain: .orphanedApps,
                        allocatedBytes: fp.allocatedBytes,
                        itemCount: fp.itemCount,
                        lastModified: fp.lastModified,
                        associatedBundleID: lower,
                        advisory: advisory
                    )
                )
            }
        }

        return results.sorted { $0.allocatedBytes > $1.allocatedBytes }
    }

    private func buildGranularIDEOrphanItem(
        profile: KnownAppProfile,
        existingURLs: [URL],
        keepList: KeepListStore?
    ) -> ScannableItem? {
        let fm = FileManager.default
        let safeCacheNames: Set<String> = [
            "Cache", "CachedData", "CachedExtensionVSIXs", "CachedExtensions",
            "Code Cache", "GPUCache", "DawnCache", "DawnGraphiteCache", "DawnWebGPUCache",
            "logs", "Crashpad", "Service Worker", "WebStorage"
        ]

        var subItems: [ScannableItem] = []
        var totalBytes: Int64 = 0
        var totalCount = 0
        var latestMod: Date?

        for rootURL in existingURLs {
            let rootFootprint = ConcurrentDiskScanner.measureFootprint(at: rootURL)
            totalBytes += rootFootprint.allocatedBytes
            totalCount += rootFootprint.itemCount
            if let m = rootFootprint.lastModified, (latestMod == nil || m > latestMod!) {
                latestMod = m
            }

            if rootURL.lastPathComponent.hasPrefix(".") {
                // e.g. ~/.vscode/extensions
                let extDir = rootURL.appendingPathComponent("extensions")
                let target = fm.fileExists(atPath: extDir.path) ? extDir : rootURL
                let fp = ConcurrentDiskScanner.measureFootprint(at: target)
                if fp.allocatedBytes >= 500_000 {
                    let pinned = keepList?.isPinned(url: target) ?? false
                    let adv = ItemAdvisory(
                        level: .warning,
                        badgeTitle: "Warning • Installed IDE Extensions",
                        whatIsThis: "Downloaded extensions for uninstalled \(profile.displayName) (\(target.path)). Independent of active Antigravity extensions.",
                        consequenceIfRemoved: "If you reinstall \(profile.displayName) later, you will need to re-download your extensions.",
                        requiresExplicitAck: true,
                        isPinnedByUser: pinned
                    ).withPinState(pinned)
                    subItems.append(
                        ScannableItem(
                            url: target,
                            title: "\(profile.displayName) — Installed Extensions",
                            subtitle: target.path,
                            domain: .orphanedApps,
                            allocatedBytes: fp.allocatedBytes,
                            itemCount: fp.itemCount,
                            lastModified: fp.lastModified,
                            associatedAppName: profile.displayName,
                            advisory: adv
                        )
                    )
                }
            } else if rootURL.path.contains("/Application Support/") {
                guard let children = try? fm.contentsOfDirectory(at: rootURL, includingPropertiesForKeys: nil, options: []) else {
                    continue
                }
                for child in children {
                    let cName = child.lastPathComponent
                    if safetyPolicy.evaluateProtection(for: child).isProtected { continue }
                    let fp = ConcurrentDiskScanner.measureFootprint(at: child)
                    guard fp.allocatedBytes >= 1_000_000 else { continue }
                    let pinned = keepList?.isPinned(url: child) ?? false

                    if safeCacheNames.contains(cName) {
                        let adv = ItemAdvisory(
                            level: .safe,
                            badgeTitle: "Safe • Regenerable IDE Cache",
                            whatIsThis: "\(cName) inside uninstalled \(profile.displayName) (cached .vsix packages, logs, or GPU caches).",
                            consequenceIfRemoved: "Safe to remove even if you reinstall \(profile.displayName); user settings are unaffected.",
                            isPinnedByUser: pinned
                        ).withPinState(pinned)
                        subItems.append(
                            ScannableItem(
                                url: child,
                                title: "\(profile.displayName) — \(cName)",
                                subtitle: child.path,
                                domain: .orphanedApps,
                                allocatedBytes: fp.allocatedBytes,
                                itemCount: fp.itemCount,
                                lastModified: fp.lastModified,
                                associatedAppName: profile.displayName,
                                advisory: adv
                            )
                        )
                    } else if cName == "User" {
                        let adv = ItemAdvisory(
                            level: .warning,
                            badgeTitle: "Warning • User Settings & State",
                            whatIsThis: "Settings (settings.json), keybindings, snippets, and workspaceStorage for \(profile.displayName).",
                            consequenceIfRemoved: "Deletes saved \(profile.displayName) preferences and workspace history.",
                            requiresExplicitAck: true,
                            isPinnedByUser: pinned
                        ).withPinState(pinned)
                        subItems.append(
                            ScannableItem(
                                url: child,
                                title: "\(profile.displayName) — User Settings & Workspace State",
                                subtitle: child.path,
                                domain: .orphanedApps,
                                allocatedBytes: fp.allocatedBytes,
                                itemCount: fp.itemCount,
                                lastModified: fp.lastModified,
                                associatedAppName: profile.displayName,
                                advisory: adv
                            )
                        )
                    }
                }
            }
        }

        guard totalBytes >= 1_000_000, let primary = existingURLs.first else { return nil }
        subItems.sort { $0.allocatedBytes > $1.allocatedBytes }

        let parentPinned = keepList?.isPinned(urls: existingURLs) ?? false
        let parentAdv = ItemAdvisory(
            level: .warning,
            badgeTitle: "Warning • Uninstalled IDE (Expand for Granular Choice)",
            whatIsThis: "\(profile.displayName) is uninstalled, leaving \(ByteFormatting.string(from: totalBytes)) across Application Support and home dotfiles.",
            consequenceIfRemoved: "Expand sub-items to clean only Safe .vsix/log caches, or stage the entire group to remove extensions & settings too.",
            requiresExplicitAck: true,
            isPinnedByUser: parentPinned
        ).withPinState(parentPinned)

        return ScannableItem(
            id: "orphan:\(profile.displayName)",
            url: primary,
            additionalURLs: Array(existingURLs.dropFirst()),
            title: "\(profile.displayName) (Uninstalled — All Leftovers)",
            subtitle: existingURLs.map(\.path).joined(separator: " + "),
            domain: .orphanedApps,
            allocatedBytes: totalBytes,
            itemCount: totalCount,
            lastModified: latestMod,
            associatedAppName: profile.displayName,
            associatedBundleID: profile.bundleIDs.first,
            advisory: parentAdv,
            subItems: subItems
        )
    }
}
