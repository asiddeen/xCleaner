import AppKit
import SwiftUI
import XCleanerCore

@MainActor
final class XCleanerAppDelegate: NSObject, NSApplicationDelegate {
    let viewModel = AppViewModel()
    let menuBarController = MenuBarController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        menuBarController.configure(with: viewModel)
        viewModel.onMenuBarVisibilityChanged = { [weak self] isVisible in
            self?.menuBarController.updateVisibility(isVisible: isVisible)
        }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !viewModel.preferences.showMenuBarExtra
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
        return true
    }
}

@main
struct XCleanerApp: App {
    @NSApplicationDelegateAdaptor(XCleanerAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("xCleaner") {
            MainShellView(viewModel: appDelegate.viewModel)
                .frame(minWidth: 1020, minHeight: 640)
                .task {
                    appDelegate.viewModel.performInitialLoad()
                }
        }
        .defaultSize(width: 1180, height: 730)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan Smart Junk") {
                    appDelegate.viewModel.launchSmartJunkScan()
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Refresh APFS Storage Pulse") {
                    Task { await appDelegate.viewModel.refreshVolumeMetrics() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Toggle Decision Inspector") {
                    appDelegate.viewModel.isInspectorVisible.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
    }
}
