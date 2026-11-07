import Foundation

/// Built-in action keys that are plain text transforms: done here, at once and exactly, instead of
/// asking a model (which may answer in another language, or add a word).
enum LocalTransform {
    case uppercase, lowercase, keyboardLayout

    func apply(to text: String) -> String {
        switch self {
        case .uppercase: text.uppercased()
        case .lowercase: text.lowercased()
        case .keyboardLayout: KeyboardLayoutMap.convert(text)
        }
    }
}

extension ActionKey {
    /// Recognized by the built-in instruction, so a renamed key still counts and an edited one goes
    /// to the model as written.
    var localTransform: LocalTransform? {
        switch prompt {
        case ActionKey.uppercasePrompt: .uppercase
        case ActionKey.lowercasePrompt: .lowercase
        case ActionKey.keyboardLayoutPrompt: .keyboardLayout
        default: nil
        }
    }
}
