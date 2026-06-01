import SwiftUI

/// `RadarScopeCanvas` — the SECONDARY "Scope" map mode. Pure-`Canvas` port of the STARS/ERAM look
/// from `RadarScope2Overlay.kt` (phosphor-green CRT aesthetic): revolving sweep, dashed range rings
/// with a 10° compass rose, heading-rotated diamond targets, smart-placed data blocks, and a
/// receiver crosshair.
///
/// On Android this overlaid an OSMdroid `MapView` (which supplied the projection). iOS has no map
/// underneath in this mode, so the scope is self-contained: it uses the same equirectangular
/// projection as the Radar feature (mapping doc §"Radar"), centered on the receiver, with a fixed
/// scale chosen so the outermost (200 nm) ring fits the smaller screen dimension.
struct RadarScopeCanvas: View {
    let aircraft: [Aircraft]
    let receiverLat: Double
    let receiverLon: Double
    let selectedHex: String?
    var onSelect: (String) -> Void

    private static let ringsNm: [Double] = [25, 50, 75, 100, 125, 150, 175, 200].map { $0 / 1.15078 }
    private static let maxRingNm = 200.0 / 1.15078

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let maxRadius = min(size.width, size.height) / 2 * 0.92
            let pxPerNm = maxRadius / Self.maxRingNm

