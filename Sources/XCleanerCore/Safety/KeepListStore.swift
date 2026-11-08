import Foundation

public struct KeepListEntry: Identifiable, Codable, Sendable, Equatable {
    public var id: String { path }
    public let path: String
    public let label: String
    public let addedAt: Date

    public init(path: String, label: String, addedAt: Date = Date()) {
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.label = label
        self.addedAt = addedAt
    }
}

public final class KeepListStore: @unchecked Sendable {
    private let lock = NSLock()
    private let storageURL: URL
    private var entriesByPath: [String: KeepListEntry] = [:]

    public init(storageURL: URL? = nil) {
        if let storageURL {
            self.storageURL = storageURL
        } else {
            let appSupport = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/xCleaner", isDirectory: true)
            self.storageURL = appSupport.appendingPathComponent("keep-list.json")
        }
        loadFromDisk()
    }

    public func allEntries() -> [KeepListEntry] {
        lock.lock()
        defer { lock.unlock() }
        return entriesByPath.values.sorted { $0.addedAt > $1.addedAt }
    }

    public func isPinned(url: URL) -> Bool {
        isPinned(path: url.standardizedFileURL.path)
    }

    public func isPinned(urls: [URL]) -> Bool {
        urls.contains { isPinned(url: $0) }
    }

    public func isPinned(path: String) -> Bool {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        lock.lock()
        defer { lock.unlock() }
        if entriesByPath[normalized] != nil {
            return true
        }
        for pinnedPath in entriesByPath.keys {
            if normalized.hasPrefix(pinnedPath + "/") {
                return true
            }
        }
        return false
    }

    public func pin(url: URL, label: String? = nil) {
        let normalized = url.standardizedFileURL.path
        let displayLabel = label ?? url.lastPathComponent
        lock.lock()
        entriesByPath[normalized] = KeepListEntry(path: normalized, label: displayLabel)
        let snapshot = Array(entriesByPath.values)
        lock.unlock()
        saveToDisk(snapshot)
    }

    public func unpin(url: URL) {
        unpin(path: url.standardizedFileURL.path)
    }

    public func unpin(path: String) {
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        lock.lock()
        entriesByPath.removeValue(forKey: normalized)
        // Also unpin any ancestor if user clicked unpin on a child of a pinned folder
        let matchingAncestors = entriesByPath.keys.filter { normalized.hasPrefix($0 + "/") }
        for ancestor in matchingAncestors {
            entriesByPath.removeValue(forKey: ancestor)
        }
        let snapshot = Array(entriesByPath.values)
        lock.unlock()
        saveToDisk(snapshot)
    }

    public func togglePin(url: URL, label: String? = nil) -> Bool {
        if isPinned(url: url) {
            unpin(url: url)
            return false
        } else {
            pin(url: url, label: label)
            return true
        }
    }

    private func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: storageURL.path),
              let data = try? Data(contentsOf: storageURL),
              let decoded = try? JSONDecoder().decode([KeepListEntry].self, from: data) else {
            return
        }
        lock.lock()
        defer { lock.unlock() }
        entriesByPath = Dictionary(uniqueKeysWithValues: decoded.map { ($0.path, $0) })
    }

    private func saveToDisk(_ entries: [KeepListEntry]) {
        let folder = storageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: storageURL, options: .atomic)
        }
    }
}
