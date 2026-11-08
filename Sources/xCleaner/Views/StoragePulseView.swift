import SwiftUI
import XCleanerCore

struct StoragePulseView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerRow

                if let metrics = viewModel.volumeMetrics {
                    if metrics.isCriticallyConstrained {
                        criticalPressureCallout(metrics: metrics)
                    }

                    apfsContainerCard(metrics: metrics)

                    FullDiskAccessBanner(
                        unscannedEstimateBytes: metrics.tccUnscannedBytesEstimate,
                        hasFullDiskAccess: viewModel.probeTCCFullDiskAccess(),
                        onGrantAccess: { viewModel.openFullDiskAccessSettings() }
                    )

                    quickActionCardsGrid(metrics: metrics)

                    maintenanceAndSnapshotsSection(metrics: metrics)
                } else {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Inspecting APFS container & volumes…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 160)
                }
            }
            .padding(20)
        }
        .navigationTitle("Storage Pulse")
    }

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Apple Silicon APFS Storage Pulse")
                    .font(.system(size: 20, weight: .semibold))
                Text("Real-time container breakdown replacing df, diskutil apfs list, and tmutil.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await viewModel.refreshVolumeMetrics() }
            } label: {
                Label("Refresh APFS", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .disabled(viewModel.isRefreshingVolume)
        }
    }

    private func criticalPressureCallout(metrics: VolumeMetrics) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color(nsColor: .systemRed))

            VStack(alignment: .leading, spacing: 4) {
                Text("High Storage & Swap Pressure Detected (\(ByteFormatting.string(from: metrics.rawAvailableBytes)) Raw Free)")
                    .font(.system(size: 13.5, weight: .semibold))
                Text("Opportunistic free capacity is \(ByteFormatting.string(from: metrics.opportunisticAvailableBytes)) and macOS VM swap is consuming \(ByteFormatting.string(from: metrics.vmSwapBytes)). Reclaiming 15–25 GB of caches or old toolchains will restore headroom and reduce SSD swap thrashing.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Review Smart Junk") {
                viewModel.selectedSection = .smartJunk
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .systemRed).opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color(nsColor: .systemRed).opacity(0.32), lineWidth: 1)
        )
    }

    private func apfsContainerCard(metrics: VolumeMetrics) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .lastTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Macintosh HD (APFS Container)")
                        .font(.system(size: 14, weight: .semibold))
                    Text("\(ByteFormatting.string(from: metrics.containerUsedBytes)) used of \(ByteFormatting.string(from: metrics.totalBytes))")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(ByteFormatting.string(from: metrics.rawAvailableBytes)) Free")
                        .font(.system(size: 18, weight: .bold))
                        .monospacedDigit()
                    if metrics.purgeableBytes > 0 {
                        Text("\(ByteFormatting.string(from: metrics.importantAvailableBytes)) incl. macOS purgeable")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            // Segmented APFS Bar
            GeometryReader { geo in
                let total = Double(max(1, metrics.totalBytes))
                let dataW = geo.size.width * (Double(metrics.dataVolumeUsedBytes) / total)
                let vmW = geo.size.width * (Double(metrics.vmSwapBytes) / total)
                let sysW = geo.size.width * (Double(metrics.systemVolumeBytes + metrics.prebootAndRecoveryBytes) / total)
                let purgeW = geo.size.width * (Double(metrics.purgeableBytes) / total)

                HStack(spacing: 1.5) {
                    Rectangle()
                        .fill(Color.accentColor.gradient)
                        .frame(width: max(4, dataW - purgeW))
                    if purgeW > 2 {
                        Rectangle()
                            .fill(Color(nsColor: .systemTeal).opacity(0.65))
                            .frame(width: purgeW)
                    }
                    if vmW > 2 {
                        Rectangle()
                            .fill(Color(nsColor: .systemOrange))
                            .frame(width: vmW)
                    }
                    if sysW > 2 {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.55))
                            .frame(width: sysW)
                    }
                    Spacer(minLength: 0)
                }
                .background(Color.primary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .frame(height: 18)

            // Legend Grid
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 165), spacing: 10)
            ], spacing: 10) {
                legendTile(
                    color: .accentColor,
                    title: "User & App Data Volume",
                    bytes: metrics.dataVolumeUsedBytes,
                    note: "Your files, caches, SDKs & apps"
                )
                legendTile(
                    color: Color(nsColor: .systemOrange),
                    title: "APFS VM Swap Volume",
                    bytes: metrics.vmSwapBytes,
                    note: "Managed by macOS kernel memory"
                )
                legendTile(
                    color: .secondary,
                    title: "macOS System + Preboot",
                    bytes: metrics.systemVolumeBytes + metrics.prebootAndRecoveryBytes,
                    note: "Signed OS, Cryptexes & Recovery"
                )
                legendTile(
                    color: Color(nsColor: .systemTeal),
                    title: "macOS Purgeable Space",
                    bytes: metrics.purgeableBytes,
                    note: "Reclaimed on demand by APFS"
                )
                legendTile(
                    color: Color(nsColor: .systemGreen),
                    title: "Raw Unallocated Free",
                    bytes: metrics.rawAvailableBytes,
                    note: "Immediately writable blocks"
                )
                legendTile(
                    color: Color(nsColor: .systemPurple),
                    title: "Local TM Snapshots",
                    bytes: 0,
                    customValue: "\(metrics.localSnapshots.count) snapshot(s)",
                    note: metrics.localSnapshots.isEmpty ? "Zero snapshot bloat" : "Thin via tmutil below"
                )
            }
        }
        .xCleanerCard(padding: 16)
    }

    private func legendTile(
        color: Color,
        title: String,
        bytes: Int64,
        customValue: String? = nil,
        note: String
    ) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .padding(.top, 4)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(customValue ?? ByteFormatting.string(from: bytes))
                    .font(.system(size: 13.5, weight: .semibold))
                    .monospacedDigit()
                Text(note)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        )
    }

    private func quickActionCardsGrid(metrics: VolumeMetrics) -> some View {
        let junkBytes = viewModel.smartJunkReport?.totalFoundBytes ?? 0
        let safeBytes = viewModel.smartJunkReport?.autoSafeBytes ?? 0
        let toolchainBytes = viewModel.toolchainItems.reduce(Int64(0)) { $0 + $1.allocatedBytes }

        return LazyVGrid(columns: [
            GridItem(.adaptive(minimum: 205), spacing: 12)
        ], spacing: 12) {
            navigationSummaryCard(
                symbol: "sparkles.rectangle.stack",
                tint: Color(nsColor: .systemGreen),
                title: "Smart Junk & Caches",
                metric: viewModel.isScanningSmartJunk ? "Scanning…" : ByteFormatting.string(from: junkBytes),
                detail: safeBytes > 0
                    ? "\(ByteFormatting.string(from: safeBytes)) rated Safe • Rest user-decided"
                    : "Browsers, updaters, npm, orphaned apps & builds",
                buttonTitle: "Inspect Smart Junk"
            ) {
                viewModel.selectedSection = .smartJunk
            }

            navigationSummaryCard(
                symbol: "shippingbox.and.arrow.backward",
                tint: Color(nsColor: .systemOrange),
                title: "Toolchains & SSH Docker",
                metric: viewModel.isScanningToolchains ? "Scanning…" : ByteFormatting.string(from: toolchainBytes),
                detail: "\(viewModel.toolchainItems.count) SDK/runtime versions • \(viewModel.sshTargets.count) SSH host(s)",
                buttonTitle: "Compare Versions"
            ) {
                viewModel.selectedSection = .toolchainsAndDocker
            }

            navigationSummaryCard(
                symbol: "square.grid.3x2",
                tint: .accentColor,
                title: "Visual Folder Explorer",
                metric: viewModel.explorerScanRoot.map { ByteFormatting.string(from: $0.allocatedBytes) } ?? "ncdu + Treemap",
                detail: "Interactive size bars & squarified treemap for any folder",
                buttonTitle: "Explore Disk"
            ) {
                viewModel.selectedSection = .visualExplorer
                if viewModel.explorerScanRoot == nil && !viewModel.isScanningExplorer {
                    viewModel.launchExplorerScan()
                }
            }
        }
    }

    private func navigationSummaryCard(
        symbol: String,
        tint: Color,
        title: String,
        metric: String,
        detail: String,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            Text(metric)
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
            Text(detail)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(minHeight: 30, alignment: .topLeading)

            Button(action: action) {
                HStack {
                    Text(buttonTitle)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .xCleanerCard(padding: 14)
    }

    private func maintenanceAndSnapshotsSection(metrics: VolumeMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Native CLI Maintenance Runners (Zero Raw Root Deletion)")
                .font(.system(size: 13.5, weight: .semibold))

            HStack(spacing: 12) {
                if SafeToolPruner.locateHomebrew() != nil {
                    Button {
                        Task { await viewModel.runHomebrewPrune() }
                    } label: {
                        Label("Run brew cleanup", systemImage: "mug")
                    }
                    .disabled(viewModel.isRunningMaintenanceTool)
                }

                if SafeToolPruner.isSimctlAvailable() {
                    Button {
                        Task { await viewModel.runSimulatorPrune() }
                    } label: {
                        Label("Prune Unavailable Simulators", systemImage: "iphone.slash")
                    }
                    .disabled(viewModel.isRunningMaintenanceTool)
                }

                if !metrics.localSnapshots.isEmpty {
                    Button {
                        Task { await viewModel.runSnapshotThinning() }
                    } label: {
                        Label("Thin \(metrics.localSnapshots.count) Local TM Snapshot(s)…", systemImage: "clock.arrow.2.circlepath")
                    }
                    .disabled(viewModel.isRunningMaintenanceTool)
                }

                if viewModel.isRunningMaintenanceTool {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }

            if let output = viewModel.maintenanceLogOutput, !output.isEmpty {
                Text(output)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(5)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.primary.opacity(0.04))
                    )
            }
        }
        .xCleanerCard(padding: 14)
    }
}
