import AppKit

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    // Agent app: no Dock icon or menu bar, even when run outside the .app bundle.
    app.setActivationPolicy(.accessory)
    app.run()
}
