import Foundation
import Testing
@testable import XCleanerCore

@Suite("Concurrent Disk Scanner & Symlink Immunity")
struct ConcurrentDiskScannerTests {
    @Test("Accurately measures directory trees and ignores symlink cycles without hanging or double-counting")
    func scansDirectoryTreeAndIgnoresSymlinkCycles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcleaner-diskscan-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let dirA = root.appendingPathComponent("Alpha", isDirectory: true)
        let dirB = root.appendingPathComponent("Beta", isDirectory: true)
        try FileManager.default.createDirectory(at: dirA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dirB, withIntermediateDirectories: true)

        let payloadA = Data(repeating: 0x41, count: 65_536) // 64 KB
        let payloadB = Data(repeating: 0x42, count: 131_072) // 128 KB
        try payloadA.write(to: dirA.appendingPathComponent("a.bin"))
        try payloadB.write(to: dirB.appendingPathComponent("b.bin"))

        // Create a symlink cycle inside Alpha pointing back to root
        try FileManager.default.createSymbolicLink(
            at: dirA.appendingPathComponent("cycle-link"),
            withDestinationURL: root
        )

        let scanner = ConcurrentDiskScanner(
            advisoryEngine: AdvisoryEngine(safetyPolicy: SafetyPolicyEngine(homeDirectory: root))
        )
        let result = try await scanner.scanDirectoryTree(at: root, maxTreeDepth: 2)

        #expect(result.rootNode.children.count == 2)
        // Beta (~128 KB) must sort ahead of Alpha (~64 KB)
        #expect(result.rootNode.children.first?.name == "Beta")
        #expect(result.rootNode.logicalBytes == Int64(payloadA.count + payloadB.count))
        #expect(result.rootNode.allocatedBytes >= result.rootNode.logicalBytes)
    }
}
