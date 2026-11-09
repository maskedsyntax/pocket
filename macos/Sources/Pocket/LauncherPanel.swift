import AppKit
import SwiftUI

/// A borderless, non-activating panel: it takes keyboard focus without pulling
/// the frontmost app to the background, the way Spotlight does.
final class LauncherPanel: NSPanel {
    var onResignKey: (() -> Void)?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PanelMetrics.width, height: PanelMetrics.maxHeight),
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
        acceptsMouseMovedEvents = true
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
    private var flagsMonitor: Any?
    private var mouseMonitor: Any?
    /// The panel's top edge; resizing keeps it fixed so the search bar never moves.
    private var top: CGFloat?

    var isVisible: Bool { panel.isVisible }

    init(config: Config) {
        model = LauncherModel(config: config)
        model.onFinish = { [weak self] in self?.hide() }

        let host = NSHostingView(
            rootView: LauncherView(
                model: model,
                onSearchFieldReady: { [weak self] field in self?.searchField = field },
                onHeightChange: { [weak self] height in self?.resize(to: height) }
            )
        )
        // We size the window ourselves (top-anchored); left alone, the hosting view
        // would resize it around its bottom-left corner.
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        host.frame = NSRect(x: 0, y: 0, width: PanelMetrics.width, height: PanelMetrics.maxHeight)
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
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { model.appeared = true }
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
        self.top = top
        let height = model.panelHeight
        panel.setFrame(
            NSRect(x: visible.midX - PanelMetrics.width / 2, y: top - height, width: PanelMetrics.width, height: height),
            display: false)
    }

    private func resize(to height: CGFloat) {
        // Screens below the main one have negative coordinates, so test for nil, not > 0.
        guard let top, panel.frame.height != height else { return }
        var frame = panel.frame
        frame.origin.y = top - height
        frame.size.height = height
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            return self.handle(event) ? nil : event
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            self?.model.mouseActive = true
            return event
        }
        // ⌘ held on its own reveals the ⌘1–⌘9 badges.
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            self?.model.commandHeld = flags == .command
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        keyMonitor = nil
        flagsMonitor = nil
        mouseMonitor = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        if flags == .command && chars == "k" {
            model.toggleActions()
            return true
        }
        if model.showingActions {
            switch event.keyCode {
            case 53: model.showingActions = false  // esc closes the menu, not the panel
            case 125: model.moveAction(1)
            case 126: model.moveAction(-1)
            case 36, 76: model.runAction()
            default:
                // Anything else closes the menu and carries on as usual (e.g. typing).
                model.showingActions = false
                return handle(event)
            }
            return true
        }

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
            flags.contains(.command) ? model.revealSelected() : model.activate()
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
                model.activate(at: digit - 1)
                return true
            }
            // An agent app has no Edit menu, so wire up the standard text shortcuts.
            let actions: [String: Selector] = [
                "x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)),
                "v": #selector(NSText.paste(_:)), "a": #selector(NSText.selectAll(_:)),
                "z": Selector(("undo:")),
            ]
            // ⌘C with no text selected in the search field copies a calculation's answer.
            if chars == "c", searchField?.currentEditor()?.selectedRange.length ?? 0 == 0,
                model.copyAnswerIfCalculation()
            {
                return true
            }
            if let action = actions[chars] {
                NSApp.sendAction(action, to: nil, from: nil)
                return true
            }
        }
        if flags == [.command, .shift] && chars == "c" {
            model.copySecondary()
            return true
        }
        return false
    }
}
