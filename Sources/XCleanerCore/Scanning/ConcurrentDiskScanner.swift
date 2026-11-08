import Foundation

public struct DirectoryFootprint: Sendable, Equatable {
    public var allocatedBytes: Int64
    public var logicalBytes: Int64
    public var itemCount: Int
    public var lastModified: Date?
    public var lastAccessed: Date?
    public var permissionDeniedPaths: [String]

    public init(
        allocatedBytes: Int64 = 0,
        logicalBytes: Int64 = 0,
        itemCount: Int = 0,
        lastModified: Date? = nil,
        lastAccessed: Date? = nil,
        permissionDeniedPaths: [String] = []
    ) {
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.itemCount = itemCount
        self.lastModified = lastModified
        self.lastAccessed = lastAccessed
        self.permissionDeniedPaths = permissionDeniedPaths
    }
}

public struct ScanProgress: Sendable, Equatable {
    public let scannedFiles: Int
    public let scannedBytes: Int64
    public let currentPath: String

    public init(scannedFiles: Int, scannedBytes: Int64, currentPath: String) {
        self.scannedFiles = scannedFiles
        self.scannedBytes = scannedBytes
        self.currentPath = currentPath
    }
}

public struct DiskScanResult: Sendable, Equatable {
    public let rootNode: DiskNode
    public let permissionDeniedPaths: [String]

    public init(rootNode: DiskNode, permissionDeniedPaths: [String]) {
        self.rootNode = rootNode
        self.permissionDeniedPaths = permissionDeniedPaths
    }
}

public struct ConcurrentDiskScanner: Sendable {
    public let advisoryEngine: AdvisoryEngine
    public let maxConcurrency: Int

    private static let resourceKeys: [URLResourceKey] = [
        .isRegularFileKey,
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isPackageKey,
        .totalFileAllocatedSizeKey,
        .fileAllocatedSizeKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .contentAccessDateKey,
        .isUbiquitousItemKey,
        .ubiquitousItemDownloadingStatusKey
    ]

    public init(
        advisoryEngine: AdvisoryEngine = AdvisoryEngine(),
        maxConcurrency: Int = min(8, max(2, ProcessInfo.processInfo.activeProcessorCount))
    ) {
        self.advisoryEngine = advisoryEngine
        self.maxConcurrency = maxConcurrency
    }

