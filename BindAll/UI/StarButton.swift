import SwiftUI

/// The single violet star BindAll puts at the end of a selection or in the corner of a text field:
/// just the star, no badge around it.
struct StarButton: View {
    /// "Actions for the selection" / "Actions for this text", for VoiceOver and the tooltip.
    let label: String
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: "sparkle", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color.brand)
            .frame(width: StarButton.size, height: StarButton.size)
            .contentShape(.rect)
            .help(label)
    }

    /// The click target; the star itself is smaller.
    static let size: CGFloat = 20
}
