import AppKit
import SwiftUI
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var launchAtLoginItem: NSMenuItem?
    private var accountItems: [AccountProfile: NSMenuItem] = [:]
    private let usageMonitor = UsageMonitor()
    private var hostingView: NSHostingView<MenuBarLabelView>?
    private weak var statusButton: NSStatusBarButton?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        statusButton = button

        let hosting = NSHostingView(rootView: MenuBarLabelView(usage: usageMonitor))
        let fittingSize = hosting.fittingSize
        hosting.frame = NSRect(origin: .zero, size: fittingSize)
        button.addSubview(hosting)
        button.frame = hosting.frame
        hostingView = hosting

        usageMonitor.onChange = { [weak self] in self?.refitStatusItem() }
        usageMonitor.start()

        let menu = NSMenu()
        menu.delegate = self

        for profile in AccountProfile.allCases {
            let accountItem = NSMenuItem(
                title: profile.title,
                action: #selector(selectAccount(_:)),
                keyEquivalent: ""
            )
            accountItem.target = self
            accountItem.representedObject = profile
            menu.addItem(accountItem)
            accountItems[profile] = accountItem
        }

        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(launchAtLogin)
        launchAtLoginItem = launchAtLogin

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ClaudeCodeUsage", action: #selector(quit), keyEquivalent: "q"))
        item.menu = menu

        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        let active = AccountProfile.detectActive()
        for (profile, menuItem) in accountItems {
            menuItem.state = (profile == active) ? .on : .off
        }
    }

    @objc private func selectAccount(_ sender: NSMenuItem) {
        guard let profile = sender.representedObject as? AccountProfile else { return }
        Task { [weak self] in
            guard let self else { return }
            switch await profile.run() {
            case .success:
                self.usageMonitor.refresh()
            case .failure(let error):
                NSLog("Failed to switch to \(profile.title): \(error.message)")
                let alert = NSAlert()
                alert.messageText = "Couldn't Switch to \(profile.title)"
                alert.informativeText = error.message
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    @objc private func toggleLaunchAtLogin() {
        guard let launchAtLoginItem else { return }
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                launchAtLoginItem.state = .off
            } else {
                try SMAppService.mainApp.register()
                launchAtLoginItem.state = .on
            }
        } catch {
            NSLog("Failed to toggle launch at login: \(error.localizedDescription)")
            let alert = NSAlert()
            alert.messageText = "Couldn't Update Launch at Login"
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.runModal()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func refitStatusItem() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let hosting = self.hostingView, let button = self.statusButton else { return }
            let fittingSize = hosting.fittingSize
            hosting.frame = NSRect(origin: .zero, size: fittingSize)
            button.frame = hosting.frame
        }
    }
}
