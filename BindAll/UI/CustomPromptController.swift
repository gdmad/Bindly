import AppKit
import SwiftUI

/// Hosts `CustomPromptView`. It has to take focus to be typed into, so the caller remembers where
/// the text came from before showing it.
@MainActor
final class CustomPromptController {
    private var panel: NSPanel?

    func show(recent: [String], scope: String, near point: NSPoint,
              onRun: @escaping (_ prompt: String, _ showOnly: Bool, _ save: Bool) -> Void) {
        close()
        let model = CustomPromptModel(recent: recent, scope: scope,
                                      onRun: { [weak self] prompt, showOnly, save in
                                          self?.close()
                                          onRun(prompt, showOnly, save)
                                      },
                                      onClose: { [weak self] in
                                          UsageLog.record(.customPrompt, .dismissed, reason: "close")
                                          self?.close()
                                      })
        let hosting = NSHostingController(rootView: CustomPromptView(model: model))
        let panel = KeyablePanel(contentViewController: hosting)
        panel.styleMask = [.titled, .closable, .fullSizeContentView]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: point.x - size.width / 2, y: point.y - size.height - 12))
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
