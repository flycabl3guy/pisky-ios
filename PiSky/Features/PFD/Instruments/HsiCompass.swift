import SwiftUI

/// Track-up HSI compass rose — substitute for the 737 attitude indicator on the
/// PiSky PFD. ADS-B does NOT broadcast roll/pitch, so the central instrument
/// slot is filled with the navigation rose, which uses data we actually have:
///
///   - Outer ring with cardinal letters (N/E/S/W) and decade labels (03, 06, ...)
///   - Aircraft chevron fixed at center, track-up orientation
///   - Magenta selected-heading bug riding the rose perimeter
///   - Bottom turn-rate indicator (amber > 3.5°/s) derived from track deltas
///   - Center digital readout of current track, top of rose
///
/// The rose rotates so the current track is always at the top. The chevron is
/// fixed. Decade labels are counter-rotated to read upright in world space.
///
/// Ports `feature/pfd/instruments/HsiCompass.kt`.
struct HsiCompass: View {
    let trackDeg: Double?
    let navHeadingDeg: Double?
    let turnRateDegSec: Double

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let cy = h / 2 + 8                    // shift center down for top readout room
            let outerR = min(w, h) * 0.42

            // ── Top track readout box ────────────────────────────────────────
            let trackStr = trackDeg.map { String(format: "%03d°", Int((($0 + 360).truncatingRemainder(dividingBy: 360)).rounded())) } ?? "---°"
            let roText = ctx.resolve(Text(trackStr)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(PfdColors.white))
            let roSize = roText.measure(in: size)
            let boxW = roSize.width + 16
            let boxH = roSize.height + 6
            let boxX = cx - boxW / 2
            let boxY = (cy - outerR) - boxH - 4
            ctx.fill(Path(CGRect(x: boxX, y: boxY, width: boxW, height: boxH)),
                     with: .color(PfdColors.background))
            ctx.stroke(Path(CGRect(x: boxX, y: boxY, width: boxW, height: boxH)),
                       with: .color(PfdColors.white), lineWidth: 1.5)
            ctx.draw(roText, at: CGPoint(x: cx, y: boxY + boxH / 2), anchor: .center)

            // ── Fixed lubber line at top of rose ────────────────────────────
            var lubber = Path()
            lubber.move(to: CGPoint(x: cx, y: cy - outerR - 2))
            lubber.addLine(to: CGPoint(x: cx - 6, y: cy - outerR - 14))
            lubber.addLine(to: CGPoint(x: cx + 6, y: cy - outerR - 14))
            lubber.closeSubpath()
            ctx.fill(lubber, with: .color(PfdColors.white))

            // ── Rose ring (rotates so track is at top) ──────────────────────
            let track = trackDeg ?? 0.0
            var rose = ctx
            rose.translateBy(x: cx, y: cy)
            rose.rotate(by: .degrees(-track))
            rose.translateBy(x: -cx, y: -cy)

            // Tick marks every 5°, decade ticks longer
            for deg in stride(from: 0, to: 360, by: 5) {
                let isDecade = deg % 30 == 0
                let tickInner = isDecade ? outerR - 16 : outerR - 8
                let rad = Double(deg - 90) * .pi / 180   // -90 so 0° (N) is up
                var tick = Path()
                tick.move(to: CGPoint(x: cx + cos(rad) * tickInner, y: cy + sin(rad) * tickInner))
                tick.addLine(to: CGPoint(x: cx + cos(rad) * outerR, y: cy + sin(rad) * outerR))
                rose.stroke(tick, with: .color(PfdColors.white), lineWidth: isDecade ? 2 : 1)
            }

            // Decade labels — N E S W at cardinals, "03" "06" etc otherwise.
            for deg in stride(from: 0, to: 360, by: 30) {
                let label: String
                switch deg {
                case 0:   label = "N"
                case 90:  label = "E"
                case 180: label = "S"
                case 270: label = "W"
                default:  label = String(format: "%02d", deg / 10)
                }
                let rad = Double(deg - 90) * .pi / 180
                let r = outerR - 30
                let lx = cx + cos(rad) * r
                let ly = cy + sin(rad) * r
                let isCardinal = deg % 90 == 0
                let txt = rose.resolve(Text(label)
                    .font(.system(size: isCardinal ? 18 : 13, weight: .bold))
                    .foregroundColor(PfdColors.white))
                // Counter-rotate the label about its center so it reads upright.
                var labelCtx = rose
                labelCtx.translateBy(x: lx, y: ly)
                labelCtx.rotate(by: .degrees(track))
                labelCtx.translateBy(x: -lx, y: -ly)
                labelCtx.draw(txt, at: CGPoint(x: lx, y: ly), anchor: .center)
            }

