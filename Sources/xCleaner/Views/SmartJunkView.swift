import SwiftUI
import XCleanerCore

struct SmartJunkView: View {
    @Bindable var viewModel: AppViewModel
    @State private var selectedDomain: JunkDomain?
    @State private var searchText: String = ""
    @State private var expandedItemIDs: Set<String> = []

    private var filteredItems: [ScannableItem] {
        guard let all = viewModel.smartJunkReport?.items else { return [] }
        return all.filter { item in
            if let domain = selectedDomain, item.domain != domain {
                return false
            }
            if item.domain == .projectArtifacts,
               viewModel.preferences.minimumProjectStalenessDays > 0,
               (item.stalenessDays ?? 0) < viewModel.preferences.minimumProjectStalenessDays {
                return false
            }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                return item.title.lowercased().contains(q)
                    || item.subtitle.lowercased().contains(q)
                    || item.advisory.badgeTitle.lowercased().contains(q)
            }
            return true
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryHeaderBar
            Divider()
            filterControlBar
            Divider()
            domainFilterStrip
            Divider()

            if viewModel.isScanningSmartJunk && viewModel.smartJunkReport == nil {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning macOS caches, browser Service Workers, dev caches, monorepos & uninstalled apps…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Cancel Scan") {
                        viewModel.cancelSmartJunkScan()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredItems.isEmpty {
                emptyStateView
            } else {
                let maxBytes = max(1, filteredItems.first?.allocatedBytes ?? 1)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if let domain = selectedDomain {
                            Text(domain.summaryDescription)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .padding(.bottom, 2)
                        }

                        ForEach(filteredItems) { item in
                            scannableRow(item: item, maxBytes: maxBytes, isSubItem: false)

                            if !item.subItems.isEmpty && expandedItemIDs.contains(item.id) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(item.subItems) { sub in
                                        scannableRow(item: sub, maxBytes: max(1, item.allocatedBytes), isSubItem: true)
                                    }
                                }
                                .padding(.leading, 26)
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
        .navigationTitle("Smart Junk")
    }

    // MARK: - Top Summary & Action Bar (Never Crushes Horizontally)

    private var summaryHeaderBar: some View {
        let totalBytes = viewModel.smartJunkReport?.totalFoundBytes ?? 0
        let safeBytes = viewModel.smartJunkReport?.autoSafeBytes ?? 0

        return HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(viewModel.smartJunkReport == nil && viewModel.isScanningSmartJunk ? "Scanning…" : ByteFormatting.string(from: totalBytes))
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .fixedSize()

                if viewModel.smartJunkReport != nil {
                    Text("reclaimable")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }

                if safeBytes > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("\(ByteFormatting.string(from: safeBytes)) Safe")
                            .font(.system(size: 11.5, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(Color(nsColor: .systemGreen))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color(nsColor: .systemGreen).opacity(0.13))
                    )
                    .fixedSize()
                }
            }

            Spacer(minLength: 10)

            Button {
                viewModel.stageSafeSmartJunkOnly()
            } label: {
                Label("Stage Safe Only", systemImage: "checkmark.shield")
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .disabled(safeBytes == 0)
            .help("Stages only green Safe items (unlocked & unpinned). Caution and Warning items are never auto-selected.")

            if viewModel.isScanningSmartJunk {
                Button {
                    viewModel.cancelSmartJunkScan()
                } label: {
                    Label("Stop", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                .fixedSize()
            } else {
                Button {
                    viewModel.launchSmartJunkScan()
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .fixedSize()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Search & Project Staleness Filter Bar

    private var filterControlBar: some View {
        HStack(spacing: 10) {
            SearchFilterField(
                placeholder: "Filter caches, apps, or project paths…",
                text: $searchText
            )
            .frame(minWidth: 170, maxWidth: 270)

            if selectedDomain == nil || selectedDomain == .projectArtifacts {
                Menu {
                    ForEach([0, 30, 60, 90, 180], id: \.self) { days in
                        Button {
                            viewModel.preferences.minimumProjectStalenessDays = days
                            viewModel.launchSmartJunkScan()
                        } label: {
                            HStack {
                                Text(projectAgeMenuOptionTitle(days))
                                if viewModel.preferences.minimumProjectStalenessDays == days {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label(currentProjectAgeShortLabel, systemImage: "calendar.badge.clock")
                        .font(.system(size: 12))
                }
                .fixedSize()
                .help("Filter developer project build folders by idle age")
            }

            Spacer(minLength: 6)

            Text("\(filteredItems.count) item(s) • Caution & Warning stay unselected")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
    }

    private var currentProjectAgeShortLabel: String {
        let d = viewModel.preferences.minimumProjectStalenessDays
        return d == 0 ? "Projects: All Ages" : "Projects: >\(d)d Idle"
    }

    private func projectAgeMenuOptionTitle(_ days: Int) -> String {
        days == 0 ? "All Project Ages" : "Idle Over \(days) Days"
    }

    // MARK: - Horizontal Category Filter Chips

    private var domainFilterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                domainChip(
                    title: "All Categories",
                    symbol: "tray.full",
                    bytes: viewModel.smartJunkReport?.totalFoundBytes ?? 0,
                    isSelected: selectedDomain == nil
                ) {
                    selectedDomain = nil
                }

                ForEach(JunkDomain.allCases) { domain in
                    let domainItems = viewModel.smartJunkReport?.items(in: domain) ?? []
                    let sum = domainItems.reduce(Int64(0)) { $0 + $1.allocatedBytes }
                    domainChip(
                        title: domain.rawValue,
                        symbol: domain.symbolName,
                        bytes: sum,
                        isSelected: selectedDomain == domain
                    ) {
                        selectedDomain = domain
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private func domainChip(
        title: String,
        symbol: String,
        bytes: Int64,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5.5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: isSelected ? .semibold : .regular))
                Text(ByteFormatting.string(from: bytes))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    // MARK: - Scannable Item Row

    private func scannableRow(item: ScannableItem, maxBytes: Int64, isSubItem: Bool) -> some View {
        let subject = InspectorSubject.scannable(item)
        let isSelected = viewModel.inspectorSubject == subject
        let isStaged = viewModel.isStaged(urls: item.allTargetURLs)
        let isPinned = viewModel.isPinned(item.allTargetURLs)
        let hasSubs = !item.subItems.isEmpty
        let isExpanded = expandedItemIDs.contains(item.id)

        return HStack(alignment: .center, spacing: 10) {
            StageCheckboxOrLockButton(
                advisory: item.advisory,
                isStaged: isStaged
            ) {
                viewModel.toggleStage(subject: subject)
            }

            if hasSubs {
                Button {
                    if isExpanded {
                        expandedItemIDs.remove(item.id)
                    } else {
                        expandedItemIDs.insert(item.id)
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .font(.system(size: 13.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Expand granular sub-items (.vsix caches vs extensions & settings)")
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(item.title)
                        .font(.system(size: isSubItem ? 12.5 : 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    AdvisoryPillView(advisory: item.advisory, compact: true)

                    if let days = item.stalenessDays, days >= 30, item.domain == .projectArtifacts {
                        Text("\(days)d idle")
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.primary.opacity(0.06)))
                            .fixedSize()
                    }

                    Spacer(minLength: 6)

                    if let lockingApp = item.advisory.lockedByAppName {
                        Button("Quit \(lockingApp)") {
                            viewModel.quitAppAndRefreshLocks(
                                bundleID: item.associatedBundleID ?? item.advisory.lockedByBundleID,
                                appName: lockingApp
                            )
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .fixedSize()
                    }

                    if item.advisory.level != .protected {
                        Button {
                            viewModel.togglePin(urls: item.allTargetURLs, label: item.title)
                        } label: {
                            Image(systemName: isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 12))
                                .foregroundStyle(isPinned ? .blue : .secondary)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(isPinned ? "Unpin item" : "Pin to Keep (never clean)")
                    }

                    Button {
                        viewModel.revealInFinder(item.url)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")

                    Text(ByteFormatting.string(from: item.allocatedBytes))
                        .font(.system(size: 13.5, weight: .bold))
                        .monospacedDigit()
                        .fixedSize()
                        .frame(minWidth: 70, alignment: .trailing)
                }

                HStack(spacing: 8) {
                    Text(item.advisory.badgeTitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AdvisoryPalette.tint(for: item.advisory))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)

                    Text("•")
                        .font(.system(size: 10))
                        .foregroundStyle(.tertiary)

                    Text(item.subtitle)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    ProportionalBar(
                        fraction: Double(item.allocatedBytes) / Double(maxBytes),
                        tint: AdvisoryPalette.tint(for: item.advisory)
                    )
                    .frame(width: 76)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9.5)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(
                    isSelected
                        ? Color.accentColor.opacity(0.11)
                        : Color(nsColor: .controlBackgroundColor)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(
                    isSelected
                        ? Color.accentColor.opacity(0.6)
                        : Color(nsColor: .separatorColor).opacity(0.6),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.inspectorSubject = subject
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.seal")
                .font(.system(size: 30))
                .foregroundStyle(Color(nsColor: .systemGreen))
            Text("No Matching Items Found")
                .font(.system(size: 14, weight: .semibold))
            Text("Adjust your category/age filter or click Rescan to inspect caches and workspaces.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
