import Carbon.HIToolbox
import Foundation

/// "Check before sending": in a chat app, a plain Return with issues still underlined in the field is
/// held back once and a warning shown; Return again sends. Everything else goes through untouched.
enum PreSendPolicy {
    struct State: Equatable {
        /// Issues underlined in the focused field of a chat app, and nothing else wants Return.
        var armed = false
        /// The warning is up: the next Return sends.
        var warning = false
        /// The chat app's process; a key bound for any other app is never touched.
        var pid: pid_t = 0
    }

    enum Action: Equatable {
        case pass
        /// Hold this Return back and show the warning.
        case warn
        /// The user confirmed: let Return through, take the warning down.
        case send
        /// Tab: open the first issue instead.
        case review
        /// ⌘Return: Fix all, through the preview.
        case fixAll
        /// Esc: take the warning down, nothing is sent.
        case dismiss
        /// Any other key while the warning is up: it goes through and the warning goes away.
        case passAndDismiss
    }

    static let chatApps: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.anthropic.claudefordesktop", "ru.keepcoder.Telegram",
        "com.hnc.Discord", "com.apple.MobileSMS", "net.whatsapp.WhatsApp", "desktop.WhatsApp",
    ]

    static func action(keyCode: Int, command: Bool, shift: Bool, option: Bool, control: Bool, state: State,
                       targetPid: pid_t) -> Action {
        guard targetPid == state.pid || targetPid == 0 else { return .pass }
        let isReturn = keyCode == kVK_Return || keyCode == kVK_ANSI_KeypadEnter
        if state.warning {
            if isReturn && command && !shift && !option && !control { return .fixAll }
            if isReturn && !command && !shift && !option && !control { return .send }
            if keyCode == kVK_Tab && !command && !option && !control { return .review }
            if keyCode == kVK_Escape { return .dismiss }
            return .passAndDismiss
        }
        guard state.armed, isReturn, !command, !shift, !option, !control else { return .pass }
        return .warn
    }

    static func warningText(count: Int) -> String {
        let issues = count == 1 ? "1 issue" : "\(count) issues"
        return "\(issues) left. Return sends anyway · Tab shows them · ⌘Return fixes all"
    }
}
