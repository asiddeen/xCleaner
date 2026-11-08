import Foundation

public struct AppUninstallerScanner: Sendable {
    public let safetyPolicy: SafetyPolicyEngine

    public init(safetyPolicy: SafetyPolicyEngine = SafetyPolicyEngine()) {
        self.safetyPolicy = safetyPolicy
    }

    public func scanInstalledApps(
        applicationRoots: [URL]? = nil,
        runningApps: [RunningApplicationSnapshot] = [],
        keepList: KeepListStore? = nil
    ) -> [InstalledAppBundle] {
        let home = safetyPolicy.homeDirectory
        let roots = applicationRoots ?? [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/Applications/Utilities"),
            URL(fileURLWithPath: "/System/Applications"),
            URL(fileURLWithPath: "/System/Applications/Utilities"),
            home.appendingPathComponent("Applications")
        ]

        let fm = FileManager.default
        var appURLs: [URL] = []

        for root in roots {
            guard let level1 = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey], options: []) else {
                continue
            }
            for item in level1 {
                if item.pathExtension.lowercased() == "app" {
                    appURLs.append(item.standardizedFileURL)
                } else if (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    if let level2 = try? fm.contentsOfDirectory(at: item, includingPropertiesForKeys: nil, options: []) {
                        for sub in level2 where sub.pathExtension.lowercased() == "app" {
                            appURLs.append(sub.standardizedFileURL)
                        }
                    }
                }
            }
        }

        var results: [InstalledAppBundle] = []

        for appURL in appURLs {
            if Task.isCancelled { break }
            let (bundleID, displayName, version) = parseAppMetadata(at: appURL)
            let isSystemProtected = isAppleOrOwnBundle(appURL: appURL, bundleID: bundleID)

            let isRunning = runningApps.contains { app in
                if let bid = bundleID, let appBid = app.bundleIdentifier, bid.caseInsensitiveCompare(appBid) == .orderedSame {
                    return true
                }
                return displayName.caseInsensitiveCompare(app.localizedName) == .orderedSame
            }

            let locations = discoverAssociatedLocations(
                appURL: appURL,
                bundleID: bundleID,
                displayName: displayName,
                isSystemProtected: isSystemProtected,
                isRunning: isRunning,
                keepList: keepList
            )

            results.append(
                InstalledAppBundle(
                    appURL: appURL,
                    bundleID: bundleID,
                    displayName: displayName,
                    version: version,
                    isSystemProtected: isSystemProtected,
                    isRunning: isRunning,
                    locations: locations
                )
            )
        }

        return results.sorted { $0.totalFootprintBytes > $1.totalFootprintBytes }
    }

    private func isAppleOrOwnBundle(appURL: URL, bundleID: String?) -> Bool {
        let path = appURL.path
        if path.hasPrefix("/System/") || path.hasPrefix("/System/Applications") {
            return true
        }
        if let bid = bundleID?.lowercased() {
            if bid.hasPrefix("com.apple.") || bid == "com.xcleaner.app" {
                return true
            }
        }
        if appURL.lastPathComponent.lowercased() == "xcleaner.app" {
            return true
        }
        return false
    }

    private func parseAppMetadata(at appURL: URL) -> (bundleID: String?, displayName: String, version: String?) {
        let baseName = appURL.deletingPathExtension().lastPathComponent
        let infoPlistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            return (nil, baseName, nil)
        }

        let bid = plist["CFBundleIdentifier"] as? String
        let name = (plist["CFBundleDisplayName"] as? String) ?? (plist["CFBundleName"] as? String) ?? baseName
        let version = (plist["CFBundleShortVersionString"] as? String) ?? (plist["CFBundleVersion"] as? String)
        return (bid, name, version)
    }

    private func discoverAssociatedLocations(
        appURL: URL,
        bundleID: String?,
        displayName: String,
        isSystemProtected: Bool,
        isRunning: Bool,
        keepList: KeepListStore?
    ) -> [AppAssociatedLocation] {
        let home = safetyPolicy.homeDirectory
        let fm = FileManager.default
        var locations: [AppAssociatedLocation] = []

        // 1. The App bundle itself
        let appFootprint = ConcurrentDiskScanner.measureFootprint(at: appURL)
        let appPinned = keepList?.isPinned(url: appURL) ?? false
        let appAdvisory: ItemAdvisory
        if isSystemProtected {
            appAdvisory = ItemAdvisory(
                level: .protected,
                badgeTitle: "Protected System Bundle",
                whatIsThis: "\(displayName) is a core macOS system or security-protected application.",
                consequenceIfRemoved: "Apple system and xCleaner binaries cannot be removed.",
                requiresExplicitAck: false
            )
        } else {
            appAdvisory = ItemAdvisory(
                level: .warning,
                badgeTitle: "Warning • Application Executable",
                whatIsThis: "The main application bundle for \(displayName) in /Applications.",
                consequenceIfRemoved: "Trashing the app bundle uninstalls \(displayName) from macOS.",
                requiresExplicitAck: true,
                lockedByAppName: isRunning ? displayName : nil,
                isPinnedByUser: appPinned
            ).withPinState(appPinned)
        }

        locations.append(
            AppAssociatedLocation(
                url: appURL,
                category: .appBundle,
                allocatedBytes: appFootprint.allocatedBytes,
                itemCount: appFootprint.itemCount,
                lastModified: appFootprint.lastModified,
                advisory: appAdvisory
            )
        )

        // Only search user Library for third-party apps or user-writable locations
        guard let bid = bundleID, !bid.isEmpty else { return locations }
        let rawBid = bid.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerBid = rawBid.lowercased()
        let normName = InstalledAppsIndex.normalize(displayName)

        // Potential relative sub-paths in ~/Library
        struct TargetCandidate {
            let relativePath: String
            let category: AppLocationCategory
            let title: String
        }

        var candidates: [TargetCandidate] = [
            // Safe caches & logs
            TargetCandidate(relativePath: "Library/Caches/\(rawBid)", category: .safeCacheOrLog, title: "Caches"),
            TargetCandidate(relativePath: "Library/Caches/\(displayName)", category: .safeCacheOrLog, title: "Caches"),
            TargetCandidate(relativePath: "Library/Caches/\(rawBid).ShipIt", category: .safeCacheOrLog, title: "Update Staging"),
            TargetCandidate(relativePath: "Library/Logs/\(displayName)", category: .safeCacheOrLog, title: "Logs"),
            TargetCandidate(relativePath: "Library/Logs/\(rawBid)", category: .safeCacheOrLog, title: "Logs"),
            TargetCandidate(relativePath: "Library/Saved Application State/\(rawBid).savedState", category: .safeCacheOrLog, title: "Saved State"),
            TargetCandidate(relativePath: "Library/WebKit/\(rawBid)", category: .safeCacheOrLog, title: "WebKit Cache"),
            TargetCandidate(relativePath: "Library/HTTPStorages/\(rawBid)", category: .safeCacheOrLog, title: "HTTP Storage"),

            // Application Support & Containers
            TargetCandidate(relativePath: "Library/Application Support/\(displayName)", category: .supportAndContainers, title: "Application Support"),
            TargetCandidate(relativePath: "Library/Application Support/\(rawBid)", category: .supportAndContainers, title: "Application Support"),
            TargetCandidate(relativePath: "Library/Containers/\(rawBid)", category: .supportAndContainers, title: "Sandboxed Container"),

            // Preferences
            TargetCandidate(relativePath: "Library/Preferences/\(rawBid).plist", category: .preferences, title: "Preferences (.plist)")
        ]

        // Special IDE profiles
        if normName == "visualstudiocode" || lowerBid == "com.microsoft.vscode" {
            candidates.append(TargetCandidate(relativePath: ".vscode", category: .supportAndContainers, title: "Extensions (~/.vscode)"))
            candidates.append(TargetCandidate(relativePath: "Library/Application Support/Code", category: .supportAndContainers, title: "VS Code Support"))
        } else if normName == "cursor" {
            candidates.append(TargetCandidate(relativePath: ".cursor", category: .supportAndContainers, title: "Cursor Config (~/.cursor)"))
        } else if normName == "windsurf" {
            candidates.append(TargetCandidate(relativePath: ".windsurf", category: .supportAndContainers, title: "Windsurf Config (~/.windsurf)"))
        }

        var seenPaths = Set<String>([appURL.path])

        for c in candidates {
            let targetURL = home.appendingPathComponent(c.relativePath).standardizedFileURL
            let p = targetURL.path
            guard !seenPaths.contains(p) else { continue }
            seenPaths.insert(p)
            guard fm.fileExists(atPath: p) else { continue }

            let footprint = ConcurrentDiskScanner.measureFootprint(at: targetURL)
            guard footprint.allocatedBytes > 0 else { continue }

            let isPinned = keepList?.isPinned(url: targetURL) ?? false
            let advisory: ItemAdvisory

            if isSystemProtected {
                advisory = ItemAdvisory(
                    level: .protected,
                    badgeTitle: "System Data Protected",
                    whatIsThis: "\(displayName) \(c.title) is managed by Apple macOS.",
                    consequenceIfRemoved: "Protected by system safety policy.",
                    requiresExplicitAck: false
                )
            } else if c.category == .safeCacheOrLog {
                advisory = ItemAdvisory(
                    level: .safe,
                    badgeTitle: "Safe • Regenerable Cache",
                    whatIsThis: "\(displayName) \(c.title) in \(c.relativePath).",
                    consequenceIfRemoved: "Recreated automatically if \(displayName) runs again; logins and settings stay intact.",
                    requiresExplicitAck: false,
                    lockedByAppName: isRunning ? displayName : nil,
                    isPinnedByUser: isPinned
                ).withPinState(isPinned)
            } else {
                advisory = ItemAdvisory(
                    level: .warning,
                    badgeTitle: "Warning • \(c.title)",
                    whatIsThis: "\(displayName) \(c.title) in \(c.relativePath).",
                    consequenceIfRemoved: "Removes saved local user data, templates, or preferences for \(displayName).",
                    requiresExplicitAck: true,
                    lockedByAppName: isRunning ? displayName : nil,
                    isPinnedByUser: isPinned
                ).withPinState(isPinned)
            }

            locations.append(
                AppAssociatedLocation(
                    url: targetURL,
                    category: c.category,
                    allocatedBytes: footprint.allocatedBytes,
                    itemCount: footprint.itemCount,
                    lastModified: footprint.lastModified,
                    advisory: advisory
                )
            )
        }

        return locations
    }
}
