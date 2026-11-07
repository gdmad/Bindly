import SwiftUI

struct ActionsSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            ShortcutsSection()

            Section {
                // A TextEditor, not a vertical TextField: the prompt is multi-paragraph text where
                // Return must insert a newline.
                TextEditor(text: deferredWrite($appState.settings.defaultPrompt))
                    .scrollContentBackground(.hidden)
                    .frame(height: 90)
                    .darkField()
                Button("Restore default prompt", action: restoreDefaultPrompt)
                    .controlSize(.small)
            } header: {
                HelpHeader("Default action", "The Fix selection shortcut and the star's Fix run this prompt on the selected text (spelling, grammar and punctuation by default).")
            }

            Section {
                HelpToggleRow("From the star menu", "Before Fix, Fix spelling, an action key or a custom prompt from a star replaces your text, show what will change (added words highlighted, removed ones struck through). Apply with Return, Esc to cancel.",
                              isOn: $appState.settings.previewFromMenu)
                HelpToggleRow("From the shortcuts", "The same preview for the global shortcuts. Off by default: the shortcuts are the quick path.",
                              isOn: $appState.settings.previewFromHotkeys)
            } header: {
                Text("Preview before replacing")
            }

            MaskAISlopSection()

            Section {
                ActionKeysSettingsView()
            } header: {
                HelpHeader("Action keys", "Named instructions for the AI. Each one is in the star menu and can get its own global shortcut (Record Shortcut in the expanded row), which runs it on the current selection.")
            }
        }
        .formStyle(.grouped)
        .clearFocusOnAppear()
    }

    private func restoreDefaultPrompt() {
        appState.settings.defaultPrompt = Settings().defaultPrompt
    }
}
