import AppKit
import SwiftUI

/// The panel's backdrop. `glass` uses AppKit's Liquid Glass (NSGlassEffectView)
/// on macOS 26+, and the classic behind-window blur everywhere else.
struct LauncherBackground: NSViewRepresentable {
    let style: Config.Style
    let cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSView {
        switch style {
        case .glass:
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                let glass = NSGlassEffectView()
                glass.cornerRadius = cornerRadius
                // Untinted glass is nearly clear; over busy content the text behind
                // fights with the results. A light window-colour tint keeps it legible.
                glass.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.55)
                return glass
            }
            #endif
            return blurView()
        case .blur:
            return blurView()
        case .solid:
            let view = NSView()
            view.wantsLayer = true
            view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            return view
        }
    }

    func updateNSView(_ view: NSView, context: Context) {
        // Layer colours don't follow appearance changes on their own.
        if style == .solid {
            view.effectiveAppearance.performAsCurrentDrawingAppearance {
                view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
            }
        }
    }

    private func blurView() -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
}
