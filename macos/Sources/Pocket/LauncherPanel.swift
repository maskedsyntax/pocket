import AppKit
import SwiftUI

/// A borderless, non-activating panel: it takes keyboard focus without pulling
/// the frontmost app to the background, the way Spotlight does.
final class LauncherPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: PanelMetrics.height),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}

@MainActor
final class LauncherController {
    let model: LauncherModel
    private let panel = LauncherPanel()
    private weak var searchField: NSTextField?
    private var keyMonitor: Any?

    var isVisible: Bool { panel.isVisible }

    init(config: Config) {
        model = LauncherModel(config: config)
        model.onFinish = { [weak self] in self?.hide() }

        let host = NSHostingView(
            rootView: LauncherView(model: model) { [weak self] field in
                self?.searchField = field
            }
        )
        host.frame = NSRect(x: 0, y: 0, width: PanelMetrics.width, height: PanelMetrics.height)
        panel.contentView = host
        panel.appearance = config.nsAppearance
        panel.onResignKey = { [weak self] in self?.hide() }
    }

    func toggle() {
        isVisible ? hide() : show()
    }

    func show() {
        model.reset()
        model.reload()
        position()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        if let searchField { panel.makeFirstResponder(searchField) }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            panel.animator().alphaValue = 1
        }
        panel.invalidateShadow()
        installKeyMonitor()
    }

    func hide() {
        guard panel.isVisible else { return }
        removeKeyMonitor()
        panel.orderOut(nil)
    }

    /// Centre horizontally, upper third vertically, on the screen with the cursor.
    private func position() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let top = visible.maxY - visible.height * 0.18
        panel.setFrameOrigin(NSPoint(x: visible.midX - PanelMetrics.width / 2, y: top - PanelMetrics.height))
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch event.keyCode {
        case 53:  // esc
            hide()
            return true
        case 125:  // down
            model.move(1)
            return true
        case 126:  // up
            model.move(-1)
            return true
        case 36, 76:  // return, keypad enter
            flags.contains(.command) ? model.revealSelected() : model.launch()
            return true
        default:
            break
        }

        if flags == .control {
            switch chars {
            case "n", "j": model.move(1); return true
            case "p", "k": model.move(-1); return true
            default: break
            }
        }

        if flags == .command {
            if let digit = Int(chars), (1...9).contains(digit) {
                model.launch(at: digit - 1)
                return true
            }
            // An agent app has no Edit menu, so wire up the standard text shortcuts.
            let actions: [String: Selector] = [
                "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
                "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
                "z": Selector(("undo:")),
            ]
            if let action = actions[chars] {
                NSApp.sendAction(action, to: nil, from: nil)
                return true
            }
        }
        return false
    }
}
