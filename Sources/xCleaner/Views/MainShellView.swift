import SwiftUI
import XCleanerCore

struct MainShellView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 238, ideal: 254, max: 288)
        } detail: {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    if let banner = viewModel.notifications.activeBanner {
                        inAppBannerView(banner)
                        Divider()
                    }

                    activeDetailView
                        .frame(minWidth: 485, maxWidth: .infinity, maxHeight: .infinity)

                    if !viewModel.stagedTargets.isEmpty {
                        Divider()
                        cleanupQueueBottomBar
                    }
                }

                if viewModel.isInspectorVisible {
                    Divider()
                    AdvisoryInspectorView(viewModel: viewModel)
                }
            }
        }
        .onChange(of: viewModel.selectedSection) { _, newSection in
            syncInspectorForSection(newSection)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    viewModel.isInspectorVisible.toggle()
                } label: {
                    Label("Toggle Decision Inspector", systemImage: "sidebar.right")
                }
                .help("Show or hide the right-hand Decision Inspector")
            }
        }
        .sheet(isPresented: $viewModel.isShowingQueueSheet) {
            CleanupQueueSheet(viewModel: viewModel)
        }
    }

    private func syncInspectorForSection(_ section: SidebarSection) {
        switch section {
        case .smartJunk:
            if let first = viewModel.smartJunkReport?.items.first {
                viewModel.inspectorSubject = .scannable(first)
            }
        case .appUninstaller:
            if let firstApp = viewModel.installedApps.first {
                viewModel.inspectorSubject = .installedApp(firstApp)
            }
        case .toolchainsAndDocker:
            if let first = viewModel.toolchainItems.first {
                viewModel.inspectorSubject = .toolchain(first)
            }
        case .visualExplorer:
            if let current = viewModel.currentExplorerNode {
                viewModel.inspectorSubject = .diskNode(current)
            }
        case .largeFiles:
            if let first = viewModel.largeFiles.first {
                viewModel.inspectorSubject = .largeFile(first)
            }
        default:
            break
        }
    }

    private var sidebarContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(SidebarSection.allCases, selection: $viewModel.selectedSection) { section in
                HStack(spacing: 9) {
                    Image(systemName: section.symbolName)
                        .font(.system(size: 13.5, weight: .semibold))
                        .frame(width: 18)

                    VStack(alignment: .leading, spacing: 1.5) {
                        Text(section.rawValue)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                            .layoutPriority(1)
                        Text(section.subtitle)
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    if let badge = sidebarBadge(for: section) {
                        Text(badge)
                            .font(.system(size: 10.5, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule()
                                    .fill(Color.primary.opacity(0.06))
                            )
                            .fixedSize()
                    }
                }
                .padding(.vertical, 3.5)
                .tag(section)
            }
            .listStyle(.sidebar)

            if let metrics = viewModel.volumeMetrics {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Circle()
                            .fill(metrics.isCriticallyConstrained ? Color(nsColor: .systemRed) : Color(nsColor: .systemGreen))
                            .frame(width: 7, height: 7)
                        Text("\(ByteFormatting.string(from: metrics.rawAvailableBytes)) Free")
                            .font(.system(size: 12, weight: .bold))
                            .monospacedDigit()
                            .fixedSize()
                        Spacer()
                        Text("\(Int((metrics.usedFraction * 100).rounded()))% full")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                            .fixedSize()
                    }
                    ProportionalBar(
                        fraction: metrics.usedFraction,
                        tint: metrics.isCriticallyConstrained ? Color(nsColor: .systemRed) : .accentColor,
                        height: 5
                    )
                }
                .padding(12)
            }
        }
    }

    private func sidebarBadge(for section: SidebarSection) -> String? {
        switch section {
        case .smartJunk:
            guard let bytes = viewModel.smartJunkReport?.totalFoundBytes, bytes > 0 else { return nil }
            return ByteFormatting.string(from: bytes)
        case .appUninstaller:
            let count = viewModel.installedApps.count
            return count > 0 ? "\(count) apps" : nil
        case .toolchainsAndDocker:
            let sum = viewModel.toolchainItems.reduce(Int64(0)) { $0 + $1.allocatedBytes }
            return sum > 0 ? ByteFormatting.string(from: sum) : nil
        case .settings:
            let pins = viewModel.pinnedEntries.count
            return pins > 0 ? "\(pins) pin" : nil
        default:
            return nil
        }
    }

    @ViewBuilder
    private var activeDetailView: some View {
        switch viewModel.selectedSection {
        case .storagePulse:
            StoragePulseView(viewModel: viewModel)
        case .smartJunk:
            SmartJunkView(viewModel: viewModel)
        case .appUninstaller:
            AppUninstallerView(viewModel: viewModel)
        case .toolchainsAndDocker:
            ToolchainsAndDockerView(viewModel: viewModel)
        case .visualExplorer:
            VisualExplorerView(viewModel: viewModel)
        case .largeFiles:
            LargeFilesView(viewModel: viewModel)
        case .cleanupHistory:
            CleanupHistoryView(viewModel: viewModel)
        case .settings:
            SettingsView(viewModel: viewModel)
        }
    }

    private func inAppBannerView(_ banner: InAppNotice) -> some View {
        let color: Color = {
            switch banner.severity {
            case .info: return .accentColor
            case .success: return Color(nsColor: .systemGreen)
            case .caution: return Color(nsColor: .systemOrange)
            case .warning: return Color(nsColor: .systemRed)
            }
        }()

        return HStack(spacing: 10) {
            Image(systemName: banner.severity.symbolName)
                .foregroundStyle(color)
                .font(.system(size: 14, weight: .semibold))
            Text(banner.title)
                .font(.system(size: 12.5, weight: .semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            Text("—")
                .foregroundStyle(.tertiary)
            Text(banner.message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Button {
                viewModel.notifications.dismissBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color.opacity(0.08))
    }

    private var cleanupQueueBottomBar: some View {
        let warnCount = viewModel.stagedWarningTargets.count
        return HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.up.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text("\(viewModel.stagedTargets.count) Staged")
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize()
                    Text(ByteFormatting.string(from: viewModel.totalStagedBytes))
                        .font(.system(size: 13.5, weight: .bold))
                        .foregroundStyle(Color.accentColor)
                        .monospacedDigit()
                        .fixedSize()
                    if warnCount > 0 {
                        Text("\(warnCount) Warning")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(nsColor: .systemRed))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color(nsColor: .systemRed).opacity(0.12)))
                            .fixedSize()
                    }
                }
                Text("Nothing is removed until you click Review & Clean and confirm.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button("Clear") {
                viewModel.clearQueue()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .fixedSize()

            Button {
                viewModel.isShowingQueueSheet = true
            } label: {
                Label("Review & Clean…", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.regularMaterial)
    }
}
