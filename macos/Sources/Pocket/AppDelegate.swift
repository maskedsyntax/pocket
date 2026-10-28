import AppKit
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var controller: LauncherController?
    private var hotKey: HotKey?
    private var statusItem: NSStatusItem?
    private var hotKeyMenuItem: NSMenuItem?
    private var loginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ note: Notification) {
        applyConfig()
        if CommandLine.arguments.contains("--show") {
            controller?.show()
        }
    }

    /// Launching Pocket again while it's running (e.g. `open -a Pocket`) opens the panel.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        controller?.show()
        return false
    }

    private func applyConfig() {
        let config = Config.load()
        controller?.hide()
        controller = LauncherController(config: config)

        hotKey = nil
        hotKey = HotKey(config.hotkey) { [weak self] in self?.controller?.toggle() }
        if hotKey == nil {
            NSLog("Pocket: couldn't register hotkey '\(config.hotkey)', falling back to alt+space")
            hotKey = HotKey("alt+space") { [weak self] in self?.controller?.toggle() }
        }

        if config.menubarIcon {
            setUpStatusItem()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }
        hotKeyMenuItem?.title = "Open Pocket" + (hotKey.map { "   \($0.display)" } ?? "")
    }

    private func setUpStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "magnifyingglass.circle", accessibilityDescription: "Pocket")

        let menu = NSMenu()
        menu.delegate = self
        let open = NSMenuItem(title: "Open Pocket", action: #selector(openLauncher), keyEquivalent: "")
        hotKeyMenuItem = open
        menu.addItem(open)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Edit Config…", action: #selector(editConfig), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Reload Config", action: #selector(reloadConfig), keyEquivalent: ""))
        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginMenuItem = login
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Pocket", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        for menuItem in menu.items where menuItem.action != #selector(NSApp.terminate(_:)) {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    func menuWillOpen(_ menu: NSMenu) {
        loginMenuItem?.state = SMAppService.mainApp.status == .enabled ? .on : .off
    }

    @objc private func openLauncher() {
        controller?.show()
    }

    @objc private func reloadConfig() {
        applyConfig()
    }

    @objc private func editConfig() {
        let fm = FileManager.default
        if !fm.fileExists(atPath: Config.path.path) {
            try? fm.createDirectory(at: Config.directory, withIntermediateDirectories: true)
            try? Config.template.write(to: Config.path, atomically: true, encoding: .utf8)
        }
        // pocketrc has no extension, so ask for the default text editor explicitly.
        if let editor = NSWorkspace.shared.urlForApplication(toOpen: .plainText) {
            NSWorkspace.shared.open(
                [Config.path], withApplicationAt: editor, configuration: NSWorkspace.OpenConfiguration())
        } else {
            NSWorkspace.shared.open(Config.path)
        }
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("Pocket: launch at login failed: \(error.localizedDescription)")
        }
    }
}
