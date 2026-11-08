import AVFoundation
import SwiftUI

/// Voice: Push to Talk and Dictate and translate. Their hold keys live on the Shortcuts tab, the
/// translation's target language on the Translation tab.
struct VoiceSettingsView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.showSettingsTab) private var showSettingsTab
    @State private var microphone = AVCaptureDevice.authorizationStatus(for: .audio)

    var body: some View {
        @Bindable var appState = appState
        Form {
            Section {
                HelpToggleRow("Push to Talk", "Hold the key, speak, and release: what you said is typed where the caret is, in any app. Recognition is Apple's and runs on this Mac; nothing is sent anywhere. A quick tap, or the key used together with another one, does nothing, so it keeps working as a modifier. Esc while speaking cancels.",
                              isOn: $appState.settings.pushToTalkEnabled)
                HelpToggleRow("Translate before inserting", "Push to Talk inserts the translation instead of what you said. Holding Shift when you release the key flips this for one dictation.",
                              isOn: $appState.settings.pushToTalkTranslate)
                    .disabled(!appState.settings.pushToTalkEnabled)
                HelpToggleRow("Dictate and translate", "Its own key: speak in one language and get the text in another, translated by Apple Translation on this Mac. Works whether or not Push to Talk is on.",
                              isOn: $appState.settings.voiceTranslateEnabled)
                LabeledContent("Keys (talk · translate)") {
                    HStack(spacing: 8) {
                        Text(keysSummary).foregroundStyle(.secondary)
                        Button("Change…") { showSettingsTab(.shortcuts) }
                    }
                }
            } header: {
                HelpHeader("Dictation", "Hold a key and speak; release to insert. The translation goes into the language set on the Translation tab.")
            }

            Section {
                LabeledContent("Speech") {
                    LanguagePicker(title: "Speech language", selection: $appState.settings.pushToTalkLanguage, includeAuto: true)
                }
            } header: {
                HelpHeader("Language", "The language you speak. Auto listens in the language of the current keyboard layout.")
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
                HelpHeader("Permissions", "The speech model for a language is downloaded by macOS the first time it is used.")
            }
        }
        .formStyle(.grouped)
        .onAppear { microphone = AVCaptureDevice.authorizationStatus(for: .audio) }
    }

    private var keysSummary: String {
        "\(Self.name(appState.settings.pushToTalkKey)) · \(Self.name(appState.settings.voiceTranslateKey))"
    }

    private static func name(_ key: PushToTalkKey) -> String {
        switch key {
        case .rightOption: "right ⌥"
        case .rightCommand: "right ⌘"
        case .shortcut(let config): HotkeyFormatter.string(config)
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
