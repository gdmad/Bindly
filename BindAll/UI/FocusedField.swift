import AppKit

/// Where the text being worked on sits on screen, for placing BindAll's windows next to it.
@MainActor
enum FocusedField {
    /// The focused element's frame in AppKit screen coordinates, or a small rect at the mouse.
    static func rect() -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        if let element = ProofreadAX.focusedElement(), let quartz = ProofreadAX.frame(of: element),
           quartz.width > 1, quartz.height > 1 {
            return UnderlineGeometry.appKitRect(fromQuartz: quartz, primaryScreenHeight: height)
        }
        let p = NSEvent.mouseLocation
        return CGRect(x: p.x - 1, y: p.y - 1, width: 2, height: 2)
    }

    /// The frontmost app's focused window, AppKit coordinates: the fallback place to center in.
    static func windowRect() -> CGRect? {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return nil }
        let app = AXUIElementCreateApplication(pid)
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let window = value, let quartz = ProofreadAX.frame(of: window as! AXUIElement) else { return nil }
        return UnderlineGeometry.appKitRect(fromQuartz: quartz, primaryScreenHeight: NSScreen.screens.first?.frame.height ?? 0)
    }
}
