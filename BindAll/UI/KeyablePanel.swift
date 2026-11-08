import AppKit

/// A panel that can become key (so the user can type), even from an accessory (menu-bar) app.
final class KeyablePanel: NSPanel {
    /// Esc closes BindAll's windows. A borderless panel does not pass it on to SwiftUI's
    /// `onExitCommand`, so it is caught here.
    var onEscape: (() -> Void)?
    /// The user started sizing the window by hand (an edge or the corner grip).
    var onManualResize: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, let onEscape {
            onEscape()
            return
        }
        super.sendEvent(event)
    }
}
