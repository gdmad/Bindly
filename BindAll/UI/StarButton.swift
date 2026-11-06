import SwiftUI

/// The single violet star BindAll puts at the end of a selection or in the corner of a text field:
/// just the star, no badge around it.
struct StarButton: View {
    /// "Actions for the selection" / "Actions for this text", for VoiceOver and the tooltip.
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            StarShape()
                .fill(Color.brand)
                .frame(width: StarButton.starSize, height: StarButton.starSize)
                .frame(width: StarButton.size, height: StarButton.size)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }

    /// The click target; the star itself is smaller.
    static let size: CGFloat = 20
    /// Even, so the star's center falls on a pixel boundary inside the 20 pt target.
    static let starSize: CGFloat = 10
}
