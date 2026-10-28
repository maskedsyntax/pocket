import Carbon.HIToolbox

/// A system-wide shortcut registered through Carbon's RegisterEventHotKey.
/// Unlike an event tap this needs no Accessibility permission.
final class HotKey {
    private static var handlers: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private var ref: EventHotKeyRef?
    private let id: UInt32
    let display: String

    /// Returns nil if the spec can't be parsed or the shortcut is already taken
    /// (e.g. cmd+space while Spotlight still owns it).
    init?(_ spec: String, handler: @escaping () -> Void) {
        guard let (keyCode, modifiers, display) = HotKey.parse(spec) else { return nil }
        HotKey.installHandler()

        id = HotKey.nextID
        HotKey.nextID += 1
        self.display = display

        let hotKeyID = EventHotKeyID(signature: OSType(0x504B_5420), id: id)  // "PKT "
        let status = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return nil }
        HotKey.handlers[id] = handler
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        HotKey.handlers[id] = nil
    }

    private static func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                var hotKeyID = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
                DispatchQueue.main.async { HotKey.handlers[hotKeyID.id]?() }
                return noErr
            }, 1, &eventType, nil, nil)
    }

    static func parse(_ spec: String) -> (UInt32, UInt32, String)? {
        var modifiers: UInt32 = 0
        var symbols = ""
        var key: (code: Int, name: String)?

        for part in spec.lowercased().split(separator: "+") {
            let token = part.trimmingCharacters(in: .whitespaces)
            switch token {
            case "cmd", "command", "super", "meta":
                modifiers |= UInt32(cmdKey)
            case "alt", "opt", "option":
                modifiers |= UInt32(optionKey)
            case "ctrl", "control":
                modifiers |= UInt32(controlKey)
            case "shift":
                modifiers |= UInt32(shiftKey)
            default:
                guard key == nil, let code = keyCodes[token] else { return nil }
                key = (code, token.count == 1 ? token.uppercased() : token.capitalized)
            }
        }
        guard let key else { return nil }

        // Conventional macOS order: ⌃ ⌥ ⇧ ⌘
        if modifiers & UInt32(controlKey) != 0 { symbols += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { symbols += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { symbols += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { symbols += "⌘" }
        return (UInt32(key.code), modifiers, symbols + " " + key.name)
    }

    private static let keyCodes: [String: Int] = {
        var map: [String: Int] = [
            "space": kVK_Space, "return": kVK_Return, "enter": kVK_Return, "tab": kVK_Tab,
            "escape": kVK_Escape, "esc": kVK_Escape, "`": kVK_ANSI_Grave,
            "-": kVK_ANSI_Minus, "=": kVK_ANSI_Equal, "[": kVK_ANSI_LeftBracket,
            "]": kVK_ANSI_RightBracket, ";": kVK_ANSI_Semicolon, "'": kVK_ANSI_Quote,
            ",": kVK_ANSI_Comma, ".": kVK_ANSI_Period, "/": kVK_ANSI_Slash,
            "\\": kVK_ANSI_Backslash,
        ]
        let letters: [Int] = [
            kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F, kVK_ANSI_G,
            kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_M, kVK_ANSI_N,
            kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R, kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U,
            kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X, kVK_ANSI_Y, kVK_ANSI_Z,
        ]
        for (i, code) in letters.enumerated() {
            map[String(UnicodeScalar(UInt8(97 + i)))] = code
        }
        let digits: [Int] = [
            kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
            kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
        ]
        for (i, code) in digits.enumerated() { map[String(i)] = code }
        let functionKeys: [Int] = [
            kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6,
            kVK_F7, kVK_F8, kVK_F9, kVK_F10, kVK_F11, kVK_F12,
        ]
        for (i, code) in functionKeys.enumerated() { map["f\(i + 1)"] = code }
        return map
    }()
}
