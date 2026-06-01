import SwiftUI
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// MilitaryViewModel
// ─────────────────────────────────────────────────────────────────────────────

@MainActor @Observable
final class MilitaryViewModel {
    private(set) var militaryToday: [UniqueAircraft] = []

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true; container = c

        // L2 publishes a fresh /pi-rolling-24h.json every 30 s — match that cadence so the tab
        // stays current independent of the Home screen.
        c.statsRepository.observeMilitaryHistory()
            .map { entries in entries.map(Self.enrich) }
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.militaryToday = $0 }
            .store(in: &bag)

        refreshTask = Task { [weak c] in
            while !Task.isCancelled {
                try? await c?.statsRepository.refresh24hStats()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    deinit { refreshTask?.cancel() }

    /// Map an L2 history row → UniqueAircraft, resolving a friendly type when L2 only captured a
    /// raw source-type token. Port of `MilitaryViewModel.kt`'s enrichment (mil CSV → hex DB).
    private static func enrich(_ e: MilitaryHistoryEntry) -> UniqueAircraft {
        let placeholder: Set<String> = ["mode_s", "adsb_icao", "other", "uat"]
        let captured = e.type?.trimmingCharacters(in: .whitespaces)
        let resolvedType: String?
        if let captured, !captured.isEmpty, !placeholder.contains(captured.lowercased()) {
            resolvedType = captured
        } else {
            let name = MilitaryHexDatabase.resolveName(hex: e.hex, callsign: e.callsign, type: e.type)
            resolvedType = name.isEmpty ? nil : name
        }
        return UniqueAircraft(
            hex: e.hex,
            type: resolvedType,
            callsign: e.callsign,
            registration: e.registration,
            firstSeenMs: e.firstSeenMs > 0 ? e.firstSeenMs : e.lastSeenMs,
            isMilitary: true
        )
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MilitaryScreen
// ─────────────────────────────────────────────────────────────────────────────

struct MilitaryScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = MilitaryViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            if vm.militaryToday.isEmpty {
                VStack {
                    Spacer()
                    Text("No military aircraft logged yet")
                        .font(.psMono(12, weight: .medium)).foregroundStyle(Palette.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.militaryToday) { MilitaryRow(aircraft: $0) }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                }
            }
        }
        .background(Palette.background.ignoresSafeArea())
        .task { vm.start(container) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "shield.lefthalf.filled").font(.system(size: 18))
                .foregroundStyle(Palette.brass)
            Text("Military").font(.inter(16, weight: .semibold)).foregroundStyle(Palette.brass)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(vm.militaryToday.count) total").font(.psMono(10, weight: .medium))
                .foregroundStyle(Palette.brass)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }
}

private struct MilitaryRow: View {
    let aircraft: UniqueAircraft

    private var primary: String {
        aircraft.callsign?.trimmedNonBlank
            ?? aircraft.registration?.trimmedNonBlank
            ?? aircraft.hex.uppercased()
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(primary).font(.psMono(14, weight: .bold)).foregroundStyle(Palette.brass)
                if let type = aircraft.type?.trimmedNonBlank {
                    Text(type).font(.inter(12)).foregroundStyle(Palette.textPrimary)
                }
                HStack(spacing: 6) {
                    Text(aircraft.hex.uppercased()).font(.psMono(10, weight: .medium))
                        .foregroundStyle(Palette.textMuted)
                    if let reg = aircraft.registration?.trimmedNonBlank, reg != aircraft.callsign {
                        Text("·").font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textMuted)
                        Text(reg).font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(MilTimeFmt.dateTime(aircraft.firstSeenMs))
                .font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textMuted)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// Date+time so the historical view distinguishes today's entries from earlier window entries.
enum MilTimeFmt {
    private static let dateTimeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MMM d · h:mm a"; return f
    }()
    static func dateTime(_ ms: Int64) -> String {
        dateTimeFmt.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}
