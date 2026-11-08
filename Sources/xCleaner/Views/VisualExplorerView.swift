import AppKit
import SwiftUI
import XCleanerCore

struct VisualExplorerView: View {
    @Bindable var viewModel: AppViewModel

    private var selectedNodeID: String? {
        if case .diskNode(let n) = viewModel.inspectorSubject {
            return n.id
        }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            explorerToolbar
            Divider()

            if !viewModel.explorerNavigationStack.isEmpty {
                breadcrumbBar
                Divider()
            }

            if viewModel.isScanningExplorer && viewModel.currentExplorerNode == nil {
                scanningPlaceholder
            } else if let currentNode = viewModel.currentExplorerNode {
                HSplitView {
                    rankedSizeBarList(parent: currentNode)
                        .frame(minWidth: 235, idealWidth: 320)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Squarified Treemap", systemImage: "square.grid.3x2")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Click to inspect • Double-click folder to drill down")
                                .font(.system(size: 11))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                        TreemapCanvasView(
                            nodes: currentNode.children,
                            selectedNodeID: selectedNodeID,
                            onSelectNode: { node in
                                viewModel.inspectorSubject = .diskNode(node)
                            },
                            onDrillDownNode: { node in
                                viewModel.drillIntoExplorerNode(node)
                            }
                        )
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
                        )
                    }
                    .padding(12)
                    .frame(minWidth: 240, maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                initialPromptView
            }
        }
        .navigationTitle("Visual Explorer")
    }

    private var explorerToolbar: some View {
        let home = viewModel.safetyPolicy.homeDirectory
        return HStack(spacing: 8) {
            Menu {
                Button("Home Directory (~)") {
                    viewModel.launchExplorerScan(at: home)
                }
                Button("~/Library (Caches & App Support)") {
                    viewModel.launchExplorerScan(at: home.appendingPathComponent("Library"))
                }
                ForEach(viewModel.preferences.projectRootURLs, id: \.path) { projRoot in
                    Button(projRoot.path) {
                        viewModel.launchExplorerScan(at: projRoot)
                    }
                }
                Button("~/Downloads") {
                    viewModel.launchExplorerScan(at: home.appendingPathComponent("Downloads"))
                }
            } label: {
                Label("Quick Locations", systemImage: "folder.badge.gearshape")
            }
            .fixedSize()

            Button {
                chooseFolderWithPanel()
            } label: {
                Label("Choose Folder…", systemImage: "folder.badge.plus")
            }
            .buttonStyle(.bordered)
            .fixedSize()

            Spacer()

            if viewModel.isScanningExplorer {
                if let prog = viewModel.explorerProgress {
                    Text("\(prog.scannedFiles) files • \(ByteFormatting.string(from: prog.scannedBytes))")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView().controlSize(.small)
                Button("Stop") { viewModel.cancelExplorerScan() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            } else if let current = viewModel.currentExplorerNode {
                Button {
                    viewModel.launchExplorerScan(at: current.url)
                } label: {
                    Label("Rescan Folder", systemImage: "arrow.clockwise")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                if viewModel.explorerNavigationStack.count > 1 {
                    Button {
                        viewModel.navigateExplorerToBreadcrumb(index: viewModel.explorerNavigationStack.count - 2)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(5)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }

                ForEach(Array(viewModel.explorerNavigationStack.enumerated()), id: \.element.id) { idx, node in
                    if idx > 0 {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    let isLast = idx == viewModel.explorerNavigationStack.count - 1
                    Button {
                        viewModel.navigateExplorerToBreadcrumb(index: idx)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 11))
                            Text(node.name)
                                .font(.system(size: 12, weight: isLast ? .semibold : .regular))
                            if isLast {
                                Text("(\(ByteFormatting.string(from: node.allocatedBytes)))")
                                    .font(.system(size: 11, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(isLast ? Color.accentColor.opacity(0.15) : Color.clear)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private func rankedSizeBarList(parent: DiskNode) -> some View {
        let maxChildBytes = max(1, parent.children.first?.allocatedBytes ?? 1)
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 5) {
                ForEach(parent.children) { child in
                    let isSelected = selectedNodeID == child.id
                    let isStaged = viewModel.isStaged(urls: [child.url])

                    HStack(spacing: 9) {
                        Image(systemName: child.isDirectory ? "folder.fill" : "doc.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(child.isDirectory ? Color.accentColor : .secondary)

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Text(child.name)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .lineLimit(1)
                                AdvisoryPillView(advisory: child.advisory, compact: true)
                                Spacer()
                                if isStaged {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Color.accentColor)
                                }
                                Text(ByteFormatting.string(from: child.allocatedBytes))
                                    .font(.system(size: 12.5, weight: .bold))
                                    .monospacedDigit()
                            }

                            ProportionalBar(
                                fraction: Double(child.allocatedBytes) / Double(maxChildBytes),
                                tint: AdvisoryPalette.tint(for: child.advisory),
                                height: 4.5
                            )
                        }

                        if child.isDirectory {
                            Button {
                                viewModel.drillIntoExplorerNode(child)
                            } label: {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .padding(4)
                            }
                            .buttonStyle(.plain)
                            .help("Drill into folder")
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.14) : Color(nsColor: .controlBackgroundColor))
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.inspectorSubject = .diskNode(child)
                    }
                }
            }
            .padding(10)
        }
    }

    private var scanningPlaceholder: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Mapping APFS physical allocations…")
                .font(.system(size: 13.5, weight: .semibold))
            if let prog = viewModel.explorerProgress {
                Text("\(prog.scannedFiles) files (\(ByteFormatting.string(from: prog.scannedBytes)))")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                Text(prog.currentPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 480)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var initialPromptView: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.grid.3x2")
                .font(.system(size: 34))
                .foregroundStyle(Color.accentColor)
            Text("Interactive Folder Size Bars & Treemap")
                .font(.system(size: 15, weight: .semibold))
            Text("Replaces ncdu and du -sh * with instant drill-down, symlink cycle protection, and inline safety advisories.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 10) {
                Button("Scan Home Directory (~)") {
                    viewModel.launchExplorerScan(at: viewModel.safetyPolicy.homeDirectory)
                }
                .buttonStyle(.borderedProminent)

                Button("Choose Specific Folder…") {
                    chooseFolderWithPanel()
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func chooseFolderWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Scan Folder"
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.launchExplorerScan(at: url)
        }
    }
}
