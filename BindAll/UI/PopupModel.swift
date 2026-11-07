import AppKit
import Observation

@MainActor @Observable
final class PopupModel {
    let title: String
    let text: String
    /// The text as shown: a model's Markdown styled rather than spelled out.
    let display: AttributedString
    let width: CGFloat
    let original: String?
    let sourceLanguage: String?
    let targetLanguage: String?
    @ObservationIgnored let onClose: () -> Void
    /// Puts the result in place of the text it came from; nil when there is no such place.
    @ObservationIgnored var onReplace: (() -> Void)?
    @ObservationIgnored private var copiedReset: Task<Void, Never>?
    var showOriginal = false
    private(set) var copiedText = false
    private(set) var copiedOriginal = false

    init(title: String, text: String, original: String?, sourceLanguage: String?, targetLanguage: String?,
         onClose: @escaping () -> Void) {
        self.title = title
        self.text = text
        self.display = ResultMarkdown.render(text)
        self.width = PanelWidth.fitting([String(display.characters), original ?? ""])
        self.original = original
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.onClose = onClose
    }

    /// "Russian → English" when both are known.
    var languagePair: String? {
        guard let sourceLanguage, let targetLanguage else { return nil }
        return "\(sourceLanguage) → \(targetLanguage)"
    }

    func copyText() {
        UsageLog.record(.translationPopup, .accepted, detail: "copy:\(title)")
        TextInjector.copyToPasteboard(String(display.characters))
        copiedText = true
        copiedReset?.cancel()
        copiedReset = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            copiedText = false
        }
    }

    func copyOriginal() {
        guard let original else { return }
        TextInjector.copyToPasteboard(original)
        copiedOriginal = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedOriginal = false
        }
    }
}
