import SwiftUI

/// Every global shortcut in one place, checked against each other.
struct ShortcutsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                recorder("Fix selection", $appState.settings.defaultActionHotkey, id: "fix")
                recorder("Translate selection", $appState.settings.translateHotkey, id: "translate")
                recorder("Translate from screen", $appState.settings.screenTranslateHotkey, id: "screen")
                recorder("Quick Translate", $appState.settings.quickTranslateHotkey, id: "quick")
            } header: {
                HelpHeader("Text and translation", "Click a field and press the keys. Press the same combo several times for a repeat trigger (shown as e.g. Cmd+C+C). The default Cmd+C also copies, so the selection is captured automatically.")
            }

            Section {
                LabeledContent("Explain selection") {
                    ShortcutRecorder(optionalConfig: $appState.settings.explainHotkey, others: others(excluding: "explain"))
                }
                LabeledContent("Summarize selection") {
                    ShortcutRecorder(optionalConfig: $appState.settings.summarizeHotkey, others: others(excluding: "summarize"))
                }
            } header: {
                HelpHeader("Reading", "For text someone else wrote: the result opens in a window and the text stays as it is. No shortcut by default; both are also in the menu bar.")
            }

            Section {
                HoldKeyPicker(title: "Push to Talk", modifierKey: .rightOption,
                              key: $appState.settings.pushToTalkKey, others: others(excluding: "ptt"))
                HoldKeyPicker(title: "Dictate and translate", modifierKey: .rightCommand,
                              key: $appState.settings.voiceTranslateKey, others: others(excluding: "voiceTranslate"))
            } header: {
                HelpHeader("Voice (hold)", "Held, not pressed: speak while the key is down. A right-side modifier alone keeps working as a modifier, since a quick tap or a combination with another key never records. Turn the voice actions on or off on the Voice tab.")
            }

            Section {
                if appState.settings.actionKeys.isEmpty {
                    Text("No action keys yet. Add them on the AI Actions tab.")
                        .foregroundStyle(.secondary)
                }
                // A key with no instruction does nothing, so it gets no shortcut either.
                ForEach(appState.settings.actionKeys.filter { !$0.prompt.isEmpty }) { key in
                    LabeledContent(key.title) {
                        ShortcutRecorder(optionalConfig: hotkeyBinding(for: key.id), others: others(excluding: key.id.uuidString))
                    }
                }
            } header: {
                HelpHeader("Action keys", "Runs that action key on the current selection directly.")
            }
        }
        .formStyle(.grouped)
    }

    private func recorder(_ title: String, _ config: Binding<HotkeyConfig>, id: String) -> some View {
        LabeledContent(title) {
            ShortcutRecorder(config: config, others: others(excluding: id))
        }
    }

    /// Every other shortcut, so no two actions share keys -- the hold keys included.
    private func others(excluding id: String) -> [HotkeyConfig] {
        ShortcutConflicts.others(excluding: id, in: appState.settings)
    }

    /// Resolves the key by id on every access: the array changes under the list (see ActionKeysSettingsView).
    private func hotkeyBinding(for id: ActionKey.ID) -> Binding<HotkeyConfig?> {
        Binding(
            get: { appState.settings.actionKeys.first { $0.id == id }?.hotkey },
            set: { value in
                if let index = appState.settings.actionKeys.firstIndex(where: { $0.id == id }) {
                    appState.settings.actionKeys[index].hotkey = value
                }
            }
        )
    }
}
