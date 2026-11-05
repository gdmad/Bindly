import SwiftUI

/// Closes the fixes popup; the underlines stay. Esc, moving the caret and typing do the same.
struct FixesPopupCloseButton: View {
    let fontSize: CGFloat
    let onActivate: () -> Void

    var body: some View {
        PopupCell(text: "Close", isSelected: false, fontSize: PopupMetrics.counterFontSize(fontSize),
                  systemImage: "xmark", isSecondary: true, showsTitle: false, onActivate: onActivate)
            .help("Close (Esc)")
    }
}
