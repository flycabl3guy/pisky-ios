import SwiftUI

/// HangarPlate — the foundational glass-card primitive for Hangar Luxe v6.
///
/// Ported from `core/ui/components/HangarPlate.kt`. A frosted plate with:
///   • A subtle vertical 3-stop gradient (PlateRaised → Plate → PlateSheet at 0.0/0.55/1.0)
///   • A brass-tinted hairline border, thicker (1.5) when `active`
///   • A top-edge bone highlight (glass sheen) over the top 10%
///   • A soft drop shadow at the requested elevation tier
///
/// API mirrors the Compose contract: `HangarPlate(radius:elevation:active:tint:) { content }`.
struct HangarPlate<Content: View>: View {
    var radius: CGFloat = HangarLuxe.Radius.medium
    var elevation: CGFloat = HangarLuxe.Elevation.plate
    var active: Bool = false
    var tint: Color? = nil
    var contentPadding: CGFloat = 16
    @ViewBuilder var content: () -> Content

    private var borderWidth: CGFloat {
        active ? HangarLuxe.Glass.borderActive : HangarLuxe.Glass.borderHairline
    }

    private var borderColor: Color {
        if let tint {
            return tint.opacity(active ? 0.55 : 0.32)
        }
        return active ? Palette.brass.opacity(0.55) : HangarLuxe.Glass.border
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: radius, style: .continuous) }

    // 3-stop plate gradient: PlateRaised (cardElevated) → Plate (cardBackground) → PlateSheet (cardSheet)
    private var plateGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: Palette.cardElevated,   location: 0.00),
                .init(color: Palette.cardBackground,  location: 0.55),
                .init(color: Palette.cardSheet,       location: 1.00),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    // Top-edge sheen: bone highlight fading to clear over the top 10%.
    private var highlightGradient: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: HangarLuxe.Glass.topHighlight, location: 0.0),
                .init(color: .clear,                         location: 0.10),
            ],
            startPoint: .top, endPoint: .bottom
        )
    }

    var body: some View {
        content()
            .padding(contentPadding)
            .background(plateGradient)
            .background(highlightGradient)
            .clipShape(shape)
            .overlay(shape.strokeBorder(borderColor, lineWidth: borderWidth))
            // Compose shadow(elevation, shape, clip=false): map the elevation tier to a soft shadow.
            .shadow(color: .black.opacity(0.45), radius: elevation, x: 0, y: elevation * 0.4)
    }
}

#Preview {
    ZStack {
        Palette.background.ignoresSafeArea()
        VStack(spacing: 16) {
            HangarPlate {
                Text("Plain plate").foregroundStyle(Palette.textPrimary)
            }
            HangarPlate(elevation: HangarLuxe.Elevation.raised, active: true, tint: Palette.cyan) {
                Text("Active cyan plate").foregroundStyle(Palette.textPrimary)
            }
        }
        .padding()
    }
}
