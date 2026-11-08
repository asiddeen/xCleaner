import AppKit
import Foundation
import Observation
import XCleanerCore

enum SidebarSection: String, CaseIterable, Identifiable {
    case storagePulse = "Storage Pulse"
    case smartJunk = "Smart Junk"
    case appUninstaller = "App Uninstaller"
    case toolchainsAndDocker = "Toolchains & Docker"
    case visualExplorer = "Visual Explorer"
    case largeFiles = "Large & Stale Files"
    case cleanupHistory = "Cleanup History"
    case settings = "Settings & Keep List"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .storagePulse: return "gauge.with.dots.needle.67percent"
        case .smartJunk: return "sparkles.rectangle.stack"
        case .appUninstaller: return "app.badge.checkmark"
        case .toolchainsAndDocker: return "shippingbox.and.arrow.backward"
        case .visualExplorer: return "square.grid.3x2"
        case .largeFiles: return "doc.badge.clock"
        case .cleanupHistory: return "clock.arrow.circlepath"
        case .settings: return "slider.horizontal.3"
        }
    }

    var subtitle: String {
        switch self {
        case .storagePulse: return "APFS & Swap Health"
        case .smartJunk: return "Caches, Apps & Builds"
        case .appUninstaller: return "Uninstall & Leftover Sweep"
        case .toolchainsAndDocker: return "SDKs, Runtimes & SSH"
        case .visualExplorer: return "Size Bars & Treemap"
        case .largeFiles: return "Installers & Archives"
        case .cleanupHistory: return "Freed Space Audit Log"
        case .settings: return "Roots & Pinned Items"
        }
    }
}

enum InspectorSubject: Equatable {
    case scannable(ScannableItem)
    case toolchain(ToolchainItem)
    case diskNode(DiskNode)
    case largeFile(LargeFileItem)
    case appLocation(InstalledAppBundle, AppAssociatedLocation)

    var id: String {
        switch self {
        case .scannable(let i): return "junk:\(i.id)"
        case .toolchain(let i): return "tool:\(i.id)"
        case .diskNode(let n): return "node:\(n.id)"
        case .largeFile(let f): return "large:\(f.id)"
        case .appLocation(let app, let loc): return "apploc:\(app.id):\(loc.id)"
        }
    }

    var title: String {
        switch self {
        case .scannable(let i): return i.title
        case .toolchain(let i): return "\(i.componentKind) (\(i.version))"
        case .diskNode(let n): return n.name
        case .largeFile(let f): return f.name
        case .appLocation(let app, let loc): return "\(app.displayName) — \(loc.category.rawValue)"
        }
    }

    var primaryURL: URL {
        switch self {
        case .scannable(let i): return i.url
        case .toolchain(let i): return i.primaryURL
        case .diskNode(let n): return n.url
        case .largeFile(let f): return f.url
        case .appLocation(_, let loc): return loc.url
        }
    }

    var allURLs: [URL] {
        switch self {
        case .scannable(let i): return i.allTargetURLs
        case .toolchain(let i): return i.urls
        case .diskNode(let n): return [n.url]
        case .largeFile(let f): return [f.url]
        case .appLocation(_, let loc): return [loc.url]
        }
    }

    var allocatedBytes: Int64 {
        switch self {
        case .scannable(let i): return i.allocatedBytes
        case .toolchain(let i): return i.allocatedBytes
        case .diskNode(let n): return n.allocatedBytes
        case .largeFile(let f): return f.allocatedBytes
        case .appLocation(_, let loc): return loc.allocatedBytes
        }
    }

    var itemCount: Int {
        switch self {
        case .scannable(let i): return i.itemCount
        case .toolchain(let i): return i.urls.count
        case .diskNode(let n): return n.itemCount
        case .largeFile: return 1
        case .appLocation(_, let loc): return loc.itemCount
        }
    }

    var lastModified: Date? {
        switch self {
        case .scannable(let i): return i.lastModified
        case .toolchain(let i): return i.lastModified
        case .diskNode(let n): return n.lastModified
        case .largeFile(let f): return f.lastModified
        case .appLocation(_, let loc): return loc.lastModified
        }
    }

    var advisory: ItemAdvisory {
        switch self {
        case .scannable(let i): return i.advisory
        case .toolchain(let i): return i.advisory
        case .diskNode(let n): return n.advisory
        case .largeFile(let f): return f.advisory
        case .appLocation(_, let loc): return loc.advisory
        }
    }

    var sourceLabel: String {
        switch self {
        case .scannable(let i): return i.domain.rawValue
        case .toolchain(let i): return i.ecosystem.rawValue
        case .diskNode: return "Visual Explorer"
        case .largeFile(let f): return f.category.rawValue
        case .appLocation(let app, _): return "App Uninstaller (\(app.displayName))"
        }
    }

    var associatedBundleID: String? {
        switch self {
        case .scannable(let i): return i.associatedBundleID ?? i.advisory.lockedByBundleID
        case .toolchain(let i): return i.advisory.lockedByBundleID
        case .diskNode(let n): return n.advisory.lockedByBundleID
        case .largeFile(let f): return f.advisory.lockedByBundleID
        case .appLocation(let app, let loc): return app.bundleID ?? loc.advisory.lockedByBundleID
        }
    }

    var associatedAppName: String? {
        switch self {
        case .scannable(let i): return i.associatedAppName ?? i.advisory.lockedByAppName
        case .toolchain(let i): return i.advisory.lockedByAppName
        case .diskNode(let n): return n.advisory.lockedByAppName
        case .largeFile(let f): return f.advisory.lockedByAppName
        case .appLocation(let app, _): return app.displayName
        }
    }