    /// Fast, non-symlink-following measurement of a file or directory's physical APFS footprint.
    public static func measureFootprint(at targetURL: URL) -> DirectoryFootprint {
        let standardized = targetURL.standardizedFileURL
        let fm = FileManager.default
        let keySet = Set(resourceKeys)

        guard let topValues = try? standardized.resourceValues(forKeys: keySet) else {
            // Check whether path exists or failed with EPERM/EACCES
            if !fm.isReadableFile(atPath: standardized.path) && fm.fileExists(atPath: standardized.path) {
                return DirectoryFootprint(permissionDeniedPaths: [standardized.path])
            }
            return DirectoryFootprint()
        }

        // Never follow symlinks!
        if topValues.isSymbolicLink == true {
            return DirectoryFootprint(
                allocatedBytes: 0,
                logicalBytes: 0,
                itemCount: 1,
                lastModified: topValues.contentModificationDate,
                lastAccessed: topValues.contentAccessDate
            )
        }

        // Single regular file
        if topValues.isDirectory != true {
            if isUndownloadedCloudPlaceholder(topValues) {
                return DirectoryFootprint(itemCount: 1, lastModified: topValues.contentModificationDate)
            }
            let allocated = Int64(topValues.totalFileAllocatedSize ?? topValues.fileAllocatedSize ?? topValues.fileSize ?? 0)
            let logical = Int64(topValues.fileSize ?? Int(allocated))
            return DirectoryFootprint(
                allocatedBytes: allocated,
                logicalBytes: logical,
                itemCount: 1,
                lastModified: topValues.contentModificationDate,
                lastAccessed: topValues.contentAccessDate
            )
        }

        // Directory traversal without following symlinks and avoiding crossing into /Volumes mounts
        let deniedBox = LockedStringArray()
        guard let enumerator = fm.enumerator(
            at: standardized,
            includingPropertiesForKeys: resourceKeys,
            options: [],
            errorHandler: { errURL, error in
                let nsErr = error as NSError
                if nsErr.code == NSFileReadNoPermissionError || nsErr.code == Int(EACCES) || nsErr.code == Int(EPERM) {
                    deniedBox.append(errURL.standardizedFileURL.path)
                }
                return true
            }
        ) else {
            return DirectoryFootprint(permissionDeniedPaths: [standardized.path])
        }

        var totalAllocated: Int64 = 0
        var totalLogical: Int64 = 0
        var count = 0
        var latestMod = topValues.contentModificationDate
        var latestAcc = topValues.contentAccessDate

        while !Task.isCancelled {
            var shouldBreak = false
            autoreleasepool {
                guard let nextObj = enumerator.nextObject() as? URL else {
                    shouldBreak = true
                    return
                }
                // Guard against crossing into /Volumes/* when scanning / or /System/Volumes/Data
                let childPath = nextObj.path
                if standardized.path == "/" && childPath.hasPrefix("/Volumes/") {
                    enumerator.skipDescendants()
                    return
                }
                guard let vals = try? nextObj.resourceValues(forKeys: keySet) else { return }
                if vals.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    return
                }
                count += 1
                if let mod = vals.contentModificationDate, (latestMod == nil || mod > latestMod!) {
                    latestMod = mod
                }
                if let acc = vals.contentAccessDate, (latestAcc == nil || acc > latestAcc!) {
                    latestAcc = acc
                }
                if vals.isDirectory != true && !isUndownloadedCloudPlaceholder(vals) {
                    let alloc = Int64(vals.totalFileAllocatedSize ?? vals.fileAllocatedSize ?? vals.fileSize ?? 0)
                    let logic = Int64(vals.fileSize ?? Int(alloc))
                    totalAllocated += alloc
                    totalLogical += logic
                }
            }
            if shouldBreak { break }
        }

