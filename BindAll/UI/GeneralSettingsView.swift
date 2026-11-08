import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var launchAtLogin = LoginItemManager.isEnabled

    /// The field star's three modes over its two settings: on and always / only with issues, or off.
    private var fieldStarMode: Binding<Int> {
        Binding(
            get: { !appState.settings.starFieldEnabled ? 2 : appState.settings.starFieldOnlyWithIssues ? 1 : 0 },
            set: { mode in
                appState.settings.starFieldEnabled = mode != 2
                if mode != 2 { appState.settings.starFieldOnlyWithIssues = mode == 1 }
            }
        )
    }

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                HelpToggleRow("BindAll enabled", "The master switch, the same one the menu bar carries. Off: the global shortcuts, autocomplete and proofreading all stand down until it is back on.",
                              isOn: $appState.settings.enabled)
                HelpToggleRow("Launch at login", "Starts BindAll when you log in, in the menu bar. macOS may ask you to approve it in System Settings > General > Login Items.",
                              isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in applyLaunchAtLogin(enabled) }
            } header: {
                HelpHeader("Startup", "Whether BindAll runs, and whether it starts with your Mac.")
            }

            Section {
                HelpToggleRow("Restore clipboard after replacing", "When replacing the selection, BindAll puts the result on the clipboard and pastes it. With this on, your previous clipboard contents are restored a moment after pasting, so the tool does not overwrite what you had copied. Off: the result stays on the clipboard.",
                              isOn: $appState.settings.restoreClipboard)
                HelpToggleRow("Preview from the star menu", "Before an action from a star replaces your text, show what will change (added words highlighted, removed ones struck through). Apply with Return, Esc to cancel. Fix all always shows the preview.",
                              isOn: $appState.settings.previewFromMenu)
                HelpToggleRow("Preview from the shortcuts", "The same preview for the global shortcuts. Off by default: the shortcuts are the quick path.",
                              isOn: $appState.settings.previewFromHotkeys)
            } header: {
                HelpHeader("Replacing text", "How a result goes back into the app it came from.")
            }

            Section {
                HelpToggleRow("Keep history", "Stores the last 50 results locally (menu bar > History, and History in the star menu) so a closed popup or overwritten paste can be recovered. Stored on this Mac only; never includes API keys.",
                              isOn: $appState.settings.historyEnabled)
                if !appState.settings.historyEnabled, !HistoryStore.shared.entries.isEmpty {
                    LabeledContent("Kept from before") {
                        Button("Clear History", role: .destructive) { HistoryStore.shared.clear() }
                    }
                }
                UsageDataRow()
            } header: {
                HelpHeader("Data", "What BindAll keeps on this Mac. Nothing here leaves it.")
            }

            Section {
                Picker(selection: fieldStarMode) {
                    Text("Always").tag(0)
                    Text("Only when there are issues").tag(1)
                    Text("Never").tag(2)
                } label: {
                    HelpHeader("Star in text fields", "A violet star in the bottom-right corner of the text field you are in, with the number of issues Proofread found; its menu opens on them, then the actions on the whole text. \"Only when there are issues\" hides it otherwise (and so whenever Proofread is off).")
                }
                HelpToggleRow("Star at a selection", "A violet star at the end of selected text, with the same actions for just the selection. While something is selected, the field's star steps aside, so there is only ever one. On text you cannot edit -- a web page, a PDF, a terminal -- it offers reading only: Show translation, Explain, Summarize and Copy.",
                              isOn: $appState.settings.starSelectionEnabled)
            } header: {
                HelpHeader("Stars", "Stars never show in password fields or very small fields. On text that cannot be edited (a terminal, a log) only the selection star shows, with the reading actions.")
            }

            AppFilterSection(title: "Star apps",
                             help: "Limit where stars show, separately from proofreading.",
                             modeLabel: "Show in",
                             mode: $appState.settings.starAppMode,
                             apps: $appState.settings.starApps)

            Section {
                Stepper("Text size: \(appState.settings.popupFontSize) pt",
                        value: $appState.settings.popupFontSize, in: 10...20)
            } header: {
                HelpHeader("Popups", "The floating popups: autocomplete suggestions and proofread fixes. Both use this text size.")
            }

            Section {
                LabeledContent("Accessibility") {
                    if appState.accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Grant Access…", action: AccessibilityPermission.openSystemSettings)
                    }
                }
                LabeledContent("Global shortcuts") {
                    if appState.hotkeysActive {
                        Label("Active", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Label("Not active", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                LabeledContent("Apple on-device model", value: appState.appleEngineStatus)
            } header: {
                HelpHeader("Status", "Live status. Accessibility is required for the global shortcuts and for pasting results back into the active app. \"Global shortcuts\" can show Not active even with Accessibility granted -- that means the permission is stale (common right after a macOS upgrade); remove BindAll from the Accessibility list in System Settings and grant it again. Apple on-device model shows whether Apple Intelligence is available for the on-device engine.")
            }

            Section {
                LabeledContent("Version", value: UpdateChecker.currentVersion)
                LabeledContent("Source code") {
                    Link("GitHub", destination: UpdateChecker.repositoryURL)
                }
                Button("Check for Updates…", action: UpdateChecker.checkForUpdates)
            } header: {
                HelpHeader("About", "Version and updates. Updates come from the GitHub releases.")
            }
        }
        .formStyle(.grouped)
        .onAppear { launchAtLogin = LoginItemManager.isEnabled }
    }

    /// The system can refuse (e.g. approval pending in System Settings), so the toggle re-reads the
    /// real state instead of trusting what was asked for.
    private func applyLaunchAtLogin(_ enabled: Bool) {
        LoginItemManager.apply(enabled)
        let actual = LoginItemManager.isEnabled
        if actual != launchAtLogin { launchAtLogin = actual }
    }
}
