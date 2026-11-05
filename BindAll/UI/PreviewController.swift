import AppKit
import SwiftUI

/// Shows `PreviewView` in a floating panel. It takes focus (Return applies, Esc closes); Apply hands
/// control back so the result can be pasted into the app it came from.
@MainActor
final class PreviewController {
    private var panel: NSPanel?

    func show(title: String, original: String, result: String, near point: NSPoint, onApply: @escaping () -> Void) {
        close()
        UsageLog.record(.preview, .shown)
        let model = PreviewModel(title: title, original: original, result: result,
                                 onApply: { [weak self] in
                                     UsageLog.record(.preview, .applied)
                                     self?.close()
                                     onApply()
                                 },
                                 onClose: { [weak self] in
                                     UsageLog.record(.preview, .dismissed, reason: "close")
                                     self?.close()
                                 })
        let hosting = NSHostingController(rootView: PreviewView(model: model))
        let panel = KeyablePanel(contentViewController: hosting)
        panel.styleMask = [.titled, .closable, .resizable, .fullSizeContentView]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.setContentSize(NSSize(width: 460, height: 280))
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        place(panel, near: point)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }

    private func place(_ panel: NSPanel, near point: NSPoint) {
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) ?? NSScreen.main else { return }
        let size = panel.frame.size
        let visible = screen.visibleFrame
        let x = min(max(point.x - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let y = min(max(point.y - size.height - 12, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }
}
