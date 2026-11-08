import AppKit
import SwiftUI

/// One borderless, key-capable panel for BindAll's result, preview and prompt windows: sized by its
/// SwiftUI content (and following it as it grows), placed by `PanelPlacement` next to the field.
/// Borderless, so there is no hidden title bar adding an empty band at the top.
@MainActor
final class FloatingPanelHost {
    private(set) var panel: KeyablePanel?
    private var resizeObserver: NSObjectProtocol?
    private var field = CGRect.zero

    func show<Content: View>(_ content: Content, title: String, near field: CGRect?, onEscape: @escaping () -> Void) {
        close()
        let field = field ?? FocusedField.rect()
        self.field = field
        let hosting = NSHostingController(rootView: IntegralSizeLayout { content })
        hosting.sizingOptions = [.preferredContentSize]
        let panel = KeyablePanel(contentViewController: hosting)
        panel.styleMask = [.borderless]
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

    func close() {
        if let resizeObserver { NotificationCenter.default.removeObserver(resizeObserver) }
        resizeObserver = nil
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
