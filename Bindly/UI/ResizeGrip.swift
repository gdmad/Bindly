import AppKit
import SwiftUI

/// The mark in a result or preview window's bottom-right corner. Only drawn here: the drag itself
/// is taken by `KeyablePanel` (its `gripSize` square), which keeps the top edge and grows the
/// window right and down.
struct ResizeGrip: View {
    var body: some View {
        Canvas { context, size in
            for inset in [3.0, 7.0, 11.0] {
                var path = Path()
                path.move(to: CGPoint(x: size.width - inset, y: size.height - 1))
                path.addLine(to: CGPoint(x: size.width - 1, y: size.height - inset))
                context.stroke(path, with: .style(.tertiary), lineWidth: 1)
            }
        }
        .frame(width: KeyablePanel.gripSize - 2, height: KeyablePanel.gripSize - 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
