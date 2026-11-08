import AppKit
import SwiftUI

/// One borderless, key-capable panel for BindAll's result, preview and prompt windows: sized by its
/// SwiftUI content (and following it as it grows), placed by `PanelPlacement` next to the field.
/// Borderless, so there is no hidden title bar adding an empty band at the top.
@MainActor
final class FloatingPanelHost {
    private(set) var panel: KeyablePanel?
    private var resizeObserver: NSObjectProtocol?
    private var liveResizeObserver: NSObjectProtocol?
    private var field = CGRect.zero
    /// Stops the window following its content's size.
    private var stopFollowingContent: (() -> Void)?
    /// Handed to the content of a resizable window; see `PanelSizing`.
    private(set) var sizing = PanelSizing()

    /// `resizable`: the user may size it by hand (result and preview windows).
    func show<Content: View>(_ content: Content, title: String, near field: CGRect?, resizable: Bool = false,
                             onEscape: @escaping () -> Void) {
        close()
        let field = field ?? FocusedField.rect()
        self.field = field
        let sizing = PanelSizing()
        self.sizing = sizing
        let hosting = NSHostingController(rootView: PanelContent(content: content, sizing: sizing))
        hosting.sizingOptions = [.preferredContentSize]
        stopFollowingContent = { [weak hosting] in
            hosting?.sizingOptions = []
            // The hosting view also pins the window to its content (its min and max size); lift that
            // too, or every resize is clamped straight back.
            (hosting?.view as? NSHostingView<PanelContent<Content>>)?.sizingOptions = []
            // What actually held the size: the hosting view's own fixed width and height, ranked just
            // above the window frame's (501 vs 500), and left in place when sizing stops.
            if let view = hosting?.view {
                NSLayoutConstraint.deactivate(view.constraints.filter { c in
                    (c.firstItem as? NSView) === view && c.secondItem == nil && c.relation == .equal
                        && (c.firstAttribute == .width || c.firstAttribute == .height)
                        && c.priority.rawValue > NSLayoutConstraint.Priority.windowSizeStayPut.rawValue
                })
            }
        }
        let panel = KeyablePanel(contentViewController: hosting)
        panel.styleMask = resizable ? [.borderless, .resizable] : [.borderless]
        if resizable {
            panel.minSize = NSSize(width: 380, height: 160)
            panel.onManualResize = { [weak self] in self?.becomeManual() }
            panel.gripResize = { [weak self] phase in self?.gripResize(phase) }
            liveResizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willStartLiveResizeNotification,
                                                                        object: panel, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.becomeManual() }
            }
        }
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.title = title
        panel.onEscape = onEscape
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .moveToActiveSpace]
        self.panel = panel
        panel.layoutIfNeeded()
        panel.setFrameOrigin(PanelPlacement.origin(size: panel.frame.size, near: field, window: FocusedField.windowRect()))
        // Growing keeps the top edge where it was, so a prompt field gets taller downwards. The move
        // back on screen waits for the resize to finish: done from inside the notification, with a
        // redraw, it started another layout pass, the hosting view resized the window again, and a
        // tall window at the screen's edge recursed until the stack ran out.
        resizeObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: panel,
                                                                queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                DispatchQueue.main.async { self?.keepOnScreen() }
            }
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        // Once, after the first layout: a window shorter than its content hides its own header and
        // buttons (it can then be neither moved nor closed by mouse).
        DispatchQueue.main.async { [weak self, weak panel] in
            guard let panel, panel === self?.panel, let view = panel.contentView else { return }
            let fit = view.fittingSize
            let size = panel.contentLayoutRect.size
            if abs(fit.height - size.height) > 1 || abs(fit.width - size.width) > 1 { panel.setContentSize(fit) }
        }
    }

    /// From now on the window keeps the size it is given and the content fills it: following the
    /// content too would undo the user's sizing on the next change (showing the original).
    private func becomeManual() {
        guard !sizing.isManual else { return }
        stopFollowingContent?()
        // The hosting controller pinned the window to its content's size; lift that, or every
        // resize is clamped straight back.
        if let panel {
            panel.contentMinSize = panel.minSize
            panel.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            panel.maxSize = panel.contentMaxSize
        }
        sizing.isManual = true
    }

    private var gripStart: (mouse: NSPoint, frame: NSRect)?

    /// The corner grip: the top-left corner stays, the window follows the pointer.
    private func gripResize(_ phase: PanelSizing.ResizePhase) {
        guard let panel else { return }
        switch phase {
        case .began:
            becomeManual()
            gripStart = (NSEvent.mouseLocation, panel.frame)
        case .moved:
            guard let start = gripStart else { return }
            let now = NSEvent.mouseLocation
            let width = max(panel.minSize.width, start.frame.width + now.x - start.mouse.x)
            let height = max(panel.minSize.height, start.frame.height - (now.y - start.mouse.y))
            panel.setFrame(NSRect(x: start.frame.minX, y: start.frame.maxY - height, width: width, height: height), display: true)
        case .ended:
            gripStart = nil
        }
    }

    func close() {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
        if let liveResizeObserver { NotificationCenter.default.removeObserver(liveResizeObserver) }
        liveResizeObserver = nil
        stopFollowingContent = nil
        guard let closing = panel else { return }
        panel = nil
        closing.onEscape = nil
        closing.orderOut(nil)
        // Close is usually clicked in this very window: freeing it (and its SwiftUI hierarchy) while
        // AppKit is still delivering that click left the app stuck. It goes once the event is over.
        DispatchQueue.main.async { withExtendedLifetime(closing) {} }
    }

    private func keepOnScreen() {
        guard let panel, let screen = panel.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var frame = panel.frame
        let room = visible.height - 2 * PanelPlacement.inset
        if frame.height > room {
            // Taller than the screen: it can only fit by shrinking, and a window that follows its
            // content would grow straight back -- so it stops following it and keeps this height.
            becomeManual()
            frame.size.height = room
            frame.origin.y = visible.minY + PanelPlacement.inset
            panel.setFrame(frame, display: true)
            return
        }
        if frame.minY < visible.minY + PanelPlacement.inset {
            // No more room below: the window moves up instead of running off the screen.
            frame.origin.y = visible.minY + PanelPlacement.inset
        }
        if frame.maxY > visible.maxY - PanelPlacement.inset {
            frame.origin.y = visible.maxY - PanelPlacement.inset - frame.height
        }
        // Only the origin changes, so this cannot resize the window and set the loop going again.
        if abs(frame.origin.y - panel.frame.origin.y) > 0.5 { panel.setFrameOrigin(frame.origin) }
    }
}
