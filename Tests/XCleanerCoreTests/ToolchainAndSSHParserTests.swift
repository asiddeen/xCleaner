import Foundation
import Testing
@testable import XCleanerCore

@Suite("Toolchain Version Scanner, Docker JSON & SSH Config Parsers")
struct ToolchainAndSSHParserTests {
    @Test("Locks current/default Gradle, Android SDK & Node nvm versions while allowing older/RC cleanup")
    func locksDefaultAndCurrentVersionsAcrossEcosystems() async throws {
        let tempHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("xcleaner-toolchains-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempHome) }

        // 1. Set up project referencing Gradle 8.14.5
        let projectWrapper = tempHome.appendingPathComponent("Projects/ComBIP/android/gradle/wrapper", isDirectory: true)
        try FileManager.default.createDirectory(at: projectWrapper, withIntermediateDirectories: true)
        try """
        distributionBase=GRADLE_USER_HOME
        distributionUrl=https\\://services.gradle.org/distributions/gradle-8.14.5-bin.zip
        """.write(
            to: projectWrapper.appendingPathComponent("gradle-wrapper.properties"),
            atomically: true,
            encoding: .utf8
        )

        let refs = ProjectReferenceScanner().scanReferences(in: [tempHome.appendingPathComponent("Projects")])
        #expect(refs.gradleVersionsToProjects["8.14.5"] == ["ComBIP"])

        // 2. Set up ~/.gradle with 8.10.2 (old), 8.14.5 (referenced), 9.3.1 (current/latest), and jdks/openjdk.tar.gz
        let gradle810 = tempHome.appendingPathComponent(".gradle/caches/8.10.2", isDirectory: true)
        let gradle814Cache = tempHome.appendingPathComponent(".gradle/caches/8.14.5", isDirectory: true)
        let gradle814Dist = tempHome.appendingPathComponent(".gradle/wrapper/dists/gradle-8.14.5-bin/hash123", isDirectory: true)
        let gradle931 = tempHome.appendingPathComponent(".gradle/caches/9.3.1", isDirectory: true)
        let jdksDir = tempHome.appendingPathComponent(".gradle/jdks", isDirectory: true)

        for dir in [gradle810, gradle814Cache, gradle814Dist, gradle931, jdksDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        try Data(repeating: 0x01, count: 32_000).write(to: gradle810.appendingPathComponent("cache.bin"))
        try Data(repeating: 0x02, count: 32_000).write(to: gradle814Cache.appendingPathComponent("cache.bin"))
        try Data(repeating: 0x03, count: 32_000).write(to: gradle814Dist.appendingPathComponent("gradle.zip"))
        try Data(repeating: 0x04, count: 32_000).write(to: gradle931.appendingPathComponent("cache.bin"))
        try Data(repeating: 0x05, count: 1_500_000).write(to: jdksDir.appendingPathComponent("temurin-21.tar.gz"))

        // 3. Set up Android SDK stable vs -rc1
        let rcBuildTools = tempHome.appendingPathComponent("Library/Android/sdk/build-tools/36.0.0-rc1", isDirectory: true)
        let stableBuildTools = tempHome.appendingPathComponent("Library/Android/sdk/build-tools/36.0.0", isDirectory: true)
        let oldBuildTools = tempHome.appendingPathComponent("Library/Android/sdk/build-tools/34.0.0", isDirectory: true)
        for dir in [rcBuildTools, stableBuildTools, oldBuildTools] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 0x06, count: 1_500_000).write(to: dir.appendingPathComponent("aapt2"))
        }

        // 4. Set up Node nvm with alias chain (default -> lts/* -> lts/iron -> v20.17.0), active NVM_BIN (v22.14.0), and old v18.20.4
        let nvmAliasLtsDir = tempHome.appendingPathComponent(".nvm/alias/lts", isDirectory: true)
        try FileManager.default.createDirectory(at: nvmAliasLtsDir, withIntermediateDirectories: true)
        try "lts/*\n".write(to: tempHome.appendingPathComponent(".nvm/alias/default"), atomically: true, encoding: .utf8)
        try "lts/iron\n".write(to: nvmAliasLtsDir.appendingPathComponent("*"), atomically: true, encoding: .utf8)
        try "v20.17.0\n".write(to: nvmAliasLtsDir.appendingPathComponent("iron"), atomically: true, encoding: .utf8)

        let node18 = tempHome.appendingPathComponent(".nvm/versions/node/v18.20.4", isDirectory: true)
        let node20 = tempHome.appendingPathComponent(".nvm/versions/node/v20.17.0", isDirectory: true)
        let node22 = tempHome.appendingPathComponent(".nvm/versions/node/v22.14.0", isDirectory: true)
        for dir in [node18, node20, node22] {
            try FileManager.default.createDirectory(at: dir.appendingPathComponent("bin"), withIntermediateDirectories: true)
            try Data(repeating: 0x07, count: 1_500_000).write(to: dir.appendingPathComponent("bin/node"))
        }

        let policy = SafetyPolicyEngine(homeDirectory: tempHome)
        let mockEnv = ["NVM_BIN": node22.appendingPathComponent("bin").path]
        let scanner = ToolchainVersionScanner(safetyPolicy: policy, environment: mockEnv)
        let items = scanner.scanAllToolchains(projectReferences: refs, keepList: nil)

        // Verify Gradle: 9.3.1 locked, 8.14.5 Warning, 8.10.2 Caution
        let item931 = try #require(items.first { $0.version == "9.3.1" })
        #expect(item931.status == .activeOrLatest)
        #expect(item931.advisory.level == .protected)
        #expect(item931.advisory.canBeStaged == false)

        let item814 = try #require(items.first { $0.version == "8.14.5" })
        #expect(item814.status == .referencedByProject)
        #expect(item814.advisory.level == .warning)
        #expect(item814.advisory.canBeStaged == true)
        #expect(item814.urls.count == 2)

        let item810 = try #require(items.first { $0.version == "8.10.2" })
        #expect(item810.status == .superseded)
        #expect(item810.advisory.level == .caution)
        #expect(item810.advisory.canBeStaged == true)

        let jdkArchive = try #require(items.first { $0.id == "gradle:jdk-archives" })
        #expect(jdkArchive.advisory.level == .safe)

        // Verify Android SDK: 36.0.0 locked, 36.0.0-rc1 and 34.0.0 removable
        let stableItem = try #require(items.first { $0.version == "36.0.0" })
        #expect(stableItem.status == .activeOrLatest)
        #expect(stableItem.advisory.level == .protected)
        #expect(stableItem.advisory.canBeStaged == false)

        let rcItem = try #require(items.first { $0.version == "36.0.0-rc1" })
        #expect(rcItem.status == .releaseCandidateOrPreview)
        #expect(rcItem.advisory.canBeStaged == true)

        let oldSDKItem = try #require(items.first { $0.version == "34.0.0" })
        #expect(oldSDKItem.status == .superseded)
        #expect(oldSDKItem.advisory.canBeStaged == true)

        // Verify Node nvm: v20.17.0 (default alias) & v22.14.0 (current NVM_BIN) locked, v18.20.4 removable
        let nvm20 = try #require(items.first { $0.version == "v20.17.0" })
        #expect(nvm20.advisory.level == .protected)
        #expect(nvm20.advisory.canBeStaged == false)

        let nvm22 = try #require(items.first { $0.version == "v22.14.0" })
        #expect(nvm22.advisory.level == .protected)
        #expect(nvm22.advisory.canBeStaged == false)

        let nvm18 = try #require(items.first { $0.version == "v18.20.4" })
        #expect(nvm18.status == .superseded)
        #expect(nvm18.advisory.canBeStaged == true)

        // Verify SafetyPolicyEngine hard-blocks deleting default/current versions at execution layer too
        #expect(policy.evaluateProtection(for: gradle931).isProtected == true)
        #expect(policy.evaluateProtection(for: stableBuildTools).isProtected == true)
        #expect(policy.evaluateProtection(for: node20).isProtected == true)
        #expect(policy.evaluateProtection(for: node18).isProtected == false)
        #expect(policy.evaluateProtection(for: gradle810).isProtected == false)
    }

