import SwiftUI

/// PolarRose — SwiftUI `Canvas` port of `core/ui/components/PolarRose.kt`.
///
/// North-up polar coverage rose (PPI style): dashed concentric range rings with labels,
/// cardinal/inter-cardinal spokes every 45°, then the receiver's coverage polygon as a
/// glowing radial-gradient fill with altitude-coloured vertices, live aircraft dots, and a
/// center receiver pip. Pure rendering — give it pre-projected points.
///
/// Coordinate math preserved: `angle = (bearing − 90)°`, `point = (cx + r·cosθ, cy + r·sinθ)`,
/// `maxR = minDimension/2 · 0.86`.

/// One coverage vertex: where (bearing) and how far (0..1 of max range), plus a colour.
struct RosePoint: Identifiable {
    let id = UUID()
    let bearingDeg: Double
    let rangeFraction: Float
    let color: Color
}

struct PolarRose: View {
    let points: [RosePoint]
    let ringLabels: [String]
    var accent: Color = Palette.cyan
    var liveDots: [RosePoint] = []

    var body: some View {
        Canvas { ctx, size in
            let cx = size.width / 2
            let cy = size.height / 2
            let maxR = Swift.min(size.width, size.height) / 2 * 0.86
            let rings = Swift.max(ringLabels.count, 1)
            let dash = StrokeStyle(lineWidth: 1, dash: [3, 6])

            // range rings + labels
            let labelSize = maxR * 0.075
            for i in 1...rings {
                let r = maxR * CGFloat(i) / CGFloat(rings)
                ctx.stroke(circleStroke(center: CGPoint(x: cx, y: cy), r: r),
                           with: .color(Palette.outline.opacity(0.55)), style: dash)
                if i - 1 < ringLabels.count {
                    // Kotlin: drawText centered at (cx, cy - r + textSize). Native baseline ≈ that y;
                    // we offset up by ~0.5·size so the resolved (top-anchored) text centers on the baseline.
                    let lbl = drawText(ctx, ringLabels[i - 1], font: .psMono(labelSize), color: Palette.textMuted)
                    ctx.draw(lbl, at: CGPoint(x: cx, y: cy - r + labelSize * 0.5), anchor: .center)
                }
            }

            // spokes every 45°
            for b in stride(from: 0, to: 360, by: 45) {
                let a = deg2radPR(Double(b - 90))
                var spoke = Path()
                spoke.move(to: CGPoint(x: cx, y: cy))
                spoke.addLine(to: CGPoint(x: cx + maxR * cos(a), y: cy + maxR * sin(a)))
                ctx.stroke(spoke, with: .color(Palette.outline.opacity(b % 90 == 0 ? 0.6 : 0.35)), style: dash)
            }

            // cardinal labels (brass, bold)
            let cardSize = maxR * 0.10
            let cr = maxR + cardSize * 0.9
            func card(_ s: String, _ pt: CGPoint) {
                ctx.draw(drawText(ctx, s, font: .psMono(cardSize, weight: .bold), color: Palette.brass),
                         at: pt, anchor: .center)
            }
            card("N", CGPoint(x: cx, y: cy - cr + cardSize * 0.35 - cardSize * 0.5))
            card("S", CGPoint(x: cx, y: cy + cr + cardSize * 0.35 - cardSize * 0.5))
            card("E", CGPoint(x: cx + cr, y: cy + cardSize * 0.35 - cardSize * 0.5))
            card("W", CGPoint(x: cx - cr, y: cy + cardSize * 0.35 - cardSize * 0.5))

            // coverage polygon
            if !points.isEmpty {
                let sorted = points.sorted { $0.bearingDeg < $1.bearingDeg }
                func pt(_ p: RosePoint) -> CGPoint {
                    let a = deg2radPR(p.bearingDeg - 90)
                    let r = maxR * CGFloat(Swift.min(Swift.max(p.rangeFraction, 0), 1))
                    return CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
                }
                var poly = Path()
                for (i, p) in sorted.enumerated() {
                    let o = pt(p)
                    if i == 0 { poly.move(to: o) } else { poly.addLine(to: o) }
                }
                poly.closeSubpath()
                // radial gradient fill from center
                ctx.fill(poly, with: .radialGradient(
                    Gradient(colors: [accent.opacity(0.06), accent.opacity(0.26)]),
                    center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: maxR))
                ctx.stroke(poly, with: .color(accent.opacity(0.85)), style: StrokeStyle(lineWidth: 1.6))
                // altitude-coloured vertices
                for p in sorted {
                    ctx.fill(circlePath(center: pt(p), r: 2.2), with: .color(p.color))
                }
            }

            // live aircraft dots (glowing) on top
            for p in liveDots {
                let a = deg2radPR(p.bearingDeg - 90)
                let r = maxR * CGFloat(Swift.min(Swift.max(p.rangeFraction, 0), 1))
                let o = CGPoint(x: cx + r * cos(a), y: cy + r * sin(a))
                ctx.fill(circlePath(center: o, r: 5), with: .color(p.color.opacity(0.30)))
                ctx.fill(circlePath(center: o, r: 2.6), with: .color(p.color))
            }

            // receiver center
            let c = CGPoint(x: cx, y: cy)
            ctx.fill(circlePath(center: c, r: maxR * 0.018), with: .color(accent))
            ctx.fill(circlePath(center: c, r: maxR * 0.04), with: .color(accent.opacity(0.3)))
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - helpers

private func deg2radPR(_ d: Double) -> Double { d * .pi / 180 }

/// Stroked-circle path for ring outlines.
private func circleStroke(center: CGPoint, r: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
}

/// Resolve a styled `Text` for drawing inside a `Canvas` (mirrors Compose `nativeCanvas.drawText`).
private func drawText(_ ctx: GraphicsContext, _ s: String, font: Font, color: Color) -> GraphicsContext.ResolvedText {
    ctx.resolve(Text(s).font(font).foregroundColor(color))
}

#Preview {
    PolarRose(
        points: (0..<24).map { i in
            RosePoint(bearingDeg: Double(i) * 15,
                      rangeFraction: Float.random(in: 0.4...0.95),
                      color: Palette.radarAltitude(Int.random(in: 0...40000)))
        },
        ringLabels: ["50", "100", "150", "200"],
        accent: Palette.cyan,
        liveDots: [
            RosePoint(bearingDeg: 30, rangeFraction: 0.6, color: Palette.cyan),
            RosePoint(bearingDeg: 200, rangeFraction: 0.8, color: Palette.brass),
        ]
    )
    .padding()
    .background(Palette.background)
}
