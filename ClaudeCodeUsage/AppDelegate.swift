import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        let hosting = NSHostingView(rootView: MenuBarLabelView())
        let fittingSize = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: fittingSize)
        button.addSubview(hosting)
        button.frame = hosting.frame

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit ClaudeCodeUsage", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
