import AppKit
import Observation

/// The text before and after an action, waiting for Apply.
@MainActor @Observable
final class PreviewModel {
    enum Mode: String, CaseIterable, Identifiable {
        case changes = "Changes"
        case result = "Result"
        var id: Self { self }
    }

    let title: String
    let original: String
    let result: String
    let parts: [TextDiff.Part]
    let width: CGFloat
    /// Something worth knowing that the diff does not show (e.g. stock phrases left in the text).
    let note: String?
    var mode: Mode = .changes
    private(set) var copied = false
    @ObservationIgnored let onApply: () -> Void
    @ObservationIgnored let onClose: () -> Void

    init(title: String, original: String, result: String, note: String? = nil,
         onApply: @escaping () -> Void, onClose: @escaping () -> Void) {
        self.note = note
        self.title = title
        self.original = original
        self.result = result
        self.parts = TextDiff.words(old: original, new: result)
        self.width = PanelWidth.fitting([original, result])
        self.onApply = onApply
        self.onClose = onClose
    }

    var hasChanges: Bool { TextDiff.hasChanges(parts) }

    func copy() {
        TextInjector.copyToPasteboard(result)
        copied = true
        UsageLog.record(.preview, .accepted, detail: "copy")
    }
}
