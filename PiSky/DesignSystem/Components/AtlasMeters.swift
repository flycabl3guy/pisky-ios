import SwiftUI

/// Atlas meters — SwiftUI `Canvas` ports of `core/ui/components/AtlasMeters.kt`.
///
/// `RadialMeter` (270° arc from 135°, tick ring, glow) and `RingStat` (full circle).
/// Fill animates to new values via `.animation(_:value:)`. Angle convention matches Compose
/// `drawArc` (degrees, clockwise, 0° = +x axis); ticks use `cos/sin` on radians.

private func deg2rad(_ d: Double) -> Double { d * .pi / 180 }

// MARK: - RadialMeter

/// Premium 270° arc gauge — track + glowing filled arc + tick ring, with a centred
/// value/unit/label stack. Animates to new values. Starts at 135°, sweeps 270°.
struct RadialMeter: View {
    let value: Float
    let min: Float
    let max: Float
    let label: String
    let unit: String
    var diameter: CGFloat = 132
    var color: Color = Palette.cyan
    var valueText: String? = nil

    private var frac: CGFloat {
        CGFloat(Swift.min(Swift.max((value - min) / (max - min), 0), 1))
    }

    @State private var animated: CGFloat = 0

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let minDim = Swift.min(size.width, size.height)
                let stroke = minDim * 0.085
                let inset = stroke / 2 + minDim * 0.02
                let rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)
                let startAngle = 135.0
                let sweepFull = 270.0

                let cx = size.width / 2, cy = size.height / 2
                let rOuter = minDim / 2 - inset * 0.2
                let rInner = rOuter - stroke * 0.7

                // tick ring
                for i in 0...30 {
                    let a = deg2rad(startAngle + sweepFull * Double(i) / 30)
                    let major = i % 5 == 0
                    let r2 = major ? rInner - stroke * 0.35 : rInner
                    var tick = Path()
                    tick.move(to: CGPoint(x: cx + rOuter * cos(a), y: cy + rOuter * sin(a)))
                    tick.addLine(to: CGPoint(x: cx + r2 * cos(a), y: cy + r2 * sin(a)))
                    ctx.stroke(tick, with: .color(Palette.outline.opacity(major ? 0.9 : 0.45)),
                               style: StrokeStyle(lineWidth: major ? 1.6 : 1))
                }

                // background track
                ctx.stroke(arcPath(rect: rect, start: startAngle, sweep: sweepFull),
                           with: .color(Palette.outline.opacity(0.55)),
                           style: StrokeStyle(lineWidth: stroke, lineCap: .round))

                // glow + active arc
                let sweep = sweepFull * Double(animated)
                if sweep > 0 {
                    ctx.stroke(arcPath(rect: rect, start: startAngle, sweep: sweep),
                               with: .color(color.opacity(0.22)),
                               style: StrokeStyle(lineWidth: stroke * 1.9, lineCap: .round))
                    ctx.stroke(arcPath(rect: rect, start: startAngle, sweep: sweep),
                               with: .color(color),
                               style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                }
            }

            VStack(spacing: 0) {
                Text(valueText ?? String(Int(value)))
                    .font(.psMono(26, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text(unit).font(.inter(10)).foregroundStyle(Palette.textMuted)
                Spacer().frame(height: 2)
                Text(label.uppercased())
                    .font(.inter(9, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(color)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear { withAnimation(.easeInOut(duration: 0.6)) { animated = frac } }
        .onChange(of: frac) { _, new in withAnimation(.easeInOut(duration: 0.6)) { animated = new } }
    }
}

// MARK: - RingStat

/// Full-circle ring stat for compact tiles. Sweeps from −90° (top) clockwise.
struct RingStat: View {
    let fraction: Double
    let centerText: String
    let label: String
    var diameter: CGFloat = 84
    var color: Color = Palette.cyan

    private var target: CGFloat { CGFloat(Swift.min(Swift.max(fraction, 0), 1)) }
    @State private var animated: CGFloat = 0

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let minDim = Swift.min(size.width, size.height)
                let stroke = minDim * 0.11
                let inset = stroke / 2
                let rect = CGRect(x: inset, y: inset, width: size.width - inset * 2, height: size.height - inset * 2)

                ctx.stroke(arcPath(rect: rect, start: -90, sweep: 360),
                           with: .color(Palette.outline.opacity(0.5)),
                           style: StrokeStyle(lineWidth: stroke))
                let sweep = 360.0 * Double(animated)
                if sweep > 0 {
                    ctx.stroke(arcPath(rect: rect, start: -90, sweep: sweep),
                               with: .color(color.opacity(0.2)),
                               style: StrokeStyle(lineWidth: stroke * 1.7))
                    ctx.stroke(arcPath(rect: rect, start: -90, sweep: sweep),
                               with: .color(color),
                               style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                }
            }

            VStack(spacing: 0) {
                Text(centerText)
                    .font(.psMono(15, weight: .bold))
                    .foregroundStyle(Palette.textPrimary)
                Text(label.uppercased())
                    .font(.inter(8)).tracking(0.5)
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .frame(width: diameter, height: diameter)
        .onAppear { withAnimation(.easeInOut(duration: 0.5)) { animated = target } }
        .onChange(of: target) { _, new in withAnimation(.easeInOut(duration: 0.5)) { animated = new } }
    }
}

// MARK: - shared arc helper

/// An open arc `Path` matching Compose `drawArc(startAngle, sweepAngle)` semantics:
/// angles in degrees, 0° = +x axis, positive = clockwise (SwiftUI screen coords).
func arcPath(rect: CGRect, start: Double, sweep: Double) -> Path {
    var p = Path()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    let radius = rect.width / 2
    p.addArc(center: center, radius: radius,
             startAngle: .degrees(start), endAngle: .degrees(start + sweep), clockwise: false)
    return p
}

#Preview {
    HStack(spacing: 24) {
        RadialMeter(value: 187, min: 0, max: 250, label: "Range", unit: "nm", color: qualityColor(0.75))
        RingStat(fraction: 0.68, centerText: "68%", label: "Integ", color: Palette.brass)
    }
    .padding()
    .background(Palette.background)
}
