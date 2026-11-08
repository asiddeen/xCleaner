import SwiftUI
import XCleanerCore

enum AdvisoryPalette {
    static func isCurrentOrDefaultLock(_ advisory: ItemAdvisory) -> Bool {
        guard advisory.level == .protected else { return false }
        let lower = advisory.badgeTitle.lowercased()
        return lower.contains("current") || lower.contains("default") || lower.contains("locked")
    }

    static func tint(for advisory: ItemAdvisory) -> Color {
        if advisory.isPinnedByUser {
            return Color(nsColor: .systemBlue)
        }
        if advisory.isLockedByRunningApp {
            return Color(nsColor: .systemOrange)
        }
        if isCurrentOrDefaultLock(advisory) {
            return Color(nsColor: .systemTeal)
        }
        return tint(for: advisory.level)
    }

    static func tint(for level: AdvisoryLevel) -> Color {
        switch level {
        case .safe:
            return Color(nsColor: .systemGreen)
        case .caution:
            return Color(nsColor: .systemOrange)
        case .warning:
            return Color(nsColor: .systemRed)
        case .protected:
            return .secondary
        }
    }

    static func symbol(for advisory: ItemAdvisory) -> String {
        if advisory.isPinnedByUser {
            return "pin.fill"
        }
        if advisory.isLockedByRunningApp {
            return "app.badge.checkmark"
        }
        if isCurrentOrDefaultLock(advisory) {
            return "lock.fill"
        }
        return advisory.level.symbolName
    }
}

struct AdvisoryPillView: View {
    let advisory: ItemAdvisory
    var compact: Bool = false

    var body: some View {
        let color = AdvisoryPalette.tint(for: advisory)
        HStack(spacing: 4) {
            Image(systemName: AdvisoryPalette.symbol(for: advisory))
                .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
            Text(displayLabel)
                .font(.system(size: compact ? 10.5 : 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .foregroundStyle(color)
        .padding(.horizontal, compact ? 6.5 : 8)
        .padding(.vertical, compact ? 2 : 3)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(color.opacity(0.13))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(color.opacity(0.28), lineWidth: 0.75)
        )
        .fixedSize(horizontal: compact, vertical: true)
    }

    private var displayLabel: String {
        if advisory.isPinnedByUser {
            return compact ? "Pinned" : "Pinned to Keep"
        }
        if let app = advisory.lockedByAppName {
            return compact ? "\(app) Open" : "\(app) Running"
        }
        if compact {
            if AdvisoryPalette.isCurrentOrDefaultLock(advisory) {
                return "Current • Locked"
            }
            return advisory.level.displayName
        }
        return advisory.badgeTitle
    }
}

struct StageCheckboxOrLockButton: View {
    let advisory: ItemAdvisory
    let isStaged: Bool
    let onToggle: () -> Void

    var body: some View {
        Group {
            if advisory.level == .protected {
                Image(systemName: "lock.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(
                        AdvisoryPalette.isCurrentOrDefaultLock(advisory)
                            ? Color(nsColor: .systemTeal)
                            : Color.secondary.opacity(0.65)
                    )
                    .help("Removal disabled: \(advisory.badgeTitle)")
            } else if advisory.isPinnedByUser && !isStaged {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color(nsColor: .systemBlue))
                    .help("Pinned to Keep — unpin first if you want to stage this item")
            } else if let app = advisory.lockedByAppName, !isStaged {
                Image(systemName: "app.badge")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color(nsColor: .systemOrange))
                    .help("\(app) is currently open — quit \(app) before staging")
            } else {
                Button(action: onToggle) {
                    Image(systemName: isStaged ? "checkmark.square.fill" : "square")
                        .font(.system(size: 15.5, weight: .medium))
                        .foregroundStyle(isStaged ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(isStaged ? "Remove from Cleanup Queue" : "Stage for Cleanup")
            }
        }
        .frame(width: 20, height: 20)
    }
}

struct SearchFilterField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12))

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear filter")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor).opacity(0.75))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.85), lineWidth: 1)
        )
    }
}

struct ProportionalBar: View {
    let fraction: Double
    let tint: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.07))
                Capsule()
                    .fill(tint.gradient)
                    .frame(width: max(3, geo.size.width * min(1, max(0, fraction))))
            }
        }
        .frame(height: height)
    }
}

struct XCleanerCardModifier: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
            )
    }
}

extension View {
    func xCleanerCard(padding: CGFloat = 14) -> some View {
        modifier(XCleanerCardModifier(padding: padding))
    }
}
