import SwiftUI

/// Reports its content's size rounded up to whole points. A window sized by its SwiftUI content
/// (`FloatingPanelHost`) is a whole number of points; content whose own width was fractional came
/// out a fraction narrower than it asked for, laid itself out again, and the window and its content
/// went round that loop until the app ran out of stack.
struct IntegralSizeLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(proposal)
        return CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: bounds.height))
    }
}
