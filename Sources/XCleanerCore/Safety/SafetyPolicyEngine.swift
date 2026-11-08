import Foundation

public struct ProtectionVerdict: Sendable, Equatable {
    public let isProtected: Bool
    public let reasonTitle: String?
    public let explanation: String?

    public static let allowed = ProtectionVerdict(isProtected: false, reasonTitle: nil, explanation: nil)

    public static func blocked(title: String, explanation: String) -> ProtectionVerdict {
        ProtectionVerdict(isProtected: true, reasonTitle: title, explanation: explanation)
    }
}

public struct SafetyPolicyEngine: Sendable {
    public let homeDirectory: URL

    private static let hardSystemPrefixes: [String] = [
        "/System",
        "/Library",
        "/usr",
        "/bin",
        "/sbin",
        "/cores",
        "/dev",
        "/etc",
        "/private/etc",
        "/private/var/db",
        "/private/var/vm",
        "/private/var/root",
        "/private/var/run",
        "/private/var/log",
        "/private/var/spool",
        "/private/var/install",
        "/private/var/protected",
        "/private/var/audit",
        "/private/var/networkd",
        "/var/db",
        "/var/vm",
        "/var/root",
        "/var/run",
        "/var/log",
        "/var/spool",
        "/var/install",
        "/var/protected",
        "/Applications",
        "/opt/homebrew/Cellar",
        "/usr/local/Cellar"
    ]

    private static let exactProtectedRoots: Set<String> = [
        "/",
        "/Users",
        "/Volumes",
        "/private",
        "/private/var",
        "/private/tmp",
        "/var",
        "/tmp"
    ]

    private static let protectedCredentialExtensions: Set<String> = [
        "pem", "key", "p12", "pfx", "kdbx", "keystore", "jks", "mobileprovision", "cer", "crt"
    ]

    private static let protectedBrowserDataNames: Set<String> = [
        "cookies",
        "cookies-journal",
        "login data",
        "login data for account",
        "bookmarks",
        "bookmarks.bak",
        "history",
        "favicons",
        "sessions",
        "session storage",
        "local storage",
        "indexeddb",
        "extension cookies",
        "sync data",
        "preferences",
        "secure preferences",
        "web data",
        "passkey_enclave_state",
        "trusted_vault.pb"
    ]

