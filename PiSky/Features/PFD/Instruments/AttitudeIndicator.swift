import SwiftUI

/// Attitude indicator (artificial horizon) for the PFD — driven by *derived*
/// kinematics, not transmitted attitude (ADS-B carries neither pitch nor roll):
///
///  • Horizon pitch  = flight-path angle  γ = atan2(VS/60, GS·1.68781).
///    This is the aircraft's real climb/descent angle, not body pitch.
///  • Bank           = broadcast `roll` when present; otherwise a coordinated-turn
///    estimate  φ = atan(ω·V / g)  from the derived turn rate.
///
/// Both are honestly labelled (FPA, and "EST" on an estimated bank). When neither
/// can be derived (on ground / no speed) the horizon is shown level and dimmed
/// with an "ATTITUDE N/A" caption rather than faking a level attitude.
///
/// Ports `feature/pfd/instruments/AttitudeIndicator.kt`. The Compose
/// `clipRect { rotate { translate { … } } }` becomes a copied/clipped/rotated/
/// translated `GraphicsContext`.
struct AttitudeIndicator: View {
    let pitchDeg: Double
    let bankDeg: Double
    let fpaValid: Bool
    let bankEstimated: Bool

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let cx = w / 2
                let cy = h / 2
                let pxPerDeg = h / 36                     // ±18° visible top-to-bottom
                let pitchPx = (fpaValid ? pitchDeg : 0) * pxPerDeg
                let bank = (fpaValid || bankEstimated) ? bankDeg : 0
                // Live (full opacity) whenever pitch OR bank is derivable; dimmed
                // only in the truly-degraded "no attitude at all" state.
                let dim: Double = (fpaValid || bankEstimated) ? 1.0 : 0.45

                // ── Rotating + translated scene (sky/ground/horizon/ladder) ──
                var scene = ctx
                scene.clip(to: Path(CGRect(origin: .zero, size: size)))
                scene.translateBy(x: cx, y: cy)
                scene.rotate(by: .degrees(-bank))
                scene.translateBy(x: -cx, y: -cy)        // pivot about (cx, cy)
                scene.translateBy(x: 0, y: pitchPx)      // Compose translate(top: pitchPx)

                // Sky + ground (over-sized so rotation never reveals a corner)
                scene.fill(
                    Path(CGRect(x: -w, y: cy - 3 * h, width: 3 * w, height: 3 * h)),
                    with: .color(PfdColors.sky.opacity(dim)))
                scene.fill(
                    Path(CGRect(x: -w, y: cy, width: 3 * w, height: 3 * h)),
                    with: .color(PfdColors.ground.opacity(dim)))
                // Horizon line
                var horizon = Path()
                horizon.move(to: CGPoint(x: -w, y: cy))
                horizon.addLine(to: CGPoint(x: 2 * w, y: cy))
                scene.stroke(horizon, with: .color(PfdColors.white.opacity(dim)), lineWidth: 2.5)

                // Pitch ladder (symmetric ±5/10/15/20)
                let rungs: [(Int, CGFloat)] = [
                    (-20, 0.18), (-15, 0.20), (-10, 0.30), (-5, 0.14),
                    (5, 0.14), (10, 0.30), (15, 0.20), (20, 0.18),
                ]
                let labelSize = h * 0.028
                for (deg, frac) in rungs {
                    let y = cy - CGFloat(deg) * pxPerDeg
                    let half = w * frac / 2
                    var rung = Path()
                    rung.move(to: CGPoint(x: cx - half, y: y))
                    rung.addLine(to: CGPoint(x: cx + half, y: y))
                    scene.stroke(rung, with: .color(PfdColors.white.opacity(dim)), lineWidth: 1.6)
                    if abs(deg) >= 10 {
                        let txt = scene.resolve(Text("\(abs(deg))")
                            .font(.system(size: labelSize, weight: .regular))
                            .foregroundColor(PfdColors.white.opacity(dim)))
                        scene.draw(txt, at: CGPoint(x: cx - half - w * 0.03, y: y), anchor: .center)
                        scene.draw(txt, at: CGPoint(x: cx + half + w * 0.03, y: y), anchor: .center)
                    }
                }

