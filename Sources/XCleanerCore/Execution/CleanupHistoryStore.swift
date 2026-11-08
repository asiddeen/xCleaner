import Foundation

public final class CleanupHistoryStore: @unchecked Sendable {
    private let lock = NSLock()
    public let logFileURL: URL

    public init(logFileURL: URL? = nil) {
        if let logFileURL {
            self.logFileURL = logFileURL
        } else {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support/xCleaner", isDirectory: true)
            self.logFileURL = dir.appendingPathComponent("cleanup-history.jsonl")
        }
    }

    public func append(_ record: CleanupRecord) {
        lock.lock()
        defer { lock.unlock() }

        let folder = logFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(record) else { return }
        data.append(0x0A) // '\n'

        if FileManager.default.fileExists(atPath: logFileURL.path),
           let handle = try? FileHandle(forWritingTo: logFileURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logFileURL, options: .atomic)
        }
    }

    public func loadAll() -> [CleanupRecord] {
        lock.lock()
        defer { lock.unlock() }

        guard FileManager.default.fileExists(atPath: logFileURL.path),
              let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var records: [CleanupRecord] = []

        for line in content.split(whereSeparator: \.isNewline) {
            if let data = String(line).data(using: .utf8),
               let record = try? decoder.decode(CleanupRecord.self, from: data) {
                records.append(record)
            }
        }
        return records.sorted { $0.timestamp > $1.timestamp }
    }

    public func clearHistory() {
        lock.lock()
        defer { lock.unlock() }
        try? FileManager.default.removeItem(at: logFileURL)
    }
}
