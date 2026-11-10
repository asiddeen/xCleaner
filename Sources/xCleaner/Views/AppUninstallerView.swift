import AppKit
import SwiftUI
import XCleanerCore

struct AppUninstallerView: View {
    private enum AppFilterTab: String, CaseIterable, Identifiable {
        case installed = "Installed Applications"
        case leftovers = "Uninstalled Leftovers"
        var id: String { rawValue }
    }

    @Bindable var viewModel: AppViewModel
    @State private var activeTab: AppFilterTab = .installed
    @State private var searchText: String = ""
    @State private var expandedAppIDs: Set<String> = []

    private var filteredInstalledApps: [InstalledAppBundle] {
        viewModel.installedApps.filter { app in
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                return app.displayName.lowercased().contains(q)
                    || (app.bundleID?.lowercased().contains(q) ?? false)
            }
            return true
        }
    }

    private var orphanedLeftoverItems: [ScannableItem] {
        guard let report = viewModel.smartJunkReport else { return [] }
        return report.items.filter { $0.domain == .orphanedApps }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()

            switch activeTab {
            case .installed:
                installedAppsView
            case .leftovers:
                leftoversView
            }
        }
        .navigationTitle("App Uninstaller")
        .onAppear {
            if viewModel.installedApps.isEmpty && !viewModel.isScanningApps {
                viewModel.launchAppScan()
            } else if let firstApp = viewModel.installedApps.first {
                switch viewModel.inspectorSubject {
                case .installedApp, .appLocation:
                    break
                default:
                    viewModel.inspectorSubject = .installedApp(firstApp)
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Picker("Mode", selection: $activeTab) {
                ForEach(AppFilterTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 360)

            Spacer(minLength: 8)

            SearchFilterField(placeholder: "Search app name or bundle ID…", text: $searchText)
                .frame(minWidth: 170, maxWidth: 260)

            Button {
                viewModel.launchAppScan()
                viewModel.launchSmartJunkScan()
            } label: {
                Label("Rescan Apps", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .disabled(viewModel.isScanningApps)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Installed Apps View

    private var installedAppsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.isScanningApps && viewModel.installedApps.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning /Applications & ~/Library for associated app containers & caches…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredInstalledApps.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "app.badge.checkmark")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("No Matching Applications Found")
                        .font(.system(size: 14, weight: .semibold))
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(filteredInstalledApps) { app in
                            installedAppCard(app)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func installedAppCard(_ app: InstalledAppBundle) -> some View {
        let isExpanded = expandedAppIDs.contains(app.id)
        let isSelected: Bool = {
            switch viewModel.inspectorSubject {
            case .installedApp(let sel):
                return sel.id == app.id
            case .appLocation(let sel, _):
                return sel.id == app.id
            default:
                return false
            }
        }()

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                // App Icon
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.appURL.path))
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(app.displayName)
                            .font(.system(size: 13.5, weight: .semibold))
                        if let ver = app.version {
                            Text("v\(ver)")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        if app.isSystemProtected {
                            Text("System Protected")
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Capsule().fill(Color.primary.opacity(0.06)))
                        }
                        if app.isRunning {
                            HStack(spacing: 4) {
                                Circle().fill(Color.orange).frame(width: 6, height: 6)
                                Text("Running")
                                    .font(.system(size: 10.5, weight: .semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    Text(app.bundleID ?? app.appURL.path)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                // Total footprint
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ByteFormatting.string(from: app.totalFootprintBytes))
                        .font(.system(size: 14, weight: .bold))
                        .monospacedDigit()
                    Text("\(app.locations.count) location(s)")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }

                // Action Buttons
                if !app.isSystemProtected {
                    HStack(spacing: 6) {
                        if app.safeCacheBytes > 0 {
                            Button("Clean Caches") {
                                viewModel.inspectorSubject = .installedApp(app)
                                viewModel.stageAppSafeCaches(app)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("Stage regenerable caches only (\(ByteFormatting.string(from: app.safeCacheBytes)))")
                        }

                        Button("Reset App") {
                            viewModel.inspectorSubject = .installedApp(app)
                            viewModel.stageAppReset(app)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Factory reset: stage caches, support files & preferences while keeping the app bundle")

                        Button("Uninstall") {
                            viewModel.inspectorSubject = .installedApp(app)
                            viewModel.stageFullAppUninstall(app)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(nsColor: .systemRed))
                        .controlSize(.small)
                        .help("Stage app bundle and all ~/Library leftovers for removal")
                    }
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                viewModel.inspectorSubject = .installedApp(app)
            }

            // Expand disclosure
            if !app.locations.isEmpty {
                Button {
                    if isExpanded {
                        expandedAppIDs.remove(app.id)
                    } else {
                        expandedAppIDs.insert(app.id)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text(isExpanded ? "Hide Associated Locations" : "Show \(app.locations.count) Associated Locations (Caches, Prefs, Support)")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)

                if isExpanded {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(app.locations) { loc in
                            appLocationRow(app: app, location: loc)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            viewModel.inspectorSubject = .installedApp(app)
        }
    }

    private func appLocationRow(app: InstalledAppBundle, location: AppAssociatedLocation) -> some View {
        let subject = InspectorSubject.appLocation(app, location)
        let isStaged = viewModel.isStaged(urls: [location.url])
        let isLocSelected: Bool = {
            if case .appLocation(let selApp, let selLoc) = viewModel.inspectorSubject {
                return selApp.id == app.id && selLoc.id == location.id
            }
            return false
        }()

        return HStack(spacing: 8) {
            StageCheckboxOrLockButton(
                advisory: location.advisory,
                isStaged: isStaged
            ) {
                viewModel.inspectorSubject = subject
                viewModel.toggleStage(subject: subject)
            }

            Image(systemName: location.category.symbolName)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(location.category.rawValue)
                        .font(.system(size: 12, weight: .medium))
                    AdvisoryPillView(advisory: location.advisory, compact: true)
                    Spacer()
                    Text(ByteFormatting.string(from: location.allocatedBytes))
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                }

                Text(location.url.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isLocSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.025))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isLocSelected ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.inspectorSubject = subject
        }
    }

    // MARK: - Leftovers View (Orphaned Apps)

    private var leftoversView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if orphanedLeftoverItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 30))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                    Text("No Orphaned App Leftovers Detected")
                        .font(.system(size: 14, weight: .semibold))
                    Text("No leftover Application Support folders or uninstalled IDE configurations were found.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(orphanedLeftoverItems) { item in
                            orphanedRow(item: item)
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func orphanedRow(item: ScannableItem) -> some View {
        let subject = InspectorSubject.scannable(item)
        let isStaged = viewModel.isStaged(urls: item.allTargetURLs)
        let isSelected: Bool = {
            if case .scannable(let sel) = viewModel.inspectorSubject {
                return sel.id == item.id
            }
            return false
        }()

        return HStack(spacing: 10) {
            StageCheckboxOrLockButton(
                advisory: item.advisory,
                isStaged: isStaged
            ) {
                viewModel.inspectorSubject = subject
                viewModel.toggleStage(subject: subject)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                    AdvisoryPillView(advisory: item.advisory, compact: true)
                    Spacer()
                    Button {
                        viewModel.revealInFinder(item.url)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    Text(ByteFormatting.string(from: item.allocatedBytes))
                        .font(.system(size: 13.5, weight: .bold))
                        .monospacedDigit()
                }

                Text(item.subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.primary.opacity(0.035))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.65) : Color.primary.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onTapGesture {
            viewModel.inspectorSubject = subject
        }
    }
}
