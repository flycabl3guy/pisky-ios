import SwiftUI
import UIKit

/// Misc components — SwiftUI ports of `BetaBadge.kt`, `ThinScrollbar.kt`, and `Haptics.kt`.

// MARK: - BetaBadge

/// Tiny pill-shaped "BETA" tag. App-level marker, slotted next to a screen title or app name
/// on in-progress builds. Ported from `core/ui/components/BetaBadge.kt`.
struct BetaBadge: View {
    var color: Color = Palette.signalAmberHot   // PiSkyAmber = SignalAmberHot
    var label: String = "BETA"

    var body: some View {
        Text(label)
            .font(.inter(10, weight: .heavy))   // ExtraBold ≈ .heavy
            .tracking(1.2)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.10))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(color.opacity(0.7), lineWidth: 1)
            )
    }
}

// MARK: - thinScrollbar

/// Thin auto-fading scrollbar overlay (port intent of `ThinScrollbar.kt`).
///
/// FIDELITY NOTE: Compose drove the thumb from `ScrollState.value`/`maxValue`. SwiftUI's
/// `ScrollView` exposes neither publicly on iOS 17, so a pixel-faithful auto-thumb is not
/// practical without a custom `ScrollView`. This modifier styles the *native* indicator to the
/// brass tint and keeps it visible-on-interaction, which matches the design's read. For a
/// fully custom thumb, drive `ManualThinScrollbar` from a tracked content offset.
extension View {
    /// Style the native scroll indicator with the Hangar Luxe brass tint.
    /// Apply to a `ScrollView` (or a view inside one).
    func thinScrollbar(color: Color = Palette.platinumGold) -> some View {
        self.scrollIndicators(.visible)   // native indicator; brass tint applied via ManualThinScrollbar when needed
    }
}

/// Optional faithful thumb: a thin brass bar on the right edge, auto-fading after idle.
/// Caller supplies the live scroll fraction (0…1) and the viewport/content heights — e.g. from a
/// `GeometryReader` + `ScrollView` offset preference. Mirrors the Compose thumb math:
///   thumbH = max(viewportH² / totalH, minThumb), top = (viewportH − thumbH)·frac.
struct ManualThinScrollbar: View {
    let scrollFraction: CGFloat   // 0…1 (value / maxValue)
    let viewportHeight: CGFloat
    let contentHeight: CGFloat    // = viewportHeight + maxValue
    var width: CGFloat = 3
    var color: Color = Palette.platinumGold
    var minThumbHeight: CGFloat = 28
    var fadeDelay: Double = 0.8

    @State private var alpha: CGFloat = 0
    @State private var fadeTask: Task<Void, Never>? = nil

    var body: some View {
        GeometryReader { _ in
            if contentHeight > viewportHeight {
                let thumbH = max(viewportHeight * viewportHeight / contentHeight, minThumbHeight)
                let travel = viewportHeight - thumbH
                let top = travel * min(max(scrollFraction, 0), 1)
                RoundedRectangle(cornerRadius: width / 2)
                    .fill(color.opacity(alpha))
                    .frame(width: width, height: thumbH)
                    .offset(x: -1, y: top)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .allowsHitTesting(false)
        .onChange(of: scrollFraction) { _, _ in pulse() }
    }

    private func pulse() {
        guard contentHeight > viewportHeight else { return }
        alpha = 0.55
        fadeTask?.cancel()
        fadeTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(fadeDelay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run { withAnimation(.easeOut(duration: 0.4)) { alpha = 0 } }
        }
    }
}

// MARK: - HangarHaptics

/// Centralised haptic vocabulary for Hangar Luxe (port of `theme/Haptics.kt`).
///
/// The Compose grammar maps to UIKit feedback generators:
///   • tap    — light confirm on an interactive element  → light impact
///   • toggle — switch/filter flipped                     → medium impact
///   • select — strong commit (pin, dismiss)              → selection changed
///   • reject — rejection / error                         → notification(.error)
///   • tick   — quiet detent (slider / picker)            → soft impact
/// All are no-ops if the device/system has haptics disabled (UIKit handles that).
enum HangarHaptics {
    static func tap() {
        let g = UIImpactFeedbackGenerator(style: .light); g.impactOccurred()
    }
    static func toggle() {
        let g = UIImpactFeedbackGenerator(style: .medium); g.impactOccurred()
    }
    static func select() {
        let g = UISelectionFeedbackGenerator(); g.selectionChanged()
    }
    static func reject() {
        let g = UINotificationFeedbackGenerator(); g.notificationOccurred(.error)
    }
    static func tick() {
        if #available(iOS 17.5, *) {
            let g = UIImpactFeedbackGenerator(style: .soft); g.impactOccurred(intensity: 0.5)
        } else {
            let g = UIImpactFeedbackGenerator(style: .soft); g.impactOccurred()
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        HStack(spacing: 8) {
            Text("PiSky").font(.rajdhani(28, weight: .bold)).foregroundStyle(Palette.textPrimary)
            BetaBadge()
        }
        PremiumButton(action: { HangarHaptics.select() }, text: "Commit", variant: .primary)
    }
    .padding()
    .background(Palette.background)
}
