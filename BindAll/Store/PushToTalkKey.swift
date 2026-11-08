import Foundation

/// What is held for Push to Talk.
enum PushToTalkKey: Codable, Hashable {
    /// The right Option key alone (`kVK_RightOption`); the left one stays an ordinary modifier.
    case rightOption
    /// The right Command key alone (`kVK_RightCommand`): "dictate and translate" by default.
    case rightCommand
    /// A key of the user's choosing, held down (its modifiers must be held with it).
    case shortcut(HotkeyConfig)
}

extension PushToTalkKey {
    /// The keys Push to Talk watches: plain dictation on `dictate`, dictate-and-translate on
    /// `translate` (nil = that one is off). Both on one key would be ambiguous, so dictation keeps it.
    static func monitored(dictate: PushToTalkKey?, translate: PushToTalkKey?)
        -> (dictate: PushToTalkKey?, translate: PushToTalkKey?) {
        (dictate, translate == dictate && dictate != nil ? nil : translate)
    }
}