            // Magenta heading bug on the perimeter (a small diamond)
            if let hdg = navHeadingDeg {
                let rad = (hdg - 90) * .pi / 180
                let bx = cx + cos(rad) * outerR
                let by = cy + sin(rad) * outerR
                var bug = Path()
                bug.move(to: CGPoint(x: bx, y: by - 10))
                bug.addLine(to: CGPoint(x: bx + 7, y: by - 2))
                bug.addLine(to: CGPoint(x: bx, y: by + 6))
                bug.addLine(to: CGPoint(x: bx - 7, y: by - 2))
                bug.closeSubpath()
                rose.fill(bug, with: .color(PfdColors.magenta))
            }

            // ── Aircraft chevron fixed at center, pointing up ───────────────
            var ac = Path()
            ac.move(to: CGPoint(x: cx, y: cy - 16))            // nose
            ac.addLine(to: CGPoint(x: cx + 18, y: cy + 6))      // right wingtip
            ac.addLine(to: CGPoint(x: cx + 6,  y: cy + 4))      // right wing root
            ac.addLine(to: CGPoint(x: cx + 4,  y: cy + 12))     // right tail
            ac.addLine(to: CGPoint(x: cx,      y: cy + 8))      // tail center
            ac.addLine(to: CGPoint(x: cx - 4,  y: cy + 12))     // left tail
            ac.addLine(to: CGPoint(x: cx - 6,  y: cy + 4))      // left wing root
            ac.addLine(to: CGPoint(x: cx - 18, y: cy + 6))      // left wingtip
            ac.closeSubpath()
            ctx.fill(ac, with: .color(PfdColors.background))
            ctx.stroke(ac, with: .color(PfdColors.chevronEdge), lineWidth: 2)

            // ── Turn rate indicator (small triangle below center) ───────────
            let turnLabelY = cy + outerR + 6
            let maxTurn = 6.0
            let turnNorm = max(-1.0, min(1.0, turnRateDegSec / maxTurn))
            let turnX = cx + CGFloat(turnNorm) * (outerR * 0.6)
            var tri = Path()
            tri.move(to: CGPoint(x: turnX, y: turnLabelY))
            tri.addLine(to: CGPoint(x: turnX - 6, y: turnLabelY + 8))
            tri.addLine(to: CGPoint(x: turnX + 6, y: turnLabelY + 8))
            tri.closeSubpath()
            let turnColor = abs(turnRateDegSec) > 3.5 ? PfdColors.amber : PfdColors.white
            ctx.fill(tri, with: .color(turnColor))

            // Center reference tick + scale ticks at ±std-rate
            var centerTick = Path()
            centerTick.move(to: CGPoint(x: cx, y: turnLabelY - 2))
            centerTick.addLine(to: CGPoint(x: cx, y: turnLabelY + 10))
            ctx.stroke(centerTick, with: .color(PfdColors.white), lineWidth: 1.5)
            for mark in [-3.0, 3.0] {
                let mx = cx + CGFloat(mark / maxTurn) * (outerR * 0.6)
                var m = Path()
                m.move(to: CGPoint(x: mx, y: turnLabelY + 2))
                m.addLine(to: CGPoint(x: mx, y: turnLabelY + 8))
                ctx.stroke(m, with: .color(PfdColors.white), lineWidth: 1)
            }
            let turnLabel = String(format: "TURN RATE  %+.1f°/s", turnRateDegSec)
            let tlText = ctx.resolve(Text(turnLabel)
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.8)
                .foregroundColor(PfdColors.white))
            let tlSize = tlText.measure(in: size)
            ctx.draw(tlText, at: CGPoint(x: cx, y: turnLabelY + 14 + tlSize.height / 2), anchor: .center)
        }
        .background(PfdColors.background)
    }
}
