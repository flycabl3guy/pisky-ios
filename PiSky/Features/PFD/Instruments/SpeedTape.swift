import SwiftUI

/// Vertical ground-speed tape — Boeing 737 PFD style, drawn against a fixed
/// pointer at vertical center. Major tick every 10 kt (numbered), minor every
/// 5 kt. ±50 kt visible range (5 px/kt over a ~500 px tall tape).
///
/// Honest labeling: ADS-B does NOT broadcast IAS/TAS/Mach on this rig (BDS 5,0
/// is not decoded). We display GROUND SPEED with a "GS KTS" header so the user
/// can't confuse it for airspeed. The Boeing speed-trend vector and V-speed
/// markers are omitted — no source data.
///
/// Ports `feature/pfd/instruments/SpeedTape.kt`.
struct SpeedTape: View {
    let groundSpeedKt: Double?

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cy = h / 2
            let gs = groundSpeedKt ?? 0.0
            // Pixels per knot — 5 px/kt gives ±50 kt visible on a ~500 px tall tape.
            let pxPerKt: CGFloat = 5

            // Tick range ±60 kt around current
            let minTick = max(Int(gs) - 60, 0)
            let maxTick = Int(gs) + 60
            for kt in minTick...maxTick where kt % 5 == 0 {
                let deltaKt = Double(kt) - gs
                let y = cy - CGFloat(deltaKt) * pxPerKt
                if y < 0 || y > h { continue }
                let isMajor = kt % 10 == 0
                var tick = Path()
                tick.move(to: CGPoint(x: w - (isMajor ? 22 : 12), y: y))
                tick.addLine(to: CGPoint(x: w - 4, y: y))
                ctx.stroke(tick, with: .color(PfdColors.white), lineWidth: isMajor ? 2 : 1)
                if isMajor {
                    let txt = ctx.resolve(Text("\(kt)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(PfdColors.white))
                    ctx.draw(txt, at: CGPoint(x: w - 30, y: y), anchor: .trailing)
                }
            }

            // Header — "GS KTS"
            let header = ctx.resolve(Text("GS KTS")
                .font(.system(size: 9))
                .tracking(1.2)
                .foregroundColor(PfdColors.headerGray))
            let hSize = header.measure(in: size)
            ctx.draw(header, at: CGPoint(x: w / 2, y: 4 + hSize.height / 2), anchor: .center)

            // Fixed center pointer — black box outlined in white with the current GS
            let boxW = w - 8
            let boxH: CGFloat = 36
            let boxX: CGFloat = 4
            let boxY = cy - boxH / 2
            ctx.fill(Path(CGRect(x: boxX, y: boxY, width: boxW, height: boxH)),
                     with: .color(PfdColors.background))
            ctx.stroke(Path(CGRect(x: boxX, y: boxY, width: boxW, height: boxH)),
                       with: .color(PfdColors.white), lineWidth: 2)
            let readout = groundSpeedKt == nil ? "—" : "\(Int(gs.rounded()))"
            let ro = ctx.resolve(Text(readout)
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(PfdColors.white))
            ctx.draw(ro, at: CGPoint(x: boxX + boxW / 2, y: cy), anchor: .center)

            // Pointer triangle on right edge of the box pointing at the tape
            var tri = Path()
            tri.move(to: CGPoint(x: boxX + boxW, y: cy))
            tri.addLine(to: CGPoint(x: boxX + boxW + 8, y: cy - 6))
            tri.addLine(to: CGPoint(x: boxX + boxW + 8, y: cy + 6))
            tri.closeSubpath()
            ctx.fill(tri, with: .color(PfdColors.white))
        }
        .background(PfdColors.tapePanel)
    }
}