    func toStageTarget() -> CleanupStageTarget {
        CleanupStageTarget(
            id: primaryURL.standardizedFileURL.path,
            title: title,
            subtitle: primaryURL.path,
            urls: allURLs,
            allocatedBytes: allocatedBytes,
            sourceLabel: sourceLabel,
            associatedBundleID: associatedBundleID,
            associatedAppName: associatedAppName,
            advisory: advisory
        )
    }
}

@MainActor
@Observable
final class AppViewModel {
    // Navigation & Inspector State
    var selectedSection: SidebarSection = .storagePulse
    var inspectorSubject: InspectorSubject?
    var isInspectorVisible: Bool = true
    var isShowingQueueSheet: Bool = false

    // Preferences, Notifications & Core Services
    let preferences: UserPreferences
    let notifications: NotificationManager
    let safetyPolicy: SafetyPolicyEngine
    let advisoryEngine: AdvisoryEngine
    let keepListStore: KeepListStore
    let historyStore: CleanupHistoryStore
    let runningAppGuard: LiveRunningAppGuard

    private let volumeMonitor = APFSVolumeMonitor()
    private let smartScanner: SmartJunkScanner
    private let appUninstallerScanner: AppUninstallerScanner
    private let toolchainScanner: ToolchainVersionScanner
    private let diskScanner: ConcurrentDiskScanner
    private let largeFileScanner: LargeFileScanner
    private let dockerAndSSH: DockerAndSSHService
    private let cleanupService: CleanupService
    private let safeToolPruner = SafeToolPruner()

    // Data Snapshots
    var volumeMetrics: VolumeMetrics?
    var smartJunkReport: SmartJunkScanReport?
    var installedApps: [InstalledAppBundle] = []
    var toolchainItems: [ToolchainItem] = []
    var projectReferences = ProjectToolchainReferences()
    var localDockerStatus: LocalDockerStatus?
    var sshTargets: [SSHServerTarget] = []
    var remoteServerStatuses: [String: RemoteServerStatus] = [:]
    var dockerOperationLog: String?

    // Visual Explorer State
    var explorerScanRoot: DiskNode?
    var explorerNavigationStack: [DiskNode] = []
    var explorerProgress: ScanProgress?
    var permissionDeniedPaths: [String] = []

    // Large Files & History
    var largeFiles: [LargeFileItem] = []
    var cleanupHistory: [CleanupRecord] = []
    var pinnedEntries: [KeepListEntry] = []

    // Unified Staged Cleanup Queue
    var stagedTargets: [CleanupStageTarget] = []

    // Loading Flags & Active Cancellable Tasks
    var isRefreshingVolume = false
    var isScanningSmartJunk = false
    var isScanningApps = false
    var isScanningToolchains = false
    var isProbingDockerOrSSH = false
    var isScanningExplorer = false
    var isScanningLargeFiles = false
    var isExecutingCleanup = false
    var isRunningMaintenanceTool = false
    var maintenanceLogOutput: String?

    @ObservationIgnored private var smartScanTask: Task<Void, Never>?
    @ObservationIgnored private var explorerScanTask: Task<Void, Never>?
    @ObservationIgnored private var largeFilesTask: Task<Void, Never>?
    @ObservationIgnored private var didBootstrap = false
    @ObservationIgnored var onMenuBarVisibilityChanged: ((Bool) -> Void)?

    init(
        preferences: UserPreferences = UserPreferences(),
        notifications: NotificationManager = NotificationManager()
    ) {
        self.preferences = preferences
        self.notifications = notifications

        let policy = SafetyPolicyEngine()
        let advisory = AdvisoryEngine(safetyPolicy: policy)
        let keepStore = KeepListStore()
        let histStore = CleanupHistoryStore()
        let appGuard = LiveRunningAppGuard()

        self.safetyPolicy = policy
        self.advisoryEngine = advisory
        self.keepListStore = keepStore
        self.historyStore = histStore
        self.runningAppGuard = appGuard

        self.smartScanner = SmartJunkScanner(safetyPolicy: policy)
        self.appUninstallerScanner = AppUninstallerScanner(safetyPolicy: policy)
        self.toolchainScanner = ToolchainVersionScanner(safetyPolicy: policy)
        self.diskScanner = ConcurrentDiskScanner(advisoryEngine: advisory)
        self.largeFileScanner = LargeFileScanner(advisoryEngine: advisory)
        self.dockerAndSSH = DockerAndSSHService(homeDirectory: policy.homeDirectory)
        self.cleanupService = CleanupService(
            safetyPolicy: policy,
            runningAppGuard: appGuard,
            historyStore: histStore
        )

        self.cleanupHistory = histStore.loadAll()
        self.pinnedEntries = keepStore.allEntries()
        self.sshTargets = dockerAndSSH.discoverSSHServers(customTargets: preferences.customSSHServers)
    }

    // MARK: - Initial Bootstrap

    func performInitialLoad() {
        guard !didBootstrap else { return }
        didBootstrap = true
        notifications.requestAuthorizationIfNeeded()
        Task {
            await refreshVolumeMetrics()
            launchSmartJunkScan()
            launchAppScan()
            await refreshToolchainsAndLocalDocker()
        }
    }

    func setShowMenuBarExtra(_ visible: Bool) {
        preferences.showMenuBarExtra = visible
        onMenuBarVisibilityChanged?(visible)
    }

