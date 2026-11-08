import SwiftUI

/// The single violet star BindAll puts at the end of a selection or in the corner of a text field:
/// just the star, no badge around it. While an action runs it becomes `StarBusyView`.
struct StarButton: View {
    /// "Actions for the selection" / "Actions for this text", for VoiceOver and the tooltip.
    let label: String
    let activity: StarActivity
    let action: () -> Void

    @Environment(\.displayScale) private var displayScale
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    /// Issues in the field: a small dot in the most serious one's color by the upper right ray, as
    /// the underlines are colored; with "Differentiate Without Color", that kind's symbol.
    @ViewBuilder private var issueMark: some View {
        if !activity.busy, activity.count > 0, let kind = activity.worstIssue {
            Group {
                if differentiateWithoutColor {
                    Image(systemName: IssueKindStyle.symbolName(kind))
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(IssueKindStyle.color(kind))
                } else {
                    Circle()
                        .fill(IssueKindStyle.color(kind))
                        .frame(width: 5, height: 5)
                        .padding(1)
                        .background(Color(nsColor: .windowBackgroundColor), in: .circle)
                }
            }
            .offset(x: starSize * 0.42, y: -starSize * 0.42)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    var body: some View {
        Button(action: action) {
            star
                .frame(width: StarButton.size, height: StarButton.size)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay { issueMark }
        .accessibilityLabel(label)
        .accessibilityValue(activity.busy ? "Working" : activity.count > 0 ? "\(activity.count) issues" : "")
        .help(activity.count > 0 ? "\(label) — \(activity.count == 1 ? "1 issue" : "\(activity.count) issues")" : label)
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
