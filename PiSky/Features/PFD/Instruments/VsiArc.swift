import SwiftUI

/// Vertical Speed Indicator — Boeing 737 PFD style.
/// Range ±6000 fpm, log-spaced labels at 1, 2, 6 (thousand fpm).
/// White pointer + digital readout (shown only when |VS| > 400 fpm).
///
/// Log scale: position(fpm) = sign · ln(1 + |fpm|/100) / ln(1 + 6000/100) — wide
/// spread at low fpm, narrow at high fpm, matching the 737 VSI's tighter
/// top/bottom tick spacing. Positive fpm → up (smaller y).
///
/// Ports `feature/pfd/instruments/VsiArc.kt`.
struct VsiArc: View {
    let verticalRateFpm: Int?

    /// y = h/2 − norm·(h/2 − 8), norm = sign·ln(1+|fpm|/100)/ln(1+6000/100).
    private func yFromFpm(_ fpm: Double, _ h: CGFloat) -> CGFloat {
        let maxLog = log(1.0 + 6000.0 / 100.0)
        let s: Double = fpm > 0 ? 1 : (fpm < 0 ? -1 : 0)
        let norm = s * log(1.0 + abs(fpm) / 100.0) / maxLog
        return h / 2 - CGFloat(norm) * (h / 2 - 8)
    }

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cy = h / 2
            let vs = Double(verticalRateFpm ?? 0)

            // Center reference line
            var center = Path()
            center.move(to: CGPoint(x: 0, y: cy))
            center.addLine(to: CGPoint(x: w / 2, y: cy))
            ctx.stroke(center, with: .color(PfdColors.white), lineWidth: 1.5)

            // Major ticks at ±1000, ±2000, ±6000
            for fpm in [-6000, -2000, -1000, 1000, 2000, 6000] {
                let y = yFromFpm(Double(fpm), h)
                var tick = Path()
                tick.move(to: CGPoint(x: 0, y: y))
                tick.addLine(to: CGPoint(x: w / 3, y: y))
                ctx.stroke(tick, with: .color(PfdColors.white), lineWidth: 1.5)
                let label = "\(abs(fpm) / 1000)"
                let txt = ctx.resolve(Text(label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(PfdColors.white))
                ctx.draw(txt, at: CGPoint(x: w / 3 + 4, y: y), anchor: .leading)
            }

            // Minor ticks at ±500, ±1500
            for fpm in [-1500, -500, 500, 1500] {
                let y = yFromFpm(Double(fpm), h)
                var tick = Path()
                tick.move(to: CGPoint(x: 0, y: y))
                tick.addLine(to: CGPoint(x: w / 5, y: y))
                ctx.stroke(tick, with: .color(PfdColors.white), lineWidth: 1)
            }

            // Pointer — moving needle from left edge to value point
            let ny = yFromFpm(vs, h)
            var needle = Path()
            needle.move(to: CGPoint(x: 0, y: cy))
            needle.addLine(to: CGPoint(x: w * 0.7, y: ny))
            ctx.stroke(needle, with: .color(PfdColors.white), lineWidth: 3)

            // Digital readout — only when |VS| > 400 fpm
            let vr = verticalRateFpm ?? 0
            if abs(vr) > 400 {
                let sign = vr > 0 ? "+" : ""
                let txt = "\(sign)\(vr)"
                let ro = ctx.resolve(Text(txt)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(PfdColors.white))
                let roSize = ro.measure(in: size)
                let ry: CGFloat = vr > 0 ? 2 : (h - roSize.height - 2)
                ctx.draw(ro, at: CGPoint(x: w / 2, y: ry + roSize.height / 2), anchor: .center)
            }
        }
        .background(PfdColors.tapePanel)
    }
}
