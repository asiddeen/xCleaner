import Foundation

public struct ProjectArtifactScanner: Sendable {
    public let safetyPolicy: SafetyPolicyEngine

    public init(safetyPolicy: SafetyPolicyEngine = SafetyPolicyEngine()) {
        self.safetyPolicy = safetyPolicy
    }

    public static func defaultProjectRoots(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let candidates = ["Projects", "Developer", "Code", "Workspace", "Repos", "Sites"]
        let fm = FileManager.default
        return candidates
            .map { homeDirectory.appendingPathComponent($0, isDirectory: true).standardizedFileURL }
            .filter { fm.fileExists(atPath: $0.path) }
    }

    public func scanProjectArtifacts(
        in projectRoots: [URL],
        maxDepth: Int = 7,
        minimumBytes: Int64 = 1_000_000,
        minimumStalenessDays: Int = 0,
        keepList: KeepListStore? = nil,
        now: Date = Date()
    ) -> [ScannableItem] {
        let fm = FileManager.default
        var discovered: [ScannableItem] = []
        var visitedDirs = Set<String>()

        for root in projectRoots.map(\.standardizedFileURL) {
            if Task.isCancelled { break }
            guard fm.fileExists(atPath: root.path) else { continue }
            walkDirectory(
                dir: root,
                workspaceRoot: root,
                depth: 0,
                maxDepth: maxDepth,
                minimumBytes: minimumBytes,
                minimumStalenessDays: minimumStalenessDays,
                keepList: keepList,
                now: now,
                visitedDirs: &visitedDirs,
                results: &discovered
            )
        }

        return discovered.sorted { $0.allocatedBytes > $1.allocatedBytes }
    }

    private struct ArtifactClassification {
        let kindLabel: String
        let level: AdvisoryLevel
        let badgeTitle: String
        let whatIsThis: String
        let consequence: String
    }

    private func walkDirectory(
        dir: URL,
        workspaceRoot: URL,
        depth: Int,
        maxDepth: Int,
        minimumBytes: Int64,
        minimumStalenessDays: Int,
        keepList: KeepListStore?,
        now: Date,
        visitedDirs: inout Set<String>,
        results: inout [ScannableItem]
    ) {
        guard depth <= maxDepth, !Task.isCancelled else { return }
        let standardizedDir = dir.standardizedFileURL
        guard visitedDirs.insert(standardizedDir.path).inserted else { return }

        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .contentModificationDateKey]
        guard let entries = try? fm.contentsOfDirectory(
            at: standardizedDir,
            includingPropertiesForKeys: keys,
            options: []
        ) else {
            return
        }

        let siblingNames = Set(entries.map(\.lastPathComponent))

