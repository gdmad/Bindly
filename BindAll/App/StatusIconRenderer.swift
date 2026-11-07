import AppKit

/// The menu-bar icon: three four-point sparkles, drawn rather than taken from the `sparkles` symbol
/// so each can be lit on its own while BindAll works. A template image, so the system still tints it
/// for the menu bar's appearance and inverts it for the click highlight.
enum StatusIconRenderer {
    static let size = NSSize(width: 18, height: 18)

    /// Center and radius of each sparkle in an 18 pt square (y up), biggest first, laid out like the
    /// `sparkles` symbol the icon used to be.
    private static let sparkles: [(x: CGFloat, y: CGFloat, r: CGFloat)] = [
        (10.5, 6.8, 6.2), (4.4, 12.6, 3.4), (9.4, 16.1, 2.1),
    ]

    static func image(alphas: [Double] = [1, 1, 1], description: String) -> NSImage {
        let image = NSImage(size: size, flipped: false) { _ in
            for (i, s) in sparkles.enumerated() {
                NSColor.black.withAlphaComponent(i < alphas.count ? alphas[i] : 1).setFill()
                sparkle(center: CGPoint(x: s.x, y: s.y), radius: s.r).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description
        return image
    }

    /// The same silhouette as `StarShape`.
    private static func sparkle(center c: CGPoint, radius r: CGFloat, waist: CGFloat = 0.08) -> NSBezierPath {
        let w = r * waist
        let path = NSBezierPath()
        path.move(to: CGPoint(x: c.x, y: c.y + r))
        path.curve(to: CGPoint(x: c.x + r, y: c.y), controlPoint: CGPoint(x: c.x + w, y: c.y + w))
        path.curve(to: CGPoint(x: c.x, y: c.y - r), controlPoint: CGPoint(x: c.x + w, y: c.y - w))
        path.curve(to: CGPoint(x: c.x - r, y: c.y), controlPoint: CGPoint(x: c.x - w, y: c.y - w))
        path.curve(to: CGPoint(x: c.x, y: c.y + r), controlPoint: CGPoint(x: c.x - w, y: c.y + w))
        path.close()
        return path
    }
}

private extension NSBezierPath {
    /// A quadratic curve, as `StarShape` uses, expressed as the equivalent cubic.
    func curve(to end: CGPoint, controlPoint q: CGPoint) {
        let start = currentPoint
        let c1 = CGPoint(x: start.x + 2 / 3 * (q.x - start.x), y: start.y + 2 / 3 * (q.y - start.y))
        let c2 = CGPoint(x: end.x + 2 / 3 * (q.x - end.x), y: end.y + 2 / 3 * (q.y - end.y))
        curve(to: end, controlPoint1: c1, controlPoint2: c2)
    }
}
