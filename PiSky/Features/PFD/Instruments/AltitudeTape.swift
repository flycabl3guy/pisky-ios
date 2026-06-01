import SwiftUI

/// Vertical altitude tape — Boeing 737 PFD style. Major tick every 100 ft
/// (numbered), minor every 20 ft. ±400 ft visible (0.5 px/ft over a ~800 px
/// column). The selected MCP altitude is shown in magenta above the tape, with
/// a magenta bug riding the tape (parked at top/bottom edge when out of range).
///
/// Altitude-alert: amber outline around the current-alt readout when within
/// ±900 ft of MCP target (Boeing FCOM C-chord visual cue).
///
/// Kollsman/QNH bar at the bottom shows the pressure setting in green; turns
/// amber when ≠ 29.92 inHg standard (transition-level vicinity hint).
///
/// Ports `feature/pfd/instruments/AltitudeTape.kt`.
struct AltitudeTape: View {
    let altBaroFt: Int?
    let altMcpFt: Int?
    let qnhHpa: Double?

    var body: some View {
        VStack(spacing: 0) {
            // ── MCP selected altitude readout (magenta, above tape) ─────────
            Text(altMcpFt.map { Fmt.grouped($0) } ?? "—")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(PfdColors.magenta)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(PfdColors.background)

            // ── Tape canvas ─────────────────────────────────────────────────
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let cy = h / 2
                let alt = CGFloat(altBaroFt ?? 0)
                // px per ft — 0.5 px/ft gives ±h/(2·pxPerFt) visible. For h=800 → ±800 ft.
                let pxPerFt: CGFloat = 0.5

                let minTick = Int((alt - h / 2 / pxPerFt) / 20) * 20
                let maxTick = Int((alt + h / 2 / pxPerFt) / 20) * 20 + 20
                var ft = minTick
                while ft <= maxTick {
                    let y = cy - (CGFloat(ft) - alt) * pxPerFt
                    if y >= 0 && y <= h {
                        let isMajor = ft % 100 == 0
                        var tick = Path()
                        tick.move(to: CGPoint(x: 0, y: y))
                        tick.addLine(to: CGPoint(x: isMajor ? 18 : 10, y: y))
                        ctx.stroke(tick, with: .color(PfdColors.white), lineWidth: isMajor ? 2 : 1)
                        if isMajor {
                            let label = Fmt.grouped(ft)
                            let txt = ctx.resolve(Text(label)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(PfdColors.white))
                            // Compose anchored top-left at (22, y - h/2); center vertically on y.
                            ctx.draw(txt, at: CGPoint(x: 22, y: y), anchor: .leading)
                        }
                    }
                    ft += 20
                }

                // MCP magenta bug — slides onto tape when within range, parks at edge otherwise
                if let mcp = altMcpFt {
                    let mcpY = cy - (CGFloat(mcp) - alt) * pxPerFt
                    let parked: CGFloat = mcpY < 6 ? 6 : (mcpY > h - 6 ? h - 6 : mcpY)
                    var bug = Path()
                    bug.move(to: CGPoint(x: 0, y: parked - 7))
                    bug.addLine(to: CGPoint(x: 8, y: parked - 7))
                    bug.addLine(to: CGPoint(x: 14, y: parked))
                    bug.addLine(to: CGPoint(x: 8, y: parked + 7))
                    bug.addLine(to: CGPoint(x: 0, y: parked + 7))
                    bug.closeSubpath()
                    ctx.fill(bug, with: .color(PfdColors.magenta))
                }

                // Current altitude readout box — center
                let boxW = w - 8
                let boxH: CGFloat = 36
                let boxX: CGFloat = 4
                let boxY = cy - boxH / 2
                ctx.fill(Path(CGRect(x: boxX, y: boxY, width: boxW, height: boxH)),
                         with: .color(PfdColors.background))

                // Alert-band outline: amber when within ±900 ft of MCP
                let alertActive: Bool = {
                    if let m = altMcpFt, let a = altBaroFt { return abs(m - a) <= 900 }
                    return false
                }()
                ctx.stroke(Path(CGRect(x: boxX, y: boxY, width: boxW, height: boxH)),
                           with: .color(alertActive ? PfdColors.amber : PfdColors.white),
                           lineWidth: alertActive ? 3 : 2)
                let readout = altBaroFt.map { Fmt.grouped($0) } ?? "—"
                let ro = ctx.resolve(Text(readout)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(PfdColors.white))
                ctx.draw(ro, at: CGPoint(x: boxX + boxW / 2, y: cy), anchor: .center)

                // Pointer triangle on left edge of box pointing at tape
                var tri = Path()
                tri.move(to: CGPoint(x: boxX, y: cy))
                tri.addLine(to: CGPoint(x: boxX - 8, y: cy - 6))
                tri.addLine(to: CGPoint(x: boxX - 8, y: cy + 6))
                tri.closeSubpath()
                ctx.fill(tri, with: .color(PfdColors.white))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(PfdColors.tapePanel)

            // ── Kollsman / QNH bar (below tape) ─────────────────────────────
            qnhBar
        }
    }

    private var qnhBar: some View {
        let inHg = qnhHpa.map { $0 * 0.02953 }
        let nonStd = inHg.map { abs($0 - 29.92) > 0.01 } ?? false
        let text: String = {
            guard let inHg else { return "STD 29.92" }
            return String(format: "%.2f IN", inHg)
        }()
        return Text(text)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(nonStd ? PfdColors.amber : PfdColors.green)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(PfdColors.background)
    }
}
