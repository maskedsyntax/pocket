import AppKit

/// Settings read from ~/.config/pocket/pocketrc — the same file the Linux build uses.
/// Unknown keys are ignored, so one pocketrc can be shared between both platforms.
struct Config {
    enum Style: String {
        case glass  // Liquid Glass on macOS 26+, falls back to blur
        case blur  // classic vibrancy material
        case solid  // opaque window background
    }

    enum Appearance: String {
        case auto, dark, light
    }

    var font: String?
    var fontSize: CGFloat = 22
    var style: Style = .glass
    var appearance: Appearance = .auto
    var hotkey = "cmd+space"
    var accent: NSColor?
    var menubarIcon = true
    var maxResults = 60
    var appDirs: [String] = []

    static var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/pocket")
    }

    static var path: URL {
        directory.appendingPathComponent("pocketrc")
    }

    static func load() -> Config {
        var config = Config()
        guard let text = try? String(contentsOf: path, encoding: .utf8) else {
            return config
        }

        for line in text.split(whereSeparator: \.isNewline) {
            let line = line.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let colon = line.firstIndex(of: ":") else { continue }

            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.isEmpty { continue }

            switch key {
            case "font":
                config.font = value
            case "font-size":
                if let size = Double(value), size > 0 { config.fontSize = CGFloat(size) }
            case "style":
                if let style = Style(rawValue: value.lowercased()) { config.style = style }
            case "appearance":
                if let appearance = Appearance(rawValue: value.lowercased()) {
                    config.appearance = appearance
                }
            case "hotkey":
                config.hotkey = value
            case "accent":
                config.accent = NSColor(hex: value)
            case "menubar-icon":
                config.menubarIcon = !["false", "no", "off", "0"].contains(value.lowercased())
            case "max-results":
                if let n = Int(value), n > 0 { config.maxResults = n }
            case "app-dirs":
                config.appDirs = value.split(separator: ",").map {
                    NSString(string: $0.trimmingCharacters(in: .whitespaces)).expandingTildeInPath
                }
            default:
                break
            }
        }
        return config
    }

    /// Resolves `font` as a family name ("JetBrains Mono" / "JetBrainsMono") in the
    /// requested weight, or as an exact PostScript name ("JetBrainsMono-Bold"),
    /// falling back to the system font (SF Pro).
    func nsFont(size: CGFloat? = nil, weight: NSFont.Weight = .regular) -> NSFont {
        let size = size ?? fontSize
        guard let name = font else {
            return .systemFont(ofSize: size, weight: weight)
        }

        let wanted = name.replacingOccurrences(of: " ", with: "").lowercased()
        let family = NSFontManager.shared.availableFontFamilies.first {
            $0.replacingOccurrences(of: " ", with: "").lowercased() == wanted
        }
        if let family {
            let descriptor = NSFontDescriptor(fontAttributes: [
                .family: family,
                .traits: [NSFontDescriptor.TraitKey.weight: weight],
            ])
            if let font = NSFont(descriptor: descriptor, size: size) {
                return font
            }
        }
        if let font = NSFont(name: name, size: size) {
            return font
        }
        return .systemFont(ofSize: size, weight: weight)
    }

    var nsAppearance: NSAppearance? {
        switch appearance {
        case .auto: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }

    static let template = """
        # Pocket configuration — shared by the Linux and macOS builds.
        # Lines are `key: value`. Keys a platform does not understand are ignored.

        # --- shared ---
        # font: JetBrains Mono
        # font-size: 22

        # --- macOS ---
        # style: glass          # glass | blur | solid
        # appearance: auto      # auto | dark | light
        # hotkey: cmd+space     # e.g. alt+space, ctrl+shift+p
        # accent: #7C5CFF       # highlight colour for the selected row
        # menubar-icon: true
        # max-results: 60
        # app-dirs: ~/Dev/Apps, /Volumes/Tools/Applications

        # --- Linux ---
        # icon-theme: Papirus

        """
}

extension NSColor {
    convenience init?(hex: String) {
        var hex = hex.trimmingCharacters(in: .whitespaces)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, let value = UInt64(hex, radix: 16) else {
            return nil
        }
        let hasAlpha = hex.count == 8
        let r = CGFloat((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let g = CGFloat((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let b = CGFloat((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let a = hasAlpha ? CGFloat(value & 0xFF) / 255 : 1
        self.init(srgbRed: r, green: g, blue: b, alpha: a)
    }
}