                // ── Bank scale (fixed) — arc ticks at the top ──
                let arcR = h * 0.44
                let bankTicks = [-60, -45, -30, -20, -10, 0, 10, 20, 30, 45, 60]
                for t in bankTicks {
                    let a = Double(-90 + t) * .pi / 180
                    let major = (t % 30 == 0) || (t == 0)
                    let r2 = arcR - h * (major ? 0.05 : 0.03)
                    var tick = Path()
                    tick.move(to: CGPoint(x: cx + arcR * cos(a), y: cy + arcR * sin(a)))
                    tick.addLine(to: CGPoint(x: cx + r2 * cos(a), y: cy + r2 * sin(a)))
                    ctx.stroke(tick, with: .color(PfdColors.white), lineWidth: major ? 2 : 1.2)
                }
                // Fixed reference triangle at top
                let topY = cy - arcR
                var fixedTri = Path()
                fixedTri.move(to: CGPoint(x: cx, y: topY + h * 0.012))
                fixedTri.addLine(to: CGPoint(x: cx - h * 0.022, y: topY - h * 0.03))
                fixedTri.addLine(to: CGPoint(x: cx + h * 0.022, y: topY - h * 0.03))
                fixedTri.closeSubpath()
                ctx.fill(fixedTri, with: .color(PfdColors.amber))

                // Rolling bank pointer (rotates with bank, points up to the scale)
                var pointerCtx = ctx
                pointerCtx.translateBy(x: cx, y: cy)
                pointerCtx.rotate(by: .degrees(-bank))
                pointerCtx.translateBy(x: -cx, y: -cy)
                var pointer = Path()
                pointer.move(to: CGPoint(x: cx, y: cy - arcR + h * 0.012))
                pointer.addLine(to: CGPoint(x: cx - h * 0.020, y: cy - arcR + h * 0.05))
                pointer.addLine(to: CGPoint(x: cx + h * 0.020, y: cy - arcR + h * 0.05))
                pointer.closeSubpath()
                pointerCtx.fill(pointer, with: .color(PfdColors.white))

                // ── Fixed aircraft symbol (Boeing-style amber wing bars + center dot) ──
                let wingY = cy
                let wingInner = w * 0.10
                let wingOuter = w * 0.30
                let barH = h * 0.018
                // left wing
                ctx.fill(Path(CGRect(x: cx - wingOuter, y: wingY - barH / 2, width: wingOuter - wingInner, height: barH)),
                         with: .color(PfdColors.amber))
                // right wing
                ctx.fill(Path(CGRect(x: cx + wingInner, y: wingY - barH / 2, width: wingOuter - wingInner, height: barH)),
                         with: .color(PfdColors.amber))
                // center reference
                ctx.fill(Path(CGRect(x: cx - barH / 2, y: wingY - barH / 2, width: barH, height: barH)),
                         with: .color(PfdColors.amber))
                // small down-strokes at wing roots
                var lroot = Path()
                lroot.move(to: CGPoint(x: cx - wingInner, y: wingY))
                lroot.addLine(to: CGPoint(x: cx - wingInner, y: wingY + h * 0.025))
                ctx.stroke(lroot, with: .color(PfdColors.amber), lineWidth: 3)
                var rroot = Path()
                rroot.move(to: CGPoint(x: cx + wingInner, y: wingY))
                rroot.addLine(to: CGPoint(x: cx + wingInner, y: wingY + h * 0.025))
                ctx.stroke(rroot, with: .color(PfdColors.amber), lineWidth: 3)
            }

            // ── Honest labels (overlaid SwiftUI text) ──
            VStack {
                HStack(alignment: .top) {
                    Text(fpaValid ? "FPA \(signed1(pitchDeg))°" : "FPA —")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(PfdColors.white)
                    Spacer()
                    Text((fpaValid || bankEstimated)
                         ? "BANK \(signed0(bankDeg))°\(bankEstimated ? " EST" : "")"
                         : "BANK —")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(bankEstimated ? PfdColors.amber : PfdColors.white)
                }
                .padding(6)
                Spacer()
                Text(captionText)
                    .font(.system(size: 8.5))
                    .foregroundColor(PfdColors.amber.opacity(0.85))
                    .padding(.bottom, 3)
            }
        }
    }

    private var captionText: String {
        if fpaValid { return "DERIVED ATT · flight-path, no IRU" }
        if bankEstimated { return "DERIVED ATT · bank only (no VS)" }
        return "ATTITUDE N/A — on ground / no speed"
    }

    /// "%+.1f" — sign always shown, one decimal.
    private func signed1(_ v: Double) -> String { String(format: "%+.1f", v) }
    /// "%+.0f" — sign always shown, no decimals.
    private func signed0(_ v: Double) -> String { String(format: "%+.0f", v) }
}
