import AppKit
import SwiftUI

/// The floating star. A non-activating panel, so clicking it never takes focus from the text field;
/// the click opens the actions menu right at the star.
@MainActor
final class StarPanel {
    private var panel: NSPanel?
    private(set) var isVisible = false

    /// `origin` is the star's bottom-left corner in AppKit screen coordinates.
    func show(at origin: NSPoint, label: String, onClick: @escaping (NSView) -> Void) {
        let panel = self.panel ?? makePanel()
        var hostRef: NSView?
        let host = FirstMouseHostingView(rootView: StarButton(label: label) {
            if let hostRef { onClick(hostRef) }
        })
        hostRef = host
        panel.contentView = host
        // AX geometry is fractional; a panel between device pixels gets resampled and the star blurs.
        let rect = NSRect(origin: origin, size: NSSize(width: StarButton.size, height: StarButton.size))
        let screen = NSScreen.screens.first { $0.frame.contains(origin) } ?? NSScreen.main
        panel.setFrame(screen?.backingAlignedRect(rect, options: .alignAllEdgesNearest) ?? rect.integral, display: true)
        panel.orderFront(nil)
        isVisible = true
    }

    func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    private func makePanel() -> NSPanel {
        let panel = PopupPanel.make(ignoresMouseEvents: false)
        panel.title = "BindAll Star"
        self.panel = panel
        return panel
    }
}
