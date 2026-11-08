import AppKit
import SwiftUI

/// Hosts `CustomPromptView`. It has to take focus to be typed into, so the caller remembers where
/// the text came from before showing it.
@MainActor
final class CustomPromptController {
    private let host = FloatingPanelHost()

    func show(recent: [String], scope: String, near field: CGRect? = nil,
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
        host.show(CustomPromptView(model: model), title: "BindAll Prompt", near: field, onEscape: model.onClose)
    }

    func close() {
        host.close()
    }
}
