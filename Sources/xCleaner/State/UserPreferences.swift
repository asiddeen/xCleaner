import Foundation
import Observation
import XCleanerCore

@MainActor
@Observable
final class UserPreferences {
    private let defaults: UserDefaults

    private enum Keys {
        static let projectRootPaths = "xcleaner.projectRootPaths"
        static let customSSHServers = "xcleaner.customSSHServers"
        static let minimumProjectStalenessDays = "xcleaner.minimumProjectStalenessDays"
        static let largeFileThresholdMB = "xcleaner.largeFileThresholdMB"
        static let lowDiskThresholdGB = "xcleaner.lowDiskThresholdGB"
        static let showMenuBarExtra = "xcleaner.showMenuBarExtra"
        static let notificationsEnabled = "xcleaner.notificationsEnabled"
    }

    var projectRootPaths: [String] {
        didSet { defaults.set(projectRootPaths, forKey: Keys.projectRootPaths) }
    }

    var customSSHServers: [SSHServerTarget] {
        didSet {
            if let data = try? JSONEncoder().encode(customSSHServers) {
                defaults.set(data, forKey: Keys.customSSHServers)
            }
        }
    }

    var minimumProjectStalenessDays: Int {
        didSet { defaults.set(minimumProjectStalenessDays, forKey: Keys.minimumProjectStalenessDays) }
    }

    var largeFileThresholdMB: Int {
        didSet { defaults.set(largeFileThresholdMB, forKey: Keys.largeFileThresholdMB) }
    }

    var lowDiskThresholdGB: Int {
        didSet { defaults.set(lowDiskThresholdGB, forKey: Keys.lowDiskThresholdGB) }
    }

    var showMenuBarExtra: Bool {
        didSet { defaults.set(showMenuBarExtra, forKey: Keys.showMenuBarExtra) }
    }

    var notificationsEnabled: Bool {
        didSet { defaults.set(notificationsEnabled, forKey: Keys.notificationsEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let savedRoots = defaults.stringArray(forKey: Keys.projectRootPaths), !savedRoots.isEmpty {
            self.projectRootPaths = savedRoots
        } else {
            let detected = ProjectArtifactScanner.defaultProjectRoots().map(\.path)
            self.projectRootPaths = detected
        }

        if let data = defaults.data(forKey: Keys.customSSHServers),
           let decoded = try? JSONDecoder().decode([SSHServerTarget].self, from: data) {
            self.customSSHServers = decoded
        } else {
            self.customSSHServers = []
        }

        self.minimumProjectStalenessDays = defaults.object(forKey: Keys.minimumProjectStalenessDays) as? Int ?? 0
        let savedLargeMB = defaults.object(forKey: Keys.largeFileThresholdMB) as? Int ?? 100
        self.largeFileThresholdMB = max(25, savedLargeMB)

        let savedLowGB = defaults.object(forKey: Keys.lowDiskThresholdGB) as? Int ?? 15
        self.lowDiskThresholdGB = max(5, savedLowGB)

        self.showMenuBarExtra = defaults.object(forKey: Keys.showMenuBarExtra) as? Bool ?? true
        self.notificationsEnabled = defaults.object(forKey: Keys.notificationsEnabled) as? Bool ?? true
    }

    var projectRootURLs: [URL] {
        projectRootPaths.map { URL(fileURLWithPath: $0).standardizedFileURL }
    }

    var largeFileMinimumBytes: Int64 {
        Int64(largeFileThresholdMB) * 1_000_000
    }

    func addProjectRoot(_ url: URL) {
        let path = url.standardizedFileURL.path
        guard !projectRootPaths.contains(path) else { return }
        projectRootPaths.append(path)
    }

    func removeProjectRoot(path: String) {
        projectRootPaths.removeAll { $0 == path }
    }

    func addCustomSSHServer(alias: String, host: String, user: String?, port: Int?) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHost.isEmpty else { return }
        let trimmedAlias = alias.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = SSHServerTarget(
            alias: trimmedAlias.isEmpty ? trimmedHost : trimmedAlias,
            host: trimmedHost,
            user: user?.trimmingCharacters(in: .whitespacesAndNewlines),
            port: port,
            source: "Custom"
        )
        if !customSSHServers.contains(where: { $0.id == target.id }) {
            customSSHServers.append(target)
        }
    }

    func removeCustomSSHServer(id: String) {
        customSSHServers.removeAll { $0.id == id }
    }
}