    // MARK: - Storage Pulse & TCC Gap

    func refreshVolumeMetrics() async {
        isRefreshingVolume = true
        defer { isRefreshingVolume = false }

        var metrics = await volumeMonitor.fetchMetrics()
        if let root = explorerScanRoot,
           root.url.path == safetyPolicy.homeDirectory.path,
           !permissionDeniedPaths.isEmpty {
            let estimatedSystemAndShared = metrics.systemVolumeBytes + 12_000_000_000
            metrics = metrics.withTCCUnscannedEstimate(
                scannedHomeAndSystemBytes: root.allocatedBytes + estimatedSystemAndShared,
                hadPermissionDenials: true
            )
        } else if !permissionDeniedPaths.isEmpty {
            // Even before full home scan, surface TCC notice if denials occurred
            metrics = VolumeMetrics(
                totalBytes: metrics.totalBytes,
                rawAvailableBytes: metrics.rawAvailableBytes,
                importantAvailableBytes: metrics.importantAvailableBytes,
                opportunisticAvailableBytes: metrics.opportunisticAvailableBytes,
                dataVolumeUsedBytes: metrics.dataVolumeUsedBytes,
                systemVolumeBytes: metrics.systemVolumeBytes,
                vmSwapBytes: metrics.vmSwapBytes,
                prebootAndRecoveryBytes: metrics.prebootAndRecoveryBytes,
                localSnapshots: metrics.localSnapshots,
                tccUnscannedBytesEstimate: metrics.tccUnscannedBytesEstimate
            )
        }
        self.volumeMetrics = metrics

        notifications.notifyLowDiskIfNeeded(
            rawAvailableBytes: metrics.rawAvailableBytes,
            thresholdGB: preferences.lowDiskThresholdGB,
            notificationsEnabled: preferences.notificationsEnabled
        )
    }

    func probeTCCFullDiskAccess() -> Bool {
        let tccProtectedTestDir = safetyPolicy.homeDirectory.appendingPathComponent("Library/Safari")
        guard FileManager.default.fileExists(atPath: tccProtectedTestDir.path) else { return true }
        return FileManager.default.isReadableFile(atPath: tccProtectedTestDir.path)
    }

    func openFullDiskAccessSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Smart Junk Scan

    func launchSmartJunkScan() {
        smartScanTask?.cancel()
        isScanningSmartJunk = true
        let roots = preferences.projectRootURLs
        let staleness = preferences.minimumProjectStalenessDays
        let keepStore = keepListStore
        let scanner = smartScanner
        let toolScanner = toolchainScanner
        let appGuard = runningAppGuard

        smartScanTask = Task {
            defer { self.isScanningSmartJunk = false }
            let running = await appGuard.activeApplications()
            do {
                let report = try await Task.detached(priority: .userInitiated) {
                    try await scanner.runSmartScan(
                        projectRoots: roots,
                        runningApps: running,
                        keepList: keepStore,
                        minimumProjectStalenessDays: staleness
                    )
                }.value
                guard !Task.isCancelled else { return }
                self.smartJunkReport = report
                self.projectReferences = report.projectReferences
                if self.inspectorSubject == nil, let topItem = report.items.first {
                    self.inspectorSubject = .scannable(topItem)
                }

                // Keep toolchains synchronized with newly discovered project references
                let updatedTools = await Task.detached(priority: .utility) {
                    toolScanner.scanAllToolchains(
                        projectReferences: report.projectReferences,
                        keepList: keepStore
                    )
                }.value
                if !Task.isCancelled {
                    self.applyUpdatedToolchains(updatedTools)
                }
            } catch is CancellationError {
                return
            } catch {
                self.notifications.postNotice(
                    severity: .caution,
                    title: "Smart Scan Interrupted",
                    message: error.localizedDescription
                )
            }
        }
    }

    func cancelSmartJunkScan() {
        smartScanTask?.cancel()
        isScanningSmartJunk = false
    }

    // MARK: - App Uninstaller & Leftover Scanner

    func launchAppScan() {
        isScanningApps = true
        let scanner = appUninstallerScanner
        let keepStore = keepListStore
        let appGuard = runningAppGuard

        Task {
            defer { self.isScanningApps = false }
            let running = await appGuard.activeApplications()
            let apps = await Task.detached(priority: .userInitiated) {
                scanner.scanInstalledApps(runningApps: running, keepList: keepStore)
            }.value
            guard !Task.isCancelled else { return }
            self.installedApps = apps
        }
    }

    func stageAppSafeCaches(_ app: InstalledAppBundle) {
        let safeLocations = app.locations.filter { $0.category == .safeCacheOrLog && $0.advisory.canBeStaged }
        var added = 0
        for loc in safeLocations {
            let target = InspectorSubject.appLocation(app, loc).toStageTarget()
            if !isStaged(urls: target.urls) {
                toggleStage(target: target)
                added += 1
            }
        }
        if added > 0 {
            notifications.postNotice(
                severity: .info,
                title: "Staged \(added) Cache(s) for \(app.displayName)",
                message: "App binary and preferences stay intact."
            )
        }
    }

    func stageAppReset(_ app: InstalledAppBundle) {
        let nonBinaryLocations = app.locations.filter { $0.category != .appBundle && $0.advisory.canBeStaged }
        var added = 0
        for loc in nonBinaryLocations {
            let target = InspectorSubject.appLocation(app, loc).toStageTarget()
            if !isStaged(urls: target.urls) {
                toggleStage(target: target)
                added += 1
            }
        }
        if added > 0 {
            notifications.postNotice(
                severity: .caution,
                title: "Staged Factory Reset for \(app.displayName)",
                message: "Staged caches, support files, and preferences. App bundle stays in /Applications."
            )
        }
    }

