import Observation
import SwiftUI

/// Whether the user has sized a result or preview window by hand. Until then the window follows its
/// text; after that the content fills whatever size was chosen and scrolls inside it.
@MainActor @Observable
final class PanelSizing {
    var isManual = false

    /// The corner grip's drag, as `KeyablePanel` reports it (the host reads the pointer).
    enum ResizePhase { case began, moved, ended }
}

/// A scrolling text area: as tall as its text up to `maxHeight` while the window follows its
/// content, or taking its share of the window once that was sized by hand.
struct PanelScrollSizing: ViewModifier {
    let maxHeight: CGFloat
    let isManual: Bool

    func body(content: Content) -> some View {
        if isManual {
            content.frame(maxHeight: .infinity)
        } else {
            content.frame(maxHeight: maxHeight).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The window's content: a width given by the text, or the whole window once sized by hand.
struct PanelRootSizing: ViewModifier {
    let width: CGFloat
    let isManual: Bool

    func body(content: Content) -> some View {
        if isManual {
            content.frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        } else {
            content.frame(width: width, alignment: .topLeading).fixedSize(horizontal: false, vertical: true)
        }
    }
}
