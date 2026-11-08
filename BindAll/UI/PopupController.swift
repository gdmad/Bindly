import AppKit
import SwiftUI

/// Shows a floating panel next to the field with result text, an optional original-text section,
/// a Copy button and a Close button. The panel can become key so Esc and text selection work.
/// It stays until Esc or Close: a click elsewhere used to close it, which lost the translation the
/// moment the user switched apps to paste it.
@MainActor
final class PopupController {
    private let host = FloatingPanelHost()
    private let copyShortcut = CopyShortcutMonitor()

    /// `field`: the text this is about (AppKit screen rect); the focused field when nil.
    func show(title: String, text: String, original: String? = nil, sourceLanguage: String? = nil,
              targetLanguage: String? = nil, near field: CGRect? = nil, onReplace: (() -> Void)? = nil) {
        close()
        let field = field ?? FocusedField.rect()
        let model = PopupModel(title: title, text: text, original: original,
                               sourceLanguage: sourceLanguage, targetLanguage: targetLanguage,
                               onClose: { [weak self] in self?.close() })
        if let onReplace {
            model.onReplace = { [weak self] in
                self?.close()
                onReplace()
            }
        }
        host.show(PopupView(model: model, maxBodyHeight: PanelPlacement.maxHeight(near: field) - 120),
                  title: "BindAll Translation", near: field, onEscape: model.onClose)
        if let panel = host.panel { copyShortcut.install(on: panel, copyAll: model.copyText) }
    }

    func close() {
        copyShortcut.remove()
        host.close()
    }
}
