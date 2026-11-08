import Foundation

/// When and what to draw as inline ("ghost") text right after the caret, the way macOS's own inline
/// predictions do. Only at the end of a line: in the middle of one the gray text would be drawn over
/// the words that follow the caret.
enum InlineCompletion {
    /// Whether the caret sits at the end of its line (the next character is a newline, or there is none).
    static func caretAtLineEnd(in text: String, caret: Int) -> Bool {
        let ns = text as NSString
        guard caret >= 0, caret <= ns.length else { return false }
        guard caret < ns.length else { return true }
        let next = ns.character(at: caret)
        return next == 0x0A || next == 0x0D
    }

    /// The part of `word` still to be typed after `partial`, or nil when `word` does not simply
    /// continue it (a correction rather than a completion -- that one is offered in the list).
    static func suffix(of word: String, after partial: String) -> String? {
        guard word.count > partial.count,
              word.lowercased().hasPrefix(partial.lowercased()) else { return nil }
        return String(word.dropFirst(partial.count))
    }
}
