import AVFoundation
import SwiftUI

/// Push to Talk: hold a key, speak, release; the words are typed where the caret is.
struct VoiceSettingsView: View {
    @Environment(AppState.self) private var appState
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var customShortcut = HotkeyConfig(keyCode: 49, modifiers: HotkeyModifiers(command: false, control: true), repeatCount: 1)

    @State private var usesRightOption = true
    @State private var translateUsesRightCommand = true
    @State private var translateShortcut = HotkeyConfig(keyCode: 49, modifiers: HotkeyModifiers(command: false, option: true, control: true), repeatCount: 1)

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                HelpToggleRow("Enable Push to Talk", "Hold the key, speak, and release: what you said is typed where the caret is, in any app. Recognition is Apple's and runs on this Mac; nothing is sent anywhere. A quick tap, or the key used together with another one, does nothing, so it keeps working as a modifier. Esc while speaking cancels.",
                              isOn: $appState.settings.pushToTalkEnabled)
                Picker("Hold", selection: $usesRightOption) {
                    Text("Right Option").tag(true)
                    Text("Custom shortcut").tag(false)
                }
                .onChange(of: usesRightOption) { _, rightOption in
                    Task { @MainActor in appState.settings.pushToTalkKey = rightOption ? .rightOption : .shortcut(customShortcut) }
                }
                if !usesRightOption {
                    LabeledContent("Shortcut") {
                        ShortcutRecorder(config: $customShortcut, others: [])
                            .onChange(of: customShortcut) { _, config in
                                Task { @MainActor in appState.settings.pushToTalkKey = .shortcut(config) }
                            }
                    }
                }
                LabeledContent("Language") {
                    LanguagePicker(title: "Language", selection: $appState.settings.pushToTalkLanguage, includeAuto: true)
                }
            } header: {
                Text("Push to Talk")
            } footer: {
                Text("Auto listens in the language of the current keyboard layout.")
            }

            Section {
                HelpToggleRow("Dictate and translate", "Hold this key to speak in one language and get the text in another, translated by Apple Translation on this Mac. It works on its own key whether or not Push to Talk above is on, and whatever \"Translate before inserting\" is set to.",
                              isOn: $appState.settings.voiceTranslateEnabled)
                Picker("Hold", selection: $translateUsesRightCommand) {
                    Text("Right Command").tag(true)
                    Text("Custom shortcut").tag(false)
                }
                .onChange(of: translateUsesRightCommand) { _, rightCommand in
                    Task { @MainActor in appState.settings.voiceTranslateKey = rightCommand ? .rightCommand : .shortcut(translateShortcut) }
                }
                if !translateUsesRightCommand {
                    LabeledContent("Shortcut") {
                        ShortcutRecorder(config: $translateShortcut, others: [])
                            .onChange(of: translateShortcut) { _, config in
                                Task { @MainActor in appState.settings.voiceTranslateKey = .shortcut(config) }
                            }
                    }
                }
                HelpToggleRow("Translate before inserting", "Speak in one language and get the text in another, translated by Apple Translation on this Mac. Applies to Push to Talk; holding Shift when you release the key flips it for one dictation.",
                              isOn: $appState.settings.pushToTalkTranslate)
                LabeledContent("Into") {
                    LanguagePicker(title: "Into", selection: $appState.settings.pushToTalkTargetLanguage, includeAuto: false,
                                   leadingOption: (tag: "same", title: "Same as Translation"))
                }
            } header: {
                Text("Translation")
            }

            Section {
                LabeledContent("Microphone") {
                    switch microphone {
                    case .authorized:
                        Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    case .notDetermined:
                        Button("Allow", action: requestMicrophone)
                    default:
                        Button("Open Privacy Settings", action: openPrivacySettings)
                    }
                }
            } header: {
                Text("Permissions")
            } footer: {
                Text("The speech model for a language is downloaded by macOS the first time it is used.")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            microphone = AVCaptureDevice.authorizationStatus(for: .audio)
            usesRightOption = appState.settings.pushToTalkKey == .rightOption
            if case .shortcut(let config) = appState.settings.pushToTalkKey { customShortcut = config }
            translateUsesRightCommand = appState.settings.voiceTranslateKey == .rightCommand
            if case .shortcut(let config) = appState.settings.voiceTranslateKey { translateShortcut = config }
        }
    }

    private func requestMicrophone() {
        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            microphone = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    private func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
