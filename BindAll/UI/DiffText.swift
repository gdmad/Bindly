import SwiftUI

/// Renders `TextDiff` parts as one attributed string: added words on a green tint, removed ones
/// struck through in red. Colors plus strikethrough, so the change still reads without color.
enum DiffText {
    static func attributed(_ parts: [TextDiff.Part]) -> AttributedString {
        var out = AttributedString()
        for part in parts {
            switch part {
            case .same(let text):
                out += AttributedString(text)
            case .added(let text):
                var piece = AttributedString(text)
                piece.backgroundColor = .green.opacity(0.22)
                piece.underlineStyle = .single
                out += piece
            case .removed(let text):
                var piece = AttributedString(text)
                piece.foregroundColor = .red
                piece.strikethroughStyle = .single
                out += piece
            }
        }
        return out
    }
}
