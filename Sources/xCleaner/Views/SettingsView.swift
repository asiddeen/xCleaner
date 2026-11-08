import AppKit
import SwiftUI
import XCleanerCore

struct SettingsView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Settings & Pinned Keep List")
                    .font(.system(size: 19, weight: .semibold))

                pinnedKeepListSection
                projectRootsSection
                behaviorAndAlertsSection
                safetyGuaranteeSection
            }
            .padding(20)
        }
        .navigationTitle("Settings & Keep List")
    }

    private var pinnedKeepListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Pinned to Keep (\(viewModel.pinnedEntries.count))", systemImage: "pin.fill")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }
            Text("Items you pin (e.g. Spotify offline songs, specific Gradle or Node versions, or active workspaces) are never staged or deleted until you unpin them.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            if viewModel.pinnedEntries.isEmpty {
                Text("No items pinned yet. Click the pin icon on any item across Smart Junk, Toolchains, or Explorer to protect it.")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 6)
            } else {
                ForEach(viewModel.pinnedEntries) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entry.label)
                                .font(.system(size: 12.5, weight: .semibold))
                            Text(entry.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Unpin") {
                            viewModel.unpinEntry(entry)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.035)))
                }
            }
        }
        .xCleanerCard(padding: 14)
    }

    private var projectRootsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Developer Workspace Scan Roots", systemImage: "folder.badge.gearshape")
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    panel.prompt = "Add Workspace Root"
                    if panel.runModal() == .OK, let url = panel.url {
                        viewModel.preferences.addProjectRoot(url)
                        viewModel.launchSmartJunkScan()
                    }
                } label: {
                    Label("Add Workspace Folder…", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text("Scanned up to depth 7 for project build artifacts (node_modules, dist, android/app/build, .next, .build, target, venv, R renv) and toolchain pins (gradle-wrapper.properties, .nvmrc).")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            ForEach(viewModel.preferences.projectRootPaths, id: \.self) { path in
                HStack {
                    Image(systemName: "folder")
                        .foregroundStyle(.secondary)
                    Text(path)
                        .font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Button {
                        viewModel.preferences.removeProjectRoot(path: path)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.035)))
            }
        }
        .xCleanerCard(padding: 14)
    }

    private var behaviorAndAlertsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Alerts, Menu Bar & Permissions", systemImage: "bell.badge")
                .font(.system(size: 14, weight: .semibold))

            Toggle("Show xCleaner Companion in macOS Menu Bar (0% idle CPU)", isOn: Binding(
                get: { viewModel.preferences.showMenuBarExtra },
                set: { viewModel.setShowMenuBarExtra($0) }
            ))

            Toggle("Enable Low-Disk & Cleanup Summary macOS Notifications", isOn: Binding(
                get: { viewModel.preferences.notificationsEnabled },
                set: { viewModel.preferences.notificationsEnabled = $0 }
            ))

            HStack {
                Text("Low-Disk Warning Threshold:")
                    .font(.system(size: 12.5))
                Picker("", selection: Binding(
                    get: { viewModel.preferences.lowDiskThresholdGB },
                    set: { viewModel.preferences.lowDiskThresholdGB = $0 }
                )) {
                    Text("< 10 GB Free").tag(10)
                    Text("< 15 GB Free").tag(15)
                    Text("< 25 GB Free").tag(25)
                    Text("< 40 GB Free").tag(40)
                }
                .frame(width: 150)
                Spacer()
                Button("Open Full Disk Access…") {
                    viewModel.openFullDiskAccessSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .xCleanerCard(padding: 14)
    }

    private var safetyGuaranteeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Hardcoded macOS Stability & Data Protection Policy", systemImage: "lock.shield.fill")
                .font(.system(size: 13.5, weight: .semibold))
            Text("xCleaner strictly blocks deletion of /System, /Library, /Applications, Keychains, Preferences, Mail, Messages, Safari, iCloud Mobile Documents, CloudStorage (Google Drive/OneDrive), MobileSync iOS backups, Apple Photos libraries, ~/.ssh, ~/.gnupg, ~/.aws, ~/.kube, OAuth tokens, cryptographic keys (.pem/.key/.p12/.keystore), every .git folder, browser Cookies/Logins/Bookmarks/History/Local Storage/IndexedDB, and raw Docker.raw VM disks.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .xCleanerCard(padding: 14)
    }
}
