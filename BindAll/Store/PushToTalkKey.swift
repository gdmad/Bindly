import Foundation

/// What is held for Push to Talk.
enum PushToTalkKey: Codable, Hashable {
    /// The right Option key alone (`kVK_RightOption`); the left one stays an ordinary modifier.
    case rightOption
    /// A key of the user's choosing, held down (its modifiers must be held with it).
    case shortcut(HotkeyConfig)
}
