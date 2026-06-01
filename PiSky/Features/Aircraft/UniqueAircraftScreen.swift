import SwiftUI
import Combine

// ─────────────────────────────────────────────────────────────────────────────
// UniqueAircraftViewModel
// ─────────────────────────────────────────────────────────────────────────────

@MainActor @Observable
final class UniqueAircraftViewModel {
    private(set) var uniqueToday: [UniqueAircraft] = []

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true; container = c
        c.aircraftRepository.observeUniqueToday()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.uniqueToday = $0 }
            .store(in: &bag)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// UniqueAircraftScreen
// ─────────────────────────────────────────────────────────────────────────────

struct UniqueAircraftScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = UniqueAircraftViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            legend
            if vm.uniqueToday.isEmpty {
                VStack {
                    Spacer()
                    Text("No aircraft seen yet today")
                        .font(.psMono(12, weight: .medium)).foregroundStyle(Palette.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(vm.uniqueToday) { UniqueAircraftRow(aircraft: $0) }
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
            Image(systemName: "airplane").font(.system(size: 18)).foregroundStyle(Palette.brassBright)
            Text("Today's Aircraft").font(.inter(16, weight: .semibold))
                .foregroundStyle(Palette.brassBright)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(vm.uniqueToday.count) unique").font(.psMono(10, weight: .medium))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Home · Aircraft · Today · Tagged · Map")
            Text("· Lists every unique aircraft seen since midnight")
            Text("· Shows callsign/reg, decoded name (C-17 Globemaster, FA-18 Hornet, F-35 Lightning II), type code + hex, first seen time")
            Text("· Unknown type codes show raw code — nothing hidden")
        }
        .font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.bottom, 8)
    }
}

private struct UniqueAircraftRow: View {
    let aircraft: UniqueAircraft

    private var decoded: String? { AircraftTypeNames.decode(aircraft.type) }
    private var primary: String {
        aircraft.callsign?.trimmedNonBlank
            ?? aircraft.registration?.trimmedNonBlank
            ?? aircraft.hex.uppercased()
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(primary).font(.psMono(14, weight: .bold)).foregroundStyle(Palette.brassBright)
                if let decoded {
                    Text(decoded).font(.inter(12)).foregroundStyle(Palette.textPrimary)
                }
                HStack(spacing: 6) {
                    if let type = aircraft.type {
                        Text(type.uppercased()).font(.psMono(10, weight: .medium))
                            .foregroundStyle(decoded != nil ? Palette.textMuted : Palette.cyan)
                        Text("·").font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textMuted)
                    }
                    Text(aircraft.hex.uppercased()).font(.psMono(10, weight: .medium))
                        .foregroundStyle(Palette.textMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 2) {
                Text(UniqueTimeFmt.time(aircraft.firstSeenMs))
                    .font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textMuted)
                if let reg = aircraft.registration?.trimmedNonBlank, reg != aircraft.callsign {
                    Text(reg).font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textSecondary)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

enum UniqueTimeFmt {
    private static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "h:mm a"; return f
    }()
    static func time(_ ms: Int64) -> String {
        timeFmt.string(from: Date(timeIntervalSince1970: Double(ms) / 1000))
    }
}
