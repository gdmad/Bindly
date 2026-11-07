import SwiftUI

/// "Fix all": every issue's first fix at once, shown in the preview before anything is written. An
/// icon with the number of issues beside Skip, Add to dictionary and Close, its full name kept for
/// VoiceOver and the tooltip. A cell like Skip (not a Button): in the never-key panel cells take the
/// first click.
struct FixesPopupFixAllButton: View {
    let count: Int
    let fontSize: CGFloat
    let onActivate: () -> Void

    var body: some View {
        PopupCell(text: "\(count)", isSelected: false,
                  fontSize: PopupMetrics.counterFontSize(fontSize),
                  systemImage: "wand.and.stars", isSecondary: true, onActivate: onActivate,
                  highlightsOnHover: true, accessibilityText: "Fix all (\(count))")
            .monospacedDigit()
            .help("Fix all \(count) issues, with a preview (⌘Return)")
    }
}
