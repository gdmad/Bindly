import SwiftUI

/// Everything about proofreading, starting with its on/off switch and including the LanguageTool
/// connection (LanguageTool serves only this feature). There is no shortcut: checking runs on its
/// own after a pause in typing.
struct ProofreadSettingsView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                HelpToggleRow("Enable Proofread", "Checks the text field you are typing in with a LanguageTool server shortly after you pause, and underlines every issue in place. Click an underlined word to see the fixes. The public server sends text to languagetool.org; use a self-hosted server for full privacy.",
                              isOn: $appState.settings.correctEnabled)
            } header: {
                HelpHeader("Proofread", "Spelling and grammar by LanguageTool, underlined as you type.")
            }

            Section {
                HelpToggleRow("Check before sending", "In chat apps (Slack, Claude, Telegram, Discord, Messages, WhatsApp), pressing Return while issues are still underlined does not send at once: a note says how many are left. Return again sends anyway, Tab shows the first issue, Cmd+Return fixes them all with a preview, Esc goes back to the text. Shift+Return and Return in an open popup or suggestion are never held.",
                              isOn: $appState.settings.preSendCheck)
                    .disabled(!appState.settings.correctEnabled)
                LabeledContent("Language") {
                    LanguagePicker(title: "Language", selection: $appState.settings.languageToolLanguage, includeAuto: true)
                }
                AdvancedDisclosure(id: "proofread") {
                LabeledContent {
                    // Value first, arrows after it: a Stepper's own label goes to the right of the
                    // control, which reads backwards inside a right-aligned row.
                    HStack(spacing: 6) {
                        Text("\(appState.settings.proofreadMinLength) characters")
                        Stepper("Minimum length", value: $appState.settings.proofreadMinLength, in: 1...100)
                            .labelsHidden()
                    }
                } label: {
                    HelpHeader("Skip fields shorter than", "Short fields are usually search boxes, address bars and login forms: checking them would send their contents to the server for nothing. Anything shorter than this is left alone.")
                }
                }
            } header: {
                HelpHeader("Checking", "Click an underlined word to see the fixes. Return applies the first fix; Down goes into the fixes to pick another (arrows, then Return); Tab and Shift+Tab move between problem words; the eye icon skips this place; the book icon adds the word to your personal dictionary; Fix all (or Cmd+Return) applies every first fix at once, with a preview; Esc or the cross closes the popup. Until you press Down the popup takes no arrows, so moving the caret, selecting and switching the input language work as usual and close it. Skipped in password fields.\n\nThe whole field is sent one paragraph at a time, so LanguageTool sees enough context to catch grammar; unchanged paragraphs are cached and not sent again.")
            }

            Section {
                Stepper("Fixes shown per issue: \(appState.settings.proofreadMaxReplacements)",
                        value: $appState.settings.proofreadMaxReplacements, in: 1...10)
                Picker("Layout", selection: $appState.settings.proofreadLayout) {
                    ForEach(PopupLayout.allCases, id: \.self) { layout in
                        Text(layout.displayName).tag(layout)
                    }
                }
            } header: {
                HelpHeader("Fixes popup", "How many fixes the popup offers for each issue, and how they are arranged.")
            }

            PersonalDictionarySection()

            LanguageToolConnectionSection()

            AppFilterSection(title: "Apps",
                             help: "Limit where proofreading runs. 'Only selected' checks just the listed apps; 'All except' leaves them alone.",
                             modeLabel: "Check in",
                             mode: $appState.settings.proofreadAppMode,
                             apps: $appState.settings.proofreadApps)
        }
        .formStyle(.grouped)
    }
}
