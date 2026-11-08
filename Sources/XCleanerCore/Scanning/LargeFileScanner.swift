import Foundation

public struct LargeFileScanner: Sendable {
    public let advisoryEngine: AdvisoryEngine

    public init(advisoryEngine: AdvisoryEngine = AdvisoryEngine()) {
        self.advisoryEngine = advisoryEngine
    }

    public func scanLargeFiles(
        in roots: [URL],
        minimumBytes: Int64 = 50_000_000,
        runningApps: [RunningApplicationSnapshot] = [],
        keepList: KeepListStore? = nil
    ) async throws -> (items: [LargeFileItem], permissionDeniedPaths: [String]) {
        try Task.checkCancellation()
        let uniqueRoots = deduplicateRoots(roots)

        var allItems: [LargeFileItem] = []
        var denied: [String] = []

        try await withThrowingTaskGroup(of: ([LargeFileItem], [String]).self) { group in
            for root in uniqueRoots {
                group.addTask {
                    self.scanSingleRoot(
                        root: root,
                        minimumBytes: minimumBytes,
                        runningApps: runningApps,
                        keepList: keepList
                    )
                }
            }
            for try await (items, errs) in group {
                allItems.append(contentsOf: items)
                denied.append(contentsOf: errs)
            }
        }

        // Deduplicate by path and sort descending by allocatedBytes
        var seen = Set<String>()
        var deduplicated: [LargeFileItem] = []
        for item in allItems.sorted(by: { $0.allocatedBytes > $1.allocatedBytes }) {
            if seen.insert(item.id).inserted {
                deduplicated.append(item)
            }
        }

        return (deduplicated, Array(Set(denied)).sorted())
    }

    private func scanSingleRoot(
        root: URL,
        minimumBytes: Int64,
        runningApps: [RunningApplicationSnapshot],
        keepList: KeepListStore?
    ) -> ([LargeFileItem], [String]) {
        let standardizedRoot = root.standardizedFileURL
        let fm = FileManager.default
        guard fm.fileExists(atPath: standardizedRoot.path) else { return ([], []) }

        let keys: [URLResourceKey] = [
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
        let keySet = Set(keys)

        var denied: [String] = []
        let deniedLock = NSLock()
        guard let enumerator = fm.enumerator(
            at: standardizedRoot,
            includingPropertiesForKeys: keys,
            options: [],
            errorHandler: { errURL, error in
                let nsErr = error as NSError
                if nsErr.code == NSFileReadNoPermissionError || nsErr.code == Int(EACCES) || nsErr.code == Int(EPERM) {
                    deniedLock.lock()
                    denied.append(errURL.standardizedFileURL.path)
                    deniedLock.unlock()
                }
                return true
            }
        ) else {
            return ([], [])
        }

        var results: [LargeFileItem] = []
        let homePath = advisoryEngine.safetyPolicy.homeDirectory.path
        let skippedDirectoryNames: Set<String> = [
            ".git", "node_modules", "CloudStorage", "Mobile Documents", "Photos Library.photoslibrary"
        ]

        while !Task.isCancelled {
            var shouldBreak = false
            autoreleasepool {
                guard let url = enumerator.nextObject() as? URL else {
                    shouldBreak = true
                    return
                }
                guard let vals = try? url.resourceValues(forKeys: keySet) else { return }
                if vals.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    return
                }
                if vals.isDirectory == true {
                    let name = url.lastPathComponent
                    if skippedDirectoryNames.contains(name) ||
                        vals.isPackage == true ||
                        url.path == "\(homePath)/Library/Containers/com.docker.docker" {
                        enumerator.skipDescendants()
                    }
                    return
                }
                guard vals.isRegularFile == true,
                      !ConcurrentDiskScanner.isUndownloadedCloudPlaceholder(vals) else {
                    return
                }
                let allocated = Int64(vals.totalFileAllocatedSize ?? vals.fileAllocatedSize ?? vals.fileSize ?? 0)
                guard allocated >= minimumBytes else { return }

                let advisory = advisoryEngine.assessPath(
                    url: url,
                    runningApps: runningApps,
                    keepList: keepList
                )
                results.append(
                    LargeFileItem(
                        url: url,
                        allocatedBytes: allocated,
                        lastModified: vals.contentModificationDate,
                        lastAccessed: vals.contentAccessDate,
                        advisory: advisory
                    )
                )
            }
            if shouldBreak { break }
        }

        return (results, denied)
    }

    private func deduplicateRoots(_ roots: [URL]) -> [URL] {
        let sorted = roots.map(\.standardizedFileURL).sorted { $0.path.count < $1.path.count }
        var kept: [URL] = []
        for candidate in sorted {
            if !kept.contains(where: { candidate.path == $0.path || candidate.path.hasPrefix($0.path + "/") }) {
                kept.append(candidate)
            }
        }
        return kept
    }
}
