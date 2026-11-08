import Foundation

/// Fixed text transforms that need no AI: done here, at once and exactly. They have no instruction
/// to edit -- a changed instruction would silently have sent the text to a model instead.
enum TextTool: String, CaseIterable, Identifiable {
    case uppercase, lowercase, keyboardLayout

    var id: Self { self }

    var title: String {
        switch self {
        case .uppercase: "UPPERCASE"
        case .lowercase: "lowercase"
        case .keyboardLayout: "Fix keyboard layout"
        }
    }

    func apply(to text: String) -> String {
        switch self {
        case .uppercase: text.uppercased()
        case .lowercase: text.lowercased()
        case .keyboardLayout: KeyboardLayoutMap.convert(text)
        }
    }

    /// The instruction the action key that did this used to carry, before it became a tool.
    var legacyPrompt: String {
        switch self {
        case .uppercase: "Convert the text to UPPERCASE. Output only the result."
        case .lowercase: "Convert the text to lowercase. Output only the result."
        case .keyboardLayout: "Convert this wrong-keyboard-layout text to the intended layout (e.g. Ghbdtn -> Привет). Output only the result."
        }
    }
}

/// Stored settings from when these were action keys: the untouched keys become the tools (their
/// shortcut moves with them); a key whose instruction was edited stays an AI action key.
enum TextToolMigration {
    static func migrate(_ keys: [ActionKey], hotkeys: [String: HotkeyConfig]) -> (keys: [ActionKey], hotkeys: [String: HotkeyConfig]) {
        var hotkeys = hotkeys
        let kept = keys.filter { key in
            guard let tool = TextTool.allCases.first(where: { $0.legacyPrompt == key.prompt }) else { return true }
            if let hotkey = key.hotkey, hotkeys[tool.rawValue] == nil { hotkeys[tool.rawValue] = hotkey }
            return false
        }
        return (kept, hotkeys)
    }
}