        return DirectoryFootprint(
            allocatedBytes: totalAllocated,
            logicalBytes: totalLogical,
            itemCount: max(1, count),
            lastModified: latestMod,
            lastAccessed: latestAcc,
            permissionDeniedPaths: deniedBox.values()
        )
    }

    /// Scans a directory hierarchy concurrently down to `maxTreeDepth` for the Visual Folder Explorer.
    public func scanDirectoryTree(
        at rootURL: URL,
        maxTreeDepth: Int = 2,
        runningApps: [RunningApplicationSnapshot] = [],
        keepList: KeepListStore? = nil,
        projectGradleRefs: [String: [String]] = [:],
        onProgress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> DiskScanResult {
        try Task.checkCancellation()
        let standardizedRoot = rootURL.standardizedFileURL
        let fm = FileManager.default
        let keySet = Set(Self.resourceKeys)

        var deniedPaths: [String] = []
        let topEntries: [URL]
        do {
            topEntries = try fm.contentsOfDirectory(
                at: standardizedRoot,
                includingPropertiesForKeys: Self.resourceKeys,
                options: []
            )
        } catch let error as NSError {
            if error.code == NSFileReadNoPermissionError || error.code == Int(EACCES) || error.code == Int(EPERM) {
                deniedPaths.append(standardizedRoot.path)
            }
            let emptyNode = DiskNode(
                url: standardizedRoot,
                isDirectory: true,
                allocatedBytes: 0,
                logicalBytes: 0,
                itemCount: 0,
                advisory: advisoryEngine.assessPath(
                    url: standardizedRoot,
                    runningApps: runningApps,
                    keepList: keepList,
                    projectGradleRefs: projectGradleRefs
                )
            )
            return DiskScanResult(rootNode: emptyNode, permissionDeniedPaths: deniedPaths)
        }

        // Partition entries into bounded concurrent tasks
        let progressTracker = ProgressAccumulator(callback: onProgress)
        var childNodes: [DiskNode] = []

        try await withThrowingTaskGroup(of: (DiskNode?, [String]).self) { group in
            var activeCount = 0
            for entry in topEntries {
                try Task.checkCancellation()
                // Skip /Volumes traversal when scanning /
                if standardizedRoot.path == "/" && entry.lastPathComponent == "Volumes" {
                    continue
                }
                if activeCount >= maxConcurrency {
                    if let (node, errs) = try await group.next() {
                        if let node { childNodes.append(node) }
                        deniedPaths.append(contentsOf: errs)
                        activeCount -= 1
                    }
                }
                activeCount += 1
                group.addTask {
                    try Task.checkCancellation()
                    return self.buildNodeSync(
                        at: entry,
                        remainingDepth: max(0, maxTreeDepth - 1),
                        keySet: keySet,
                        runningApps: runningApps,
                        keepList: keepList,
                        projectGradleRefs: projectGradleRefs,
                        progressTracker: progressTracker
                    )
                }
            }

            while let (node, errs) = try await group.next() {
                if let node { childNodes.append(node) }
                deniedPaths.append(contentsOf: errs)
            }
        }

        childNodes.sort { $0.allocatedBytes > $1.allocatedBytes }

        let totalAllocated = childNodes.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        let totalLogical = childNodes.reduce(Int64(0)) { $0 + $1.logicalBytes }
        let totalCount = childNodes.reduce(0) { $0 + $1.itemCount }
        let latestMod = childNodes.compactMap(\.lastModified).max()
        let latestAcc = childNodes.compactMap(\.lastAccessed).max()

        let rootAdvisory = advisoryEngine.assessPath(
            url: standardizedRoot,
            runningApps: runningApps,
            keepList: keepList,
            projectGradleRefs: projectGradleRefs
        )

        let rootNode = DiskNode(
            url: standardizedRoot,
            isDirectory: true,
            allocatedBytes: totalAllocated,
            logicalBytes: totalLogical,
            itemCount: totalCount,
            lastModified: latestMod,
            lastAccessed: latestAcc,
            advisory: rootAdvisory,
            children: childNodes
        )

        return DiskScanResult(
            rootNode: rootNode,
            permissionDeniedPaths: Array(Set(deniedPaths)).sorted()
        )
    }

    private func buildNodeSync(
        at url: URL,
        remainingDepth: Int,
        keySet: Set<URLResourceKey>,
        runningApps: [RunningApplicationSnapshot],
        keepList: KeepListStore?,
        projectGradleRefs: [String: [String]],
        progressTracker: ProgressAccumulator
    ) -> (DiskNode?, [String]) {
        if Task.isCancelled { return (nil, []) }
        let standardized = url.standardizedFileURL
        let fm = FileManager.default

        guard let vals = try? standardized.resourceValues(forKeys: keySet) else {
            if !fm.isReadableFile(atPath: standardized.path) && fm.fileExists(atPath: standardized.path) {
                return (nil, [standardized.path])
            }
            return (nil, [])
        }

        // Never follow symlinks!
        if vals.isSymbolicLink == true {
            return (nil, [])
        }

        let advisory = advisoryEngine.assessPath(
            url: standardized,
            runningApps: runningApps,
            keepList: keepList,
            projectGradleRefs: projectGradleRefs
        )

        if vals.isDirectory != true {
            if Self.isUndownloadedCloudPlaceholder(vals) {
                return (nil, [])
            }
            let alloc = Int64(vals.totalFileAllocatedSize ?? vals.fileAllocatedSize ?? vals.fileSize ?? 0)
            let logic = Int64(vals.fileSize ?? Int(alloc))
            progressTracker.record(files: 1, bytes: alloc, path: standardized.path)
            let node = DiskNode(
                url: standardized,
                isDirectory: false,
                allocatedBytes: alloc,
                logicalBytes: logic,
                itemCount: 1,
                lastModified: vals.contentModificationDate,
                lastAccessed: vals.contentAccessDate,
                advisory: advisory
            )
            return (node, [])
        }

        // If remainingDepth > 0 and not an opaque .app/.photoslibrary package, expand children recursively
        if remainingDepth > 0 && vals.isPackage != true {
            do {
                let entries = try fm.contentsOfDirectory(
                    at: standardized,
                    includingPropertiesForKeys: Self.resourceKeys,
                    options: []
                )
                var subNodes: [DiskNode] = []
                var denied: [String] = []
                for child in entries {
                    if Task.isCancelled { break }
                    let (cNode, cDenied) = buildNodeSync(
                        at: child,
                        remainingDepth: remainingDepth - 1,
                        keySet: keySet,
                        runningApps: runningApps,
                        keepList: keepList,
                        projectGradleRefs: projectGradleRefs,
                        progressTracker: progressTracker
                    )
                    if let cNode { subNodes.append(cNode) }
                    denied.append(contentsOf: cDenied)
                }
                subNodes.sort { $0.allocatedBytes > $1.allocatedBytes }
                let alloc = subNodes.reduce(Int64(0)) { $0 + $1.allocatedBytes }
                let logic = subNodes.reduce(Int64(0)) { $0 + $1.logicalBytes }
                let count = max(1, subNodes.reduce(0) { $0 + $1.itemCount })
                let mod = subNodes.compactMap(\.lastModified).max() ?? vals.contentModificationDate
                let acc = subNodes.compactMap(\.lastAccessed).max() ?? vals.contentAccessDate
                let node = DiskNode(
                    url: standardized,
                    isDirectory: true,
                    allocatedBytes: alloc,
                    logicalBytes: logic,
                    itemCount: count,
                    lastModified: mod,
                    lastAccessed: acc,
                    advisory: advisory,
                    children: subNodes
                )
                return (node, denied)
            } catch let error as NSError {
                if error.code == NSFileReadNoPermissionError || error.code == Int(EACCES) || error.code == Int(EPERM) {
                    return (nil, [standardized.path])
                }
            }
        }

        // Leaf directory measurement via fast non-symlink enumerator
        let footprint = Self.measureFootprint(at: standardized)
        progressTracker.record(
            files: footprint.itemCount,
            bytes: footprint.allocatedBytes,
            path: standardized.path
        )
        let node = DiskNode(
            url: standardized,
            isDirectory: true,
            allocatedBytes: footprint.allocatedBytes,
            logicalBytes: footprint.logicalBytes,
            itemCount: footprint.itemCount,
            lastModified: footprint.lastModified ?? vals.contentModificationDate,
            lastAccessed: footprint.lastAccessed ?? vals.contentAccessDate,
            advisory: advisory
        )
        return (node, footprint.permissionDeniedPaths)
    }

    internal static func isUndownloadedCloudPlaceholder(_ vals: URLResourceValues) -> Bool {
        guard vals.isUbiquitousItem == true else { return false }
        if let status = vals.ubiquitousItemDownloadingStatus, status != .current {
            return true
        }
        return false
    }
}

private final class LockedStringArray: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    func values() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class ProgressAccumulator: @unchecked Sendable {
    private let lock = NSLock()
    private let callback: (@Sendable (ScanProgress) -> Void)?
    private var files = 0
    private var bytes: Int64 = 0
    private var lastEmit = Date.distantPast

    init(callback: (@Sendable (ScanProgress) -> Void)?) {
        self.callback = callback
    }

    func record(files deltaFiles: Int, bytes deltaBytes: Int64, path: String) {
        guard let callback else { return }
        var snapshot: ScanProgress?
        let now = Date()
        lock.lock()
        files += deltaFiles
        bytes += deltaBytes
        if now.timeIntervalSince(lastEmit) >= 0.08 {
            lastEmit = now
            snapshot = ScanProgress(scannedFiles: files, scannedBytes: bytes, currentPath: path)
        }
        lock.unlock()
        if let snapshot {
            callback(snapshot)
        }
    }
}
