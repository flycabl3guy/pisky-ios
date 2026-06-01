import SwiftUI

/// `HomeScreen` — port of `HomeScreen.kt` (v6 Hangar Luxe). Contract §5:
/// `HomeScreen(onNavigateToSettings: () -> Void)`.
///
/// A single instrument face: a slim header (PISKY wordmark left; live status pill + settings cog
/// right), the `RadarHero` scope plotting every live aircraft by (distance, bearing), and a
/// brass-bordered `HeroStatPlate` with the four hero numbers. Adapts to a side-by-side layout in
/// landscape (radar left, header + plate right), vertical stack in portrait.
struct HomeScreen: View {
    let onNavigateToSettings: () -> Void

    @Environment(AppContainer.self) private var container
    @Environment(\.dimens) private var dimens
    @State private var vm = HomeViewModel()

    init(onNavigateToSettings: @escaping () -> Void) { self.onNavigateToSettings = onNavigateToSettings }

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            ZStack {
                Palette.background.ignoresSafeArea()
                if landscape { landscapeLayout(geo) } else { portraitLayout }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task { vm.start(container) }
    }

    // ── Layouts ────────────────────────────────────────────────────────────────
    private func landscapeLayout(_ geo: GeometryProxy) -> some View {
        HStack(spacing: 0) {
            RadarHero(aircraft: vm.allAircraft, maxRangeNm: max(vm.peakRangeNm, vm.currentRangeNm, 50))
                .frame(maxHeight: .infinity)
                .padding(dimens.screenPadding)
                .frame(maxWidth: geo.size.height)
            VStack(spacing: 16) {
                header(compact: true)
                HeroStatPlate(visible: vm.visibleCount, closestNm: vm.closestAircraft?.distanceNm,
                              maxRangeNm: vm.peakRangeNm,
                              militaryToday: max(vm.militaryToday.count, vm.rolling24hStats.militarySeen))
                Spacer()
            }
            .padding(dimens.screenPadding)
            .frame(maxWidth: .infinity)
        }
    }

    private var portraitLayout: some View {
        ScrollView {
            VStack(spacing: 0) {
                header(compact: false)
                Spacer().frame(height: 8)
                RadarHero(aircraft: vm.allAircraft, maxRangeNm: max(vm.peakRangeNm, vm.currentRangeNm, 50))
                    .padding(.horizontal, dimens.screenPadding)
                Spacer().frame(height: 14)
                HeroStatPlate(visible: vm.visibleCount, closestNm: vm.closestAircraft?.distanceNm,
                              maxRangeNm: vm.peakRangeNm,
                              militaryToday: max(vm.militaryToday.count, vm.rolling24hStats.militarySeen))
                    .padding(.horizontal, dimens.screenPadding)
                Spacer().frame(height: 24)
            }
        }
    }

    // ── Header row ──────────────────────────────────────────────────────────────
    private func header(compact: Bool) -> some View {
        HStack(alignment: .center) {
            HStack(spacing: 0) {
                Text("PI").font(.rajdhani(26, weight: .bold)).tracking(1.6).foregroundStyle(Palette.textPrimary)
                Text("SKY").font(.rajdhani(26, weight: .bold)).tracking(1.6).foregroundStyle(Palette.brassBright)
            }
            Spacer()
            StatusPill(host: vm.host, status: vm.statusKind)
            Button { HangarHaptics.tap(); onNavigateToSettings() } label: {
                Image(systemName: "gearshape.fill").foregroundStyle(Palette.brass.opacity(0.85))
            }
            .padding(.leading, 8)
        }
        .padding(.horizontal, compact ? 0 : dimens.screenPadding)
        .padding(.vertical, compact ? 4 : 12)
    }
}
