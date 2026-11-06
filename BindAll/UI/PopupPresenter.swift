import AppKit
import SwiftUI

/// Owns a popup's panel and puts a SwiftUI view in it. Both popups did this by hand, one through an
/// `AnyView` so that a single method could take two different views; being generic removes that.
///
/// The panel never becomes key: the user's text field keeps focus so the caret stays where they are
/// typing. So `orderFront` rather than `makeKey`, and no `NSApp.activate` anywhere.
final class PopupPresenter {
    private var panel: NSPanel?
    /// Autocomplete ignores mouse events entirely; the proofread popup accepts them, because its rows
    /// can be clicked.
    private let ignoresMouseEvents: Bool

    /// Names the panel (never shown on a borderless panel); lets the end-to-end test tell windows apart.
    private let name: String

    init(ignoresMouseEvents: Bool, name: String) {
        self.ignoresMouseEvents = ignoresMouseEvents
        self.name = name
    }

    /// Shows `view`, placed by `origin`, which is handed the view's fitted size.
    /// Returns where the panel went, so the caller can tell whether it landed above its anchor.
    @discardableResult
    func present<Content: View>(_ view: Content, origin: (NSSize) -> NSPoint) -> NSRect {
        let host = FirstMouseHostingView(rootView: view)
        let panel = self.panel ?? makePanel()
        panel.contentView = host
        panel.layoutIfNeeded()
        let size = host.fittingSize
        panel.setContentSize(size)
        let placed = origin(size)
        panel.setFrameOrigin(placed)
        panel.orderFront(nil) // NOT makeKey: the text field must keep focus.
        return NSRect(origin: placed, size: size)
    }

    func hide() {
        panel?.orderOut(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = PopupPanel.make(ignoresMouseEvents: ignoresMouseEvents)
        panel.title = name
        self.panel = panel
        return panel
    }
}
