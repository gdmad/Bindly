import SwiftUI

/// The single violet star BindAll puts at the end of a selection or in the corner of a text field:
/// just the star, no badge around it. It turns and pulses while an action runs.
struct StarButton: View {
    /// "Actions for the selection" / "Actions for this text", for VoiceOver and the tooltip.
    let label: String
    let activity: StarActivity
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            star
                .frame(width: StarButton.size, height: StarButton.size)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(activity.busy ? "Working" : "")
        .help(label)
    }

    @ViewBuilder private var star: some View {
        let shape = StarShape()
            .fill(Color.brand)
            .frame(width: starSize, height: starSize)
        if activity.busy {
            TimelineView(.animation) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                shape
                    .rotationEffect(.degrees(reduceMotion ? 0 : (t * 180).truncatingRemainder(dividingBy: 360)))
                    .opacity(0.55 + 0.45 * (0.5 + 0.5 * sin(t * 2 * .pi / 1.2)))
            }
        } else {
            shape
        }
    }

    /// At 1x an odd pixel count centers the thin rays on whole pixels; at 2x 12 pt already does.
    private var starSize: CGFloat { displayScale < 2 ? 13 : StarButton.starSize }

    /// The click target; the star itself is smaller.
    static let size: CGFloat = 24
    static let starSize: CGFloat = 12
}
