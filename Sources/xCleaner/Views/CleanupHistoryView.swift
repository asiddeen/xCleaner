import SwiftUI
import XCleanerCore

struct CleanupHistoryView: View {
    @Bindable var viewModel: AppViewModel

    private var cumulativeFreedBytes: Int64 {
        viewModel.cleanupHistory.reduce(0) { $0 + $1.freedBytes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cleanup Audit History")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Persistent JSONL audit trail in ~/Library/Application Support/xCleaner/cleanup-history.jsonl")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if cumulativeFreedBytes > 0 {
                    Text("Total Reclaimed: \(ByteFormatting.string(from: cumulativeFreedBytes))")
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(nsColor: .systemGreen).opacity(0.14)))
                        .fixedSize()
                }

                Button("Open Log Folder") {
                    viewModel.revealInFinder(viewModel.historyStore.logFileURL)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if viewModel.cleanupHistory.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text("No Cleanups Recorded Yet")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Every Move-to-Trash, Permanent Delete, or Docker Prune operation is logged here with full path details.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(viewModel.cleanupHistory) { record in
                            recordCard(record)
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Cleanup History")
    }

    private func recordCard(_ record: CleanupRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(record.actionKind, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13.5, weight: .semibold))
                Spacer()
                if record.freedBytes > 0 {
                    Text(ByteFormatting.string(from: record.freedBytes))
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(Color(nsColor: .systemGreen))
                        .monospacedDigit()
                }
                Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if let notes = record.notes, !notes.isEmpty {
                Text(notes)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            if !record.cleanedPaths.isEmpty {
                DisclosureGroup("Cleaned Paths (\(record.cleanedPaths.count))") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(record.cleanedPaths, id: \.self) { p in
                            Text(p)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 12, weight: .medium))
            }

            if !record.skippedItems.isEmpty {
                DisclosureGroup("Safety Skips (\(record.skippedItems.count))") {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(record.skippedItems, id: \.self) { s in
                            Text(s)
                                .font(.system(size: 11))
                                .foregroundStyle(Color(nsColor: .systemOrange))
                        }
                    }
                    .padding(.top, 4)
                }
                .font(.system(size: 12, weight: .medium))
            }
        }
        .xCleanerCard(padding: 13)
    }
}
