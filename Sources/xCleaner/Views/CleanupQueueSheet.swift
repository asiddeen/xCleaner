import SwiftUI
import XCleanerCore

struct CleanupQueueSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var deletionMode: DeletionMode = .moveToTrash
    @State private var hasAcknowledgedWarnings: Bool = false

    private var requiresExplicitGate: Bool {
        !viewModel.stagedWarningTargets.isEmpty || deletionMode == .permanentDelete
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Review Cleanup Queue")
                        .font(.system(size: 17, weight: .semibold))
                    Text("\(viewModel.stagedTargets.count) item(s) staged • \(ByteFormatting.string(from: viewModel.totalStagedBytes)) estimated space")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
                Button("Clear All") {
                    viewModel.clearQueue()
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Divider()

            // Staged Targets Scroll List
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(viewModel.stagedTargets) { target in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(target.title)
                                        .font(.system(size: 12.5, weight: .semibold))
                                        .lineLimit(1)
                                    AdvisoryPillView(advisory: target.advisory, compact: true)
                                }
                                Text(target.subtitle)
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(ByteFormatting.string(from: target.allocatedBytes))
                                .font(.system(size: 12.5, weight: .bold))
                                .monospacedDigit()

                            Button {
                                viewModel.removeStagedTarget(id: target.id)
                                if viewModel.stagedTargets.isEmpty { dismiss() }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove from queue")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.035)))
                    }
                }
            }
            .frame(minHeight: 170, maxHeight: 260)

            // Deletion Mode Selector
            VStack(alignment: .leading, spacing: 6) {
                Text("DELETION METHOD")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(.secondary)

                Picker("Method", selection: Binding(
                    get: { deletionMode },
                    set: { newMode in
                        deletionMode = newMode
                        hasAcknowledgedWarnings = false
                    }
                )) {
                    Text("Move to Trash (Recoverable via Finder — Recommended)").tag(DeletionMode.moveToTrash)
                    Text("Permanent Delete (Immediate Free Space — Unrecoverable)").tag(DeletionMode.permanentDelete)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.035)))

            // Explicit Warning & Permanent Delete Acknowledgment Gate
            if requiresExplicitGate {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color(nsColor: .systemRed))
                        Text(deletionMode == .permanentDelete
                             ? "Permanent Deletion + Warning Impact Review"
                             : "Explicit Confirmation Required for \(viewModel.stagedWarningTargets.count) Warning Item(s)")
                            .font(.system(size: 12.5, weight: .semibold))
                    }

                    ForEach(viewModel.stagedWarningTargets.prefix(3)) { warnItem in
                        Text("• \(warnItem.title): \(warnItem.advisory.consequenceIfRemoved)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if deletionMode == .permanentDelete {
                        Text("• Permanent Delete bypasses macOS Trash and frees APFS blocks immediately, so files cannot be Put Back from Trash.")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }

                    Toggle(
                        "I reviewed these consequences and want xCleaner to proceed",
                        isOn: $hasAcknowledgedWarnings
                    )
                    .font(.system(size: 12, weight: .medium))
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(nsColor: .systemRed).opacity(0.09))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color(nsColor: .systemRed).opacity(0.35), lineWidth: 1)
                )
            }

            HStack {
                Text("Safety Policy re-verifies running apps, Keep List pins, and protected paths before every file operation.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .disabled(viewModel.isExecutingCleanup)

                Button {
                    Task { await viewModel.executeStagedCleanup(mode: deletionMode) }
                } label: {
                    if viewModel.isExecutingCleanup {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(deletionMode == .moveToTrash
                             ? "Move \(viewModel.stagedTargets.count) Item(s) to Trash"
                             : "Permanently Delete \(viewModel.stagedTargets.count) Item(s)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(deletionMode == .permanentDelete ? Color(nsColor: .systemRed) : .accentColor)
                .disabled(
                    viewModel.stagedTargets.isEmpty ||
                    viewModel.isExecutingCleanup ||
                    (requiresExplicitGate && !hasAcknowledgedWarnings)
                )
            }
        }
        .padding(20)
        .frame(width: 600)
    }
}
