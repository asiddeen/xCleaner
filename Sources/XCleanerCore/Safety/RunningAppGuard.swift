import AppKit
import Foundation

public struct RunningApplicationSnapshot: Sendable, Equatable {
    public let bundleIdentifier: String?
    public let localizedName: String
    public let executablePath: String?

    public init(bundleIdentifier: String?, localizedName: String, executablePath: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.localizedName = localizedName
        self.executablePath = executablePath
    }
}

public protocol RunningAppChecking: Sendable {
    func activeApplications() async -> [RunningApplicationSnapshot]
    func requestGracefulTermination(bundleID: String?, appName: String?) async -> Bool
}

public struct LiveRunningAppGuard: RunningAppChecking {
    public init() {}

    public func activeApplications() async -> [RunningApplicationSnapshot] {
        await MainActor.run {
            NSWorkspace.shared.runningApplications.compactMap { app in
                guard !app.isTerminated else { return nil }
                let name = app.localizedName ?? app.bundleIdentifier ?? "Application"
                return RunningApplicationSnapshot(
                    bundleIdentifier: app.bundleIdentifier,
                    localizedName: name,
                    executablePath: app.executableURL?.path
                )
            }
        }
    }

    public func requestGracefulTermination(bundleID: String?, appName: String?) async -> Bool {
        await MainActor.run {
            let apps = NSWorkspace.shared.runningApplications.filter { app in
                guard !app.isTerminated else { return false }
                if let bundleID, let candidateID = app.bundleIdentifier,
                   candidateID.caseInsensitiveCompare(bundleID) == .orderedSame {
                    return true
                }
                if let appName, let candidateName = app.localizedName,
                   candidateName.caseInsensitiveCompare(appName) == .orderedSame {
                    return true
                }
                return false
            }
            guard !apps.isEmpty else { return true }
            var allSignaled = true
            for app in apps {
                if !app.terminate() {
                    allSignaled = false
                }
            }
            return allSignaled
        }
    }
}

public enum RunningLockMatcher {
    public static func findLockingApp(
        for url: URL,
        explicitBundleID: String? = nil,
        explicitAppName: String? = nil,
        runningApps: [RunningApplicationSnapshot],
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> RunningApplicationSnapshot? {
        // 1. Check explicit bundle ID or app name if supplied by rule
        if let explicitBundleID {
            if let match = runningApps.first(where: {
                $0.bundleIdentifier?.caseInsensitiveCompare(explicitBundleID) == .orderedSame
            }) {
                return match
            }
        }
        if let explicitAppName {
            if let match = runningApps.first(where: {
                $0.localizedName.caseInsensitiveCompare(explicitAppName) == .orderedSame
            }) {
                return match
            }
        }

        let path = url.standardizedFileURL.path
        let lowerPath = path.lowercased()

        // 2. Check Chromium SingletonLock inside ~/Library/Application Support/<App>/SingletonLock
        let appSupportRoot = homeDirectory.appendingPathComponent("Library/Application Support").standardizedFileURL.path
        if path.hasPrefix(appSupportRoot + "/") {
            let relative = String(path.dropFirst(appSupportRoot.count + 1))
            let topComponents = relative.split(separator: "/").map(String.init)
            if let first = topComponents.first {
                let candidateRoots: [URL]
                if first == "Google", topComponents.count >= 2 {
                    candidateRoots = [
                        URL(fileURLWithPath: appSupportRoot).appendingPathComponent("Google/\(topComponents[1])")
                    ]
                } else {
                    candidateRoots = [URL(fileURLWithPath: appSupportRoot).appendingPathComponent(first)]
                }
                for root in candidateRoots {
                    let singletonLock = root.appendingPathComponent("SingletonLock")
                    if (try? FileManager.default.attributesOfItem(atPath: singletonLock.path)) != nil {
                        // Verify if the app itself is in runningApps, or report the folder owner as active via SingletonLock
                        let inferredName = root.lastPathComponent
                        if let match = runningApps.first(where: {
                            $0.localizedName.localizedCaseInsensitiveContains(inferredName)
                        }) {
                            return match
                        }
                        return RunningApplicationSnapshot(bundleIdentifier: explicitBundleID, localizedName: inferredName)
                    }
                }
            }
        }

        // 3. Match ~/Library/Caches/<bundle-id-or-name> against running apps
        let cachesRoot = homeDirectory.appendingPathComponent("Library/Caches").standardizedFileURL.path
        if path.hasPrefix(cachesRoot + "/") {
            let folderName = String(path.dropFirst(cachesRoot.count + 1)).split(separator: "/").first.map(String.init) ?? ""
            let cleanFolder = folderName.replacingOccurrences(of: ".ShipIt", with: "")
            if !cleanFolder.isEmpty {
                for app in runningApps {
                    if let bid = app.bundleIdentifier, bid.caseInsensitiveCompare(cleanFolder) == .orderedSame {
                        return app
                    }
                    if app.localizedName.caseInsensitiveCompare(cleanFolder) == .orderedSame {
                        return app
                    }
                }
            }
        }

        // 4. Special guard for Google Chrome when cleaning ~/Library/Caches/Google/Chrome
        if lowerPath.contains("/caches/google/chrome") {
            if let match = runningApps.first(where: { $0.bundleIdentifier == "com.google.Chrome" }) {
                return match
            }
        }

        return nil
    }
}
