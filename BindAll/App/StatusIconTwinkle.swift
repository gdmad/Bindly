import Foundation

/// When each of the menu-bar icon's three sparkles is lit while an action runs: they flare one after
/// another, like a wave, then rest dim until the next round.
enum StatusIconTwinkle {
    static let period: Double = 1.5
    /// How far behind the previous sparkle each one flares, in seconds.
    static let stagger: Double = 0.3
    static let dim: Double = 0.25

    /// Alpha of the big, upper and lower sparkle at time `t` (seconds, any origin).
    static func alphas(at t: Double) -> [Double] {
        (0..<3).map { alpha(phase: (t - Double($0) * stagger) / period) }
    }

    /// Up to full in the first fifth of the round, back down by 45 %, dim for the rest.
    static func alpha(phase: Double) -> Double {
        let p = phase - phase.rounded(.down)
        let rise = 0.2, fall = 0.45
        let lit: Double
        if p < rise { lit = ease(p / rise) }
        else if p < fall { lit = 1 - ease((p - rise) / (fall - rise)) }
        else { lit = 0 }
        return dim + (1 - dim) * lit
    }

    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
