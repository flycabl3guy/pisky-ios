import SwiftUI
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// FavoritesViewModel
// ─────────────────────────────────────────────────────────────────────────────

@MainActor @Observable
final class FavoritesViewModel {
    /// Favorites currently live in the feed — shown with fresh data, sorted by callsign.
    private(set) var liveAircraft: [Aircraft] = []
    /// All saved favorite hex codes (even if not currently visible).
    private(set) var favoriteHexCodes: Set<String> = []

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true; container = c

        c.aircraftRepository.observeAircraft()
            .combineLatest(c.aircraftRepository.observeFavoriteHexCodes())
            .map { aircraft, favs in
                aircraft.filter { favs.contains($0.hex) }
                    .sorted { $0.displayCallsign < $1.displayCallsign }
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.liveAircraft = $0 }
            .store(in: &bag)

        c.aircraftRepository.observeFavoriteHexCodes()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.favoriteHexCodes = $0 }
            .store(in: &bag)
    }

    /// Saved favorites that are not currently overhead, sorted.
    var offlineHexes: [String] {
        favoriteHexCodes.subtracting(liveAircraft.map(\.hex)).sorted()
    }

    func removeFavorite(_ hex: String) {
        Task { await container?.aircraftRepository.removeFavorite(hex: hex) }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// FavoritesScreen
// ─────────────────────────────────────────────────────────────────────────────

struct FavoritesScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = FavoritesViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            if vm.favoriteHexCodes.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if !vm.liveAircraft.isEmpty {
                            sectionLabel("LIVE NOW", color: Palette.brassBright)
                            ForEach(vm.liveAircraft) { ac in
                                FavoriteRow(
                                    callsign: ac.displayCallsign,
                                    subtitle: "\(ac.altitudeDisplay)  \(ac.speedDisplay)",
                                    isLive: true,
                                    accentColor: ac.isMlat ? Palette.signalAmberHot : Palette.brassBright,
                                    onRemove: { vm.removeFavorite(ac.hex) }
                                )
                                Spacer().frame(height: 8)
                            }
                        }
                        if !vm.offlineHexes.isEmpty {
                            sectionLabel("SAVED", color: Palette.textMuted)
                            ForEach(vm.offlineHexes, id: \.self) { hex in
                                FavoriteRow(
                                    callsign: hex.uppercased(),
                                    subtitle: "Not currently visible",
                                    isLive: false,
                                    accentColor: Palette.textMuted,
                                    onRemove: { vm.removeFavorite(hex) }
                                )
                                Spacer().frame(height: 8)
                            }
                        }
                        Spacer().frame(height: 16)
                    }
                    .padding(.horizontal, 16).padding(.top, 4)
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .task { vm.start(container) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill").font(.system(size: 18)).foregroundStyle(Palette.statusError)
            Text("Favorites").font(.inter(16, weight: .semibold)).foregroundStyle(Palette.brassBright)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(vm.favoriteHexCodes.count)").font(.psMono(10, weight: .medium))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func sectionLabel(_ text: String, color: Color) -> some View {
        Text(text).font(.psMono(10, weight: .medium)).foregroundStyle(color)
            .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "heart").font(.system(size: 36)).foregroundStyle(Palette.textMuted)
            Text("No favorites yet").font(.inter(14)).foregroundStyle(Palette.textMuted)
            Text("Tap the heart icon on any aircraft to save it here.")
                .font(.inter(12)).foregroundStyle(Palette.textMuted)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct FavoriteRow: View {
    let callsign: String
    let subtitle: String
    let isLive: Bool
    let accentColor: Color
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text(callsign).font(.psMono(14, weight: .bold)).foregroundStyle(accentColor)
                    if isLive {
                        Text("LIVE").font(.psMono(10, weight: .medium)).foregroundStyle(Palette.brassBright)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(Palette.brassBright.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
                Text(subtitle).font(.inter(12)).foregroundStyle(Palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { HangarHaptics.reject(); onRemove() } label: {
                Image(systemName: "heart.fill").font(.system(size: 18))
                    .foregroundStyle(Palette.statusError).frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
