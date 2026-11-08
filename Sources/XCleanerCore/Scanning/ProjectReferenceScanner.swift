import Foundation

public struct ProjectToolchainReferences: Sendable, Equatable {
    /// Maps Gradle version string (e.g. "8.14.5") -> sorted array of project names referencing it.
    public let gradleVersionsToProjects: [String: [String]]
    /// Maps Node version string without leading "v" (e.g. "24.17.0" or "22") -> sorted array of project names.
    public let nodeVersionsToProjects: [String: [String]]

    public init(
        gradleVersionsToProjects: [String: [String]] = [:],
        nodeVersionsToProjects: [String: [String]] = [:]
    ) {
        self.gradleVersionsToProjects = gradleVersionsToProjects
        self.nodeVersionsToProjects = nodeVersionsToProjects
    }
}

public struct ProjectReferenceScanner: Sendable {
    public init() {}

    public func scanReferences(in projectRoots: [URL], maxDepth: Int = 5) -> ProjectToolchainReferences {
        let fm = FileManager.default
        var gradleRefs: [String: Set<String>] = [:]
        var nodeRefs: [String: Set<String>] = [:]

        let skippedDirs: Set<String> = [
            "node_modules", ".git", ".gradle", "build", "dist", "Pods", ".build", "target", "renv", ".venv", "venv"
        ]

        for root in projectRoots.map(\.standardizedFileURL) {
            guard fm.fileExists(atPath: root.path) else { continue }
            walk(
                dir: root,
                workspaceRoot: root,
                currentDepth: 0,
                maxDepth: maxDepth,
                skippedDirs: skippedDirs,
                gradleRefs: &gradleRefs,
                nodeRefs: &nodeRefs
            )
        }

        return ProjectToolchainReferences(
            gradleVersionsToProjects: gradleRefs.mapValues { $0.sorted() },
            nodeVersionsToProjects: nodeRefs.mapValues { $0.sorted() }
        )
    }

    private func walk(
        dir: URL,
        workspaceRoot: URL,
        currentDepth: Int,
        maxDepth: Int,
        skippedDirs: Set<String>,
        gradleRefs: inout [String: Set<String>],
        nodeRefs: inout [String: Set<String>]
    ) {
        guard currentDepth <= maxDepth, !Task.isCancelled else { return }
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return
        }

        for entry in entries {
            guard let vals = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  vals.isSymbolicLink != true else {
                continue
            }
            let name = entry.lastPathComponent
            if vals.isDirectory == true {
                if skippedDirs.contains(name) { continue }
                walk(
                    dir: entry,
                    workspaceRoot: workspaceRoot,
                    currentDepth: currentDepth + 1,
                    maxDepth: maxDepth,
                    skippedDirs: skippedDirs,
                    gradleRefs: &gradleRefs,
                    nodeRefs: &nodeRefs
                )
            } else if name == "gradle-wrapper.properties" {
                if let content = try? String(contentsOf: entry, encoding: .utf8),
                   let version = Self.parseGradleVersion(fromWrapperProperties: content) {
                    let projName = Self.projectDisplayName(for: entry, under: workspaceRoot)
                    gradleRefs[version, default: []].insert(projName)
                }
            } else if name == ".nvmrc" || name == ".node-version" {
                if let raw = try? String(contentsOf: entry, encoding: .utf8) {
                    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                        .replacingOccurrences(of: "v", with: "")
                    if !trimmed.isEmpty, trimmed.first?.isNumber == true {
                        let projName = Self.projectDisplayName(for: entry, under: workspaceRoot)
                        nodeRefs[trimmed, default: []].insert(projName)
                    }
                }
            }
        }
    }

    public static func parseGradleVersion(fromWrapperProperties content: String) -> String? {
        for line in content.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"), trimmed.contains("distributionUrl") else { continue }
            // Example: distributionUrl=https\://services.gradle.org/distributions/gradle-8.14.5-bin.zip
            guard let gradleRange = trimmed.range(of: "gradle-") else { continue }
            let afterGradle = trimmed[gradleRange.upperBound...]
            if let dashEnd = afterGradle.range(of: "-bin.zip") ?? afterGradle.range(of: "-all.zip") {
                let ver = String(afterGradle[..<dashEnd.lowerBound])
                if !ver.isEmpty { return ver }
            }
        }
        return nil
    }

    private static func projectDisplayName(for fileURL: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = fileURL.standardizedFileURL.path
        guard filePath.hasPrefix(rootPath + "/") else {
            return fileURL.deletingLastPathComponent().lastPathComponent
        }
        let relative = String(filePath.dropFirst(rootPath.count + 1))
        let parts = relative.split(separator: "/").map(String.init)
        return parts.first ?? root.lastPathComponent
    }
}