            TimelineView(.animation) { timeline in
                // 8 s revolution (matches the 8000 ms Android tween).
                let t = timeline.date.timeIntervalSinceReferenceDate
                let sweepDeg = (t.truncatingRemainder(dividingBy: 8.0) / 8.0) * 360.0

                Canvas { ctx, _ in
                    drawSweep(ctx, center: center, angleDeg: sweepDeg, radius: max(size.width, size.height))
                    drawRingsAndCompass(ctx, center: center, pxPerNm: pxPerNm)

                    let acWithPos = aircraft.filter(\.hasPosition)
                    drawVelocityVectors(ctx, acWithPos, center: center, pxPerNm: pxPerNm)
                    drawTargets(ctx, acWithPos, center: center, pxPerNm: pxPerNm)
                    drawDataBlocks(ctx, acWithPos, center: center, pxPerNm: pxPerNm)
                    drawCrosshair(ctx, center: center)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { value in
                    selectNearest(at: value.location, center: center, pxPerNm: pxPerNm)
                }
            )
        }
        .background(Palette.background)
    }

    // ── Projection (equirectangular, centered on receiver) ─────────────────────
    private func project(_ lat: Double, _ lon: Double, center: CGPoint, pxPerNm: CGFloat) -> CGPoint {
        let dx = (lon - receiverLon) * 60 * cos(receiverLat.radians)
        let dy = -(lat - receiverLat) * 60
        return CGPoint(x: center.x + CGFloat(dx) * pxPerNm, y: center.y + CGFloat(dy) * pxPerNm)
    }

    /// Tap-select nearest projected target within 48 pt (mirrors the Radar feature's tolerance).
    private func selectNearest(at point: CGPoint, center: CGPoint, pxPerNm: CGFloat) {
        var best: Aircraft?
        var bestDist: CGFloat = 48
        for ac in aircraft {
            guard let lat = ac.latitude, let lon = ac.longitude else { continue }
            let p = project(lat, lon, center: center, pxPerNm: pxPerNm)
            let d = hypot(p.x - point.x, p.y - point.y)
            if d < bestDist { bestDist = d; best = ac }
        }
        if let hex = best?.hex { HangarHaptics.select(); onSelect(hex) }
    }

    // ── 1. Sweep ─────────────────────────────────────────────────────────────
    private func drawSweep(_ ctx: GraphicsContext, center: CGPoint, angleDeg: Double, radius: CGFloat) {
        let lead = (angleDeg - 90).radians
        var line = Path()
        line.move(to: center)
        line.addLine(to: CGPoint(x: center.x + radius * CGFloat(cos(lead)),
                                 y: center.y + radius * CGFloat(sin(lead))))
        ctx.stroke(line, with: .color(Self.sweepGreen.opacity(0.18)), lineWidth: 1.2)
    }

    // ── 2. Range rings + compass rose ──────────────────────────────────────────
    private func drawRingsAndCompass(_ ctx: GraphicsContext, center: CGPoint, pxPerNm: CGFloat) {
        let dash = StrokeStyle(lineWidth: 1.2, dash: [12, 8])
        for nm in Self.ringsNm {
            let r = nm * Double(pxPerNm)
            guard r >= 8 else { continue }
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            ctx.stroke(Path(ellipseIn: rect), with: .color(Self.ringColor), style: dash)
            // Mile label at ~1 o'clock (-60°).
            let la = (-60.0).radians
            let lx = center.x + CGFloat(r) * CGFloat(cos(la))
            let ly = center.y + CGFloat(r) * CGFloat(sin(la))
            let mi = Int((nm * 1.15078).rounded())
            ctx.draw(Text("\(mi) mi").font(.psMono(11, weight: .medium)).foregroundStyle(Self.ringLabel),
                     at: CGPoint(x: lx, y: ly))
        }
        // Compass ticks every 10°; majors every 30° with labels on the outer ring.
        let maxR = Self.maxRingNm * Double(pxPerNm)
        guard maxR >= 20 else { return }
        let cardinals: [Int: String] = [0: "N", 30: "030", 60: "060", 90: "E", 120: "120", 150: "150",
                                         180: "S", 210: "210", 240: "240", 270: "W", 300: "300", 330: "330"]
        for deg in stride(from: 0, to: 360, by: 10) {
            let rad = Double(deg - 90).radians
            let isMajor = deg % 30 == 0
            let tickLen = isMajor ? 16.0 : 8.0
            let inner = maxR - tickLen
            var p = Path()
            p.move(to: CGPoint(x: center.x + CGFloat(inner * cos(rad)), y: center.y + CGFloat(inner * sin(rad))))
            p.addLine(to: CGPoint(x: center.x + CGFloat(maxR * cos(rad)), y: center.y + CGFloat(maxR * sin(rad))))
            ctx.stroke(p, with: .color(Self.compassColor), lineWidth: isMajor ? 1.5 : 0.8)
            if isMajor, let label = cardinals[deg] {
                let lr = maxR + 18
                ctx.draw(
                    Text(label).font(.psMono(label.count == 1 ? 15 : 11, weight: label.count == 1 ? .bold : .regular))
                        .foregroundStyle(Self.compassLabel),
                    at: CGPoint(x: center.x + CGFloat(lr * cos(rad)), y: center.y + CGFloat(lr * sin(rad)))
                )
            }
        }
    }

    // ── 5b. Velocity vectors ────────────────────────────────────────────────
    private func drawVelocityVectors(_ ctx: GraphicsContext, _ acs: [Aircraft], center: CGPoint, pxPerNm: CGFloat) {
        for ac in acs {
            guard let lat = ac.latitude, let lon = ac.longitude,
                  let track = ac.track, let gs = ac.groundSpeed, gs >= 30 else { continue }
            let distNm = gs / 3600 * 90
            let trackRad = track.radians
            let endLat = lat + (distNm / 60) * cos(trackRad)
            let endLon = lon + (distNm / 60 / cos(lat.radians)) * sin(trackRad)
            var p = Path()
            p.move(to: project(lat, lon, center: center, pxPerNm: pxPerNm))
            p.addLine(to: project(endLat, endLon, center: center, pxPerNm: pxPerNm))
            ctx.stroke(p, with: .color(Self.leaderColor.opacity(0.5)),
                       style: StrokeStyle(lineWidth: 1, lineCap: .round))
        }
    }

    // ── 5c. Aircraft symbols (heading-rotated diamond) ──────────────────────────
    private func drawTargets(_ ctx: GraphicsContext, _ acs: [Aircraft], center: CGPoint, pxPerNm: CGFloat) {
        for ac in acs {
            guard let lat = ac.latitude, let lon = ac.longitude else { continue }
            let pos = project(lat, lon, center: center, pxPerNm: pxPerNm)
            let heading = ac.track ?? 0
            let isSel = ac.hex == selectedHex
            let color = targetColor(ac)
            let halfW: CGFloat = isSel ? 6 : 4.5
            let halfH: CGFloat = isSel ? 8 : 6
            var diamond = Path()
            diamond.move(to: CGPoint(x: pos.x, y: pos.y - halfH))
            diamond.addLine(to: CGPoint(x: pos.x + halfW, y: pos.y))
            diamond.addLine(to: CGPoint(x: pos.x, y: pos.y + halfH))
            diamond.addLine(to: CGPoint(x: pos.x - halfW, y: pos.y))
            diamond.closeSubpath()

            var sub = ctx
            sub.translateBy(x: pos.x, y: pos.y)
            sub.rotate(by: .degrees(heading))
            sub.translateBy(x: -pos.x, y: -pos.y)
            if isSel { sub.fill(diamond, with: .color(color.opacity(0.5))) }   // glow proxy
            sub.fill(diamond, with: .color(color))
        }
    }

    // ── 5d. Data blocks (smart placement) ───────────────────────────────────────
    private func drawDataBlocks(_ ctx: GraphicsContext, _ acs: [Aircraft], center: CGPoint, pxPerNm: CGFloat) {
        let positions = acs.compactMap { ac -> (Aircraft, CGPoint)? in
            guard let lat = ac.latitude, let lon = ac.longitude else { return nil }
            return (ac, project(lat, lon, center: center, pxPerNm: pxPerNm))
        }
        let allPts = positions.map(\.1)
        for (ac, pos) in positions {
            let isSel = ac.hex == selectedHex
            let isEmer = ac.emergency != .none
            let color = targetColor(ac)
            let dim = isSel ? color : color.opacity(0.7)
            let dir = pickBlockDirection(pos, allPts)
            let leader: CGFloat = isSel ? 20 : 14
            let bx = pos.x + dir.x * leader, by = pos.y + dir.y * leader
            var line = Path(); line.move(to: pos); line.addLine(to: CGPoint(x: bx, y: by))
            ctx.stroke(line, with: .color(color.opacity(0.3)), lineWidth: 0.6)

            let anchor: UnitPoint = dir.x < 0 ? .trailing : .leading
            // Line 1: callsign
            let cs = ac.callsign?.trimmingCharacters(in: .whitespaces).isEmpty == false
                ? ac.callsign!.trimmingCharacters(in: .whitespaces) : ac.hex.uppercased()
            ctx.draw(Text(cs).font(.psMono(isSel ? 13 : 11, weight: .bold)).foregroundStyle(color),
                     at: CGPoint(x: bx, y: by), anchor: anchor)
            // Line 2: FL + trend + speed
            let altText = ac.isOnGround ? "GND" : (ac.altitudeBaro.map { String(format: "%03d", $0 / 100) } ?? "---")
            let vr = ac.verticalRate ?? 0
            let trend = vr > 300 ? "↑" : (vr < -300 ? "↓" : "")
            let spd = ac.groundSpeed.map { String(format: "%03d", Int($0)) } ?? "---"
            ctx.draw(Text("\(altText)\(trend) \(spd)").font(.psMono(isSel ? 11 : 9)).foregroundStyle(dim),
                     at: CGPoint(x: bx, y: by + 12), anchor: anchor)
            // Line 3: squawk (emergency / selected) or type
            let line3: String? = isEmer ? "SQ\(ac.squawk ?? "")"
                : (isSel && ac.squawk != nil ? "SQ\(ac.squawk!)" : ac.type)
            if let l3 = line3 {
                ctx.draw(Text(l3).font(.psMono(isSel ? 10 : 9))
                    .foregroundStyle(isEmer ? Self.emergencyColor : dim.opacity(0.5)),
                         at: CGPoint(x: bx, y: by + 24), anchor: anchor)
            }
        }
    }

    private func drawCrosshair(_ ctx: GraphicsContext, center: CGPoint) {
        let arm: CGFloat = 14, gap: CGFloat = 4
        func seg(_ a: CGPoint, _ b: CGPoint) { var p = Path(); p.move(to: a); p.addLine(to: b)
            ctx.stroke(p, with: .color(Self.centerColor), lineWidth: 1.2) }
        seg(CGPoint(x: center.x - arm, y: center.y), CGPoint(x: center.x - gap, y: center.y))
        seg(CGPoint(x: center.x + gap, y: center.y), CGPoint(x: center.x + arm, y: center.y))
        seg(CGPoint(x: center.x, y: center.y - arm), CGPoint(x: center.x, y: center.y - gap))
        seg(CGPoint(x: center.x, y: center.y + gap), CGPoint(x: center.x, y: center.y + arm))
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - 1.5, y: center.y - 1.5, width: 3, height: 3)),
                 with: .color(Self.centerColor))
    }

    private func targetColor(_ ac: Aircraft) -> Color {
        if ac.hex == selectedHex { return Self.selectedColor }
        if ac.emergency != .none { return Self.emergencyColor }
        if ac.classification.level.isMilOrLikely { return Self.militaryColor }
        return Self.phosphorGreen
    }

    /// Pick the data-block direction minimizing overlap; prefers upper-right.
    private func pickBlockDirection(_ pos: CGPoint, _ all: [CGPoint]) -> CGPoint {
        let candidates: [CGPoint] = [
            CGPoint(x: 1, y: -1), CGPoint(x: 1, y: 0.5), CGPoint(x: -1, y: -1), CGPoint(x: -1, y: 0.5),
            CGPoint(x: 1, y: 0), CGPoint(x: -1, y: 0), CGPoint(x: 0, y: -1.2), CGPoint(x: 0, y: 1),
        ]
        var best = candidates[0]; var bestDist: CGFloat = -1
        for dir in candidates {
            let bc = CGPoint(x: pos.x + dir.x * 30, y: pos.y + dir.y * 30)
            let minD = all.filter { $0 != pos }
                .map { hypot(bc.x - $0.x, bc.y - $0.y) }.min() ?? .greatestFiniteMagnitude
            if minD > bestDist { bestDist = minD; best = dir }
        }
        return best
    }

    // ── STARS/ERAM phosphor palette (RadarScope2Overlay.kt) ────────────────────
    private static let phosphorGreen = Color(hex: 0x33FF66)
    private static let ringColor     = Color(hex: 0x3C9A55)
    private static let ringLabel     = Color(hex: 0x7FE09E)
    private static let compassColor  = Color(hex: 0x2A6B3A)
    private static let compassLabel  = Color(hex: 0x55CC77)
    private static let selectedColor = Color(hex: 0xFFFF33)
    private static let emergencyColor = Color(hex: 0xFF3333)
    private static let militaryColor = Color(hex: 0x33CCFF)
    private static let sweepGreen    = Color(hex: 0x33FF66)
    private static let leaderColor   = Color(hex: 0x22AA44)
    private static let centerColor   = Color(hex: 0x33FF66)
}
