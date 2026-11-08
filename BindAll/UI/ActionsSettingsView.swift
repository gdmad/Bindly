import SwiftUI

/// AI Actions: the engine, the default prompt, the action keys and the clean-up of AI results.
struct ActionsSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.showSettingsTab) private var showSettingsTab

    /// Providers that can take over: a key is set, or none is needed (Ollama). Read once when the tab
    /// appears, not on every redraw: each read is a Keychain query.
    @State private var fallbackProviders: [ProviderKind] = []

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
        .task {
            fallbackProviders = ProviderKind.allCases.filter { kind in
                kind != .apple && (!kind.requiresAPIKey || !appState.apiKey(for: kind).isEmpty
                                   || appState.settings.appleFallbackProvider == kind)
            }
        }
    }

    private func restoreDefaultPrompt() {
        appState.settings.defaultPrompt = Settings().defaultPrompt
    }
}
