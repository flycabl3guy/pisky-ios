import SwiftUI

/// Atlas HUD kit — the shared vocabulary for every Data Atlas page.
/// Ported from `core/ui/components/AtlasHud.kt`: section labels, big stats, stat plates,
/// metric rows, linear meter, segmented distribution bar, live-pulse dot, chips, page scaffold.
///
/// `qualityColor(_:)` already lives in HangarLuxe.swift — reuse it, do not redefine.

// MARK: - SectionLabel

/// Brass-uppercase section header with a hairline trailing rule.
struct SectionLabel: View {
    let text: String
    var accent: Color = Palette.brass
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(accent)
                .frame(width: 3, height: 13)
            Spacer().frame(width: 8)
            Text(text.uppercased())
                .font(.inter(12, weight: .bold))
                .tracking(1.6)
                .foregroundStyle(accent)
            Spacer().frame(width: 10)
            Rectangle()
                .fill(Palette.outline)
                .frame(height: 1)
                .frame(maxWidth: .infinity)
            if let trailing {
                Spacer().frame(width: 8)
                Text(trailing)
                    .font(.inter(11))
                    .foregroundStyle(Palette.textMuted)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}

// MARK: - BigStat

/// Big hero number with a unit and caption — the workhorse headline metric.
struct BigStat: View {
    let value: String
    let label: String
    var unit: String? = nil
    var valueColor: Color = Palette.textPrimary
    var accent: Color = Palette.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.psMono(32, weight: .bold))
                    .tracking(-0.5)
                    .foregroundStyle(valueColor)
                if let unit {
                    Text(unit)
                        .font(.inter(13, weight: .medium))
                        .foregroundStyle(Palette.textMuted)
                        .padding(.bottom, 5)
                }
            }
            HStack(spacing: 6) {
                Circle().fill(accent).frame(width: 5, height: 5)
                Text(label.uppercased())
                    .font(.inter(10, weight: .medium))
                    .tracking(1)
                    .foregroundStyle(Palette.textMuted)
            }
        }
    }
}

// MARK: - StatPlate

/// Compact label/value plate on glass — the grid building-block.
struct StatPlate: View {
    let label: String
    let value: String
    var sub: String? = nil
    var accent: Color = Palette.cyan
    var valueColor: Color = Palette.textPrimary

    var body: some View {
        HangarPlate(tint: accent.opacity(0.5), contentPadding: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label.uppercased())
                    .font(.inter(10, weight: .medium))
                    .tracking(0.8)
                    .foregroundStyle(Palette.textMuted)
                Spacer().frame(height: 5)
                Text(value)
                    .font(.psMono(19, weight: .bold))
                    .foregroundStyle(valueColor)
                if let sub {
                    Text(sub)
                        .font(.inter(10))
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - MetricRow

/// Two-column metric row — label left (muted), value right (bone, mono).
struct MetricRow: View {
    let label: String
    let value: String
    var valueColor: Color = Palette.textPrimary
    var sub: String? = nil

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.inter(13))
                    .foregroundStyle(Palette.textSecondary)
                if let sub {
                    Text(sub)
                        .font(.inter(10))
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(value)
                .font(.psMono(14, weight: .semibold))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
    }
}

// MARK: - LinearMeter

/// Horizontal meter with a track, a filled portion, and a value caption.
struct LinearMeter: View {
    let fraction: Double
    let label: String
    let valueText: String
    var color: Color = Palette.cyan
    var height: CGFloat = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(label)
                    .font(.inter(12))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(valueText)
                    .font(.psMono(12, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
            }
            .frame(maxWidth: .infinity)
            Spacer().frame(height: 5)
            Canvas { ctx, size in
                let r = size.height / 2
                let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: r)
                ctx.fill(track, with: .color(Palette.outline.opacity(0.6)))
                let w = size.width * CGFloat(min(max(fraction, 0), 1))
                if w > 0 {
                    let fill = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: size.height), cornerRadius: r)
                    ctx.fill(fill, with: .color(color))
                }
            }
            .frame(height: height)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - SegmentBar

/// One slice of a stacked distribution bar.
struct Segment: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let color: Color
}

/// Proportional stacked distribution bar with a legend below.
struct SegmentBar: View {
    let segments: [Segment]
    var height: CGFloat = 14
    var showLegend: Bool = true

