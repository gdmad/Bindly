import Foundation

/// A short user-defined shortcut that expands to a full instruction/prompt.
///
/// Example: key `w` with a layout-fix prompt so the user can write
/// `Ghbdtn rfr ltkf -- w` and have the trailing `w` resolved to the full instruction.
struct ActionKey: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var key: String
    var label: String
    var prompt: String
    /// Optional global shortcut that runs this action on the current selection directly,
    /// without typing the separator suffix. Decodes as nil from older stored settings.
    var hotkey: HotkeyConfig?
    /// Shows the result in a popup instead of replacing the text (an explanation, a summary).
    var showOnly = false

    static let defaults: [ActionKey] = [
        ActionKey(
            key: "w",
            label: "Fix keyboard layout",
            prompt: "Convert this wrong-keyboard-layout text to the intended layout (e.g. Ghbdtn -> Привет). Output only the result."
        ),
        ActionKey(
            key: "u",
            label: "UPPERCASE",
            prompt: "Convert the text to UPPERCASE. Output only the result."
        ),
        ActionKey(
            key: "l",
            label: "lowercase",
            prompt: "Convert the text to lowercase. Output only the result."
        ),
        ActionKey(
            key: "о",
            label: "Formal tone",
            prompt: "Rewrite in a formal, professional tone. Same language. Output only the result."
        ),
        ActionKey(
            key: "гг",
            label: "Polite request",
            prompt: "Rewrite the text as a short, polite, constructive request. Start with \"Привет!\" and form a complete question or request (e.g. \"когда\" -> \"Привет! Когда будет готово?\", \"пришли отчет\" -> \"Привет! Можешь прислать отчёт?\"). Same language. Output only the result."
        ),
    ]
}

extension ActionKey {
    private enum CodingKeys: String, CodingKey { case id, key, label, prompt, hotkey, showOnly }

    /// Older settings have no `showOnly`; it defaults to replacing, as before.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        key = try c.decode(String.self, forKey: .key)
        label = try c.decode(String.self, forKey: .label)
        prompt = try c.decode(String.self, forKey: .prompt)
        hotkey = try c.decodeIfPresent(HotkeyConfig.self, forKey: .hotkey)
        showOnly = try c.decodeIfPresent(Bool.self, forKey: .showOnly) ?? false
    }
}
