import SwiftUI

/// `RadarHero` — the v6 home-screen instrument face. Port of `v6/RadarHero.kt`.
///
/// A 1:1 square `Canvas`: graphite radial-gradient floor with a brass bezel; brass range rings at
/// 50/100/150/200/250 nm (fixed 250 nm scope); a 30° compass rose with N/E/S/W labels; a cyan sweep
/// revolving once per 8 s leaving a 72° fading wedge; aircraft pings placed by (distance_nm,
/// bearing_deg), glyph by emitter category, color by altitude band, lighting up as the sweep crosses
/// them; a brass tag on the nearest contact; and symmetrical FARTHEST (bottom-left) / NEAREST
/// (bottom-right) rosters drawn directly on the scope.
struct RadarHero: View {
    let aircraft: [Aircraft]
    /// Kept for API parity with the Android signature; the scope is fixed at 250 nm.
    var maxRangeNm: Double = 250

    private static let effectiveRange = 250.0

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let sweepDeg = (t.truncatingRemainder(dividingBy: HangarLuxe.Sweep.revolution)
                            / HangarLuxe.Sweep.revolution) * 360.0
            Canvas { ctx, size in
                let cx = size.width / 2, cy = size.height / 2
                let origin = CGPoint(x: cx, y: cy)
                let maxRadius = min(size.width, size.height) / 2 * 0.92
                let pxPerNm = maxRadius / CGFloat(Self.effectiveRange)

                drawScopeBackground(ctx, origin, maxRadius)
                drawRangeRings(ctx, origin, maxRadius)
                drawCompassMarks(ctx, origin, maxRadius)
                drawSweep(ctx, origin, maxRadius, sweepDeg)
                drawPings(ctx, origin, sweepDeg, pxPerNm, maxRadius)
                drawNearestTag(ctx, origin, pxPerNm, maxRadius)
                drawCenterMark(ctx, origin)
                drawFarthestRoster(ctx, origin, maxRadius)
                drawNearestRoster(ctx, origin, maxRadius)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // ── Background ───────────────────────────────────────────────────────────
    private func drawScopeBackground(_ ctx: GraphicsContext, _ origin: CGPoint, _ r: CGFloat) {
        let circle = Path(ellipseIn: CGRect(x: origin.x - r, y: origin.y - r, width: r * 2, height: r * 2))
        ctx.fill(circle, with: .radialGradient(
            Gradient(colors: [Color(hex: 0x11141B), Color(hex: 0x0C0E14), Palette.background]),
            center: origin, startRadius: 0, endRadius: r))
        ctx.stroke(circle, with: .color(brass(0.42)), lineWidth: 1.8)
        let rim = Path(ellipseIn: CGRect(x: origin.x - r - 4, y: origin.y - r - 4, width: (r + 4) * 2, height: (r + 4) * 2))
        ctx.stroke(rim, with: .color(brass(0.14)), lineWidth: 0.8)
    }

    // ── Range rings ──────────────────────────────────────────────────────────
    private func drawRangeRings(_ ctx: GraphicsContext, _ origin: CGPoint, _ maxRadius: CGFloat) {
        let step = 50.0   // 250 nm scope → 50/100/150/200/250
        var r = step
        while r <= Self.effectiveRange + 0.5 {
            let px = CGFloat(r / Self.effectiveRange) * maxRadius
            ctx.stroke(Path(ellipseIn: CGRect(x: origin.x - px, y: origin.y - px, width: px * 2, height: px * 2)),
                       with: .color(brass(0.22)), lineWidth: 1.0)
            ctx.draw(Text("\(Int(r))").font(.psMono(11)).foregroundStyle(brass(0.55)),
                     at: CGPoint(x: origin.x + px + 10, y: origin.y), anchor: .leading)
            r += step
        }
    }

    // ── Compass marks ──────────────────────────────────────────────────────────
    private func drawCompassMarks(_ ctx: GraphicsContext, _ origin: CGPoint, _ maxRadius: CGFloat) {
        for deg in stride(from: 0, to: 360, by: 30) {
            let rad = Double(deg - 90).radians
            let inner = deg % 90 == 0 ? maxRadius - 12 : maxRadius - 6
            var p = Path()
            p.move(to: CGPoint(x: origin.x + inner * CGFloat(cos(rad)), y: origin.y + inner * CGFloat(sin(rad))))
            p.addLine(to: CGPoint(x: origin.x + maxRadius * CGFloat(cos(rad)), y: origin.y + maxRadius * CGFloat(sin(rad))))
            ctx.stroke(p, with: .color(brass(deg % 90 == 0 ? 0.65 : 0.30)), lineWidth: deg % 90 == 0 ? 2 : 1)
        }
        for (deg, label) in [(0, "N"), (90, "E"), (180, "S"), (270, "W")] {
            let rad = Double(deg - 90).radians
            let r = maxRadius - 32
            let pos = CGPoint(x: origin.x + r * CGFloat(cos(rad)), y: origin.y + r * CGFloat(sin(rad)))
            ctx.draw(Text(label).font(.psMono(14, weight: .bold)).foregroundStyle(Palette.brassBright), at: pos)
        }
    }

    // ── Sweep ────────────────────────────────────────────────────────────────
    private func drawSweep(_ ctx: GraphicsContext, _ origin: CGPoint, _ maxRadius: CGFloat, _ sweepDeg: Double) {
        let trailDeg = HangarLuxe.Sweep.trailDegrees
        let rad0 = (sweepDeg - 90).radians
        var wedge = Path()
        wedge.move(to: origin)
        wedge.addLine(to: CGPoint(x: origin.x + maxRadius * CGFloat(cos(rad0)),
                                  y: origin.y + maxRadius * CGFloat(sin(rad0))))
        wedge.addArc(center: origin, radius: maxRadius,
                     startAngle: .degrees(sweepDeg - 90),
                     endAngle: .degrees(sweepDeg - 90 - trailDeg),
                     clockwise: true)
        wedge.closeSubpath()
        // Soft fade behind the lead edge.
        ctx.fill(wedge, with: .linearGradient(
            Gradient(colors: [cyan(0.22), cyan(0.04), .clear]),
            startPoint: CGPoint(x: origin.x + maxRadius * CGFloat(cos(rad0)),
                                y: origin.y + maxRadius * CGFloat(sin(rad0))),
            endPoint: origin))
        // Sharp leading line.
        let tip = CGPoint(x: origin.x + maxRadius * CGFloat(cos(rad0)), y: origin.y + maxRadius * CGFloat(sin(rad0)))
        var lead = Path(); lead.move(to: origin); lead.addLine(to: tip)
        ctx.stroke(lead, with: .color(Palette.cyan), lineWidth: 2.4)
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 6, y: tip.y - 6, width: 12, height: 12)), with: .color(cyan(0.55)))
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 12, y: tip.y - 12, width: 24, height: 24)), with: .color(cyan(0.25)))
    }

    // ── Pings ────────────────────────────────────────────────────────────────
    private func drawPings(_ ctx: GraphicsContext, _ origin: CGPoint, _ sweepDeg: Double,
                          _ pxPerNm: CGFloat, _ maxRadius: CGFloat) {
        for ac in aircraft {
            guard let dist = ac.distanceNm, let brg = ac.bearingDeg,
                  dist > 0, CGFloat(dist) * pxPerNm <= maxRadius else { continue }
            let pos = polarToOffset(origin: origin, distanceNm: dist, bearingDeg: brg, pixelsPerNm: pxPerNm)

            let delta = ((sweepDeg - brg).truncatingRemainder(dividingBy: 360) + 360)
                .truncatingRemainder(dividingBy: 360)
            let excitement = delta < HangarLuxe.Sweep.trailDegrees
                ? 1 - (delta / HangarLuxe.Sweep.trailDegrees) : 0
            let base = altitudeColor(ac.altitudeBaro, ac.emergency)
            let excited = lerp(base, Palette.cyan, excitement * 0.55)
            let outline = lerp(Palette.brassBright, base, 0.55)

            if excitement > 0.05 {
                let hr = CGFloat(18 + excitement * 16)
                ctx.fill(Path(ellipseIn: CGRect(x: pos.x - hr, y: pos.y - hr, width: hr * 2, height: hr * 2)),
                         with: .color(excited.opacity(excitement * 0.30)))
            }
            // Aft trail dot when moving.
            if let track = ac.track, let gs = ac.groundSpeed, gs > 30 {
                let backRad = (track + 90).radians
                let tp = CGPoint(x: pos.x + 10 * CGFloat(cos(backRad)), y: pos.y + 10 * CGFloat(sin(backRad)))
                ctx.fill(Path(ellipseIn: CGRect(x: tp.x - 4, y: tp.y - 4, width: 8, height: 8)),
                         with: .color(base.opacity(0.18)))
            }
            let kind = glyphKindFor(category: ac.category, isMilitary: ac.isMilitary, isOnGround: ac.isOnGround)
            let heading = ac.track ?? ac.trueHeading ?? ac.magHeading ?? brg
            let rPx: CGFloat
            switch kind {
            case .heavy, .mil:     rPx = 11
            case .jet, .medium:    rPx = 9
            case .heli, .ground:   rPx = 8
            default:               rPx = 7
            }
            ctx.drawAircraftGlyph(kind, center: pos, headingDeg: heading, radius: rPx, fill: excited, outline: outline)

            if ac.emergency != .none {
                ctx.stroke(Path(ellipseIn: CGRect(x: pos.x - 24, y: pos.y - 24, width: 48, height: 48)),
                           with: .color(Palette.emergencyRed.opacity(0.45)), lineWidth: 2)
            }
        }
    }

    // ── Nearest tag ──────────────────────────────────────────────────────────
    private func drawNearestTag(_ ctx: GraphicsContext, _ origin: CGPoint, _ pxPerNm: CGFloat, _ maxRadius: CGFloat) {
        guard let nearest = aircraft
            .filter({ ($0.distanceNm ?? 0) > 0 && $0.bearingDeg != nil })
            .min(by: { $0.distanceNm! < $1.distanceNm! }) else { return }
        let pos = polarToOffset(origin: origin, distanceNm: nearest.distanceNm!,
                                bearingDeg: nearest.bearingDeg!, pixelsPerNm: pxPerNm)
        let tag = CGPoint(x: pos.x + 18, y: pos.y - 22)
        var line = Path(); line.move(to: pos); line.addLine(to: tag)
        ctx.stroke(line, with: .color(brass(0.55)), lineWidth: 1)
        let alt = nearest.altitudeBaro.map { "\(Fmt.grouped($0)) ft" } ?? "—"
        let dist = String(format: "%.1f nm", nearest.distanceNm!)
        ctx.draw(Text(nearest.displayCallsign).font(.psMono(13, weight: .bold)).foregroundStyle(Palette.brassBright),
                 at: tag, anchor: .bottomLeading)
        ctx.draw(Text("\(alt) · \(dist)").font(.psMono(10)).foregroundStyle(Palette.textMuted),
                 at: CGPoint(x: tag.x, y: tag.y + 14), anchor: .topLeading)
    }

    private func drawCenterMark(_ ctx: GraphicsContext, _ origin: CGPoint) {
        ctx.fill(Path(ellipseIn: CGRect(x: origin.x - 3.5, y: origin.y - 3.5, width: 7, height: 7)), with: .color(brass(0.85)))
        ctx.fill(Path(ellipseIn: CGRect(x: origin.x - 1.5, y: origin.y - 1.5, width: 3, height: 3)), with: .color(Palette.brass))
        var h = Path(); h.move(to: CGPoint(x: origin.x - 7, y: origin.y)); h.addLine(to: CGPoint(x: origin.x + 7, y: origin.y))
        var v = Path(); v.move(to: CGPoint(x: origin.x, y: origin.y - 7)); v.addLine(to: CGPoint(x: origin.x, y: origin.y + 7))
        ctx.stroke(h, with: .color(brass(0.40)), lineWidth: 1)
        ctx.stroke(v, with: .color(brass(0.40)), lineWidth: 1)
    }

    // ── Rosters ────────────────────────────────────────────────────────────────
    private func drawFarthestRoster(_ ctx: GraphicsContext, _ origin: CGPoint, _ maxRadius: CGFloat) {
        let rows = aircraft.filter { ($0.distanceNm ?? 0) > 0 && $0.bearingDeg != nil }
            .sorted { $0.distanceNm! > $1.distanceNm! }.prefix(6).map { $0 }
        guard !rows.isEmpty else { return }
        drawRosterBlock(ctx, baseX: origin.x - maxRadius * 0.95, baseY: origin.y + maxRadius * 0.42,
                        title: "FARTHEST", subtitle: "long-range contacts", rows: rows)
    }

    private func drawNearestRoster(_ ctx: GraphicsContext, _ origin: CGPoint, _ maxRadius: CGFloat) {
        let rows = aircraft.filter { ($0.distanceNm ?? 0) > 0 && $0.bearingDeg != nil }
            .sorted { $0.distanceNm! < $1.distanceNm! }.prefix(6).map { $0 }
        guard !rows.isEmpty else { return }
        drawRosterBlock(ctx, baseX: origin.x + maxRadius * 0.95 - 200, baseY: origin.y + maxRadius * 0.42,
                        title: "NEAREST", subtitle: "closest contacts", rows: rows)
    }

    private func drawRosterBlock(_ ctx: GraphicsContext, baseX: CGFloat, baseY: CGFloat,
                                title: String, subtitle: String, rows: [Aircraft]) {
        ctx.draw(Text(title).font(.psMono(16, weight: .bold)).foregroundStyle(Palette.brassBright),
                 at: CGPoint(x: baseX, y: baseY), anchor: .topLeading)
        ctx.draw(Text(subtitle).font(.psMono(10)).foregroundStyle(Palette.textMuted),
                 at: CGPoint(x: baseX, y: baseY + 18), anchor: .topLeading)
        var div = Path(); div.move(to: CGPoint(x: baseX, y: baseY + 34)); div.addLine(to: CGPoint(x: baseX + 200, y: baseY + 34))
        ctx.stroke(div, with: .color(brass(0.42)), lineWidth: 1.2)
        let firstRowY = baseY + 46
        for (i, ac) in rows.enumerated() {
            let y = firstRowY + CGFloat(i) * 17
            let tint = ac.isMilitary ? Palette.brassBright : Palette.cyanDim
            ctx.draw(Text(String(ac.displayCallsign.padding(toLength: 8, withPad: " ", startingAt: 0)))
                .font(.psMono(12, weight: .bold)).foregroundStyle(tint),
                     at: CGPoint(x: baseX, y: y), anchor: .topLeading)
            ctx.draw(Text(bearingToCardinal(ac.bearingDeg!)).font(.psMono(11)).foregroundStyle(brass(0.80)),
                     at: CGPoint(x: baseX + 95, y: y), anchor: .topLeading)
            ctx.draw(Text(String(format: "%.1f nm", ac.distanceNm!)).font(.psMono(11)).foregroundStyle(Palette.textPrimary),
                     at: CGPoint(x: baseX + 135, y: y), anchor: .topLeading)
        }
    }

    private func bearingToCardinal(_ deg: Double) -> String {
        let d = deg.truncatingRemainder(dividingBy: 360).magnitude
        switch d {
        case ..<22.5:  return "N"
        case ..<67.5:  return "NE"
        case ..<112.5: return "E"
        case ..<157.5: return "SE"
        case ..<202.5: return "S"
        case ..<247.5: return "SW"
        case ..<292.5: return "W"
        case ..<337.5: return "NW"
        default:       return "N"
        }
    }

    // ── Color helpers ────────────────────────────────────────────────────────
    private func brass(_ a: Double) -> Color { Palette.brass.opacity(a) }
    private func cyan(_ a: Double) -> Color { Palette.cyan.opacity(a) }

    private func altitudeColor(_ altFt: Int?, _ emergency: Emergency) -> Color {
        if emergency != .none { return Palette.emergencyRed }
        switch altFt {
        case .none:                          return Palette.cyanDim
        case .some(let a) where a < 5_000:   return Palette.altLow
        case .some(let a) where a < 20_000:  return Palette.altMid
        default:                             return Palette.altHigh
        }
    }

    private func lerp(_ a: Color, _ b: Color, _ t: Double) -> Color {
        let tt = min(max(t, 0), 1)
        let ca = UIColor(a), cb = UIColor(b)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ca.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        cb.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(.sRGB,
                     red: ar + (br - ar) * tt, green: ag + (bg - ag) * tt,
                     blue: ab + (bb - ab) * tt, opacity: aa + (ba - aa) * tt)
    }
}
