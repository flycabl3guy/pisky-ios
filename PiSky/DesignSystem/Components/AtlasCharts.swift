import SwiftUI

/// Atlas charts — SwiftUI `Canvas` ports of `core/ui/components/AtlasCharts.kt`.
///
/// `TimeSeriesChart`, `MiniTrend`, `BarHistogram` (+ `HistoBar`), `BoxPlotH`,
/// and `ScatterPlot` (+ `ScatterPoint`). Value→pixel math preserved line-for-line:
///   • span = (max−min)·1.12, py = h·(1 − (v−lo)/span), px = w·i/(n−1)
///   • triple stroke glow/mid/sharp + gradient area fill, dashed quartile grid
///   • BoxPlotH: fx(v) = ((v−axisMin)/span)·w; box height 0.55·h
///
/// `Int(_:)`-rounding helper matches Kotlin `roundToInt()`.

private func roundToInt(_ v: Float) -> Int { Int((v).rounded()) }

// MARK: - TimeSeriesChart

/// Premium single-metric time-series chart: glowing line over a gradient area fill,
/// dashed baseline grid, and a tap-to-inspect crosshair surfacing the touched sample.
/// Auto-scales to the series' own min/max with 12% headroom. Short series → flat dim line.
struct TimeSeriesChart: View {
    let values: [Float]
    let label: String
    let unit: String
    var color: Color = Palette.cyan
    var height: CGFloat = 150
    var valueFormat: (Float) -> String = { String(roundToInt($0)) }
    var invertY: Bool = false

    @State private var selected: Int? = nil

    private var mn: Float { values.min() ?? 0 }
    private var mx: Float { values.max() ?? 1 }
    private var pad: Float { max((mx - mn) * 0.12, mx == mn ? 1 : 0) }
    private var lo: Float { mn - pad }
    private var hi: Float { mx + pad }
    private var span: Float { max(hi - lo, 1e-6) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: label + live/selected value
            HStack {
                Text(label.uppercased())
                    .font(.inter(10, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(Palette.textMuted)
                Spacer()
                let shown = selected.flatMap { values.indices.contains($0) ? values[$0] : nil } ?? values.last
                if let shown {
                    Text(valueFormat(shown))
                        .font(.psMono(16, weight: .bold))
                        .foregroundStyle(color)
                    Spacer().frame(width: 3)
                    Text(unit).font(.inter(10)).foregroundStyle(Palette.textMuted)
                }
            }
            .frame(maxWidth: .infinity)
            Spacer().frame(height: 6)

            Canvas { ctx, size in
                let w = size.width, h = size.height
                // dashed grid (quartiles)
                let dash = StrokeStyle(lineWidth: 1, dash: [4, 8])
                for i in 0...4 {
                    let y = h * CGFloat(i) / 4
                    var p = Path(); p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: w, y: y))
                    ctx.stroke(p, with: .color(Palette.outline.opacity(0.5)), style: dash)
                }
                guard values.count >= 2 else {
                    var p = Path(); p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2))
                    ctx.stroke(p, with: .color(Palette.textMuted.opacity(0.3)), style: StrokeStyle(lineWidth: 2))
                    return
                }
                func py(_ v: Float) -> CGFloat {
                    let nv = (v - lo) / span
                    return invertY ? h * CGFloat(nv) : h * CGFloat(1 - nv)
                }
                func px(_ i: Int) -> CGFloat { w * CGFloat(i) / CGFloat(values.count - 1) }

                // area fill
                var area = Path()
                area.move(to: CGPoint(x: 0, y: h))
                for (i, v) in values.enumerated() { area.addLine(to: CGPoint(x: px(i), y: py(v))) }
                area.addLine(to: CGPoint(x: w, y: h)); area.closeSubpath()
                ctx.fill(area, with: .linearGradient(
                    Gradient(colors: [color.opacity(0.34), color.opacity(0.02)]),
                    startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))

