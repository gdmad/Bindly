import SwiftUI

/// The app icon's gradient, sampled from the icon, for the star's color shift while it works.
enum BrandPalette {
    /// Magenta, violet, pink, then the brand violet, in sRGB.
    static let stops: [(r: Double, g: Double, b: Double)] = [
        (0.82, 0.22, 0.90), (0.60, 0.23, 0.94), (0.96, 0.49, 0.89), (0.60, 0.06, 0.88),
    ]

    /// The color `phase` of the way around the stops (any real number; it wraps).
    static func color(at phase: Double) -> Color {
        let n = Double(stops.count)
        let x = (phase - phase.rounded(.down)) * n
        let i = Int(x) % stops.count
        let f = x - x.rounded(.down)
        let a = stops[i], b = stops[(i + 1) % stops.count]
        return Color(red: a.r + (b.r - a.r) * f, green: a.g + (b.g - a.g) * f, blue: a.b + (b.b - a.b) * f)
    }
}
