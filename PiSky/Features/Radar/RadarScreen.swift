import SwiftUI

/// `RadarScreen` — port of `RadarScreen.kt`. Contract §5: `RadarScreen()`.
///
/// Pure-SwiftUI-`Canvas` PPI. Equirectangular projection centered on the receiver
/// (`dx = (lon−c.lon)·60·cos(c.lat)/nmPerPx`, `dy = −(lat−c.lat)·60/nmPerPx`), pinch-zoom
/// (nm/width 20–4000), drag-pan (in degrees), range rings 25/50/100/150/200 nm, cardinal ticks,
/// 60-sample fading FIFO trails, altitude-banded heading-rotated triangles (`Palette.radarAltitude`),
/// callsign labels, tap-select nearest within 48 pt, plus HUD + control bar + selected-aircraft bar.
struct RadarScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = RadarViewModel()

    // Zoom in nm-per-screen-width; pan in (lat, lon) degree offsets.
    @State private var zoomNmPerWidth: Double = 400
    @State private var panLat: Double = 0
    @State private var panLon: Double = 0
    // Gesture-relative accumulators.
    @State private var gestureBaseZoom: Double = 400
    @State private var lastDrag: CGSize = .zero

    private static let ringsNm: [Double] = [25, 50, 100, 150, 200]
    private static let cowdenLat = 39.247
    private static let cowdenLon = -88.86

    private var rxLat: Double { vm.receiver?.latitude ?? Self.cowdenLat }
    private var rxLon: Double { vm.receiver?.longitude ?? Self.cowdenLon }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let cx = size.width / 2, cy = size.height / 2
            let nmPerPx = zoomNmPerWidth / Double(size.width)
            let centerLat = rxLat + panLat
            let centerLon = rxLon + panLon

            ZStack {
                Palette.background.ignoresSafeArea()

                Canvas { ctx, _ in
                    let rx = project(rxLat, rxLon, centerLat, centerLon, nmPerPx, cx, cy)

                    if vm.showRings {
                        drawRangeRings(ctx, rx, nmPerPx: nmPerPx, size: size)
                        drawCardinalCompass(ctx, cx: cx, cy: cy, size: size)
                    }
                    if vm.showTrails {
                        for (hex, pts) in vm.trails where pts.count >= 2 {
                            drawTrail(ctx, pts, centerLat, centerLon, nmPerPx, cx, cy, selected: hex == vm.selectedHex)
                        }
                    }
                    // Draw others first, the selected aircraft last so it overlays.
                    for a in vm.aircraft where a.hex != vm.selectedHex {
                        drawMarker(ctx, a, centerLat, centerLon, nmPerPx, cx, cy, selected: false, size: size)
                    }
                    for a in vm.aircraft where a.hex == vm.selectedHex {
                        drawMarker(ctx, a, centerLat, centerLon, nmPerPx, cx, cy, selected: true, size: size)
                    }
                    drawReceiverCrosshair(ctx, rx)
                }
                .contentShape(Rectangle())
                .gesture(magnify(size: size))
                .simultaneousGesture(drag(size: size, centerLat: centerLat))
                .gesture(tap(size: size, cx: cx, cy: cy, nmPerPx: nmPerPx, centerLat: centerLat, centerLon: centerLon))

                hud(size: size)
                controlBar
                if let ac = vm.aircraft.first(where: { $0.hex == vm.selectedHex }) {
                    VStack { Spacer(); HStack { selectedBar(ac); Spacer() } }
                        .padding(12)
                }
                if vm.aircraft.filter(\.hasPosition).isEmpty { emptyState }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task { vm.start(container) }
    }

    // ── Gestures ───────────────────────────────────────────────────────────────
    private func magnify(size: CGSize) -> some Gesture {
        // iOS 17 MagnifyGesture; `.magnification` is the pinch scale factor.
        MagnifyGesture()
            .onChanged { value in
                zoomNmPerWidth = (gestureBaseZoom / Double(value.magnification)).clamped(20, 4000)
            }
            .onEnded { _ in gestureBaseZoom = zoomNmPerWidth }
    }

    private func drag(size: CGSize, centerLat: Double) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let dx = value.translation.width - lastDrag.width
                let dy = value.translation.height - lastDrag.height
                lastDrag = value.translation
                let nmPerPx = zoomNmPerWidth / Double(size.width)
                panLat += -Double(dy) * nmPerPx / 60
                panLon += -Double(dx) * nmPerPx / (60 * cos((centerLat).radians))
            }
            .onEnded { _ in lastDrag = .zero }
    }

    private func tap(size: CGSize, cx: CGFloat, cy: CGFloat, nmPerPx: Double,
                     centerLat: Double, centerLon: Double) -> some Gesture {
        SpatialTapGesture().onEnded { value in
            var best: Aircraft?; var bestDist: CGFloat = 48
            for a in vm.aircraft {
                guard let lat = a.latitude, let lon = a.longitude else { continue }
                let p = project(lat, lon, centerLat, centerLon, nmPerPx, cx, cy)
                let d = hypot(p.x - value.location.x, p.y - value.location.y)
                if d < bestDist { bestDist = d; best = a }
            }
            HangarHaptics.select()
            vm.selectAircraft(best?.hex)
        }
    }

    // ── Projection ───────────────────────────────────────────────────────────
    private func project(_ lat: Double, _ lon: Double, _ centerLat: Double, _ centerLon: Double,
                         _ nmPerPx: Double, _ cx: CGFloat, _ cy: CGFloat) -> CGPoint {
        let dx = (lon - centerLon) * 60 * cos(centerLat.radians) / nmPerPx
        let dy = -(lat - centerLat) * 60 / nmPerPx
        return CGPoint(x: cx + CGFloat(dx), y: cy + CGFloat(dy))
    }

    // ── Range rings ──────────────────────────────────────────────────────────
    private func drawRangeRings(_ ctx: GraphicsContext, _ c: CGPoint, nmPerPx: Double, size: CGSize) {
        let ring = Palette.brass.opacity(0.22)
        let label = Palette.brass.opacity(0.65)
        let dash = StrokeStyle(lineWidth: 1.2, dash: [8, 8])
        for nm in Self.ringsNm {
            let r = CGFloat(nm / nmPerPx)
            guard r >= 12, r <= max(size.width, size.height) * 1.5 else { continue }
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                       with: .color(ring), style: dash)
            let lx = c.x + r + 4
            if lx >= 0, lx <= size.width - 24 {
                ctx.draw(Text("\(Int(nm)) nm").font(.psMono(10, weight: .semibold)).foregroundStyle(label),
                         at: CGPoint(x: lx, y: c.y), anchor: .leading)
            }
        }
    }

    private func drawCardinalCompass(_ ctx: GraphicsContext, cx: CGFloat, cy: CGFloat, size: CGSize) {
        let r = min(size.width, size.height) * 0.46
        let tick: CGFloat = 8
        let color = Palette.textMuted.opacity(0.7)
        func seg(_ a: CGPoint, _ b: CGPoint) { var p = Path(); p.move(to: a); p.addLine(to: b)
            ctx.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round)) }
        seg(CGPoint(x: cx, y: cy - r), CGPoint(x: cx, y: cy - r + tick))
        seg(CGPoint(x: cx + r - tick, y: cy), CGPoint(x: cx + r, y: cy))
        seg(CGPoint(x: cx, y: cy + r - tick), CGPoint(x: cx, y: cy + r))
        seg(CGPoint(x: cx - r, y: cy), CGPoint(x: cx - r + tick, y: cy))
    }

    private func drawReceiverCrosshair(_ ctx: GraphicsContext, _ c: CGPoint) {
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10)),
                 with: .color(Palette.brass))
        ctx.stroke(Path(ellipseIn: CGRect(x: c.x - 12, y: c.y - 12, width: 24, height: 24)),
                   with: .color(Palette.brass.opacity(0.35)), lineWidth: 1.5)
    }

    // ── Trails (fading FIFO) ───────────────────────────────────────────────────
    private func drawTrail(_ ctx: GraphicsContext, _ pts: [RadarViewModel.TrailPoint],
                          _ centerLat: Double, _ centerLon: Double, _ nmPerPx: Double,
                          _ cx: CGFloat, _ cy: CGFloat, selected: Bool) {
        let base = selected ? Palette.brass : Palette.brass.opacity(0.4)
        let baseAlpha = selected ? 1.0 : 0.4
        for i in 1..<pts.count {
            let p0 = project(pts[i - 1].lat, pts[i - 1].lon, centerLat, centerLon, nmPerPx, cx, cy)
            let p1 = project(pts[i].lat, pts[i].lon, centerLat, centerLon, nmPerPx, cx, cy)
            let fade = Double(i) / Double(pts.count)
            var p = Path(); p.move(to: p0); p.addLine(to: p1)
            ctx.stroke(p, with: .color(base.opacity(baseAlpha * fade)),
                       style: StrokeStyle(lineWidth: selected ? 2.5 : 1.5, lineCap: .round))
        }
    }

    // ── Aircraft marker (altitude-banded, heading-rotated triangle) ─────────────
    private func drawMarker(_ ctx: GraphicsContext, _ a: Aircraft,
                           _ centerLat: Double, _ centerLon: Double, _ nmPerPx: Double,
                           _ cx: CGFloat, _ cy: CGFloat, selected: Bool, size: CGSize) {
        guard let lat = a.latitude, let lon = a.longitude else { return }
        let p = project(lat, lon, centerLat, centerLon, nmPerPx, cx, cy)
        guard p.x >= -50, p.x <= size.width + 50, p.y >= -50, p.y <= size.height + 50 else { return }

        let color = Palette.radarAltitude(a.altitudeBaro)
        if selected {
            ctx.stroke(Path(ellipseIn: CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28)),
                       with: .color(Palette.brass), lineWidth: 2)
        }
        let half: CGFloat = 8
        var tri = Path()
        tri.move(to: CGPoint(x: p.x, y: p.y - half * 1.4))            // nose
        tri.addLine(to: CGPoint(x: p.x - half, y: p.y + half * 0.6))  // left tail
        tri.addLine(to: CGPoint(x: p.x + half, y: p.y + half * 0.6))  // right tail
        tri.closeSubpath()
        var sub = ctx
        sub.translateBy(x: p.x, y: p.y)
        sub.rotate(by: .degrees(a.track ?? 0))
        sub.translateBy(x: -p.x, y: -p.y)
        sub.fill(tri, with: .color(color))

        if vm.showLabels {
            let cs = a.callsign?.trimmingCharacters(in: .whitespaces).isEmpty == false
                ? a.callsign!.trimmingCharacters(in: .whitespaces) : a.hex
            ctx.draw(Text(cs).font(.psMono(10, weight: selected ? .bold : .medium))
                .foregroundStyle(selected ? Palette.brass : Palette.textSecondary),
                     at: CGPoint(x: p.x + 12, y: p.y), anchor: .leading)
        }
    }

    // ── HUD / control bar / selected bar / empty state ──────────────────────────
    private func hud(size: CGSize) -> some View {
        VStack {
            HStack {
                HStack(spacing: 12) {
                    Text("RADAR").font(.psMono(12, weight: .bold)).foregroundStyle(Palette.brass)
                    Text("\(vm.aircraft.count) aircraft  ·  \(Int(zoomNmPerWidth)) nm wide")
                        .font(.psMono(11)).foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Palette.cardBackground.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                Spacer()
            }
            Spacer()
        }
        .padding(12)
    }

    private var controlBar: some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 4) {
                    iconButton("scope") { panLat = 0; panLon = 0; zoomNmPerWidth = 400; gestureBaseZoom = 400 }
                    iconButton(vm.showTrails ? "square.stack.3d.up.fill" : "square.stack.3d.up",
                               tint: vm.showTrails ? Palette.brass : Palette.textMuted) { vm.toggleTrails() }
                    iconButton("arrow.clockwise", tint: Palette.textSecondary) { vm.clearTrails() }
                }
                .padding(.horizontal, 4).padding(.vertical, 2)
                .background(Palette.cardBackground.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Spacer()
        }
        .padding(12)
    }

    private func iconButton(_ icon: String, tint: Color = Palette.brass, action: @escaping () -> Void) -> some View {
        Button { HangarHaptics.tap(); action() } label: {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(tint)
                .frame(width: 40, height: 40)
        }
    }

    private func selectedBar(_ a: Aircraft) -> some View {
        HStack(spacing: 16) {
            Text((a.callsign?.trimmingCharacters(in: .whitespaces).isEmpty == false
                  ? a.callsign! : a.hex).uppercased())
                .font(.psMono(14, weight: .bold)).foregroundStyle(Palette.brass)
            Text("ALT \(a.altitudeBaro.map(String.init) ?? "—")").font(.psMono(11)).foregroundStyle(Palette.textSecondary)
            Text("GS \(a.groundSpeed.map { String(Int($0)) } ?? "—")").font(.psMono(11)).foregroundStyle(Palette.textSecondary)
            Text("TRK \(a.track.map { String(Int($0)) } ?? "—")").font(.psMono(11)).foregroundStyle(Palette.textSecondary)
        }
        .padding(12)
        .background(Palette.cardBackground.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyState: some View {
        Text(vm.aircraft.isEmpty
             ? "Waiting for aircraft data…\nReceiver at \(String(format: "%.4f", rxLat)), \(String(format: "%.4f", rxLon))"
             : "\(vm.aircraft.count) aircraft tracked\nNone with positions yet — pinch/drag to explore")
            .font(.psMono(13)).foregroundStyle(Palette.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 18).padding(.vertical, 12)
            .background(Palette.cardBackground.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private extension Double {
    func clamped(_ lo: Double, _ hi: Double) -> Double { Swift.min(Swift.max(self, lo), hi) }
}
