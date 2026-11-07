import Foundation

/// No two actions may share keys: the built-in shortcuts, the action keys and the Push to Talk
/// hold keys when they are ordinary shortcuts. The Shortcuts tab checks every recorder against all
/// the others through this.
enum ShortcutConflicts {
    /// Every shortcut set in `settings`, with the id of what it belongs to.
    static func all(in settings: Settings) -> [(id: String, config: HotkeyConfig)] {
        var all: [(id: String, config: HotkeyConfig)] = [
            ("fix", settings.defaultActionHotkey), ("translate", settings.translateHotkey),
            ("screen", settings.screenTranslateHotkey), ("quick", settings.quickTranslateHotkey),
        ]
        if let c = settings.explainHotkey { all.append(("explain", c)) }
        if let c = settings.summarizeHotkey { all.append(("summarize", c)) }
        all += settings.commandHotkeys.sorted { $0.key < $1.key }.map { ("command:" + $0.key, $0.value) }
        if case .shortcut(let c) = settings.pushToTalkKey { all.append(("ptt", c)) }
        if case .shortcut(let c) = settings.voiceTranslateKey { all.append(("voiceTranslate", c)) }
        all += settings.actionKeys.compactMap { key in key.hotkey.map { (key.id.uuidString, $0) } }
        return all
    }

    /// The shortcuts a recorder for `id` must not repeat.
    static func others(excluding id: String, in settings: Settings) -> [HotkeyConfig] {
        all(in: settings).filter { $0.id != id }.map(\.config)
    }

    /// Same key, modifiers and number of presses: ⌘C twice and ⌘C three times are different shortcuts.
    static func isDuplicate(_ config: HotkeyConfig, among others: [HotkeyConfig]) -> Bool {
        others.contains(config)
    }
}