    func stageFullAppUninstall(_ app: InstalledAppBundle) {
        guard !app.isSystemProtected else {
            notifications.postNotice(
                severity: .warning,
                title: "System App Protected",
                message: "\(app.displayName) cannot be uninstalled."
            )
            return
        }
        var added = 0
        for loc in app.locations where loc.advisory.canBeStaged {
            let target = InspectorSubject.appLocation(app, loc).toStageTarget()
            if !isStaged(urls: target.urls) {
                toggleStage(target: target)
                added += 1
            }
        }
        if added > 0 {
            notifications.postNotice(
                severity: .warning,
                title: "Staged Full Uninstall of \(app.displayName)",
                message: "App bundle + all ~/Library leftovers staged into Cleanup Queue."
            )
        }
    }

    // MARK: - Toolchains, Local Docker & Remote SSH Servers

    func refreshToolchainsAndLocalDocker() async {
        isScanningToolchains = true
        let roots = preferences.projectRootURLs
        let keepStore = keepListStore
        let toolScanner = toolchainScanner
        let refScanner = ProjectReferenceScanner()
        let dockerSvc = dockerAndSSH

        async let refsAndToolsTask = Task.detached(priority: .userInitiated) { () -> (ProjectToolchainReferences, [ToolchainItem]) in
            let refs = refScanner.scanReferences(in: roots)
            let tools = toolScanner.scanAllToolchains(projectReferences: refs, keepList: keepStore)
            return (refs, tools)
        }.value

        async let localDockerTask = dockerSvc.inspectLocalDocker()

        let ((refs, tools), dockerStat) = await (refsAndToolsTask, localDockerTask)
        self.projectReferences = refs
        self.applyUpdatedToolchains(tools)
        self.localDockerStatus = dockerStat
        self.sshTargets = dockerSvc.discoverSSHServers(customTargets: preferences.customSSHServers)
        self.isScanningToolchains = false
    }

    private func applyUpdatedToolchains(_ tools: [ToolchainItem]) {
        self.toolchainItems = tools
        // Never allow newly locked default/current versions to remain in the staged cleanup queue
        let lockedPaths = Set(
            tools
                .filter { $0.advisory.level == .protected }
                .flatMap { $0.urls.map { $0.standardizedFileURL.path } }
        )
        if !lockedPaths.isEmpty {
            stagedTargets.removeAll { target in
                target.urls.contains { lockedPaths.contains($0.standardizedFileURL.path) }
            }
        }
    }

    func probeSSHServer(_ target: SSHServerTarget) async {
        isProbingDockerOrSSH = true
        defer { isProbingDockerOrSSH = false }
        let status = await dockerAndSSH.probeRemoteServer(target)
        remoteServerStatuses[target.id] = status
    }

    func probeAllSSHServers() async {
        sshTargets = dockerAndSSH.discoverSSHServers(customTargets: preferences.customSSHServers)
        guard !sshTargets.isEmpty else { return }
        isProbingDockerOrSSH = true
        defer { isProbingDockerOrSSH = false }

        let targets = sshTargets
        let svc = dockerAndSSH
        await withTaskGroup(of: RemoteServerStatus.self) { group in
            for target in targets {
                group.addTask {
                    await svc.probeRemoteServer(target)
                }
            }
            for await status in group {
                self.remoteServerStatuses[status.target.id] = status
            }
        }
    }

    func runLocalDockerPrune(builderCache: Bool, danglingImages: Bool) async {
        isProbingDockerOrSSH = true
        defer { isProbingDockerOrSSH = false }
        do {
            let output = try await dockerAndSSH.pruneLocalDocker(
                pruneBuilderCache: builderCache,
                pruneDanglingImages: danglingImages
            )
            dockerOperationLog = output
            historyStore.append(
                CleanupRecord(
                    actionKind: "Local Docker Safe Prune",
                    itemsCleanedCount: (builderCache ? 1 : 0) + (danglingImages ? 1 : 0),
                    freedBytes: 0,
                    cleanedPaths: ["local:docker"],
                    notes: String(output.prefix(400))
                )
            )
            cleanupHistory = historyStore.loadAll()
            localDockerStatus = await dockerAndSSH.inspectLocalDocker()
            await refreshVolumeMetrics()
            notifications.postNotice(
                severity: .success,
                title: "Local Docker Pruned",
                message: "Completed safe Docker CLI prune without touching volumes or running containers.",
                sendSystemNotification: true,
                notificationsEnabled: preferences.notificationsEnabled
            )
        } catch {
            notifications.postNotice(
                severity: .warning,
                title: "Local Docker Prune Failed",
                message: error.localizedDescription
            )
        }
    }

