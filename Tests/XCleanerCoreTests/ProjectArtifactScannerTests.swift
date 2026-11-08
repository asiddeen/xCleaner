import Foundation
import Testing
@testable import XCleanerCore

@Suite("Depth-7 Monorepo Project Artifact Scanner")
struct ProjectArtifactScannerTests {
    @Test("Detects depth-5+ android/app/build, dist/test-out, node_modules, and R renv while protecting .git and filtering by staleness")
    func detectsMonorepoArtifactsAndHonorsStaleness() throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcleaner-projects-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        let projectsRoot = tempHome.appendingPathComponent("Projects", isDirectory: true)

        // 1. Deep monorepo: Projects/work/hyperscreen/apps/mobile/android/app/build (depth 6)
        let mobileAppDir = projectsRoot.appendingPathComponent("work/hyperscreen/apps/mobile/android/app", isDirectory: true)
        let androidBuildDir = mobileAppDir.appendingPathComponent("build/outputs/apk", isDirectory: true)
        try FileManager.default.createDirectory(at: androidBuildDir, withIntermediateDirectories: true)
        try "plugins { id(\"com.android.application\") }".write(
            to: mobileAppDir.appendingPathComponent("build.gradle.kts"),
            atomically: true,
            encoding: .utf8
        )
        try Data(repeating: 0xAA, count: 60_000).write(to: androidBuildDir.appendingPathComponent("app-debug.apk"))

        // 2. Monorepo dist/test-out + node_modules + .git (must NOT touch .git!)
        let webPkgDir = projectsRoot.appendingPathComponent("work/hyperscreen/packages/web", isDirectory: true)
        let distDir = webPkgDir.appendingPathComponent("dist/test-out", isDirectory: true)
        let nodeModulesDir = webPkgDir.appendingPathComponent("node_modules/react", isDirectory: true)
        let gitDir = webPkgDir.appendingPathComponent(".git/objects", isDirectory: true)
        try FileManager.default.createDirectory(at: distDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: nodeModulesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: gitDir, withIntermediateDirectories: true)

        try "{\"name\":\"web\"}".write(to: webPkgDir.appendingPathComponent("package.json"), atomically: true, encoding: .utf8)
        try Data(repeating: 0xBB, count: 50_000).write(to: distDir.appendingPathComponent("bundle.js"))
        try Data(repeating: 0xCC, count: 80_000).write(to: nodeModulesDir.appendingPathComponent("index.js"))
        try Data(repeating: 0xDD, count: 90_000).write(to: gitDir.appendingPathComponent("pack-123"))

        // 3. Stale R renv project (120 days old) -> should receive .warning advisory
        let rProjDir = projectsRoot.appendingPathComponent("bio-stats", isDirectory: true)
        let renvTopDir = rProjDir.appendingPathComponent("renv", isDirectory: true)
        let renvDir = renvTopDir.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: renvDir, withIntermediateDirectories: true)
        let lockFile = rProjDir.appendingPathComponent("renv.lock")
        let pkgFile = renvDir.appendingPathComponent("ggplot2.so")
        try "{}".write(to: lockFile, atomically: true, encoding: .utf8)
        try Data(repeating: 0xEE, count: 70_000).write(to: pkgFile)

        let now = Date()
        let staleDate = now.addingTimeInterval(-120 * 86_400)
        try FileManager.default.setAttributes([.modificationDate: staleDate], ofItemAtPath: lockFile.path)
        try FileManager.default.setAttributes([.modificationDate: staleDate], ofItemAtPath: pkgFile.path)
        try FileManager.default.setAttributes([.modificationDate: staleDate], ofItemAtPath: renvDir.path)
        try FileManager.default.setAttributes([.modificationDate: staleDate], ofItemAtPath: renvTopDir.path)

        let scanner = ProjectArtifactScanner(safetyPolicy: SafetyPolicyEngine(homeDirectory: tempHome))
        let allItems = scanner.scanProjectArtifacts(
            in: [projectsRoot],
            maxDepth: 7,
            minimumBytes: 16_384,
            minimumStalenessDays: 0,
            now: now
        )

        let discoveredPaths = Set(allItems.map { $0.url.path })
        #expect(discoveredPaths.contains(mobileAppDir.appendingPathComponent("build").standardizedFileURL.path))
        #expect(discoveredPaths.contains(webPkgDir.appendingPathComponent("dist").standardizedFileURL.path))
        #expect(discoveredPaths.contains(webPkgDir.appendingPathComponent("node_modules").standardizedFileURL.path))
        #expect(discoveredPaths.contains(rProjDir.appendingPathComponent("renv").standardizedFileURL.path))
        // Ensure dist/test-out was NOT double-counted separately from dist, and .git was NEVER included
        #expect(!discoveredPaths.contains(distDir.standardizedFileURL.path))
        #expect(!discoveredPaths.contains { $0.contains("/.git") })

        // R renv must carry .warning and requiresExplicitAck
        let renvItem = allItems.first { $0.url.lastPathComponent == "renv" }
        #expect(renvItem?.advisory.level == .warning)
        #expect(renvItem?.advisory.requiresExplicitAck == true)

        // Filter > 90 days old -> only the 120d stale R renv project remains
        let staleOnly = scanner.scanProjectArtifacts(
            in: [projectsRoot],
            maxDepth: 7,
            minimumBytes: 16_384,
            minimumStalenessDays: 90,
            now: now
        )
        #expect(staleOnly.count == 1)
        #expect(staleOnly.first?.url.lastPathComponent == "renv")
    }
}
