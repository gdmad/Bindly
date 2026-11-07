import AppKit
import SwiftUI

/// The floating star. A non-activating panel, so clicking it never takes focus from the text field;
/// the click opens the actions menu right at the star.
@MainActor
final class StarPanel {
    private var panel: NSPanel?
    private(set) var isVisible = false
    let activity = StarActivity()
    /// Where the star's center is, so the panel can grow around it while the star works.
    private var center: NSPoint?

    /// `origin` is the star's bottom-left corner in AppKit screen coordinates.
    func show(at origin: NSPoint, label: String, onClick: @escaping (NSView) -> Void) {
        let panel = self.panel ?? makePanel()
        center = NSPoint(x: origin.x + StarButton.size / 2, y: origin.y + StarButton.size / 2)
        place()
        // Installed after the frame, so the first layout already happens at the final, aligned size.
        var hostRef: NSView?
        let host = FirstMouseHostingView(rootView: StarButton(label: label, activity: activity) {
            if let hostRef { onClick(hostRef) }
        })
        host.sizingOptions = []
        hostRef = host
        panel.contentView = host
        panel.orderFront(nil)
        isVisible = true
    }

    func setBusy(_ busy: Bool) {
        guard activity.busy != busy else { return }
        activity.busy = busy
        if isVisible { place() }
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    private func place() {
        guard let panel, let center else { return }
        let side = activity.busy ? StarButton.busySize : StarButton.size
        let rect = NSRect(x: (center.x - side / 2).rounded(), y: (center.y - side / 2).rounded(), width: side, height: side)
        // AX geometry is fractional; a panel between device pixels gets resampled and the star blurs.
        let screen = NSScreen.screens.first { $0.frame.contains(center) } ?? NSScreen.main
        panel.setFrame(screen?.backingAlignedRect(rect, options: .alignAllEdgesNearest) ?? rect.integral, display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = PopupPanel.make(ignoresMouseEvents: false)
        panel.title = "BindAll Star"
        // A window shadow around so small a shape reads as a blurry halo.
        panel.hasShadow = false
        self.panel = panel
        return panel
    }
}
