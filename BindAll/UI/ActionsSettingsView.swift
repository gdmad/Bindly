import SwiftUI

/// AI Actions: the engine, the default prompt, the action keys and the clean-up of AI results.
struct ActionsSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.showSettingsTab) private var showSettingsTab

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                Picker("Engine for text actions", selection: $appState.settings.defaultEngine) {
                    ForEach(ProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                Button("Configure providers…") { showSettingsTab(.providers) }
            } header: {
                HelpHeader("Engine", "Runs Fix, the action keys, Explain, Summarize and custom prompts. Translation always runs on-device via Apple's Translation framework, and proofreading always uses LanguageTool.")
            }

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

            MaskAISlopSection()

            Section {
                ActionKeysSettingsView()
            } header: {
                HelpHeader("Action keys", "Named instructions for the AI, in the star menu under Actions; a global shortcut for each is set on the Shortcuts tab. UPPERCASE, lowercase and Fix keyboard layout are not here: they work without AI and cannot be changed (star menu > Text tools).")
            }
        }
        .formStyle(.grouped)
        .clearFocusOnAppear()
    }

    private func restoreDefaultPrompt() {
        appState.settings.defaultPrompt = Settings().defaultPrompt
    }
}
