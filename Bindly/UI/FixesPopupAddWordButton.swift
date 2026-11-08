import SwiftUI

/// "Add to dictionary": this word is never flagged as a misspelling again, anywhere. An icon beside
/// Skip, with its name kept for VoiceOver and the tooltip.
struct FixesPopupAddWordButton: View {
    let fontSize: CGFloat
    let onActivate: () -> Void

    var body: some View {
        PopupCell(text: "Add to dictionary", isSelected: false,
                  fontSize: PopupMetrics.counterFontSize(fontSize),
                  systemImage: "text.book.closed", isSecondary: true, showsTitle: false, onActivate: onActivate, highlightsOnHover: true)
            .help("Add to dictionary")
    }
}
