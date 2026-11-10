import SwiftUI

/// Everything about word autocomplete, starting with its on/off switch.
struct AutocompleteSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var learnedCount = 0
    @State private var showLearned = false

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                HelpToggleRow("Word autocomplete", "Suggests completions for the word you are typing and can predict the next word. Tab inserts the first one; Down goes into the list to pick another (arrows, then Tab or Return); Esc closes it. Until you press Down the list takes no other keys, so the arrows, Return and switching the input language work as usual and close it. Works in most apps; skipped in password fields.",
                              isOn: $appState.settings.autocompleteEnabled)
            } header: {
                HelpHeader("Autocomplete", "Completions for the word you are typing, as gray text after the caret or as a list.")
            }

            Section {
                Picker(selection: $appState.settings.autocompleteMinPrefix) {
                    ForEach(2...4, id: \.self) { Text("\($0) letters").tag($0) }
                } label: {
                    HelpHeader("Suggest after", "How many letters to type before suggestions appear. From 2 there are more of them and more miss; from 3 they are more often right.")
                }
                Stepper("Suggestions shown: \(appState.settings.autocompleteCount)",
                        value: $appState.settings.autocompleteCount, in: 1...9)
                Picker("Layout", selection: $appState.settings.autocompleteLayout) {
                    ForEach(PopupLayout.allCases, id: \.self) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
                LabeledContent("Languages") {
                    Menu(languagesLabel) {
                        Toggle("Auto-detect", isOn: $appState.settings.autocompleteLanguages.isAuto)
                        Divider()
                        ForEach(AppLanguages.list, id: \.code) { language in
                            Toggle(language.name, isOn: $appState.settings.autocompleteLanguages.contains(language.code))
                        }
                    }
                    .fixedSize()
                }
            } header: {
                HelpHeader("Suggestions", "How the list looks: how many completions it offers, how they are arranged next to the cursor, and which dictionary languages they come from (or Auto).")
            }

            Section {
                HelpToggleRow("Inline suggestion", "At the end of a line the first suggestion appears as gray text right after the caret, as with macOS's own predictions: Tab accepts it, Down opens the list. In the middle of a line, or in apps that do not report where the caret is, the list is shown instead.",
                              isOn: $appState.settings.autocompleteInline)
                HelpToggleRow("Accept with Return too", "Return takes the suggestion as well as Tab. Off: Return always goes to the app (a new line, or sending in a chat).",
                              isOn: $appState.settings.autocompleteAcceptReturn)
                HelpToggleRow("Predict next word", "After a space, suggest the most likely next word, learned from what you have typed before.",
                              isOn: $appState.settings.autocompleteNextWord)
                HelpToggleRow("Learn from what you type", "Remembers the words you use (and which follow which) to rank suggestions and power next-word prediction. Stored locally; words only.",
                              isOn: $appState.settings.autocompleteLearn)
                LabeledContent("Learned words") {
                    HStack {
                        Text(learnedCount, format: .number).foregroundStyle(.secondary)
                        Button("Manage…", action: showLearnedWords).controlSize(.small)
                    }
                }
                AdvancedDisclosure(id: "autocomplete") {
                    HelpToggleRow("Rank by context", "Ranks completions using the words before the caret (bundled Russian n-gram data plus what you have typed before), instead of a fixed order.",
                                  isOn: $appState.settings.autocompleteContextRanking)
                }
            } header: {
                HelpHeader("Behavior", "How suggestions are offered and taken, and what Bindly learns from your typing.")
            }

            AppFilterSection(title: "Apps",
                             help: "Limit where autocomplete runs. 'Only selected' shows it just in the listed apps; 'All except' disables it there.",
                             modeLabel: "Show in",
                             mode: $appState.settings.autocompleteAppMode,
                             apps: $appState.settings.autocompleteApps)
        }
        .formStyle(.grouped)
        .onAppear(perform: refreshLearnedCount)
        .sheet(isPresented: $showLearned, onDismiss: refreshLearnedCount) {
            LearnedWordsView(languages: appState.settings.autocompleteLanguages)
        }
    }

    private var languagesLabel: String {
        let codes = appState.settings.autocompleteLanguages
        if codes.isEmpty { return "Auto" }
        return codes.map { AppLanguages.name(for: $0) }.joined(separator: ", ")
    }

    private func showLearnedWords() {
        showLearned = true
    }

    private func refreshLearnedCount() {
        learnedCount = AutocompleteLearningStore.shared.wordCount
    }
}
