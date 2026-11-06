import SwiftUI

/// The popup's top line: what is wrong and where this word sits among the problems found, then the
/// Skip, Add to dictionary and Close buttons.
struct FixesPopupHeader: View {
    let title: String
    let kind: IssueKind
    /// e.g. "2 of 7"
    let position: String
    let fontSize: CGFloat
    let skipSelected: Bool
    let onHoverSkip: () -> Void
    let onSkip: () -> Void
    var onAddWord: (() -> Void)?
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: PopupMetrics.inlineSpacing) {
            FixesPopupSummary(title: title, kind: kind, position: position, fontSize: fontSize)
            FixesPopupSkipButton(isSelected: skipSelected, fontSize: fontSize,
                                 onHover: onHoverSkip, onActivate: onSkip)
            if let onAddWord {
                FixesPopupAddWordButton(fontSize: fontSize, onActivate: onAddWord)
            }
            FixesPopupCloseButton(fontSize: fontSize, onActivate: onClose)
        }
    }
}