    @Test("Parses ~/.ssh/config hosts, POSIX df -Pk /, and docker system df JSON lines")
    func parsesSSHConfigAndDockerOutput() throws {
        let sshConfig = """
        # Global defaults
        Host *
            AddKeysToAgent yes
            IdentityFile ~/.ssh/id_ed25519

        Host github.com
            User git

        Host 172.17.0.100
            HostName 172.17.0.100
            User it-desk-officer
            Port 2222
        """

        let targets = DockerAndSSHService.parseSSHConfig(sshConfig)
        #expect(targets.count == 1)
        #expect(targets[0].host == "172.17.0.100")
        #expect(targets[0].user == "it-desk-officer")
        #expect(targets[0].port == 2222)

        let dfSample = """
        Filesystem     1024-blocks      Used Available Capacity Mounted on
        /dev/sda2        512000000 410000000 102000000      81% /
        """
        let parsedDF = try #require(DockerAndSSHService.parsePOSIXDFRootLine(dfSample))
        #expect(parsedDF.totalBytes == Int64(512_000_000) * 1024)
        #expect(parsedDF.usedBytes == Int64(410_000_000) * 1024)
        #expect(parsedDF.availBytes == Int64(102_000_000) * 1024)

        let dockerJSON = """
        {"Active":"2","Reclaimable":"8.4GB (70%)","Size":"12GB","TotalCount":"9","Type":"Images"}
        {"Active":"0","Reclaimable":"18.2GB","Size":"18.2GB","TotalCount":"44","Type":"Build Cache"}
        """
        let dockerRows = DockerAndSSHService.parseDockerSystemDFJSONLines(dockerJSON)
        #expect(dockerRows.count == 2)
        #expect(dockerRows[1].type == "Build Cache")
        #expect(dockerRows[1].reclaimableText == "18.2GB")
    }
}
