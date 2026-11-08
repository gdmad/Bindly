import SwiftUI

/// Closes the fixes popup; the underlines stay. Esc, moving the caret and typing do the same.
/// The same kind of cell as Skip: in the never-key panel cells take the first click, which a Button
/// did not reliably do on so small a target.
struct FixesPopupCloseButton: View {
    let fontSize: CGFloat
    let onActivate: () -> Void

    var body: some View {
        PopupCell(text: "Close", isSelected: false,
                  fontSize: PopupMetrics.counterFontSize(fontSize),
                  systemImage: "xmark", isSecondary: true, showsTitle: false, onActivate: onActivate,
                  highlightsOnHover: true)
            .help("Close (Esc)")
    }
}
