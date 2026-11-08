import AppKit
import SwiftUI

/// Shows `PreviewView` in a floating panel. It takes focus (Return applies, Esc closes); Apply hands
/// control back so the result can be pasted into the app it came from.
@MainActor
final class PreviewController {
    private let host = FloatingPanelHost()

    func show(title: String, original: String, result: String, note: String? = nil, near field: CGRect? = nil,
              onApply: @escaping () -> Void) {
        close()
        UsageLog.record(.preview, .shown)
        let model = PreviewModel(title: title, original: original, result: result, note: note,
                                 onApply: { [weak self] in
                                     UsageLog.record(.preview, .applied)
                                     self?.close()
                                     onApply()
                                 },
                                 onClose: { [weak self] in
                                     UsageLog.record(.preview, .dismissed, reason: "close")
                                     self?.close()
                                 })
        let field = field ?? FocusedField.rect()
        host.show(PreviewView(model: model, maxBodyHeight: PanelPlacement.maxHeight(near: field) - 120),
                  title: "BindAll Preview", near: field, onEscape: model.onClose)
    }

    func close() {
        host.close()
    }
}
