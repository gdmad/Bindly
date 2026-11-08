import SwiftUI

/// The single violet star BindAll puts at the end of a selection or in the corner of a text field:
/// just the star, no badge around it. While an action runs it becomes `StarBusyView`.
struct StarButton: View {
    /// "Actions for the selection" / "Actions for this text", for VoiceOver and the tooltip.
    let label: String
    let activity: StarActivity
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button(action: action) {
            star
                .frame(width: StarButton.size, height: StarButton.size)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel(label)
        .accessibilityValue(activity.busy ? "Working" : "")
        .help(label)
    }

    @ViewBuilder private var star: some View {
        if activity.busy {
            StarBusyView(starSize: starSize)
        } else {
            StarShape()
                .fill(Color.brand)
                .frame(width: starSize, height: starSize)
                // At 1x the 24 pt target's center is a pixel corner; half a point puts the odd-sized
                // star's center, and with it each thin ray, on a pixel's middle.
                .offset(x: pixelNudge, y: pixelNudge)
        }
    }

    private var starSize: CGFloat { displayScale < 2 ? 13 : StarButton.starSize }
    private var pixelNudge: CGFloat { displayScale < 2 ? 0.5 : 0 }

    /// The click target; the star itself is smaller.
    static let size: CGFloat = 24
    static let starSize: CGFloat = 12
    /// The panel while the star works, so the orbiting stars are not clipped.
    static let busySize: CGFloat = 30
}
