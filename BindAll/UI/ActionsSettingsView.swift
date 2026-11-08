import SwiftUI

/// AI Actions: the engine, the default prompt, the action keys and the clean-up of AI results.
struct ActionsSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.showSettingsTab) private var showSettingsTab

    /// Providers that can take over: a key is set, or none is needed (Ollama).
    private var fallbackProviders: [ProviderKind] {
        ProviderKind.allCases.filter { $0 != .apple && (!$0.requiresAPIKey || !appState.apiKey(for: $0).isEmpty) }
    }

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                Picker("Engine for text actions", selection: $appState.settings.defaultEngine) {
                    ForEach(ProviderKind.allCases) { kind in
                        Text(kind.displayName).tag(kind)
                    }
                }
                if appState.settings.defaultEngine == .apple {
                    Picker("If the Apple model cannot do it", selection: $appState.settings.appleFallbackProvider) {
                        Text("Show the error").tag(ProviderKind?.none)
                        ForEach(fallbackProviders) { kind in
                            Text(kind.displayName).tag(ProviderKind?.some(kind))
                        }
                    }
                }
                Button("Configure providers…") { showSettingsTab(.providers) }
            } header: {
                HelpHeader("Engine", "Runs Fix, the action keys, Explain, Summarize and custom prompts. Translation always runs on-device via Apple's Translation framework, and proofreading always uses LanguageTool.\n\nThe Apple model officially covers fewer languages than it handles in practice (Russian works). When it refuses, fails, or answers Fix, Explain or Summarize in another language than the text, the action can be run again by a provider you have set up -- the text is then sent to that provider. Off by default.")
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
