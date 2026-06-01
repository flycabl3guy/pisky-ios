import SwiftUI

/// PremiumButton — SwiftUI port of `core/ui/components/PremiumButton.kt`.
///
/// Ultra-premium button with a hairline top-edge bezel, spring press scale, and baked-in
/// haptics. Four variants (Primary/Secondary/Ghost/Danger). Icons are SF Symbol names
/// (the Compose `ImageVector` slot). `PremiumIconButton` is the icon-only square form.
///
/// Colour mapping (Compose → Palette):
///   FieldOlive = brassDim · FieldOliveDim = brassShadow · FieldOliveGlow = brassBright
///   PlatinumGold = brass · StatusError = signalRed · GlassBackground/GlassBorder = glass*

enum PremiumButtonVariant { case primary, secondary, ghost, danger }

private struct BtnColors {
    let fill: AnyShapeStyle
    let edge: Color
    let content: Color
}

private func variantPalette(_ variant: PremiumButtonVariant, pressed: Bool, enabled: Bool) -> BtnColors {
    if !enabled {
        return BtnColors(
            fill: AnyShapeStyle(Palette.cardElevated.opacity(0.4)),
            edge: Palette.glassBorder,
            content: Palette.textPrimary.opacity(0.4))
    }
    switch variant {
    case .primary:
        return BtnColors(
            fill: AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: Palette.brassDim.opacity(pressed ? 0.95 : 0.85), location: 0),
                    .init(color: Palette.brassShadow.opacity(pressed ? 0.75 : 0.65), location: 1),
                ], startPoint: .top, endPoint: .bottom)),
            edge: Palette.brass.opacity(pressed ? 0.85 : 0.55),
            content: Palette.brassBright)
    case .secondary:
        return BtnColors(
            fill: AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: Palette.glassBackground, location: 0),
                    .init(color: Palette.cardElevated.opacity(0.6), location: 1),
                ], startPoint: .top, endPoint: .bottom)),
            edge: Palette.brassDim.opacity(pressed ? 0.9 : 0.7),
            content: Palette.brassBright)
    case .ghost:
        return BtnColors(
            fill: AnyShapeStyle(Color.clear),
            edge: Palette.glassBorder,
            content: Palette.textPrimary)
    case .danger:
        return BtnColors(
            fill: AnyShapeStyle(LinearGradient(
                stops: [
                    .init(color: Palette.statusError.opacity(pressed ? 0.28 : 0.18), location: 0),
                    .init(color: Palette.statusError.opacity(0.08), location: 1),
                ], startPoint: .top, endPoint: .bottom)),
            edge: Palette.statusError.opacity(pressed ? 0.9 : 0.6),
            content: Palette.statusError)
    }
}

/// Top-edge machined-bezel hairline (Compose `topHairline`): a faint white line across the top.
private struct TopHairline: ViewModifier {
    let pressed: Bool
    func body(content: Content) -> some View {
        content.overlay(
            GeometryReader { geo in
                Path { p in
                    let inset: CGFloat = 8
                    p.move(to: CGPoint(x: inset, y: 0.5))
                    p.addLine(to: CGPoint(x: geo.size.width - inset, y: 0.5))
                }
                .stroke(Color.white.opacity(pressed ? 0.12 : 0.22), lineWidth: 1)
            }
        )
    }
}

struct PremiumButton: View {
    let action: () -> Void
    let text: String
    var variant: PremiumButtonVariant = .primary
    var icon: String? = nil
    var enabled: Bool = true
    var contentPaddingH: CGFloat = 18
    var contentPaddingV: CGFloat = 11
    var cornerRadius: CGFloat = 10

    @State private var pressed = false

    var body: some View {
        let colors = variantPalette(variant, pressed: pressed, enabled: enabled)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(colors.content)
            }
            Text(text)
                .font(.inter(13, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(colors.content)
        }
        .padding(.horizontal, contentPaddingH)
        .padding(.vertical, contentPaddingV)
        .frame(minHeight: 44)
        .background(colors.fill)
        .clipShape(shape)
        .overlay(shape.strokeBorder(colors.edge, lineWidth: 0.8))
        .modifier(TopHairline(pressed: pressed))
        .scaleEffect(pressed ? 0.96 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: pressed)
        .contentShape(shape)
        .gesture(pressGesture)
        .allowsHitTesting(enabled)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in if !pressed { pressed = true } }
            .onEnded { _ in
                pressed = false
                if enabled {
                    HangarHaptics.tap()
                    action()
                }
            }
    }
}

/// Icon-only premium button (square). `icon` is an SF Symbol name.
struct PremiumIconButton: View {
    let action: () -> Void
    let icon: String
    var accessibilityLabel: String? = nil
    var variant: PremiumButtonVariant = .secondary
    var size: CGFloat = 44
    var iconSize: CGFloat = 20
    var cornerRadius: CGFloat = 12
    var enabled: Bool = true

    @State private var pressed = false

    var body: some View {
        let colors = variantPalette(variant, pressed: pressed, enabled: enabled)
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        Image(systemName: icon)
            .font(.system(size: iconSize))
            .foregroundStyle(colors.content)
            .frame(width: size, height: size)
            .background(colors.fill)
            .clipShape(shape)
            .overlay(shape.strokeBorder(colors.edge, lineWidth: 0.8))
            .modifier(TopHairline(pressed: pressed))
            .scaleEffect(pressed ? 0.92 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.5), value: pressed)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !pressed { pressed = true } }
                    .onEnded { _ in
                        pressed = false
                        if enabled { HangarHaptics.tap(); action() }
                    }
            )
            .allowsHitTesting(enabled)
            .accessibilityLabel(accessibilityLabel ?? "")
    }
}

#Preview {
    VStack(spacing: 14) {
        PremiumButton(action: {}, text: "Primary", icon: "antenna.radiowaves.left.and.right")
        PremiumButton(action: {}, text: "Secondary", variant: .secondary)
        PremiumButton(action: {}, text: "Ghost", variant: .ghost)
        PremiumButton(action: {}, text: "Danger", variant: .danger)
        PremiumButton(action: {}, text: "Disabled", enabled: false)
        HStack(spacing: 12) {
            PremiumIconButton(action: {}, icon: "gearshape", variant: .secondary)
            PremiumIconButton(action: {}, icon: "trash", variant: .danger)
        }
    }
    .padding()
    .background(Palette.background)
}
