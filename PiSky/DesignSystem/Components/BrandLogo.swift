import SwiftUI

/// BrandLogo — SwiftUI port of `core/ui/components/BrandLogo.kt`.
///
/// The v6 PiSky mark as a miniature instrument scope: three concentric brass rings, brass
/// cardinal ticks, a slowly revolving cyan sweep wedge with a sharp lead line, and a brass
/// center hub. The sweep runs at half the home-radar speed (revolution·2 = 16 s) so it reads
/// decorative. Self-animating via `TimelineView(.animation)`.
struct BrandLogo: View {
    var size: CGFloat = 88
    var animate: Bool = true

    // Half the home-radar cadence (Kotlin: RevolutionMs * 2).
    private var revolution: Double { HangarLuxe.Sweep.revolution * 2 }

    var body: some View {
        TimelineView(.animation(paused: !animate)) { timeline in
            Canvas { ctx, canvasSize in
                let r = Swift.min(canvasSize.width, canvasSize.height) / 2
                let c = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

                let sweepDeg: Double = animate
                    ? (timeline.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: revolution) / revolution) * 360
                    : 0

                // Outer instrument bezel
                ctx.stroke(circ(c, r * 0.96), with: .color(Palette.brass.opacity(0.92)), style: StrokeStyle(lineWidth: 2.4))
                ctx.stroke(circ(c, r * 1.00), with: .color(Palette.brass.opacity(0.30)), style: StrokeStyle(lineWidth: 1.0))

                // Inner glass — radial gradient floor
                ctx.fill(fillCirc(c, r * 0.94), with: .radialGradient(
                    Gradient(colors: [Color(hex: 0x11141B), Color(hex: 0x0C0E14)]),
                    center: c, startRadius: 0, endRadius: r * 0.95))

                // Range rings
                ctx.stroke(circ(c, r * 0.66), with: .color(Palette.brass.opacity(0.42)), style: StrokeStyle(lineWidth: 1.2))
                ctx.stroke(circ(c, r * 0.33), with: .color(Palette.brass.opacity(0.30)), style: StrokeStyle(lineWidth: 1.0))

                // Cardinal tick marks (N/E/S/W)
                for deg in stride(from: 0, to: 360, by: 90) {
                    let rad = Double(deg - 90) * .pi / 180
                    let inner = r * 0.84, outer = r * 0.94
                    let cosR = CGFloat(cos(rad)), sinR = CGFloat(sin(rad))
                    var tick = Path()
                    tick.move(to: CGPoint(x: c.x + inner * cosR, y: c.y + inner * sinR))
                    tick.addLine(to: CGPoint(x: c.x + outer * cosR, y: c.y + outer * sinR))
                    ctx.stroke(tick, with: .color(Palette.brass.opacity(0.70)), style: StrokeStyle(lineWidth: 1.6))
                }

                // Sweep — soft cyan wedge with a sharp lead edge
                let rad0 = (sweepDeg - 90) * .pi / 180
                let trailDeg = HangarLuxe.Sweep.trailDegrees * 0.8
                let rr = r * 0.94
                var wedge = Path()
                wedge.move(to: c)
                wedge.addLine(to: CGPoint(x: c.x + rr * CGFloat(cos(rad0)), y: c.y + rr * CGFloat(sin(rad0))))
                // arcTo(rect, startAngle = sweepDeg - 90, sweep = -trailDeg)
                wedge.addArc(center: c, radius: rr,
                             startAngle: .degrees(sweepDeg - 90),
                             endAngle: .degrees(sweepDeg - 90 - trailDeg),
                             clockwise: true)
                wedge.closeSubpath()

                let sweepBrush = GraphicsContext.Shading.conicGradient(
                    Gradient(stops: [
                        .init(color: .clear, location: 0.00),
                        .init(color: .clear, location: 0.20),
                        .init(color: Palette.cyan.opacity(0.06), location: 0.40),
                        .init(color: Palette.cyan.opacity(0.14), location: 0.55),
                        .init(color: Palette.cyan.opacity(0.24), location: 0.70),
                        .init(color: .clear, location: 0.85),
                        .init(color: .clear, location: 1.00),
                    ]),
                    center: c, angle: .degrees(sweepDeg - 90))
                ctx.fill(wedge, with: sweepBrush)

                var lead = Path()
                lead.move(to: c)
                lead.addLine(to: CGPoint(x: c.x + rr * CGFloat(cos(rad0)), y: c.y + rr * CGFloat(sin(rad0))))
                ctx.stroke(lead, with: .color(Palette.cyan), style: StrokeStyle(lineWidth: 2.0))

                // Center hub — brass pip
                ctx.fill(fillCirc(c, r * 0.06), with: .color(Palette.brassBright))
                ctx.fill(fillCirc(c, r * 0.03), with: .color(Palette.brass))
            }
        }
        .frame(width: size, height: size)
    }

    private func circ(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }
    private func fillCirc(_ c: CGPoint, _ r: CGFloat) -> Path { circ(c, r) }
}

#Preview {
    BrandLogo(size: 160)
        .padding(40)
        .background(Palette.background)
}
