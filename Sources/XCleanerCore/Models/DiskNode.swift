import Foundation

public struct DiskNode: Identifiable, Sendable, Equatable {
    public let id: String
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
    public let itemCount: Int
    public let lastModified: Date?
    public let lastAccessed: Date?
    public let advisory: ItemAdvisory
    public let children: [DiskNode]

    public init(
        url: URL,
        name: String? = nil,
        isDirectory: Bool,
        allocatedBytes: Int64,
        logicalBytes: Int64,
        itemCount: Int,
        lastModified: Date? = nil,
        lastAccessed: Date? = nil,
        advisory: ItemAdvisory,
        children: [DiskNode] = []
    ) {
        let standardized = url.standardizedFileURL
        self.id = standardized.path
        self.url = standardized
        self.name = name ?? (standardized.lastPathComponent.isEmpty ? "/" : standardized.lastPathComponent)
        self.isDirectory = isDirectory
        self.allocatedBytes = allocatedBytes
        self.logicalBytes = logicalBytes
        self.itemCount = itemCount
        self.lastModified = lastModified
        self.lastAccessed = lastAccessed
        self.advisory = advisory
        self.children = children
    }
}

public enum LargeFileCategory: String, Codable, Sendable, CaseIterable {
    case installerOrDiskImage = "Installers & Disk Images"
    case archive = "Archives"
    case videoOrAudio = "Video & Audio"
    case aiModelOrDataset = "AI Models & Data"
    case virtualDiskOrDB = "VM Disks & Databases"
    case other = "Other Large Files"

    public var symbolName: String {
        switch self {
        case .installerOrDiskImage: return "opticaldiscdrive"
        case .archive: return "doc.zipper"
        case .videoOrAudio: return "film"
        case .aiModelOrDataset: return "cpu"
        case .virtualDiskOrDB: return "externaldrive.badge.timemachine"
        case .other: return "doc"
        }
    }

    public static func classify(url: URL) -> LargeFileCategory {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "dmg", "pkg", "iso", "ipsw", "mpkg":
            return .installerOrDiskImage
        case "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "vsix":
            return .archive
        case "mp4", "mov", "mkv", "avi", "webm", "m4v", "wav", "flac", "mp3", "m4a":
            return .videoOrAudio
        case "gguf", "safetensors", "onnx", "pt", "pth", "bin", "ckpt", "h5", "parquet":
            return .aiModelOrDataset
        case "raw", "qcow2", "vmdk", "vdi", "sparseimage", "sqlite", "db":
            return .virtualDiskOrDB
        default:
            return .other
        }
    }
}

public struct LargeFileItem: Identifiable, Sendable, Equatable {
    public let id: String
    public let url: URL
    public let name: String
    public let category: LargeFileCategory
    public let allocatedBytes: Int64
    public let lastModified: Date?
    public let lastAccessed: Date?
    public let advisory: ItemAdvisory

    public init(
        url: URL,
        category: LargeFileCategory? = nil,
        allocatedBytes: Int64,
        lastModified: Date?,
        lastAccessed: Date?,
        advisory: ItemAdvisory
    ) {
        let standardized = url.standardizedFileURL
        self.id = standardized.path
        self.url = standardized
        self.name = standardized.lastPathComponent
        self.category = category ?? LargeFileCategory.classify(url: standardized)
        self.allocatedBytes = allocatedBytes
        self.lastModified = lastModified
        self.lastAccessed = lastAccessed
        self.advisory = advisory
    }

    public var stalenessDays: Int? {
        ByteFormatting.daysBetween(lastAccessed ?? lastModified)
    }
}
