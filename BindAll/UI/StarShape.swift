import SwiftUI

/// BindAll's four-point star as a vector path: unlike the `sparkle` symbol at 10 pt it is not hinted
/// for text, so with a pixel-aligned panel its edges stay sharp at 1x and 2x.
struct StarShape: Shape {
    /// How far the waist between two points is pulled toward the center (0 = a plus, 1 = a square).
    var waist: CGFloat = 0.3

    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let w = r * waist
        let top = CGPoint(x: c.x, y: c.y - r), right = CGPoint(x: c.x + r, y: c.y)
        let bottom = CGPoint(x: c.x, y: c.y + r), left = CGPoint(x: c.x - r, y: c.y)
        var path = Path()
        path.move(to: top)
        // Each side curves in toward the center, the classic "sparkle" silhouette.
        path.addQuadCurve(to: right, control: CGPoint(x: c.x + w, y: c.y - w))
        path.addQuadCurve(to: bottom, control: CGPoint(x: c.x + w, y: c.y + w))
        path.addQuadCurve(to: left, control: CGPoint(x: c.x - w, y: c.y + w))
        path.addQuadCurve(to: top, control: CGPoint(x: c.x - w, y: c.y - w))
        path.closeSubpath()
        return path
    }
}
