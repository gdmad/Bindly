import AppKit

/// A panel that can become key (so the user can type), even from an accessory (menu-bar) app.
final class KeyablePanel: NSPanel {
    /// Esc closes BindAll's windows. A borderless panel does not pass it on to SwiftUI's
    /// `onExitCommand`, so it is caught here.
    var onEscape: (() -> Void)?
    /// The user started sizing the window by hand (an edge or the corner grip).
    var onManualResize: (() -> Void)?
    /// The corner grip's drag. Taken here, before SwiftUI: a gesture on the grip did not see the drag.
    var gripResize: ((PanelSizing.ResizePhase) -> Void)?
    private var gripping = false
    /// The bottom-right square that sizes the window (`ResizeGrip` draws it).
    static let gripSize: CGFloat = 18

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func sendEvent(_ event: NSEvent) {
        if let gripResize {
            switch event.type {
            case .leftMouseDown where event.locationInWindow.x >= frame.width - Self.gripSize && event.locationInWindow.y <= Self.gripSize:
                gripping = true
                gripResize(.began)
                return
            case .leftMouseDragged where gripping:
                gripResize(.moved)
                return
            case .leftMouseUp where gripping:
                gripping = false
                gripResize(.ended)
                return
            default:
                break
            }
        }
        if event.type == .keyDown, event.keyCode == 53, let onEscape {
            onEscape()
            return
        }
        super.sendEvent(event)
    }
}
