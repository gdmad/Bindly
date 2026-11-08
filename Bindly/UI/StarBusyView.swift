import SwiftUI

/// The star while an action runs: it turns, breathes and shifts through the icon's colors, with three
/// small stars on tilted orbits around it like electrons. With Reduce Motion only the color shifts.
struct StarBusyView: View {
    /// The star's own size; the view is `StarButton.busySize` so the orbits are not clipped.
    let starSize: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600)
            Canvas { ctx, size in
                draw(in: &ctx, center: CGPoint(x: size.width / 2, y: size.height / 2), t: t)
            }
        }
        .frame(width: StarButton.busySize, height: StarButton.busySize)
        .accessibilityHidden(true)
    }

    private struct Electron {
        let position: CGPoint
        /// -1 behind the star ... 1 in front of it.
        let depth: Double
    }

    private func draw(in ctx: inout GraphicsContext, center: CGPoint, t: Double) {
        let r = starSize / 2
        let electrons = reduceMotion ? [] : Self.electrons(radius: r * 1.55, t: t)
        for e in electrons where e.depth < 0 { drawElectron(e, in: &ctx, center: center, r: r, t: t) }

        var star = ctx
        star.translateBy(x: center.x, y: center.y)
        if !reduceMotion {
            star.rotate(by: .degrees((t * 180).truncatingRemainder(dividingBy: 360)))
            let k = 1 + 0.12 * sin(t * 2 * .pi / 1.2)
            star.scaleBy(x: k, y: k)
        }
        star.fill(StarShape().path(in: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)),
                  with: .color(BrandPalette.color(at: t * 0.6)))

        for e in electrons where e.depth >= 0 { drawElectron(e, in: &ctx, center: center, r: r, t: t) }
    }

    private func drawElectron(_ e: Electron, in ctx: inout GraphicsContext, center: CGPoint, r: CGFloat, t: Double) {
        let near = (e.depth + 1) / 2
        let size = r * 0.26 * (0.75 + 0.25 * near)
        var dot = ctx
        dot.opacity = 0.55 + 0.45 * near
        let rect = CGRect(x: center.x + e.position.x - size, y: center.y + e.position.y - size,
                          width: 2 * size, height: 2 * size)
        dot.fill(StarShape().path(in: rect), with: .color(BrandPalette.color(at: t * 0.6 + 0.5)))
    }

    /// Three ellipses tilted 60 degrees apart, each flattened to a third of its width, so they read
    /// as orbits in different planes.
    private static func electrons(radius: CGFloat, t: Double) -> [Electron] {
        (0..<3).map { i in
            let theta = t * 2 * .pi / 1.6 + Double(i) * 2.1
            let tilt = Double(i) * .pi / 3 + 0.3
            let x = radius * cos(theta), y = radius * 0.32 * sin(theta)
            return Electron(position: CGPoint(x: x * cos(tilt) - y * sin(tilt), y: x * sin(tilt) + y * cos(tilt)),
                            depth: sin(theta))
        }
    }
}
