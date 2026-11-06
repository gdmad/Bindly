import SwiftUI

/// Closes the fixes popup; the underlines stay. Esc, moving the caret and typing do the same.
/// A real button rather than a tap-gesture cell: in the never-key panel the gesture missed the first
/// click on so small a target.
struct FixesPopupCloseButton: View {
    let fontSize: CGFloat
    let onActivate: () -> Void

    var body: some View {
        Button("Close", systemImage: "xmark", action: onActivate)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: PopupMetrics.counterFontSize(fontSize)))
            .foregroundStyle(.secondary)
            .padding(.horizontal, PopupMetrics.cellPaddingH)
            .padding(.vertical, PopupMetrics.cellPaddingV)
            .contentShape(.rect)
            .help("Close (Esc)")
    }
}
