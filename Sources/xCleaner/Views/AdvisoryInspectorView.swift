import SwiftUI
import XCleanerCore

struct AdvisoryInspectorView: View {
    @Bindable var viewModel: AppViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Decision Inspector", systemImage: "shield.lefthalf.filled")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button {
                    viewModel.isInspectorVisible = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide Decision Inspector (⌥⌘I)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            Divider()

            if let subject = viewModel.inspectorSubject {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        subjectHeader(subject)
                        advisoryCallout(subject.advisory)

                        if !subject.advisory.referencedByProjects.isEmpty {
                            referencedProjectsBox(subject.advisory.referencedByProjects, isLocked: subject.advisory.level == .protected)
                        }

                        metadataGrid(subject)
                        pathsList(subject.allURLs)
                        actionButtons(subject)
                    }
                    .padding(14)
                }
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "cursorarrow.click.2")
                        .font(.system(size: 24))
                        .foregroundStyle(.tertiary)
                    Text("Select Any Item to Inspect")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Review what an item does, rebuild impact, active project references, and whether to Pin to Keep or Stage for Cleanup.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 256, idealWidth: 276, maxWidth: 306)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func subjectHeader(_ subject: InspectorSubject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            AdvisoryPillView(advisory: subject.advisory)
            Text(subject.title)
                .font(.system(size: 14, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Text(ByteFormatting.string(from: subject.allocatedBytes))
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
        }
    }

    private func advisoryCallout(_ advisory: ItemAdvisory) -> some View {
        let color = AdvisoryPalette.tint(for: advisory)
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text("WHAT IS THIS?")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(advisory.whatIsThis)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            VStack(alignment: .leading, spacing: 3) {
                Text(advisory.level == .protected ? "PROTECTION RULE" : "IMPACT IF REMOVED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(color)
                Text(advisory.consequenceIfRemoved)
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(color.opacity(0.28), lineWidth: 1)
        )
    }

    private func referencedProjectsBox(_ projects: [String], isLocked: Bool) -> some View {
        let tint: Color = isLocked ? Color(nsColor: .systemTeal) : Color(nsColor: .systemRed)
        return VStack(alignment: .leading, spacing: 6) {
            Label("Referenced by Active Projects", systemImage: "link.badge.plus")
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(tint)

            Text(projects.joined(separator: ", "))
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(tint.opacity(0.1))
                )
        }
    }

    private func metadataGrid(_ subject: InspectorSubject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            metadataRow(label: "Source", value: subject.sourceLabel)
            metadataRow(label: "Files / Targets", value: "\(subject.itemCount)")
            metadataRow(label: "Last Activity", value: ByteFormatting.relativeAge(from: subject.lastModified))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.035))
        )
    }

    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11.5, weight: .medium))
                .monospacedDigit()
                .lineLimit(1)
        }
    }

    private func pathsList(_ urls: [URL]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(urls.count > 1 ? "TARGET PATHS (\(urls.count))" : "PATH")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)

            ForEach(urls.prefix(4), id: \.path) { u in
                Text(u.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.04))
                    )
            }
            if urls.count > 4 {
                Text("+ \(urls.count - 4) more path(s)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func actionButtons(_ subject: InspectorSubject) -> some View {
        let urls = subject.allURLs
        let staged = viewModel.isStaged(urls: urls)
        let pinned = viewModel.isPinned(urls)
        let adv = subject.advisory

        return VStack(alignment: .leading, spacing: 8) {
            if adv.level == .protected {
                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(AdvisoryPalette.tint(for: adv))
                    Text(
                        AdvisoryPalette.isCurrentOrDefaultLock(adv)
                            ? "Removal Disabled (Current / Default Version)"
                            : "Removal Disabled (Protected Path)"
                    )
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.05))
                )
            } else if let lockingApp = adv.lockedByAppName {
                Button {
                    viewModel.quitAppAndRefreshLocks(bundleID: subject.associatedBundleID, appName: lockingApp)
                } label: {
                    Label("Quit \(lockingApp) to Unlock", systemImage: "power")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(nsColor: .systemOrange))
            } else {
                Button {
                    viewModel.toggleStage(subject: subject)
                } label: {
                    Label(
                        staged ? "Remove from Cleanup Queue" : "Stage for Cleanup",
                        systemImage: staged ? "minus.circle.fill" : "plus.circle.fill"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(staged ? .secondary : (adv.level == .warning ? Color(nsColor: .systemRed) : .accentColor))
                .disabled(pinned)
            }

            if adv.level != .protected {
                Button {
                    viewModel.togglePin(urls: urls, label: subject.title)
                } label: {
                    Label(
                        pinned ? "Unpin from Keep List" : "Pin to Keep (Protect)",
                        systemImage: pinned ? "pin.slash" : "pin"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button {
                    viewModel.revealInFinder(subject.primaryURL)
                } label: {
                    Label("Finder", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    viewModel.copyPathToClipboard(subject.primaryURL)
                } label: {
                    Label("Copy Path", systemImage: "doc.on.doc")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}
