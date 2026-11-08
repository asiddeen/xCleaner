import AppKit
import SwiftUI
import XCleanerCore

struct MenuBarCompanionView: View {
    @Bindable var viewModel: AppViewModel
    var onNavigateToMainWindow: (SidebarSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("xCleaner Storage Pulse", systemImage: "internaldrive.fill")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    Task { await viewModel.refreshVolumeMetrics() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .help("Refresh APFS metrics")
            }

            if let metrics = viewModel.volumeMetrics {
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("\(ByteFormatting.string(from: metrics.rawAvailableBytes)) Free")
                            .font(.system(size: 16, weight: .bold))
                            .monospacedDigit()
                        Spacer()
                        Text("of \(ByteFormatting.string(from: metrics.totalBytes))")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    ProportionalBar(
                        fraction: metrics.usedFraction,
                        tint: metrics.isCriticallyConstrained ? Color(nsColor: .systemRed) : .accentColor,
                        height: 7
                    )

                    HStack {
                        Text("Data: \(ByteFormatting.string(from: metrics.dataVolumeUsedBytes))")
                        Spacer()
                        Text("VM Swap: \(ByteFormatting.string(from: metrics.vmSwapBytes))")
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                }
            }

            if let report = viewModel.smartJunkReport {
                Divider()
                HStack {
                    Text("Discovered Junk & Builds:")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(ByteFormatting.string(from: report.totalFoundBytes))
                        .font(.system(size: 12, weight: .bold))
                        .monospacedDigit()
                }
            }

            Divider()

            HStack(spacing: 8) {
                Button {
                    onNavigateToMainWindow(.smartJunk)
                } label: {
                    Label("Open Smart Junk", systemImage: "sparkles.rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    onNavigateToMainWindow(.storagePulse)
                } label: {
                    Text("Dashboard")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack {
                Button("Rescan Now") {
                    viewModel.launchSmartJunkScan()
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)

                Spacer()

                Button("Quit xCleaner") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(width: 295)
    }
}