                // glow (stacked strokes) + sharp line
                var line = Path()
                for (i, v) in values.enumerated() {
                    let pt = CGPoint(x: px(i), y: py(v))
                    if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
                }
                ctx.stroke(line, with: .color(color.opacity(0.18)), style: StrokeStyle(lineWidth: 7))
                ctx.stroke(line, with: .color(color.opacity(0.35)), style: StrokeStyle(lineWidth: 3.5))
                ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.8))

                // last/selected point + crosshair (clamp: selected can outlive a shrinking series)
                let idx = min(max(selected ?? (values.count - 1), 0), values.count - 1)
                let cx = px(idx), cy = py(values[idx])
                if selected != nil {
                    var cross = Path(); cross.move(to: CGPoint(x: cx, y: 0)); cross.addLine(to: CGPoint(x: cx, y: h))
                    ctx.stroke(cross, with: .color(color.opacity(0.5)), style: StrokeStyle(lineWidth: 1))
                }
                ctx.fill(circlePath(center: CGPoint(x: cx, y: cy), r: 7), with: .color(color.opacity(0.25)))
                ctx.fill(circlePath(center: CGPoint(x: cx, y: cy), r: 3.2), with: .color(color))
            }
            .frame(height: height)
            .overlay(GeometryReader { geo in
                Color.clear.contentShape(Rectangle()).onTapGesture(coordinateSpace: .local) { pt in
                    guard values.count >= 2 else { return }
                    let idx = min(max(roundToInt(Float(pt.x / geo.size.width) * Float(values.count - 1)), 0), values.count - 1)
                    selected = (selected == idx) ? nil : idx
                }
            })

            // min/max footer
            HStack {
                Text("min \(valueFormat(mn))")
                    .font(.psMono(9)).foregroundStyle(Palette.textMuted)
                Spacer()
                Text("max \(valueFormat(mx))")
                    .font(.psMono(9)).foregroundStyle(Palette.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - MiniTrend

/// Compact inline sparkline for tiles (no header).
struct MiniTrend: View {
    let values: [Float]
    var color: Color = Palette.cyan
    var height: CGFloat = 34

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            guard values.count >= 2 else {
                var p = Path(); p.move(to: CGPoint(x: 0, y: h / 2)); p.addLine(to: CGPoint(x: w, y: h / 2))
                ctx.stroke(p, with: .color(color.opacity(0.3)), style: StrokeStyle(lineWidth: 1.5))
                return
            }
            let mn = values.min()!, mx = values.max()!
            let span = max(mx - mn, 1e-6)
            func px(_ i: Int) -> CGFloat { w * CGFloat(i) / CGFloat(values.count - 1) }
            func py(_ v: Float) -> CGFloat { h * CGFloat(1 - (v - mn) / span) }

            var area = Path()
            area.move(to: CGPoint(x: 0, y: h))
            for (i, v) in values.enumerated() { area.addLine(to: CGPoint(x: px(i), y: py(v))) }
            area.addLine(to: CGPoint(x: w, y: h)); area.closeSubpath()
            ctx.fill(area, with: .linearGradient(
                Gradient(colors: [color.opacity(0.30), .clear]),
                startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))

            var line = Path()
            for (i, v) in values.enumerated() {
                let pt = CGPoint(x: px(i), y: py(v))
                if i == 0 { line.move(to: pt) } else { line.addLine(to: pt) }
            }
            ctx.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.6))
            ctx.fill(circlePath(center: CGPoint(x: px(values.count - 1), y: py(values.last!)), r: 2.5),
                     with: .color(color))
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

// MARK: - BarHistogram

/// One bar of a [BarHistogram]. Bars grow from a shared baseline above their labels.
struct HistoBar: Identifiable {
    let id = UUID()
    let label: String
    let value: Float
    let color: Color
}

/// Vertical bar histogram. Bars grow from a shared baseline above their labels.
struct BarHistogram: View {
    let bars: [HistoBar]
    var barAreaHeight: CGFloat = 96
    var valueFormat: (Float) -> String = { String(roundToInt($0)) }

    private var mx: Float { max(bars.map(\.value).max() ?? 1, 1e-6) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ForEach(bars) { b in
                VStack(spacing: 0) {
                    Text(valueFormat(b.value))
                        .font(.psMono(9)).foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    Spacer().frame(height: 3)
                    let frac = min(max(b.value / mx, 0), 1)
                    let barH = max(barAreaHeight * CGFloat(frac), 2)
                    UnevenRoundedRectangle(topLeadingRadius: 3, topTrailingRadius: 3)
                        .fill(LinearGradient(
                            colors: [b.color, b.color.opacity(0.45)],
                            startPoint: .top, endPoint: .bottom))
                        .frame(height: barH)
                        .frame(maxWidth: .infinity)
                        .scaleEffect(x: 0.7, anchor: .center)
                    Spacer().frame(height: 4)
                    Text(b.label)
                        .font(.inter(9)).foregroundStyle(Palette.textMuted)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - BoxPlotH

/// Horizontal box-and-whisker plot. Whisker = min→max, box = Q1→Q3, bright line = median,
/// hollow marker = mean. Axis spans [axisMin, axisMax]. "no data" when quartiles are absent.
struct BoxPlotH: View {
    let min: Double?
    let q1: Double?
    let median: Double?
    let q3: Double?
    let max: Double?
    let avg: Double?
    let axisMin: Float
    let axisMax: Float
    let unit: String
    var color: Color = Palette.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if median == nil || q1 == nil || q3 == nil {
                Text("distribution unavailable")
                    .font(.inter(12)).foregroundStyle(Palette.textMuted)
            } else {
                Canvas { ctx, size in
                    let span = Swift.max(axisMax - axisMin, 1e-3)
                    func fx(_ v: Double) -> CGFloat {
                        CGFloat(Swift.min(Swift.max((Float(v) - axisMin) / span, 0), 1))
                    }
                    let w = size.width, midY = size.height / 2
                    // axis
                    var axis = Path(); axis.move(to: CGPoint(x: 0, y: midY)); axis.addLine(to: CGPoint(x: w, y: midY))
                    ctx.stroke(axis, with: .color(Palette.outline), style: StrokeStyle(lineWidth: 1))

                    let lo = min ?? q1!, hi = max ?? q3!
                    let xLo = fx(lo) * w, xHi = fx(hi) * w
                    // whisker
                    stroke(ctx, [CGPoint(x: xLo, y: midY), CGPoint(x: xHi, y: midY)], color.opacity(0.6), 2)
                    stroke(ctx, [CGPoint(x: xLo, y: midY - 7), CGPoint(x: xLo, y: midY + 7)], color.opacity(0.6), 2)
                    stroke(ctx, [CGPoint(x: xHi, y: midY - 7), CGPoint(x: xHi, y: midY + 7)], color.opacity(0.6), 2)
                    // box Q1..Q3
                    let xQ1 = fx(q1!) * w, xQ3 = fx(q3!) * w
                    let boxH = size.height * 0.55
                    ctx.fill(Path(CGRect(x: xQ1, y: midY - boxH / 2, width: xQ3 - xQ1, height: boxH)),
                             with: .color(color.opacity(0.22)))
                    stroke(ctx, [CGPoint(x: xQ1, y: midY - boxH / 2), CGPoint(x: xQ1, y: midY + boxH / 2)], color, 1.5)
                    stroke(ctx, [CGPoint(x: xQ3, y: midY - boxH / 2), CGPoint(x: xQ3, y: midY + boxH / 2)], color, 1.5)
                    // median
                    let xMed = fx(median!) * w
                    stroke(ctx, [CGPoint(x: xMed, y: midY - boxH / 2 - 2), CGPoint(x: xMed, y: midY + boxH / 2 + 2)], color, 3)
                    // mean marker (hollow circle)
                    if let avg {
                        let c = CGPoint(x: fx(avg) * w, y: midY)
                        ctx.stroke(circlePath(center: c, r: 4), with: .color(Palette.textPrimary), style: StrokeStyle(lineWidth: 1.5))
                    }
                }
                .frame(height: 46)

                HStack {
                    Text(String(format: "%.1f", min ?? q1!))
                        .font(.psMono(9)).foregroundStyle(Palette.textMuted)
                    Spacer()
                    Text("med \(String(format: "%.1f", median!)) \(unit)")
                        .font(.psMono(10, weight: .bold)).foregroundStyle(color)
                    Spacer()
                    Text(String(format: "%.1f", max ?? q3!))
                        .font(.psMono(9)).foregroundStyle(Palette.textMuted)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func stroke(_ ctx: GraphicsContext, _ pts: [CGPoint], _ c: Color, _ w: CGFloat) {
        var p = Path(); p.move(to: pts[0]); for q in pts.dropFirst() { p.addLine(to: q) }
        ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w))
    }
}

// MARK: - ScatterPlot

/// A scatter bubble for [ScatterPlot].
struct ScatterPoint: Identifiable {
    let id = UUID()
    let x: Float
    let y: Float
    let color: Color
    var radius: CGFloat = 4
}

/// Generic scatter plot with axis ticks. Used by the Integrity page to plot the fleet
/// across NACp (x) and NIC (y). `cx = (x/xMax)·w`, `cy = h − (y/yMax)·h`.
struct ScatterPlot: View {
    let points: [ScatterPoint]
    let xMax: Float
    let yMax: Float
    let xLabel: String
    let yLabel: String
    var height: CGFloat = 200
    var grid: Int = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(yLabel).font(.inter(9, weight: .medium)).foregroundStyle(Palette.textMuted)
                Spacer()
                Text("n=\(points.count)").font(.psMono(9)).foregroundStyle(Palette.textMuted)
            }
            .frame(maxWidth: .infinity)
            Spacer().frame(height: 4)

            Canvas { ctx, size in
                let w = size.width, h = size.height
                let dash = StrokeStyle(lineWidth: 1, dash: [3, 7])
                for i in 0...grid {
                    let gx = w * CGFloat(i) / CGFloat(grid), gy = h * CGFloat(i) / CGFloat(grid)
                    var vx = Path(); vx.move(to: CGPoint(x: gx, y: 0)); vx.addLine(to: CGPoint(x: gx, y: h))
                    var hy = Path(); hy.move(to: CGPoint(x: 0, y: gy)); hy.addLine(to: CGPoint(x: w, y: gy))
                    ctx.stroke(vx, with: .color(Palette.outline.opacity(0.4)), style: dash)
                    ctx.stroke(hy, with: .color(Palette.outline.opacity(0.4)), style: dash)
                }
                for p in points {
                    let cx = CGFloat(Swift.min(Swift.max(p.x / xMax, 0), 1)) * w
                    let cy = h - CGFloat(Swift.min(Swift.max(p.y / yMax, 0), 1)) * h
                    ctx.fill(circlePath(center: CGPoint(x: cx, y: cy), r: p.radius * 2.2), with: .color(p.color.opacity(0.18)))
                    ctx.fill(circlePath(center: CGPoint(x: cx, y: cy), r: p.radius), with: .color(p.color))
                }
            }
            .frame(height: height)

            Text(xLabel)
                .font(.inter(9, weight: .medium)).foregroundStyle(Palette.textMuted)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - shared helper

/// A filled-circle `Path` centered at `center` with radius `r`.
func circlePath(center: CGPoint, r: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
}

#Preview {
    ScrollView {
        VStack(spacing: 20) {
            TimeSeriesChart(values: [3, 7, 5, 9, 6, 11, 8, 14], label: "Range", unit: "nm", color: Palette.cyan)
            MiniTrend(values: [1, 3, 2, 5, 4, 6])
            BarHistogram(bars: [
                HistoBar(label: "0-5k", value: 12, color: Palette.statusError),
                HistoBar(label: "5-20k", value: 30, color: Palette.cyan),
                HistoBar(label: ">20k", value: 18, color: Palette.brass),
            ])
            BoxPlotH(min: -40, q1: -28, median: -22, q3: -16, max: -8, avg: -23,
                     axisMin: -50, axisMax: 0, unit: "dB")
            ScatterPlot(points: (0..<20).map { _ in
                ScatterPoint(x: .random(in: 0...11), y: .random(in: 0...11), color: Palette.cyan)
            }, xMax: 11, yMax: 11, xLabel: "NACp", yLabel: "NIC")
        }
        .padding()
    }
    .background(Palette.background)
}
