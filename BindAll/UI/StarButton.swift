import SwiftUI

/// The single violet star BindAll puts at the end of a selection or in the corner of a text field.
struct StarButton: View {
    /// "Actions for the selection" / "Actions for this text", for VoiceOver and the tooltip.
    let label: String
    let action: () -> Void

    var body: some View {
        Button(label, systemImage: "sparkle", action: action)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.brand)
            .frame(width: StarButton.size, height: StarButton.size)
            .background(.regularMaterial, in: .circle)
            .overlay { Circle().strokeBorder(Color.brand.opacity(0.35), lineWidth: 0.5) }
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .contentShape(.circle)
            .help(label)
    }

    static let size: CGFloat = 20
}
