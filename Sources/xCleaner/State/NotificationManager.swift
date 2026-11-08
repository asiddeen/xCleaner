import Foundation
import Observation
import UserNotifications

enum AppBannerSeverity: Sendable, Equatable {
    case info
    case success
    case caution
    case warning

    var symbolName: String {
        switch self {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
}

struct InAppNotice: Identifiable, Sendable, Equatable {
    let id = UUID()
    let severity: AppBannerSeverity
    let title: String
    let message: String
    let createdAt = Date()
}

private enum SystemNotificationBridge {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func deliver(identifier: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}

@MainActor
@Observable
final class NotificationManager {
    var activeBanner: InAppNotice?
    private var dismissTask: Task<Void, Never>?
    private var didSendLowDiskAlertThisSession = false

    private var isRunningInsideAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension.lowercased() == "app" &&
        Bundle.main.bundleIdentifier != nil
    }

    func requestAuthorizationIfNeeded() {
        guard isRunningInsideAppBundle else { return }
        SystemNotificationBridge.requestAuthorization()
    }

    func postNotice(
        severity: AppBannerSeverity,
        title: String,
        message: String,
        sendSystemNotification: Bool = false,
        notificationsEnabled: Bool = true
    ) {
        let notice = InAppNotice(severity: severity, title: title, message: message)
        activeBanner = notice

        dismissTask?.cancel()
        let currentID = notice.id
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(7))
            if !Task.isCancelled, self.activeBanner?.id == currentID {
                self.activeBanner = nil
            }
        }

        if sendSystemNotification && notificationsEnabled && isRunningInsideAppBundle {
            SystemNotificationBridge.deliver(
                identifier: "xcleaner.\(UUID().uuidString)",
                title: title,
                body: message
            )
        }
    }

    func notifyLowDiskIfNeeded(rawAvailableBytes: Int64, thresholdGB: Int, notificationsEnabled: Bool) {
        let thresholdBytes = Int64(thresholdGB) * 1_000_000_000
        guard rawAvailableBytes > 0, rawAvailableBytes < thresholdBytes else { return }
        guard !didSendLowDiskAlertThisSession else { return }
        didSendLowDiskAlertThisSession = true

        let availStr = ByteCountFormatter.string(fromByteCount: rawAvailableBytes, countStyle: .file)
        postNotice(
            severity: .warning,
            title: "Low Disk Space (\(availStr) Free)",
            message: "Review Smart Junk or Toolchains & Docker to safely reclaim space before swap pressure slows down macOS.",
            sendSystemNotification: true,
            notificationsEnabled: notificationsEnabled
        )
    }

    func dismissBanner() {
        dismissTask?.cancel()
        activeBanner = nil
    }
}
