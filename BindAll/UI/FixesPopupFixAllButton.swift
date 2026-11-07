import SwiftUI

/// "Fix all": every issue's first fix at once, shown in the preview before anything is written.
/// A cell like Skip (not a Button): in the never-key panel cells take the first click.
struct FixesPopupFixAllButton: View {
    let count: Int
    let fontSize: CGFloat
    let onActivate: () -> Void

    var body: some View {
        PopupCell(text: "Fix all (\(count))", isSelected: false,
                  fontSize: PopupMetrics.secondaryFontSize(fontSize),
                  fillsWidth: true, systemImage: "wand.and.stars", onActivate: onActivate,
                  highlightsOnHover: true, isProminent: true)
            .help("Fix all \(count) issues, with a preview (⌘Return)")
    }
}
