import SwiftUI
import XCleanerCore

struct ToolchainsAndDockerView: View {
    private enum SubTab: String, CaseIterable, Identifiable {
        case toolchains = "Side-by-Side SDKs & Toolchains"
        case dockerAndSSH = "Local & Remote SSH Docker"
        var id: String { rawValue }
    }

    @Bindable var viewModel: AppViewModel
    @State private var activeTab: SubTab = .toolchains
    @State private var selectedEcosystem: ToolchainEcosystem?
    @State private var searchText: String = ""
    @State private var isShowingAddSSHSheet = false
    @State private var pruneConfirmationTarget: PruneConfirmationContext?

    private struct PruneConfirmationContext: Identifiable {
        let id = UUID()
        let title: String
        let sshTarget: SSHServerTarget?
        var pruneBuilderCache: Bool = true
        var pruneDanglingImages: Bool = true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerBar
            Divider()

            switch activeTab {
            case .toolchains:
                toolchainsContent
            case .dockerAndSSH:
                dockerAndSSHContent
            }
        }
        .navigationTitle("Toolchains & Docker")
        .sheet(isPresented: $isShowingAddSSHSheet) {
            AddSSHServerSheet(viewModel: viewModel)
        }
        .sheet(item: $pruneConfirmationTarget) { ctx in
            DockerPruneConfirmSheet(
                title: ctx.title,
                initialBuilderCache: ctx.pruneBuilderCache,
                initialDanglingImages: ctx.pruneDanglingImages
            ) { builder, images in
                Task {
                    if let remote = ctx.sshTarget {
                        await viewModel.runRemoteDockerPrune(target: remote, builderCache: builder, danglingImages: images)
                    } else {
                        await viewModel.runLocalDockerPrune(builderCache: builder, danglingImages: images)
                    }
                }
            }
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Picker("Section", selection: $activeTab) {
                ForEach(SubTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 400)

            Spacer(minLength: 8)

            if activeTab == .toolchains {
                Button {
                    Task { await viewModel.refreshToolchainsAndLocalDocker() }
                } label: {
                    Label("Refresh Versions", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .fixedSize()
                .disabled(viewModel.isScanningToolchains)
            } else {
                Button {
                    isShowingAddSSHSheet = true
                } label: {
                    Label("Add SSH Server…", systemImage: "plus.rectangle.on.folder")
                }
                .buttonStyle(.bordered)
                .fixedSize()

                Button {
                    Task {
                        await viewModel.refreshToolchainsAndLocalDocker()
                        await viewModel.probeAllSSHServers()
                    }
                } label: {
                    Label("Probe Docker & SSH", systemImage: "network")
                }
                .buttonStyle(.borderedProminent)
                .fixedSize()
                .disabled(viewModel.isProbingDockerOrSSH)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    // MARK: - Side-by-Side Toolchains Tab

    private var filteredToolchains: [ToolchainItem] {
        viewModel.toolchainItems.filter { item in
            if let eco = selectedEcosystem, item.ecosystem != eco {
                return false
            }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                return item.version.lowercased().contains(q)
                    || item.componentKind.lowercased().contains(q)
                    || item.ecosystem.rawValue.lowercased().contains(q)
                    || item.advisory.badgeTitle.lowercased().contains(q)
            }
            return true
        }
    }

    private var toolchainsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SearchFilterField(
                    placeholder: "Filter SDKs, Gradle, Node, or versions…",
                    text: $searchText
                )
                .frame(minWidth: 170, maxWidth: 270)

                Spacer(minLength: 8)

                HStack(spacing: 5) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .systemTeal))
                    Text("Default & current versions are locked against removal")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor).opacity(0.4))

            Divider()

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    let totalBytes = viewModel.toolchainItems.reduce(Int64(0)) { $0 + $1.allocatedBytes }
                    ecosystemChip(
                        title: "All Toolchains",
                        symbol: "square.stack.3d.up",
                        bytes: totalBytes,
                        selected: selectedEcosystem == nil
                    ) {
                        selectedEcosystem = nil
                    }