    public init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.homeDirectory = homeDirectory.standardizedFileURL
    }

    public func evaluateProtection(for url: URL) -> ProtectionVerdict {
        let standardized = url.standardizedFileURL
        let resolved = url.resolvingSymlinksInPath().standardizedFileURL

        let verdict1 = evaluateSinglePath(standardized.path)
        if verdict1.isProtected {
            return verdict1
        }
        if resolved.path != standardized.path {
            let verdict2 = evaluateSinglePath(resolved.path)
            if verdict2.isProtected {
                return ProtectionVerdict.blocked(
                    title: "Symlink to Protected Path",
                    explanation: "Points to protected target \(resolved.path). Protected by xCleaner safety policy."
                )
            }
        }
        return .allowed
    }

    private func evaluateSinglePath(_ rawPath: String) -> ProtectionVerdict {
        let trimmed = rawPath == "/" ? "/" : (rawPath.hasSuffix("/") ? String(rawPath.dropLast()) : rawPath)
        let homePath = homeDirectory.path
        let resolvedHome = homeDirectory.resolvingSymlinksInPath().standardizedFileURL.path

        // Normalize symlink-resolved paths inside homeDirectory (e.g. /private/var/folders/... -> /var/folders/...)
        let path: String
        if resolvedHome != homePath && (trimmed == resolvedHome || trimmed.hasPrefix(resolvedHome + "/")) {
            path = homePath + String(trimmed.dropFirst(resolvedHome.count))
        } else {
            path = trimmed
        }

        if path.isEmpty || Self.exactProtectedRoots.contains(path) {
            return .blocked(
                title: "Root / System Directory Protected",
                explanation: "Top-level macOS filesystem roots cannot be modified or deleted."
            )
        }

        // Protect xCleaner's own app bundle & storage
        let ownSupport = "\(homePath)/Library/Application Support/xCleaner"
        if path == ownSupport || path.hasPrefix(ownSupport + "/") {
            return .blocked(
                title: "xCleaner Data Protected",
                explanation: "Contains xCleaner's own audit logs and pinned keep-list."
            )
        }
        let mainBundlePath = Bundle.main.bundleURL.standardizedFileURL.path
        if mainBundlePath.hasSuffix(".app") && (path == mainBundlePath || path.hasPrefix(mainBundlePath + "/")) {
            return .blocked(
                title: "Active Application Bundle",
                explanation: "xCleaner's running application bundle is protected."
            )
        }

        // Protect user's top-level home directory and standard root folders from whole-folder deletion
        let topLevelHomeRoots: Set<String> = [
            homePath,
            "\(homePath)/Desktop",
            "\(homePath)/Documents",
            "\(homePath)/Downloads",
            "\(homePath)/Library",
            "\(homePath)/Library/Application Support",
            "\(homePath)/Library/Caches",
            "\(homePath)/Library/Containers",
            "\(homePath)/Library/Group Containers",
            "\(homePath)/Movies",
            "\(homePath)/Music",
            "\(homePath)/Pictures",
            "\(homePath)/Projects",
            "\(homePath)/Public",
            "\(homePath)/Applications"
        ]
        if topLevelHomeRoots.contains(path) {
            return .blocked(
                title: "Top-Level Home Folder",
                explanation: "Top-level macOS user directories cannot be deleted as a whole. Drill inside to select specific items."
            )
        }

        // Hard OS & SIP prefixes
        for prefix in Self.hardSystemPrefixes {
            if path == prefix || path.hasPrefix(prefix + "/") {
                return .blocked(
                    title: "macOS System / Installed Binaries",
                    explanation: "System directories and installed application bundles outside user caches are protected to keep macOS stable."
                )
            }
        }

        // Source control directories (.git, .svn, .hg)
        let components = path.split(separator: "/").map(String.init)
        if components.contains(".git") || components.contains(".svn") || components.contains(".hg") {
            return .blocked(
                title: "Version Control Repository (.git)",
                explanation: "Git/VCS repository metadata stores commit history and branches and is strictly protected."
            )
        }

        // Cryptographic keys & certificates by extension
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()
        if Self.protectedCredentialExtensions.contains(ext) {
            return .blocked(
                title: "Cryptographic Key / Certificate",
                explanation: "Key, certificate, and password vault files (.\(ext)) are protected against accidental removal."
            )
        }

        // Critical user credentials & cloud/library databases
        let protectedHomeSubtrees: [(String, String, String)] = [
            ("\(homePath)/.ssh", "SSH Keys & Config", "Contains SSH keys, known_hosts, and remote server configuration."),
            ("\(homePath)/.gnupg", "GPG Keyring", "Contains GPG cryptographic keys and trust database."),
            ("\(homePath)/.aws", "AWS Credentials", "Contains AWS CLI credentials and profiles."),
            ("\(homePath)/.kube", "Kubernetes Config", "Contains cluster kubeconfig and authentication tokens."),
            ("\(homePath)/.config/gcloud", "Google Cloud Auth", "Contains gcloud SDK credentials and configurations."),
            ("\(homePath)/.docker/config.json", "Docker Registry Auth", "Stores Docker registry authentication and active contexts."),
            ("\(homePath)/.gemini/oauth_creds.json", "OAuth Credentials", "Active authentication token file."),
            ("\(homePath)/.gemini/google_accounts.json", "Account Credentials", "Active Google account configuration."),
            ("\(homePath)/.gemini/jetski-standalone-oauth-token", "Auth Token", "Active authentication token."),
            ("\(homePath)/Library/Keychains", "macOS Keychains", "Stores encrypted macOS login passwords, certificates, and secrets."),
            ("\(homePath)/Library/Preferences", "macOS App Preferences", "Stores active cfprefsd .plist configuration files for macOS and apps."),
            ("\(homePath)/Library/Mail", "Apple Mail Database", "Stores local Apple Mail messages and account mailboxes."),
            ("\(homePath)/Library/Messages", "iMessage Database", "Stores Messages chat database and attachments."),
            ("\(homePath)/Library/Safari", "Safari Bookmarks & State", "Stores Safari bookmarks, history, and extensions."),
            ("\(homePath)/Library/Mobile Documents", "iCloud Drive Synced Root", "Deleting files in Mobile Documents propagates deletions to iCloud across your devices."),
            ("\(homePath)/Library/CloudStorage", "Cloud Storage Mount", "Deleting files in CloudStorage (Google Drive, OneDrive, Dropbox) removes synced cloud files."),
            ("\(homePath)/Google Drive", "Google Drive Link", "Points to synced Google Drive cloud files."),
            ("\(homePath)/Library/Application Support/MobileSync", "iOS / iPadOS Device Backups", "Contains encrypted local iPhone/iPad backups managed via Finder."),
            ("\(homePath)/Library/Application Support/AddressBook", "Contacts Database", "Stores macOS Contacts records."),
            ("\(homePath)/Library/Calendars", "Calendars Database", "Stores macOS Calendar events."),
            ("\(homePath)/Library/Photos", "Apple Photos System Data", "Stores Apple Photos library databases."),
            ("\(homePath)/Pictures/Photos Library.photoslibrary", "Apple Photos Library", "Contains your personal Photos & Videos library."),
            ("\(homePath)/Library/Cookies", "System Cookies", "Stores authentication cookies."),
            ("\(homePath)/Library/Accounts", "macOS Internet Accounts", "Stores signed-in macOS account tokens."),
            ("\(homePath)/Library/Passwords", "Apple Passwords Data", "Stores macOS Passwords metadata.")
        ]

        for (prefix, title, explanation) in protectedHomeSubtrees {
            if path == prefix || path.hasPrefix(prefix + "/") {
                return .blocked(title: title, explanation: explanation)
            }
        }

        // Raw Container / VM Disk Images (must be pruned via CLI, never deleted directly)
        let lastComponent = url.lastPathComponent.lowercased()
        if lastComponent == "docker.raw" ||
            path.hasPrefix("\(homePath)/Library/Containers/com.docker.docker/Data/vms") ||
            path.hasPrefix("\(homePath)/.orbstack/data") ||
            path.hasPrefix("\(homePath)/.colima") {
            return .blocked(
                title: "Container Virtual Machine Disk",
                explanation: "Deleting raw VM disks (Docker.raw) destroys all containers and volumes. Use Toolchains & Docker → Safe Prune instead."
            )
        }

        // Browser Profile User State (Cookies, Login Data, Bookmarks, History, Local Storage, IndexedDB)
        if path.hasPrefix("\(homePath)/Library/Application Support/") {
            if Self.protectedBrowserDataNames.contains(lastComponent) {
                return .blocked(
                    title: "Browser Logins, Cookies & User Data",
                    explanation: "Contains browser sessions, saved logins, bookmarks, or site databases and is strictly protected."
                )
            }
            for comp in components {
                let lowerComp = comp.lowercased()
                if lowerComp == "local storage" || lowerComp == "indexeddb" || lowerComp == "session storage" {
                    // Only protect active browser profile storage (not uninstalled orphaned apps if whole folder removed, though individual storage inside active browsers is blocked)
                    return .blocked(
                        title: "Web App Local Database",
                        explanation: "IndexedDB and Local Storage hold local web application state and sessions."
                    )
                }
            }
        }

        // Default / Current Toolchain & Runtime Version Lock (Gradle, Android SDK, Node nvm, Puppeteer, Playwright)
        if let toolchainVerdict = ToolchainVersionScanner.evaluateDefaultToolchainProtection(
            for: path,
            homeDirectory: homeDirectory
        ) {
            return toolchainVerdict
        }

        return .allowed
    }
}