        for entry in entries {
            if Task.isCancelled { break }
            guard let vals = try? entry.resourceValues(forKeys: Set(keys)),
                  vals.isSymbolicLink != true,
                  vals.isDirectory == true,
                  vals.isPackage != true else {
                continue
            }

            let name = entry.lastPathComponent
            // Strictly skip VCS and cloud folders
            if name == ".git" || name == ".svn" || name == ".hg" || name == "CloudStorage" || name == "Mobile Documents" {
                continue
            }

            // Special handling for .angular/cache when angular.json is present
            if name == ".angular", siblingNames.contains("angular.json") {
                let cacheDir = entry.appendingPathComponent("cache").standardizedFileURL
                let target = fm.fileExists(atPath: cacheDir.path) ? cacheDir : entry.standardizedFileURL
                let classification = ArtifactClassification(
                    kindLabel: "Angular CLI Build Cache",
                    level: .caution,
                    badgeTitle: "Caution • Angular Build Cache",
                    whatIsThis: "Angular CLI compiler and Webpack/Vite persistent cache.",
                    consequence: "Source code is untouched; regenerated automatically on next 'ng serve' or 'ng build'."
                )
                appendArtifactIfEligible(
                    targetURL: target,
                    parentDir: standardizedDir,
                    workspaceRoot: workspaceRoot,
                    classification: classification,
                    minimumBytes: minimumBytes,
                    minimumStalenessDays: minimumStalenessDays,
                    keepList: keepList,
                    now: now,
                    results: &results
                )
                continue
            }

            if let classification = classifyArtifactDirectory(
                entry: entry,
                name: name,
                siblingNames: siblingNames
            ) {
                appendArtifactIfEligible(
                    targetURL: entry.standardizedFileURL,
                    parentDir: standardizedDir,
                    workspaceRoot: workspaceRoot,
                    classification: classification,
                    minimumBytes: minimumBytes,
                    minimumStalenessDays: minimumStalenessDays,
                    keepList: keepList,
                    now: now,
                    results: &results
                )
                // Do NOT recurse inside matched artifact directory (prevents nested node_modules or dist/test-out double-counting)
                continue
            }

            // Skip hidden dot-directories except known container folders if any
            if name.hasPrefix(".") {
                continue
            }

            walkDirectory(
                dir: entry,
                workspaceRoot: workspaceRoot,
                depth: depth + 1,
                maxDepth: maxDepth,
                minimumBytes: minimumBytes,
                minimumStalenessDays: minimumStalenessDays,
                keepList: keepList,
                now: now,
                visitedDirs: &visitedDirs,
                results: &results
            )
        }
    }

    private func classifyArtifactDirectory(
        entry: URL,
        name: String,
        siblingNames: Set<String>
    ) -> ArtifactClassification? {
        let fm = FileManager.default

        switch name {
        case "node_modules":
            guard siblingNames.contains("package.json") ||
                  siblingNames.contains("pnpm-workspace.yaml") ||
                  siblingNames.contains("yarn.lock") else {
                return nil
            }
            return ArtifactClassification(
                kindLabel: "Node.js Dependencies (node_modules)",
                level: .caution,
                badgeTitle: "Caution • Reinstall via npm/pnpm/yarn",
                whatIsThis: "Installed JavaScript/TypeScript packages for this workspace or package.",
                consequence: "Source code and lockfiles stay intact. Run npm/pnpm/yarn install before running this project again."
            )

        case ".next", ".nuxt", ".svelte-kit", ".turbo", ".parcel-cache", ".vite":
            guard siblingNames.contains("package.json") else { return nil }
            return ArtifactClassification(
                kindLabel: "Frontend Build Cache (\(name))",
                level: .caution,
                badgeTitle: "Caution • Framework Build Output",
                whatIsThis: "Compiled bundles and incremental cache generated by \(name).",
                consequence: "Source files stay untouched; rebuilt on next dev/build run."
            )

        case "dist":
            let jsMarkers: Set<String> = [
                "package.json", "tsconfig.json", "vite.config.ts", "vite.config.js",
                "webpack.config.js", "rollup.config.js", "esbuild.config.js"
            ]
            guard !siblingNames.isDisjoint(with: jsMarkers) else { return nil }
            return ArtifactClassification(
                kindLabel: "Compiled Distribution Output (dist)",
                level: .caution,
                badgeTitle: "Caution • Compiled Output Folder",
                whatIsThis: "Bundled/transpiled build output directory (including any nested test output).",
                consequence: "Regenerated by your project's build script (e.g. 'npm run build'). Verify no hand-edited files were placed inside dist/."
            )

        case "build", ".gradle":
            let gradleMarkers: Set<String> = [
                "build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts", "gradlew"
            ]
            if !siblingNames.isDisjoint(with: gradleMarkers) {
                return ArtifactClassification(
                    kindLabel: name == ".gradle" ? "Project Gradle Cache (.gradle)" : "Gradle / Android Build Output (build)",
                    level: .caution,
                    badgeTitle: "Caution • Android / Gradle Build Output",
                    whatIsThis: "Intermediate APK/AAB intermediates, Kotlin/Java classes, and local Gradle task outputs.",
                    consequence: "Source code is untouched; Android Studio or './gradlew assemble' regenerates this folder on next build."
                )
            }
            if name == "build", siblingNames.contains("CMakeLists.txt") {
                return ArtifactClassification(
                    kindLabel: "CMake Build Output (build)",
                    level: .caution,
                    badgeTitle: "Caution • CMake Build Folder",
                    whatIsThis: "Compiled native C/C++ build intermediates.",
                    consequence: "Re-run CMake configure & build to regenerate."
                )
            }
            if name == "build", siblingNames.contains("pubspec.yaml") {
                return ArtifactClassification(
                    kindLabel: "Flutter / Dart Build Output (build)",
                    level: .caution,
                    badgeTitle: "Caution • Flutter Build Output",
                    whatIsThis: "Compiled Flutter build artifacts.",
                    consequence: "Regenerated automatically on next 'flutter run' or 'flutter build'."
                )
            }
            return nil

        case "Pods":
            guard siblingNames.contains("Podfile") || siblingNames.contains("Podfile.lock") else { return nil }
            return ArtifactClassification(
                kindLabel: "CocoaPods Dependencies (Pods)",
                level: .caution,
                badgeTitle: "Caution • Restore via pod install",
                whatIsThis: "Installed iOS/macOS CocoaPods frameworks for this project.",
                consequence: "Podfile.lock stays intact; run 'pod install' before building in Xcode."
            )

        case ".build":
            guard siblingNames.contains("Package.swift") else { return nil }
            return ArtifactClassification(
                kindLabel: "SwiftPM Build Artifacts (.build)",
                level: .caution,
                badgeTitle: "Caution • Swift Build Output",
                whatIsThis: "Compiled Swift Package Manager modules and binaries.",
                consequence: "Rebuilt automatically on next 'swift build' or 'swift test'."
            )

        case "target":
            if siblingNames.contains("Cargo.toml") {
                return ArtifactClassification(
                    kindLabel: "Rust Cargo Build Artifacts (target)",
                    level: .caution,
                    badgeTitle: "Caution • Rust Cargo Target",
                    whatIsThis: "Compiled Rust crates and incremental build cache.",
                    consequence: "Source code stays untouched; next 'cargo build' recompiles dependencies."
                )
            }
            if siblingNames.contains("pom.xml") {
                return ArtifactClassification(
                    kindLabel: "Maven Build Output (target)",
                    level: .caution,
                    badgeTitle: "Caution • Maven Target Output",
                    whatIsThis: "Compiled Java classes and packaged JAR/WAR outputs.",
                    consequence: "Rebuilt on next 'mvn package'."
                )
            }
            return nil

        case ".venv", "venv":
            let pyvenvCfg = entry.appendingPathComponent("pyvenv.cfg")
            let pyMarkers: Set<String> = ["pyproject.toml", "requirements.txt", "Pipfile", "setup.py"]
            guard fm.fileExists(atPath: pyvenvCfg.path) || !siblingNames.isDisjoint(with: pyMarkers) else {
                return nil
            }
            return ArtifactClassification(
                kindLabel: "Python Virtual Environment (\(name))",
                level: .caution,
                badgeTitle: "Caution • Python Virtualenv",
                whatIsThis: "Isolated Python interpreter and pip/uv site-packages directory.",
                consequence: "Recreate the virtual environment and reinstall from requirements.txt / pyproject.toml when needed."
            )

        case "renv":
            let libraryDir = entry.appendingPathComponent("library")
            guard siblingNames.contains("renv.lock") || fm.fileExists(atPath: libraryDir.path) else {
                return nil
            }
            return ArtifactClassification(
                kindLabel: "R renv Package Library (renv)",
                level: .warning,
                badgeTitle: "Warning • R renv Library",
                whatIsThis: "Project-local R package library managed by renv.",
                consequence: "renv.lock preserves versions, but running renv::restore() may recompile C/C++/Fortran R packages from source."
            )

        default:
            return nil
        }
    }

    private func appendArtifactIfEligible(
        targetURL: URL,
        parentDir: URL,
        workspaceRoot: URL,
        classification: ArtifactClassification,
        minimumBytes: Int64,
        minimumStalenessDays: Int,
        keepList: KeepListStore?,
        now: Date,
        results: inout [ScannableItem]
    ) {
        guard !safetyPolicy.evaluateProtection(for: targetURL).isProtected else { return }
        let footprint = ConcurrentDiskScanner.measureFootprint(at: targetURL)
        guard footprint.allocatedBytes >= minimumBytes else { return }

        let activityDate = estimateProjectActivityDate(parentDir: parentDir, artifactModified: footprint.lastModified)
        let staleness = ByteFormatting.daysBetween(activityDate, and: now) ?? 0
        if minimumStalenessDays > 0 && staleness < minimumStalenessDays {
            return
        }

        let relativeDisplay = relativeProjectPath(for: targetURL, under: workspaceRoot)
        let pinned = keepList?.isPinned(url: targetURL) ?? false
        let advisory = ItemAdvisory(
            level: classification.level,
            badgeTitle: classification.badgeTitle,
            whatIsThis: classification.whatIsThis,
            consequenceIfRemoved: classification.consequence,
            requiresExplicitAck: classification.level == .warning,
            isPinnedByUser: pinned
        ).withPinState(pinned)

        results.append(
            ScannableItem(
                url: targetURL,
                title: "\(relativeDisplay) — \(classification.kindLabel)",
                subtitle: targetURL.path,
                domain: .projectArtifacts,
                allocatedBytes: footprint.allocatedBytes,
                itemCount: footprint.itemCount,
                lastModified: activityDate,
                stalenessDays: staleness,
                advisory: advisory
            )
        )
    }

    private func estimateProjectActivityDate(parentDir: URL, artifactModified: Date?) -> Date? {
        var latest = artifactModified
        let candidateFiles = [
            "package.json", "build.gradle", "build.gradle.kts", "Podfile",
            "Package.swift", "Cargo.toml", "pyproject.toml", "requirements.txt",
            "renv.lock", ".git/index", ".git/HEAD"
        ]
        for rel in candidateFiles {
            let fileURL = parentDir.appendingPathComponent(rel)
            if let mod = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate {
                if latest == nil || mod > latest! {
                    latest = mod
                }
            }
        }
        return latest
    }

    private func relativeProjectPath(for target: URL, under workspaceRoot: URL) -> String {
        let rootPath = workspaceRoot.standardizedFileURL.path
        let targetPath = target.standardizedFileURL.path
        if targetPath.hasPrefix(rootPath + "/") {
            return String(targetPath.dropFirst(rootPath.count + 1))
        }
        return target.lastPathComponent
    }
}
