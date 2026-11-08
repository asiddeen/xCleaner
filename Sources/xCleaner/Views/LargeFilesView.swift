import SwiftUI
import XCleanerCore

struct LargeFilesView: View {
    private enum SortOrder: String, CaseIterable, Identifiable {
        case largestFirst = "Largest First"
        case oldestFirst = "Most Stale First"
        var id: String { rawValue }
    }

    @Bindable var viewModel: AppViewModel
    @State private var selectedCategory: LargeFileCategory?
    @State private var sortOrder: SortOrder = .largestFirst
    @State private var searchText: String = ""

    private var filteredFiles: [LargeFileItem] {
        let filtered = viewModel.largeFiles.filter { item in
            if let cat = selectedCategory, item.category != cat {
                return false
            }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                return item.name.lowercased().contains(q) || item.url.path.lowercased().contains(q)
            }
            return true
        }

        switch sortOrder {
        case .largestFirst:
            return filtered.sorted { $0.allocatedBytes > $1.allocatedBytes }
        case .oldestFirst:
            return filtered.sorted { ($0.stalenessDays ?? 0) > ($1.stalenessDays ?? 0) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            summaryHeaderBar
            Divider()
            filterControlBar
            Divider()
            categoryStrip
            Divider()

            if viewModel.isScanningLargeFiles && viewModel.largeFiles.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Scanning Downloads, Documents, Desktop, Movies, Caches & Workspaces for large files…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredFiles.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.badge.clock")
                        .font(.system(size: 30))
                        .foregroundStyle(.tertiary)
                    Text(viewModel.largeFiles.isEmpty ? "Scan for Forgotten Installers, Archives & Large Files" : "No Matching Large Files")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Personal files are never auto-selected — review size and staleness before staging.")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if viewModel.largeFiles.isEmpty {
                        Button("Start Large File Scan") {
                            viewModel.launchLargeFilesScan()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 7) {
                        ForEach(filteredFiles) { file in
                            largeFileRow(file)
                        }
                    }
                    .padding(14)
                }
            }
        }
        .navigationTitle("Large & Stale Files")
        .onAppear {
            if viewModel.largeFiles.isEmpty && !viewModel.isScanningLargeFiles {
                viewModel.launchLargeFilesScan()
            }
        }
    }

    private var summaryHeaderBar: some View {
        let totalBytes = filteredFiles.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        return HStack(spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(viewModel.isScanningLargeFiles && viewModel.largeFiles.isEmpty ? "Scanning…" : ByteFormatting.string(from: totalBytes))
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .fixedSize()

                Text("across \(filteredFiles.count) large file(s)")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                viewModel.launchLargeFilesScan()
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .fixedSize()
            .disabled(viewModel.isScanningLargeFiles)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var filterControlBar: some View {
        HStack(spacing: 10) {
            SearchFilterField(
                placeholder: "Filter filename or folder path…",
                text: $searchText
            )
            .frame(minWidth: 165, maxWidth: 260)

            Menu {
                ForEach([50, 100, 250, 500, 1000], id: \.self) { mb in
                    Button {
                        viewModel.preferences.largeFileThresholdMB = mb
                        viewModel.launchLargeFilesScan()
                    } label: {
                        HStack {
                            Text(mb >= 1000 ? "Over 1 GB" : "Over \(mb) MB")
                            if viewModel.preferences.largeFileThresholdMB == mb {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                let cur = viewModel.preferences.largeFileThresholdMB
                Label(cur >= 1000 ? "Min: 1 GB" : "Min: \(cur) MB", systemImage: "scalemass")
                    .font(.system(size: 12))
            }
            .fixedSize()

            Menu {
                ForEach(SortOrder.allCases) { order in
                    Button {
                        sortOrder = order
                    } label: {
                        HStack {
                            Text(order.rawValue)
                            if sortOrder == order {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                Label(sortOrder.rawValue, systemImage: "arrow.up.arrow.down")
                    .font(.system(size: 12))
            }
            .fixedSize()

            Spacer(minLength: 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                let allBytes = viewModel.largeFiles.reduce(Int64(0)) { $0 + $1.allocatedBytes }
                catChip(title: "All Types", symbol: "tray.full", bytes: allBytes, selected: selectedCategory == nil) {
                    selectedCategory = nil
                }

                ForEach(LargeFileCategory.allCases, id: \.rawValue) { cat in
                    let sub = viewModel.largeFiles.filter { $0.category == cat }
                    let sum = sub.reduce(Int64(0)) { $0 + $1.allocatedBytes }
                    catChip(title: cat.rawValue, symbol: cat.symbolName, bytes: sum, selected: selectedCategory == cat) {
                        selectedCategory = cat
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private func catChip(title: String, symbol: String, bytes: Int64, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5.5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                Text(ByteFormatting.string(from: bytes))
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(selected ? .primary : .secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1)
            )
            .fixedSize()
        }
        .buttonStyle(.plain)
    }

    private func largeFileRow(_ file: LargeFileItem) -> some View {
        let subject = InspectorSubject.largeFile(file)
        let isSelected = viewModel.inspectorSubject == subject
        let isStaged = viewModel.isStaged(urls: [file.url])
        let isPinned = viewModel.isPinned([file.url])

        return HStack(spacing: 10) {
            StageCheckboxOrLockButton(
                advisory: file.advisory,
                isStaged: isStaged
            ) {
                viewModel.toggleStage(subject: subject)
            }

            Image(systemName: file.category.symbolName)
                .font(.system(size: 14.5))
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(file.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .layoutPriority(1)

                    AdvisoryPillView(advisory: file.advisory, compact: true)

                    Text(ByteFormatting.relativeAge(from: file.lastAccessed ?? file.lastModified))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize()

                    Spacer(minLength: 6)

                    if file.advisory.level != .protected {
                        Button {
                            viewModel.togglePin(urls: [file.url], label: file.name)
                        } label: {
                            Image(systemName: isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 12))
                                .foregroundStyle(isPinned ? .blue : .secondary)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        viewModel.revealInFinder(file.url)
                    } label: {
                        Image(systemName: "folder")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)

                    Text(ByteFormatting.string(from: file.allocatedBytes))
                        .font(.system(size: 13.5, weight: .bold))
                        .monospacedDigit()
                        .fixedSize()
                        .frame(minWidth: 70, alignment: .trailing)
                }

                Text(file.url.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.11) : Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.inspectorSubject = subject
        }
    }
}