    private var total: Double { max(segments.reduce(0) { $0 + $1.value }, 1e-9) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Canvas { ctx, size in
                var x: CGFloat = 0
                for seg in segments {
                    let w = size.width * CGFloat(seg.value / total)
                    let rect = Path(CGRect(x: x, y: 0, width: w, height: size.height))
                    ctx.fill(rect, with: .color(seg.color))
                    x += w
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            if showLegend {
                Spacer().frame(height: 8)
                // FlowRow analog — wrapping HStacks via a simple flexible grid of chips.
                AtlasFlow(spacing: 12, lineSpacing: 4) {
                    ForEach(segments.filter { $0.value > 0 }) { seg in
                        HStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(seg.color)
                                .frame(width: 8, height: 8)
                            Text("\(seg.label) \(formatNumber(seg.value))")
                                .font(.inter(11))
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func formatNumber(_ v: Double) -> String {
        v == v.rounded() ? String(Int(v)) : String(format: "%g", v)
    }
}

/// Minimal wrapping layout (iOS 16+ `Layout`) standing in for Compose `FlowRow`.
struct AtlasFlow: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > maxWidth, x > 0 {
                x = 0; y += lineH + lineSpacing; lineH = 0
            }
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        for sv in subviews {
            let s = sv.sizeThatFits(.unspecified)
            if x + s.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX; y += lineH + lineSpacing; lineH = 0
            }
            sv.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
    }
}

// MARK: - LiveDot

/// Pulsing "live" dot — telegraphs that data is streaming.
/// Pulse: 0.35 → 1.0 over 900 ms, reversing. Outer halo @ pulse·0.30, core @ pulse.
struct LiveDot: View {
    var color: Color = Palette.cyan
    var size: CGFloat = 9

    @State private var pulse: CGFloat = 0.35

    var body: some View {
        Canvas { ctx, sz in
            let minDim = min(sz.width, sz.height)
            let center = CGPoint(x: sz.width / 2, y: sz.height / 2)
            let halo = Path(ellipseIn: CGRect(
                x: center.x - minDim / 2, y: center.y - minDim / 2, width: minDim, height: minDim))
            ctx.fill(halo, with: .color(color.opacity(pulse * 0.30)))
            let coreR = minDim / 4.5
            let core = Path(ellipseIn: CGRect(
                x: center.x - coreR, y: center.y - coreR, width: coreR * 2, height: coreR * 2))
            ctx.fill(core, with: .color(color.opacity(pulse)))
        }
        .frame(width: size, height: size)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = 1.0
            }
        }
    }
}

// MARK: - AtlasChip

/// Small status/category pill.
struct AtlasChip: View {
    let text: String
    var color: Color = Palette.brass

    var body: some View {
        Text(text)
            .font(.inter(10.5, weight: .semibold))
            .tracking(0.5)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 3)
            .background(color.opacity(0.14))
            .clipShape(Capsule())
    }
}

// MARK: - AtlasScaffold

/// Page shell shared by every Data Atlas screen: graphite background, header with a big
/// title + optional pulsing live dot + subtitle + optional actions, then a scrolling column.
struct AtlasScaffold<Actions: View, Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var accent: Color = Palette.brass
    var live: Bool = true
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        accent: Color = Palette.brass,
        live: Bool = true,
        @ViewBuilder actions: @escaping () -> Actions = { EmptyView() },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.accent = accent
        self.live = live
        self.actions = actions
        self.content = content
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 8) {
                            Text(title)
                                .font(.inter(22, weight: .bold))
                                .tracking(0.5)
                                .foregroundStyle(Palette.textPrimary)
                            if live {
                                LiveDot(color: accent, size: 8)
                            }
                        }
                        if let subtitle {
                            Text(subtitle)
                                .font(.inter(11))
                                .foregroundStyle(Palette.textMuted)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    actions()
                }
                .frame(maxWidth: .infinity)
                Spacer().frame(height: 12)
                content()
                Spacer().frame(height: 28)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .background(Palette.background.ignoresSafeArea())
    }
}

#Preview {
    AtlasScaffold(title: "Signal Lab", subtitle: "live RF telemetry", accent: Palette.cyan) {
        VStack(spacing: 16) {
            SectionLabel(text: "Overview", trailing: "now")
            BigStat(value: "42", label: "aircraft", unit: "ac", accent: Palette.cyan)
            HStack {
                StatPlate(label: "Max range", value: "187", sub: "nm")
                StatPlate(label: "Msg rate", value: "1.2k", accent: Palette.brass)
            }
            MetricRow(label: "Median RSSI", value: "-21.4 dB")
            LinearMeter(fraction: 0.72, label: "Integrity", valueText: "72%", color: qualityColor(0.72))
            SegmentBar(segments: [
                Segment(label: "ADS-B", value: 30, color: Palette.cyan),
                Segment(label: "MLAT", value: 8, color: Palette.brass),
                Segment(label: "Other", value: 4, color: Palette.signalAmberHot),
            ])
            AtlasChip(text: "BETA")
        }
    }
}
