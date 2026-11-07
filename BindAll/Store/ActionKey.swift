import Foundation

/// A user-defined action: a named instruction, run from the star menu or its own shortcut.
struct ActionKey: Identifiable, Codable, Hashable {
    var id: UUID = UUID()
    var label: String
    var prompt: String
    /// Optional global shortcut that runs this action on the current selection directly,
    /// without typing the separator suffix. Decodes as nil from older stored settings.
    var hotkey: HotkeyConfig?
    /// Shows the result in a popup instead of replacing the text (an explanation, a summary).
    var showOnly = false

    static let defaults: [ActionKey] = [
        ActionKey(
            label: "Fix keyboard layout",
            prompt: "Convert this wrong-keyboard-layout text to the intended layout (e.g. Ghbdtn -> Привет). Output only the result."
        ),
        ActionKey(
            label: "UPPERCASE",
            prompt: "Convert the text to UPPERCASE. Output only the result."
        ),
        ActionKey(
            label: "lowercase",
            prompt: "Convert the text to lowercase. Output only the result."
        ),
        ActionKey(
            label: "Formal tone",
            prompt: "Rewrite in a formal, professional tone. Same language. Output only the result."
        ),
        ActionKey(
            label: "Polite request",
            prompt: "Rewrite the text as a short, polite, constructive request. Start with \"Привет!\" and form a complete question or request (e.g. \"когда\" -> \"Привет! Когда будет готово?\", \"пришли отчет\" -> \"Привет! Можешь прислать отчёт?\"). Same language. Output only the result."
        ),
    ]
}

extension ActionKey {
    private enum CodingKeys: String, CodingKey { case id, label, prompt, hotkey, showOnly }

    /// Older settings have no `showOnly` (it defaults to replacing) and still carry the retired
    /// suffix `key`, which is ignored.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        prompt = try c.decode(String.self, forKey: .prompt)
        hotkey = try c.decodeIfPresent(HotkeyConfig.self, forKey: .hotkey)
        showOnly = try c.decodeIfPresent(Bool.self, forKey: .showOnly) ?? false
    }
}

extension ActionKey {
    /// What menus and lists call it: the name, or the start of the instruction.
    var title: String {
        let name = label.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        let flat = prompt.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > 40 ? String(flat.prefix(39)) + "…" : (flat.isEmpty ? "Untitled" : flat)
    }

    /// A short stable token for the usage log, which never carries user text.
    var logToken: String { String(id.uuidString.prefix(8)) }
}
