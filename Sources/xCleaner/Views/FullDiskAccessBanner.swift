import SwiftUI
import XCleanerCore

struct FullDiskAccessBanner: View {
    let unscannedEstimateBytes: Int64?
    let hasFullDiskAccess: Bool
    let onGrantAccess: () -> Void

    var body: some View {
        if !hasFullDiskAccess || unscannedEstimateBytes != nil {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "hand.raised.shield.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemOrange))

                VStack(alignment: .leading, spacing: 3) {
                    if let gap = unscannedEstimateBytes, gap > 0 {
                        Text("macOS Privacy Guard Hid ~\(ByteFormatting.string(from: gap)) During Scan")
                            .font(.system(size: 13, weight: .semibold))
                    } else {
                        Text("Full Disk Access Optional — Unlock Complete System Data Visibility")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    Text("Without Full Disk Access, macOS TCC hides sandboxed Containers and Mail/Safari footprints (though those personal databases remain protected either way).")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Button(action: onGrantAccess) {
                    Label("Full Disk Access…", systemImage: "arrow.up.forward.app")
                        .font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered)
            }
            .xCleanerCard(padding: 12)
        }
    }
}
