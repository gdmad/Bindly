import Foundation

/// How the menu-bar icon's three sparkles flare while an action runs: one after another, like a wave,
/// each brightening and swelling, then resting dim until the next round. The first frame already has
/// the big sparkle lit, so even a short action shows a change at once.
enum StatusIconTwinkle {
    struct Frame: Equatable {
        var alpha: Double
        var scale: Double
    }

    static let period: Double = 1.0
    /// How far behind the previous sparkle each one flares, in seconds.
    static let stagger: Double = 0.2
    static let dim: Double = 0.15
    /// How much each sparkle swells at its peak: the big one a little, the small ones more, since a
    /// change of brightness alone is hard to see on a few pixels.
    static let peakScales: [Double] = [1.1, 1.3, 1.35]

    /// Big, upper and lower sparkle at time `t`, in seconds since the wave started.
    static func frames(at t: Double) -> [Frame] {
        peakScales.enumerated().map { i, peak in
            let lit = lit(phase: (t - Double(i) * stagger) / period + rise)
            return Frame(alpha: dim + (1 - dim) * lit, scale: 1 + (peak - 1) * lit)
        }
    }

    /// When a wave whose action ended `elapsed` seconds in should stop: at the end of its round, and
    /// never before `minimumRounds`, so a quick action is still seen.
    static func stopTime(endedAt elapsed: Double) -> Double {
        max(Double(minimumRounds) * period, (elapsed / period).rounded(.up) * period)
    }

    static let minimumRounds = 2

    private static let rise = 0.2
    private static let fall = 0.45

    /// 0...1: up over the first fifth of the round, back down by 45 %, dark for the rest.
    static func lit(phase: Double) -> Double {
        let p = phase - phase.rounded(.down)
        if p < rise { return ease(p / rise) }
        if p < fall { return 1 - ease((p - rise) / (fall - rise)) }
        return 0
    }

    private static func ease(_ x: Double) -> Double { x * x * (3 - 2 * x) }
}
