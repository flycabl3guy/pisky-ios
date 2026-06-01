import SwiftUI

/// In-memory ring buffer of recent altitude readings, keyed by aircraft hex. Survives sheet
/// open/close so the trend is immediate when re-opening the same target; trimmed when the buffer
/// exceeds the soft LRU cap. Ported from the `AltitudeHistory` object in `AltitudeSparkline.kt`.
///
/// `@MainActor` because the only callers are SwiftUI views on the main actor — keeps it lock-free
/// (the Kotlin original synchronized because Compose recomposition could touch it off-thread).
@MainActor
enum AltitudeHistory {
    private static let maxSamples = 60      // ~60 ticks ≈ 60 s at 1 Hz
    private static let maxHexes   = 200      // soft LRU cap

    struct Sample { let timestampMs: Int64; let altitudeFt: Int }

    // Insertion-ordered store: keys array tracks LRU order, dict holds the deques.
    private static var order: [String] = []
    private static var buffer: [String: [Sample]] = [:]

    static func push(hex: String, altitudeFt: Int) {
        var q = buffer[hex] ?? []
        // Skip duplicate consecutive readings — no point storing identical samples.
        if q.last?.altitudeFt == altitudeFt { return }
        q.append(Sample(timestampMs: Int64(Date().timeIntervalSince1970 * 1000), altitudeFt: altitudeFt))
        while q.count > maxSamples { q.removeFirst() }
        if buffer[hex] == nil { order.append(hex) }
        buffer[hex] = q
        // Trim coldest hexes when over cap.
        while order.count > maxHexes {
            let cold = order.removeFirst()
            buffer.removeValue(forKey: cold)
        }
    }

    static func get(_ hex: String) -> [Sample] { buffer[hex] ?? [] }
}

/// Compact 60-sample altitude sparkline with a net-delta readout. Canvas line + gradient fill +
/// trailing dot. Ported from `AltitudeSparkline.kt`.
struct AltitudeSparkline: View {
    let aircraft: Aircraft
    var lineColor: Color

    @State private var samples: [AltitudeHistory.Sample] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("ALTITUDE TREND  ·  60s")
                    .font(.psMono(10, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(Palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if samples.count >= 2 {
                    Text(deltaText)
                        .font(.psMono(10, weight: .medium))
                        .foregroundStyle(lineColor)
                }
            }
            Spacer().frame(height: 6)
            ZStack {
                LinearGradient(
                    colors: [lineColor.opacity(0.04), .clear],
                    startPoint: .top, endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                if samples.count < 2 {
                    Text("Collecting samples…")
                        .font(.psMono(10, weight: .medium))
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    Canvas { ctx, size in draw(in: ctx, size: size) }
                }
            }
            .frame(height: 48)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(Palette.cardElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Capture each altitude tick into the per-hex ring buffer, then refresh local samples.
        .task(id: SparkKey(hex: aircraft.hex, alt: aircraft.altitudeBaro, seen: aircraft.seen)) {
            if let alt = aircraft.altitudeBaro {
                AltitudeHistory.push(hex: aircraft.hex, altitudeFt: alt)
            }
            samples = AltitudeHistory.get(aircraft.hex)
        }
    }

    private var deltaText: String {
        let first = samples.first!.altitudeFt
        let last = samples.last!.altitudeFt
        let delta = last - first
        let prefix = delta > 0 ? "↑ +" : (delta < 0 ? "↓ " : "→ ")
        return "\(prefix)\(Fmt.grouped(abs(delta))) ft"
    }

    private func draw(in ctx: GraphicsContext, size: CGSize) {
        let w = size.width, h = size.height
        let pad: CGFloat = 4
        let n = samples.count
        let alts = samples.map(\.altitudeFt)
        let minA = alts.min() ?? 0
        let maxA = alts.max() ?? 0
        let rangeA = CGFloat(max(maxA - minA, 1))

        func xFor(_ i: Int) -> CGFloat { pad + (w - 2 * pad) * CGFloat(i) / CGFloat(max(n - 1, 1)) }
        func yFor(_ alt: Int) -> CGFloat {
            let norm = CGFloat(alt - minA) / rangeA
            return h - pad - (h - 2 * pad) * norm
        }

        var line = Path()
        line.move(to: CGPoint(x: xFor(0), y: yFor(samples[0].altitudeFt)))
        for i in 1..<n { line.addLine(to: CGPoint(x: xFor(i), y: yFor(samples[i].altitudeFt))) }

        var fill = Path()
        fill.move(to: CGPoint(x: xFor(0), y: h))
        fill.addLine(to: CGPoint(x: xFor(0), y: yFor(samples[0].altitudeFt)))
        for i in 1..<n { fill.addLine(to: CGPoint(x: xFor(i), y: yFor(samples[i].altitudeFt))) }
        fill.addLine(to: CGPoint(x: xFor(n - 1), y: h))
        fill.closeSubpath()

        ctx.fill(fill, with: .linearGradient(
            Gradient(colors: [lineColor.opacity(0.35), lineColor.opacity(0.02)]),
            startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: h)))
        ctx.stroke(line, with: .color(lineColor), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))

        let last = CGPoint(x: xFor(n - 1), y: yFor(samples[n - 1].altitudeFt))
        ctx.fill(Path(ellipseIn: CGRect(x: last.x - 7, y: last.y - 7, width: 14, height: 14)),
                 with: .color(lineColor.opacity(0.25)))
        ctx.fill(Path(ellipseIn: CGRect(x: last.x - 3.2, y: last.y - 3.2, width: 6.4, height: 6.4)),
                 with: .color(lineColor))
    }

    /// Equatable key that retriggers the capture task on hex / altitude / seen changes.
    private struct SparkKey: Equatable { let hex: String; let alt: Int?; let seen: Double }
}
