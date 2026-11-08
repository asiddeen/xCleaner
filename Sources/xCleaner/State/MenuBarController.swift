import AppKit
import SwiftUI

@MainActor
final class MenuBarController: NSObject {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private weak var viewModel: AppViewModel?

    override init() {
        super.init()
        popover.behavior = .transient
        popover.animates = true
    }

    func configure(with viewModel: AppViewModel) {
        self.viewModel = viewModel
        updateVisibility(isVisible: viewModel.preferences.showMenuBarExtra)
    }

    func updateVisibility(isVisible: Bool) {
        if isVisible {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                if let button = item.button {
                    let image = NSImage(
                        systemSymbolName: "internaldrive.fill",
                        accessibilityDescription: "xCleaner Storage Pulse"
                    )
                    image?.isTemplate = true
                    button.image = image
                    button.target = self
                    button.action = #selector(togglePopover(_:))
                    button.toolTip = "xCleaner — Storage Pulse & Quick Cleanup"
                }
                statusItem = item
            }
        } else {
            if popover.isShown {
                popover.performClose(nil)
            }
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        if popover.isShown {
            popover.performClose(sender)
            return
        }
        guard let button = statusItem?.button, let viewModel else { return }
        let companionView = MenuBarCompanionView(
            viewModel: viewModel,
            onNavigateToMainWindow: { [weak self] section in
                self?.popover.performClose(nil)
                self?.focusOrReopenMainWindow(viewModel: viewModel, section: section)
            }
        )
        popover.contentSize = NSSize(width: 295, height: 240)
        popover.contentViewController = NSHostingController(rootView: companionView)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func focusOrReopenMainWindow(viewModel: AppViewModel, section: SidebarSection) {
        viewModel.selectedSection = section
        NSApplication.shared.activate(ignoringOtherApps: true)
        if let existingWindow = NSApplication.shared.windows.first(where: {
            $0.canBecomeMain && !$0.className.contains("NSPopover") && !$0.className.contains("NSStatusBar")
        }) {
            existingWindow.makeKeyAndOrderFront(nil)
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
        }
    }
}
