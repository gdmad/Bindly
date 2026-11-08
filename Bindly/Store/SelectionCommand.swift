import Foundation

/// Star actions that also run on the selection from the menu bar or their own shortcut, so they do
/// not depend on a star (stars can be off, or an app can hide its text from them).
enum SelectionCommand: String, CaseIterable, Identifiable {
    case customPrompt, spelling, removeTells, translateInPlace

    var id: Self { self }

    var title: String {
        switch self {
        case .customPrompt: "Custom prompt…"
        case .spelling: "Fix spelling (LanguageTool)"
        case .removeTells: "Remove AI tells"
        case .translateInPlace: "Replace with translation"
        }
    }

    /// Its key in `Settings.commandHotkeys` and in the shortcut conflict check.
    var settingsKey: String { rawValue }
}