    func runRemoteDockerPrune(target: SSHServerTarget, builderCache: Bool, danglingImages: Bool) async {
        isProbingDockerOrSSH = true
        defer { isProbingDockerOrSSH = false }
        do {
            let output = try await dockerAndSSH.pruneRemoteDocker(
                target: target,
                pruneBuilderCache: builderCache,
                pruneDanglingImages: danglingImages
            )
            dockerOperationLog = "[\(target.displayLabel)]\n\(output)"
            historyStore.append(
                CleanupRecord(
                    actionKind: "Remote SSH Docker Prune (\(target.displayLabel))",
                    itemsCleanedCount: (builderCache ? 1 : 0) + (danglingImages ? 1 : 0),
                    freedBytes: 0,
                    cleanedPaths: ["ssh://\(target.sshDestination)"],
                    notes: String(output.prefix(400))
                )
            )
            cleanupHistory = historyStore.loadAll()
            await probeSSHServer(target)
            notifications.postNotice(
                severity: .success,
                title: "Remote Docker Pruned (\(target.alias))",
                message: "Reclaimed unused Docker build cache / images on \(target.displayLabel).",
                sendSystemNotification: true,
                notificationsEnabled: preferences.notificationsEnabled
            )
        } catch {
            notifications.postNotice(
                severity: .warning,
                title: "Remote SSH Prune Failed",
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Visual Folder Explorer

    var currentExplorerNode: DiskNode? {
        explorerNavigationStack.last ?? explorerScanRoot
    }

    func launchExplorerScan(at folderURL: URL? = nil) {
        explorerScanTask?.cancel()
        let targetURL = (folderURL ?? explorerScanRoot?.url ?? safetyPolicy.homeDirectory).standardizedFileURL
        isScanningExplorer = true
        explorerProgress = nil

        let scanner = diskScanner
        let keepStore = keepListStore
        let gradleRefs = projectReferences.gradleVersionsToProjects
        let appGuard = runningAppGuard

        explorerScanTask = Task {
            defer {
                self.isScanningExplorer = false
                self.explorerProgress = nil
            }
            let running = await appGuard.activeApplications()
            do {
                let result = try await scanner.scanDirectoryTree(
                    at: targetURL,
                    maxTreeDepth: 2,
                    runningApps: running,
                    keepList: keepStore,
                    projectGradleRefs: gradleRefs,
                    onProgress: { prog in
                        Task { @MainActor in
                            self.explorerProgress = prog
                        }
                    }
                )
                guard !Task.isCancelled else { return }
                self.explorerScanRoot = result.rootNode
                self.explorerNavigationStack = [result.rootNode]
                self.permissionDeniedPaths = result.permissionDeniedPaths
                self.inspectorSubject = .diskNode(result.rootNode)
                await self.refreshVolumeMetrics()
            } catch is CancellationError {
                return
            } catch {
                self.notifications.postNotice(
                    severity: .caution,
                    title: "Folder Scan Interrupted",
                    message: error.localizedDescription
                )
            }
        }
    }

    func cancelExplorerScan() {
        explorerScanTask?.cancel()
        isScanningExplorer = false
    }

    func drillIntoExplorerNode(_ node: DiskNode) {
        guard node.isDirectory else {
            inspectorSubject = .diskNode(node)
            return
        }
        if !node.children.isEmpty {
            explorerNavigationStack.append(node)
            inspectorSubject = .diskNode(node)
        } else {
            // Leaf directory beyond initial depth-2 tree -> scan on demand and push onto stack
            isScanningExplorer = true
            let scanner = diskScanner
            let keepStore = keepListStore
            let gradleRefs = projectReferences.gradleVersionsToProjects
            let appGuard = runningAppGuard
            Task {
                defer { self.isScanningExplorer = false }
                let running = await appGuard.activeApplications()
                if let res = try? await scanner.scanDirectoryTree(
                    at: node.url,
                    maxTreeDepth: 2,
                    runningApps: running,
                    keepList: keepStore,
                    projectGradleRefs: gradleRefs
                ) {
                    self.explorerNavigationStack.append(res.rootNode)
                    self.inspectorSubject = .diskNode(res.rootNode)
                }
            }
        }
    }

    func navigateExplorerToBreadcrumb(index: Int) {
        guard index >= 0, index < explorerNavigationStack.count else { return }
        explorerNavigationStack = Array(explorerNavigationStack.prefix(index + 1))
        if let top = currentExplorerNode {
            inspectorSubject = .diskNode(top)
        }
    }

    // MARK: - Large & Stale File Finder

    func launchLargeFilesScan() {
        largeFilesTask?.cancel()
        isScanningLargeFiles = true
        let home = safetyPolicy.homeDirectory
        var scanRoots: [URL] = [
            home.appendingPathComponent("Downloads"),
            home.appendingPathComponent("Documents"),
            home.appendingPathComponent("Desktop"),
            home.appendingPathComponent("Movies"),
            home.appendingPathComponent("Library/Caches")
        ]
        scanRoots.append(contentsOf: preferences.projectRootURLs)

        let minBytes = preferences.largeFileMinimumBytes
        let scanner = largeFileScanner
        let keepStore = keepListStore
        let appGuard = runningAppGuard

        largeFilesTask = Task {
            defer { self.isScanningLargeFiles = false }
            let running = await appGuard.activeApplications()
            do {
                let (items, denied) = try await scanner.scanLargeFiles(
                    in: scanRoots,
                    minimumBytes: minBytes,
                    runningApps: running,
                    keepList: keepStore
                )
                guard !Task.isCancelled else { return }
                self.largeFiles = items
                if !denied.isEmpty {
                    let merged = Set(self.permissionDeniedPaths).union(denied)
                    self.permissionDeniedPaths = merged.sorted()
                }
            } catch is CancellationError {
                return
            } catch {
                self.notifications.postNotice(
                    severity: .caution,
                    title: "Large File Scan Interrupted",
                    message: error.localizedDescription
                )
            }
        }
    }

    // MARK: - Safe Maintenance CLI Tools

    func runHomebrewPrune() async {
        isRunningMaintenanceTool = true
        defer { isRunningMaintenanceTool = false }
        do {
            let out = try await safeToolPruner.runHomebrewCleanup(historyStore: historyStore)
            maintenanceLogOutput = out
            cleanupHistory = historyStore.loadAll()
            await refreshVolumeMetrics()
            notifications.postNotice(severity: .success, title: "Homebrew Cache Cleaned", message: out)
        } catch {
            notifications.postNotice(severity: .warning, title: "Homebrew Cleanup Error", message: error.localizedDescription)
        }
    }

    func runSimulatorPrune() async {
        isRunningMaintenanceTool = true
        defer { isRunningMaintenanceTool = false }
        do {
            let out = try await safeToolPruner.deleteUnavailableSimulators(historyStore: historyStore)
            maintenanceLogOutput = out
            cleanupHistory = historyStore.loadAll()
            await refreshVolumeMetrics()
            notifications.postNotice(severity: .success, title: "Unavailable Simulators Removed", message: out)
        } catch {
            notifications.postNotice(severity: .warning, title: "Simulator Cleanup Error", message: error.localizedDescription)
        }
    }

    func runSnapshotThinning() async {
        isRunningMaintenanceTool = true
        defer { isRunningMaintenanceTool = false }
        do {
            let out = try await safeToolPruner.thinLocalTimeMachineSnapshots(
                targetBytes: 10_000_000_000,
                historyStore: historyStore
            )
            maintenanceLogOutput = out
            cleanupHistory = historyStore.loadAll()
            await refreshVolumeMetrics()
            notifications.postNotice(
                severity: .success,
                title: "Time Machine Snapshots Thinned",
                message: "macOS completed APFS local snapshot thinning."
            )
        } catch {
            notifications.postNotice(
                severity: .caution,
                title: "Snapshot Thinning Cancelled or Failed",
                message: error.localizedDescription
            )
        }
    }

    // MARK: - Pin to Keep & Graceful App Quit

    func isPinned(_ urls: [URL]) -> Bool {
        keepListStore.isPinned(urls: urls)
    }

    func togglePin(urls: [URL], label: String) {
        guard !urls.isEmpty else { return }
        let currentlyPinned = keepListStore.isPinned(urls: urls)
        if currentlyPinned {
            for u in urls { keepListStore.unpin(url: u) }
            notifications.postNotice(
                severity: .info,
                title: "Unpinned \(label)",
                message: "\(label) can now be staged if you choose to clean it."
            )
        } else {
            for u in urls { keepListStore.pin(url: u, label: label) }
            // Immediately remove any staged item overlapping newly pinned paths
            let pinnedSet = Set(urls.map { $0.standardizedFileURL.path })
            stagedTargets.removeAll { target in
                target.urls.contains { u in
                    let p = u.standardizedFileURL.path
                    return pinnedSet.contains { pinned in p == pinned || p.hasPrefix(pinned + "/") }
                }
            }
            notifications.postNotice(
                severity: .success,
                title: "Pinned \(label) to Keep",
                message: "xCleaner will never stage or delete \(label) unless you unpin it."
            )
        }
        pinnedEntries = keepListStore.allEntries()
        refreshInMemoryAdvisories()
    }

    func unpinEntry(_ entry: KeepListEntry) {
        keepListStore.unpin(path: entry.path)
        pinnedEntries = keepListStore.allEntries()
        refreshInMemoryAdvisories()
    }

    func quitAppAndRefreshLocks(bundleID: String?, appName: String) {
        Task {
            let signaled = await runningAppGuard.requestGracefulTermination(bundleID: bundleID, appName: appName)
            if signaled {
                notifications.postNotice(
                    severity: .info,
                    title: "Requested \(appName) to Quit",
                    message: "Waiting for \(appName) to close active file locks…"
                )
                try? await Task.sleep(for: .milliseconds(1200))
                launchSmartJunkScan()
            } else {
                notifications.postNotice(
                    severity: .caution,
                    title: "Could Not Quit \(appName) Automatically",
                    message: "Please quit \(appName) manually, then click Rescan."
                )
            }
        }
    }

    private func refreshInMemoryAdvisories() {
        if let report = smartJunkReport {
            let updated = report.items.map { updatePinOnScannable($0) }
            smartJunkReport = SmartJunkScanReport(
                items: updated,
                projectReferences: report.projectReferences,
                scannedAt: report.scannedAt
            )
        }
        toolchainItems = toolchainItems.map { item in
            let pinned = keepListStore.isPinned(urls: item.urls)
            return ToolchainItem(
                id: item.id,
                ecosystem: item.ecosystem,
                componentKind: item.componentKind,
                version: item.version,
                urls: item.urls,
                allocatedBytes: item.allocatedBytes,
                lastModified: item.lastModified,
                status: item.status,
                advisory: item.advisory.withPinState(pinned)
            )
        }
        largeFiles = largeFiles.map { file in
            let pinned = keepListStore.isPinned(url: file.url)
            return LargeFileItem(
                url: file.url,
                category: file.category,
                allocatedBytes: file.allocatedBytes,
                lastModified: file.lastModified,
                lastAccessed: file.lastAccessed,
                advisory: file.advisory.withPinState(pinned)
            )
        }
        if let subject = inspectorSubject {
            let pinned = keepListStore.isPinned(urls: subject.allURLs)
            switch subject {
            case .scannable(let s):
                inspectorSubject = .scannable(updatePinOnScannable(s))
            case .toolchain(let t):
                inspectorSubject = .toolchain(
                    ToolchainItem(
                        id: t.id,
                        ecosystem: t.ecosystem,
                        componentKind: t.componentKind,
                        version: t.version,
                        urls: t.urls,
                        allocatedBytes: t.allocatedBytes,
                        lastModified: t.lastModified,
                        status: t.status,
                        advisory: t.advisory.withPinState(pinned)
                    )
                )
            case .diskNode(let n):
                inspectorSubject = .diskNode(
                    DiskNode(
                        url: n.url,
                        name: n.name,
                        isDirectory: n.isDirectory,
                        allocatedBytes: n.allocatedBytes,
                        logicalBytes: n.logicalBytes,
                        itemCount: n.itemCount,
                        lastModified: n.lastModified,
                        lastAccessed: n.lastAccessed,
                        advisory: n.advisory.withPinState(pinned),
                        children: n.children
                    )
                )
            case .largeFile(let f):
                inspectorSubject = .largeFile(
                    LargeFileItem(
                        url: f.url,
                        category: f.category,
                        allocatedBytes: f.allocatedBytes,
                        lastModified: f.lastModified,
                        lastAccessed: f.lastAccessed,
                        advisory: f.advisory.withPinState(pinned)
                    )
                )
            case .appLocation(let app, let loc):
                inspectorSubject = .appLocation(
                    app,
                    AppAssociatedLocation(
                        url: loc.url,
                        category: loc.category,
                        allocatedBytes: loc.allocatedBytes,
                        itemCount: loc.itemCount,
                        lastModified: loc.lastModified,
                        advisory: loc.advisory.withPinState(pinned)
                    )
                )
            }
        }
    }

    private func updatePinOnScannable(_ item: ScannableItem) -> ScannableItem {
        let pinned = keepListStore.isPinned(urls: item.allTargetURLs)
        let updatedSubs = item.subItems.map { updatePinOnScannable($0) }
        return ScannableItem(
            id: item.id,
            url: item.url,
            additionalURLs: item.additionalURLs,
            title: item.title,
            subtitle: item.subtitle,
            domain: item.domain,
            allocatedBytes: item.allocatedBytes,
            itemCount: item.itemCount,
            lastModified: item.lastModified,
            stalenessDays: item.stalenessDays,
            associatedAppName: item.associatedAppName,
            associatedBundleID: item.associatedBundleID,
            advisory: item.advisory.withPinState(pinned),
            subItems: updatedSubs
        )
    }

    // MARK: - Unified Cleanup Queue Management

    var totalStagedBytes: Int64 {
        stagedTargets.reduce(0) { $0 + $1.allocatedBytes }
    }

    var stagedWarningTargets: [CleanupStageTarget] {
        stagedTargets.filter { $0.advisory.level == .warning || $0.advisory.requiresExplicitAck }
    }

    var stagedCautionCount: Int {
        stagedTargets.filter { $0.advisory.level == .caution }.count
    }

    func isStaged(urls: [URL]) -> Bool {
        let candidatePaths = urls.map { $0.standardizedFileURL.path }
        return stagedTargets.contains { target in
            let stagedPaths = target.urls.map { $0.standardizedFileURL.path }
            return candidatePaths.allSatisfy { cand in
                stagedPaths.contains { sp in cand == sp || cand.hasPrefix(sp + "/") }
            }
        }
    }

    func toggleStage(subject: InspectorSubject) {
        let target = subject.toStageTarget()
        toggleStage(target: target)
    }

    func toggleStage(target: CleanupStageTarget) {
        if isStaged(urls: target.urls) {
            unstage(urls: target.urls)
            return
        }

        // Guardrails before staging
        if target.advisory.level == .protected {
            notifications.postNotice(
                severity: .warning,
                title: "Protected Item Cannot Be Staged",
                message: target.advisory.whatIsThis
            )
            return
        }
        if target.advisory.isPinnedByUser || keepListStore.isPinned(urls: target.urls) {
            notifications.postNotice(
                severity: .info,
                title: "Item Is Pinned to Keep",
                message: "Unpin \(target.title) first if you decide to remove it."
            )
            return
        }
        if let app = target.advisory.lockedByAppName {
            notifications.postNotice(
                severity: .caution,
                title: "\(app) Is Currently Open",
                message: "Quit \(app) before staging its active caches."
            )
            return
        }

        // Remove any already-staged descendant targets if user just staged their parent group
        let incomingPaths = target.urls.map { $0.standardizedFileURL.path }
        stagedTargets.removeAll { existing in
            existing.urls.allSatisfy { existingURL in
                let ep = existingURL.standardizedFileURL.path
                return incomingPaths.contains { inc in ep == inc || ep.hasPrefix(inc + "/") }
            }
        }

        stagedTargets.append(target)
    }

    func unstage(urls: [URL]) {
        let removePaths = Set(urls.map { $0.standardizedFileURL.path })
        stagedTargets.removeAll { existing in
            existing.urls.contains { u in
                let ep = u.standardizedFileURL.path
                return removePaths.contains { rem in ep == rem || rem.hasPrefix(ep + "/") }
            }
        }
    }

    func removeStagedTarget(id: String) {
        stagedTargets.removeAll { $0.id == id }
    }

    func clearQueue() {
        stagedTargets.removeAll()
    }

    /// Stages ONLY `.safe` items (unlocked and unpinned) from Smart Junk — never `.caution` or `.warning`.
    func stageSafeSmartJunkOnly() {
        guard let report = smartJunkReport else { return }
        var addedCount = 0

        for item in report.items {
            if item.advisory.isAutoSafeCandidate && !keepListStore.isPinned(urls: item.allTargetURLs) {
                let target = InspectorSubject.scannable(item).toStageTarget()
                if !isStaged(urls: target.urls) {
                    toggleStage(target: target)
                    addedCount += 1
                }
            } else if !item.subItems.isEmpty {
                // Also pick out Safe sub-items (e.g. .vsix caches & logs) inside uninstalled IDE groups without touching User settings!
                for sub in item.subItems where sub.advisory.isAutoSafeCandidate && !keepListStore.isPinned(urls: sub.allTargetURLs) {
                    let target = InspectorSubject.scannable(sub).toStageTarget()
                    if !isStaged(urls: target.urls) {
                        toggleStage(target: target)
                        addedCount += 1
                    }
                }
            }
        }

        if addedCount > 0 {
            notifications.postNotice(
                severity: .info,
                title: "Staged \(addedCount) Safe Cache Item(s)",
                message: "Caution and Warning items remain unselected so you can decide on each one."
            )
        } else {
            notifications.postNotice(
                severity: .info,
                title: "No Additional Safe Caches to Stage",
                message: "All eligible Safe items are already in your Cleanup Queue."
            )
        }
    }

    // MARK: - Execute Staged Cleanup

    func executeStagedCleanup(mode: DeletionMode) async {
        guard !stagedTargets.isEmpty else { return }
        isExecutingCleanup = true
        defer { isExecutingCleanup = false }

        let targetsSnapshot = stagedTargets
        let result = await cleanupService.executeCleanup(
            targets: targetsSnapshot,
            mode: mode,
            keepList: keepListStore
        )

        let cleanedSet = Set(result.cleanedPaths)
        // Prune cleaned targets from queue & live scan snapshots
        stagedTargets.removeAll { target in
            target.urls.allSatisfy { cleanedSet.contains($0.standardizedFileURL.path) }
        }
        pruneCleanedPathsFromInMemoryLists(cleanedSet)

        cleanupHistory = historyStore.loadAll()
        isShowingQueueSheet = false
        await refreshVolumeMetrics()
        if targetsSnapshot.contains(where: { ToolchainEcosystem.allCases.map(\.rawValue).contains($0.sourceLabel) }) {
            await refreshToolchainsAndLocalDocker()
        }

        let freedStr = ByteFormatting.string(from: result.freedBytes)
        if !result.cleanedPaths.isEmpty {
            let skipSuffix = result.skippedReasons.isEmpty ? "" : " (\(result.skippedReasons.count) skipped)"
            notifications.postNotice(
                severity: .success,
                title: "Reclaimed \(freedStr) (\(mode.rawValue))",
                message: "Cleaned \(result.cleanedPaths.count) item(s)\(skipSuffix).",
                sendSystemNotification: true,
                notificationsEnabled: preferences.notificationsEnabled
            )
        } else if !result.skippedReasons.isEmpty {
            notifications.postNotice(
                severity: .caution,
                title: "Items Skipped by Safety Guard",
                message: result.skippedReasons.joined(separator: " • ")
            )
        }
    }

    private func pruneCleanedPathsFromInMemoryLists(_ cleanedPaths: Set<String>) {
        guard !cleanedPaths.isEmpty else { return }

        if let report = smartJunkReport {
            let filtered = report.items.compactMap { item -> ScannableItem? in
                if item.allTargetURLs.allSatisfy({ cleanedPaths.contains($0.standardizedFileURL.path) }) {
                    return nil
                }
                if !item.subItems.isEmpty {
                    let remainingSubs = item.subItems.filter { sub in
                        !sub.allTargetURLs.allSatisfy({ cleanedPaths.contains($0.standardizedFileURL.path) })
                    }
                    let removedBytes = item.subItems
                        .filter { sub in sub.allTargetURLs.allSatisfy({ cleanedPaths.contains($0.standardizedFileURL.path) }) }
                        .reduce(Int64(0)) { $0 + $1.allocatedBytes }
                    return ScannableItem(
                        id: item.id,
                        url: item.url,
                        additionalURLs: item.additionalURLs,
                        title: item.title,
                        subtitle: item.subtitle,
                        domain: item.domain,
                        allocatedBytes: max(0, item.allocatedBytes - removedBytes),
                        itemCount: item.itemCount,
                        lastModified: item.lastModified,
                        stalenessDays: item.stalenessDays,
                        associatedAppName: item.associatedAppName,
                        associatedBundleID: item.associatedBundleID,
                        advisory: item.advisory,
                        subItems: remainingSubs
                    )
                }
                return item
            }
            smartJunkReport = SmartJunkScanReport(
                items: filtered,
                projectReferences: report.projectReferences,
                scannedAt: report.scannedAt
            )
        }

        toolchainItems.removeAll { item in
            item.urls.allSatisfy { cleanedPaths.contains($0.standardizedFileURL.path) }
        }

        largeFiles.removeAll { file in
            cleanedPaths.contains(file.url.standardizedFileURL.path)
        }

        if let subject = inspectorSubject,
           subject.allURLs.allSatisfy({ cleanedPaths.contains($0.standardizedFileURL.path) }) {
            inspectorSubject = nil
        }
    }

    // MARK: - Finder & Clipboard Helpers

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copyPathToClipboard(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
        notifications.postNotice(
            severity: .info,
            title: "Copied Path",
            message: url.path
        )
    }
}