                    ForEach(ToolchainEcosystem.allCases) { eco in
                        let sub = viewModel.toolchainItems.filter { $0.ecosystem == eco }
                        let bytes = sub.reduce(Int64(0)) { $0 + $1.allocatedBytes }
                        ecosystemChip(
                            title: eco.rawValue,
                            symbol: eco.symbolName,
                            bytes: bytes,
                            selected: selectedEcosystem == eco
                        ) {
                            selectedEcosystem = eco
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))

            Divider()

            if viewModel.isScanningToolchains && viewModel.toolchainItems.isEmpty {
                VStack(spacing: 10) {
                    ProgressView()
                    Text("Cross-referencing Gradle wrappers, Android NDKs, Node nvm runtimes & Puppeteer builds…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filteredToolchains.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No Matching Toolchain Versions")
                        .font(.system(size: 13.5, weight: .semibold))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(ToolchainEcosystem.allCases) { eco in
                            let groupItems = filteredToolchains.filter { $0.ecosystem == eco }
                            if !groupItems.isEmpty {
                                ecosystemSection(ecosystem: eco, items: groupItems)
                            }
                        }
                    }
                    .padding(14)
                }
            }
        }
    }

    private func ecosystemChip(
        title: String,
        symbol: String,
        bytes: Int64,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
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

    private func ecosystemSection(ecosystem: ToolchainEcosystem, items: [ToolchainItem]) -> some View {
        let sum = items.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        let lockedCount = items.filter { $0.advisory.level == .protected }.count
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(ecosystem.rawValue, systemImage: ecosystem.symbolName)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(
                    lockedCount > 0
                        ? "\(items.count) item(s) (\(lockedCount) locked) • \(ByteFormatting.string(from: sum))"
                        : "\(items.count) item(s) • \(ByteFormatting.string(from: sum))"
                )
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize()
            }

            ForEach(items) { item in
                toolchainRow(item)
            }
        }
    }

    private func toolchainRow(_ item: ToolchainItem) -> some View {
        let subject = InspectorSubject.toolchain(item)
        let isSelected = viewModel.inspectorSubject == subject
        let isStaged = viewModel.isStaged(urls: item.urls)
        let isPinned = viewModel.isPinned(item.urls)
        let isLockedDefault = item.advisory.level == .protected

        return HStack(spacing: 10) {
            StageCheckboxOrLockButton(
                advisory: item.advisory,
                isStaged: isStaged
            ) {
                viewModel.toggleStage(subject: subject)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(item.version)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                        .fixedSize()

                    Text(item.componentKind)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(1)

                    AdvisoryPillView(advisory: item.advisory)

                    Spacer(minLength: 6)

                    if !isLockedDefault {
                        Button {
                            viewModel.togglePin(urls: item.urls, label: "\(item.componentKind) \(item.version)")
                        } label: {
                            Image(systemName: isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 12))
                                .foregroundStyle(isPinned ? .blue : .secondary)
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help(isPinned ? "Unpin version" : "Pin version to Keep")
                    }

                    Button {
                        viewModel.revealInFinder(item.primaryURL)
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

                Text(item.urls.map(\.path).joined(separator: " + "))
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
                        : (isLockedDefault
                            ? Color(nsColor: .systemTeal).opacity(0.28)
                            : Color(nsColor: .separatorColor).opacity(0.6)),
                    lineWidth: 1
                )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            viewModel.inspectorSubject = subject
        }
    }

    // MARK: - Local & Remote SSH Docker Tab

    private var dockerAndSSHContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                localDockerCard

                remoteSSHSection

                if let log = viewModel.dockerOperationLog, !log.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Label("Last Docker Prune Output", systemImage: "terminal")
                                .font(.system(size: 12.5, weight: .semibold))
                            Spacer()
                            Button("Dismiss") { viewModel.dockerOperationLog = nil }
                                .buttonStyle(.plain)
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                        Text(log)
                            .font(.system(size: 11.5, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.045)))
                    }
                    .xCleanerCard(padding: 12)
                }
            }
            .padding(16)
        }
    }

    private var localDockerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Local Mac Docker Desktop / Engine", systemImage: "cube.box.fill")
                    .font(.system(size: 14.5, weight: .semibold))
                Spacer()
                if let doc = viewModel.localDockerStatus {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(doc.isDaemonRunning ? Color(nsColor: .systemGreen) : Color(nsColor: .systemOrange))
                            .frame(width: 8, height: 8)
                        Text(doc.isDaemonRunning ? "Daemon Active" : "Daemon Offline")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let doc = viewModel.localDockerStatus {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("VM Disk Footprint (Docker.raw)")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                        Text(ByteFormatting.string(from: doc.vmDiskAllocatedBytes))
                            .font(.system(size: 18, weight: .bold))
                            .monospacedDigit()
                            .fixedSize()
                    }

                    Divider().frame(height: 32)

                    Text(doc.statusMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()

                    if doc.isDaemonRunning {
                        Button {
                            pruneConfirmationTarget = PruneConfirmationContext(
                                title: "Local Mac Docker",
                                sshTarget: nil
                            )
                        } label: {
                            Label("Safe Prune Local Docker…", systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                        .fixedSize()
                    }
                }

                if !doc.rows.isEmpty {
                    dockerSpaceTable(doc.rows)
                }
            } else {
                Text("Click Probe Docker & SSH to inspect local Docker footprint.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .xCleanerCard(padding: 14)
    }

    private var remoteSSHSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Remote SSH Build & Docker Servers", systemImage: "server.rack")
                        .font(.system(size: 14.5, weight: .semibold))
                    Text("Auto-discovered from ~/.ssh/config plus custom servers. Probes run non-interactively (BatchMode=yes) and never touch running containers or volumes.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if viewModel.isProbingDockerOrSSH {
                    ProgressView().controlSize(.small)
                }
            }

            if viewModel.sshTargets.isEmpty {
                HStack {
                    Text("No SSH server entries found in ~/.ssh/config.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Add SSH Server…") { isShowingAddSSHSheet = true }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .fixedSize()
                }
                .xCleanerCard(padding: 14)
            } else {
                ForEach(viewModel.sshTargets) { target in
                    remoteServerCard(target)
                }
            }
        }
    }

    private func remoteServerCard(_ target: SSHServerTarget) -> some View {
        let status = viewModel.remoteServerStatuses[target.id]
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "network")
                    .foregroundStyle(status?.isReachable == true ? Color(nsColor: .systemGreen) : .secondary)
                Text(target.displayLabel)
                    .font(.system(size: 13.5, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(target.source)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.primary.opacity(0.06)))
                    .fixedSize()

                Spacer(minLength: 6)

                if target.source == "Custom" {
                    Button {
                        viewModel.preferences.removeCustomSSHServer(id: target.id)
                        viewModel.sshTargets.removeAll { $0.id == target.id }
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove custom SSH target")
                }

                Button {
                    Task { await viewModel.probeSSHServer(target) }
                } label: {
                    Label(status == nil ? "Probe via SSH" : "Refresh", systemImage: "bolt.horizontal")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize()
                .disabled(viewModel.isProbingDockerOrSSH)

                if let status, status.isReachable, !status.dockerRows.isEmpty {
                    Button {
                        pruneConfirmationTarget = PruneConfirmationContext(
                            title: target.displayLabel,
                            sshTarget: target
                        )
                    } label: {
                        Label("Safe Remote Prune…", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(viewModel.isProbingDockerOrSSH)
                }
            }

            if let status {
                Text(status.statusMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(status.isReachable ? Color.secondary : Color(nsColor: .systemOrange))

                if let total = status.rootTotalBytes,
                   let used = status.rootUsedBytes,
                   let avail = status.rootAvailBytes,
                   total > 0 {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Remote Root Volume (/)")
                                .font(.system(size: 11.5, weight: .medium))
                            Spacer()
                            Text("\(ByteFormatting.string(from: used)) used / \(ByteFormatting.string(from: total)) • \(ByteFormatting.string(from: avail)) Free")
                                .font(.system(size: 11.5, weight: .semibold))
                                .monospacedDigit()
                        }
                        ProportionalBar(
                            fraction: Double(used) / Double(total),
                            tint: (Double(avail) / Double(total)) < 0.12 ? Color(nsColor: .systemRed) : .accentColor,
                            height: 7
                        )
                    }
                }

                if !status.dockerRows.isEmpty {
                    dockerSpaceTable(status.dockerRows)
                }
            } else {
                Text("Not probed yet — click Probe via SSH to inspect remote disk & Docker build cache.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .xCleanerCard(padding: 14)
    }

    private func dockerSpaceTable(_ rows: [DockerSpaceRow]) -> some View {
        VStack(spacing: 4) {
            HStack {
                Text("DOCKER RESOURCE").frame(width: 125, alignment: .leading)
                Text("TOTAL").frame(width: 56, alignment: .trailing)
                Text("ACTIVE").frame(width: 56, alignment: .trailing)
                Text("SIZE").frame(width: 90, alignment: .trailing)
                Text("RECLAIMABLE").frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)

            ForEach(rows) { row in
                HStack {
                    Text(row.type)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .frame(width: 125, alignment: .leading)
                    Text(row.totalCount)
                        .frame(width: 56, alignment: .trailing)
                    Text(row.activeCount)
                        .frame(width: 56, alignment: .trailing)
                    Text(row.sizeText)
                        .frame(width: 90, alignment: .trailing)
                    Text(row.reclaimableText)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(nsColor: .systemGreen))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .font(.system(size: 12))
                .monospacedDigit()
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.035)))
            }
        }
    }
}

