import SwiftUI

/// Responsive layout tokens — ported from `core/ui/theme/Dimensions.kt`.
///
/// Android provided `PhoneDimens` vs `TabletDimens` through a `CompositionLocal`; iOS uses an
/// `EnvironmentValues` key. The root view picks `.tablet` for regular-width size classes
/// (iPad / landscape) and `.phone` otherwise — same intent as the Android Tab S4 baseline.
struct Dimens: Equatable {
    var screenPadding: CGFloat
    var cardPadding: CGFloat
    var sectionSpacing: CGFloat
    var itemSpacing: CGFloat
    var cardCorner: CGFloat
    var cardBorderWidth: CGFloat
    var cardMinHeight: CGFloat
    var iconSmall: CGFloat
    var iconMedium: CGFloat
    var iconLarge: CGFloat
    var minTouchTarget: CGFloat
    var mapDetailPaneWidth: CGFloat
    var statsColumns: Int
    var aircraftListColumns: Int
    var headlineScale: CGFloat
    var bodyScale: CGFloat
    var heroCardHeight: CGFloat

    static let phone = Dimens(
        screenPadding: 16, cardPadding: 14, sectionSpacing: 20, itemSpacing: 8,
        cardCorner: 14, cardBorderWidth: 1, cardMinHeight: 64,
        iconSmall: 18, iconMedium: 24, iconLarge: 40, minTouchTarget: 48,
        mapDetailPaneWidth: 0, statsColumns: 2, aircraftListColumns: 1,
        headlineScale: 1.0, bodyScale: 1.0, heroCardHeight: 140
    )

    static let tablet = Dimens(
        screenPadding: 24, cardPadding: 20, sectionSpacing: 28, itemSpacing: 12,
        cardCorner: 16, cardBorderWidth: 1, cardMinHeight: 72,
        iconSmall: 22, iconMedium: 28, iconLarge: 48, minTouchTarget: 56,
        mapDetailPaneWidth: 380, statsColumns: 3, aircraftListColumns: 2,
        headlineScale: 1.15, bodyScale: 1.08, heroCardHeight: 180
    )
}

private struct DimensKey: EnvironmentKey {
    static let defaultValue: Dimens = .phone
}

extension EnvironmentValues {
    var dimens: Dimens {
        get { self[DimensKey.self] }
        set { self[DimensKey.self] = newValue }
    }
}

extension View {
    /// Inject the dimension set (call once near the root, driven by horizontal size class).
    func dimens(_ d: Dimens) -> some View { environment(\.dimens, d) }
}
