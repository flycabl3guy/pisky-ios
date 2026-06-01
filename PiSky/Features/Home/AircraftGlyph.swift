import SwiftUI

/// Aircraft glyph kit — port of `v6/AircraftGlyph.kt`. Collapses the 30-odd ADS-B emitter categories
/// into 7 visual silhouettes for the RadarHero pings, and draws each as a heading-rotated `Path`
/// (filled body + 1.2 pt outline) inside a `Canvas` `GraphicsContext`.
enum GlyphKind { case light, medium, heavy, jet, heli, mil, ground, unknown }

func glyphKindFor(category: String?, isMilitary: Bool, isOnGround: Bool) -> GlyphKind {
    if isMilitary { return .mil }
    if isOnGround { return .ground }
    switch category?.uppercased() {
    case "A1":        return .light
    case "A2", "A3":  return .medium
    case "A4", "A5":  return .heavy
    case "A6":        return .jet
    case "A7":        return .heli
    case "B1", "B2":  return .light
    case "B4", "B5":  return .ground
    default:          return .unknown
    }
}

/// Convert (distance_nm, bearing_deg) polar → Cartesian around `origin`. North-up: `angle = brg−90`.
func polarToOffset(origin: CGPoint, distanceNm: Double, bearingDeg: Double, pixelsPerNm: CGFloat) -> CGPoint {
    let rad = (bearingDeg - 90).radians
    let r = CGFloat(distanceNm) * pixelsPerNm
    return CGPoint(x: origin.x + r * CGFloat(cos(rad)), y: origin.y + r * CGFloat(sin(rad)))
}

extension GraphicsContext {
    /// Draw an aircraft glyph at `center`, rotated to `headingDeg` (0 = north, clockwise).
    func drawAircraftGlyph(_ kind: GlyphKind, center: CGPoint, headingDeg: Double,
                           radius: CGFloat, fill: Color, outline: Color) {
        var sub = self
        sub.translateBy(x: center.x, y: center.y)
        sub.rotate(by: .degrees(headingDeg))
        sub.translateBy(x: -center.x, y: -center.y)
        let path: Path
        switch kind {
        case .light:   path = Self.triangle(center, radius * 0.85)
        case .medium:  path = Self.sweptWing(center, radius * 0.95, sweep: 0.45)
        case .heavy:   path = Self.sweptWing(center, radius * 1.10, sweep: 0.65)
        case .jet:     path = Self.delta(center, radius * 1.00, fins: false)
        case .mil:     path = Self.delta(center, radius * 1.10, fins: true)
        case .heli:    Self.drawHeli(&sub, center, radius, fill: fill, outline: outline); return
        case .ground:  path = Self.square(center, radius * 0.70)
        case .unknown: path = Self.dot(center, radius * 0.55)
        }
        sub.fill(path, with: .color(fill))
        sub.stroke(path, with: .color(outline), lineWidth: 1.2)
    }

    private static func triangle(_ c: CGPoint, _ r: CGFloat) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addLine(to: CGPoint(x: c.x - r * 0.7, y: c.y + r * 0.7))
        p.addLine(to: CGPoint(x: c.x + r * 0.7, y: c.y + r * 0.7))
        p.closeSubpath()
        return p
    }

    private static func sweptWing(_ c: CGPoint, _ r: CGFloat, sweep: CGFloat) -> Path {
        let noseY = c.y - r
        let tailY = c.y + r * 0.55
        let wingY = c.y + r * (0.05 + sweep * 0.20)
        let wingX = r * (0.95 - sweep * 0.10)
        let tailX = r * 0.32
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: noseY))
        p.addLine(to: CGPoint(x: c.x - wingX, y: wingY))
        p.addLine(to: CGPoint(x: c.x - tailX, y: wingY + r * 0.05))
        p.addLine(to: CGPoint(x: c.x - tailX * 0.85, y: tailY))
        p.addLine(to: CGPoint(x: c.x + tailX * 0.85, y: tailY))
        p.addLine(to: CGPoint(x: c.x + tailX, y: wingY + r * 0.05))
        p.addLine(to: CGPoint(x: c.x + wingX, y: wingY))
        p.closeSubpath()
        return p
    }

    private static func delta(_ c: CGPoint, _ r: CGFloat, fins: Bool) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addLine(to: CGPoint(x: c.x - r * 0.85, y: c.y + r * 0.75))
        if fins {
            p.addLine(to: CGPoint(x: c.x - r * 0.40, y: c.y + r * 0.55))
            p.addLine(to: CGPoint(x: c.x - r * 0.50, y: c.y + r * 0.95))
            p.addLine(to: CGPoint(x: c.x, y: c.y + r * 0.60))
            p.addLine(to: CGPoint(x: c.x + r * 0.50, y: c.y + r * 0.95))
            p.addLine(to: CGPoint(x: c.x + r * 0.40, y: c.y + r * 0.55))
        }
        p.addLine(to: CGPoint(x: c.x + r * 0.85, y: c.y + r * 0.75))
        p.closeSubpath()
        return p
    }

    private static func square(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private static func dot(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private static func drawHeli(_ ctx: inout GraphicsContext, _ c: CGPoint, _ r: CGFloat,
                                 fill: Color, outline: Color) {
        let body = Path(ellipseIn: CGRect(x: c.x - r * 0.42, y: c.y - r * 0.42, width: r * 0.84, height: r * 0.84))
        ctx.fill(body, with: .color(fill))
        ctx.stroke(body, with: .color(outline), lineWidth: 1.2)
        let arm = r * 1.05
        var h = Path(); h.move(to: CGPoint(x: c.x - arm, y: c.y)); h.addLine(to: CGPoint(x: c.x + arm, y: c.y))
        var v = Path(); v.move(to: CGPoint(x: c.x, y: c.y - arm * 0.85)); v.addLine(to: CGPoint(x: c.x, y: c.y + arm * 0.85))
        ctx.stroke(h, with: .color(outline), lineWidth: 1.4)
        ctx.stroke(v, with: .color(outline), lineWidth: 1.4)
    }
}