private struct AddSSHServerSheet: View {
    @Bindable var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var alias: String = ""
    @State private var host: String = ""
    @State private var user: String = ""
    @State private var portText: String = "22"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Add Remote SSH Docker Server")
                .font(.system(size: 16, weight: .semibold))
            Text("Requires key-based SSH authentication (ssh-agent) because xCleaner connects with BatchMode=yes.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Form {
                TextField("Display Alias (optional):", text: $alias, prompt: Text("build-server"))
                TextField("Host or IP:", text: $host, prompt: Text("172.17.0.100"))
                TextField("SSH User:", text: $user, prompt: Text("ubuntu"))
                TextField("Port:", text: $portText)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Add Server") {
                    viewModel.preferences.addCustomSSHServer(
                        alias: alias,
                        host: host,
                        user: user.isEmpty ? nil : user,
                        port: Int(portText) ?? 22
                    )
                    Task { await viewModel.refreshToolchainsAndLocalDocker() }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

private struct DockerPruneConfirmSheet: View {
    let title: String
    @State var pruneBuilderCache: Bool
    @State var pruneDanglingImages: Bool
    let onConfirm: (Bool, Bool) -> Void
    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        initialBuilderCache: Bool,
        initialDanglingImages: Bool,
        onConfirm: @escaping (Bool, Bool) -> Void
    ) {
        self.title = title
        self._pruneBuilderCache = State(initialValue: initialBuilderCache)
        self._pruneDanglingImages = State(initialValue: initialDanglingImages)
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Confirm Safe Docker Prune — \(title)", systemImage: "exclamationmark.circle.fill")
                .font(.system(size: 15.5, weight: .semibold))

            Text("Running containers and named Docker volumes (databases, persistent data) are NEVER touched by xCleaner.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Toggle("Prune BuildKit Build Cache (docker builder prune -f)", isOn: $pruneBuilderCache)
                Toggle("Prune Dangling Untagged Images (docker image prune -f)", isOn: $pruneDanglingImages)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Run Safe Prune") {
                    let b = pruneBuilderCache
                    let i = pruneDanglingImages
                    dismiss()
                    onConfirm(b, i)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!pruneBuilderCache && !pruneDanglingImages)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
