import SwiftUI
import Combine

/// A tagged aircraft and its live counterpart (nil if not currently overhead). Port of
/// `TaggedAircraftItem` in TagsViewModel.kt.
struct TaggedAircraftItem: Identifiable, Equatable {
    let tag: AircraftTag
    let live: Aircraft?
    var id: String { tag.hex }
}

// ─────────────────────────────────────────────────────────────────────────────
// TagsViewModel
// ─────────────────────────────────────────────────────────────────────────────

@MainActor @Observable
final class TagsViewModel {
    private(set) var taggedItems: [TaggedAircraftItem] = []

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private weak var container: AppContainer?
    private var started = false

    func start(_ c: AppContainer) {
        guard !started else { return }
        started = true; container = c

        c.tagRepository.observeAll()
            .combineLatest(c.aircraftRepository.observeAircraft())
            .map { tags, liveAircraft in
                let byHex = Dictionary(liveAircraft.map { ($0.hex, $0) }, uniquingKeysWith: { a, _ in a })
                return tags.map { TaggedAircraftItem(tag: $0, live: byHex[$0.hex]) }
            }
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.taggedItems = $0 }
            .store(in: &bag)
    }

    /// Items grouped by category, in TagCategory declaration order (matches the Kotlin
    /// `TagCategory.entries.forEach`).
    var grouped: [(category: TagCategory, items: [TaggedAircraftItem])] {
        let buckets = Dictionary(grouping: taggedItems, by: { $0.tag.category })
        return TagCategory.allCases.compactMap { cat in
            guard let items = buckets[cat], !items.isEmpty else { return nil }
            return (cat, items)
        }
    }

    func untag(_ hex: String) { Task { await container?.tagRepository.untag(hex: hex) } }
    func retag(_ hex: String, _ category: TagCategory) {
        Task { await container?.tagRepository.tag(hex: hex, category: category, note: "") }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// TagsScreen
// ─────────────────────────────────────────────────────────────────────────────

struct TagsScreen: View {
    @Environment(AppContainer.self) private var container
    @State private var vm = TagsViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            if vm.taggedItems.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(vm.grouped, id: \.category) { group in
                            Text(group.category.label).font(.psMono(12, weight: .medium))
                                .foregroundStyle(tagCategoryColor(group.category))
                                .padding(.top, 8).padding(.bottom, 4)
                            ForEach(group.items) { item in
                                TaggedRow(item: item) { vm.untag(item.tag.hex) }
                            }
                        }
                        Spacer().frame(height: 8)
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
            Image(systemName: "tag.fill").font(.system(size: 20)).foregroundStyle(Palette.brassBright)
            Text("Tagged Aircraft").font(.inter(16, weight: .semibold)).foregroundStyle(Palette.brassBright)
            Spacer()
            Text("\(vm.taggedItems.count) tagged").font(.psMono(10, weight: .medium))
                .foregroundStyle(Palette.textMuted)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: "tag").font(.system(size: 44)).foregroundStyle(Palette.textMuted)
            Spacer().frame(height: 12)
            Text("No tagged aircraft").font(.inter(14)).foregroundStyle(Palette.textMuted)
            Spacer().frame(height: 4)
            Text("Tag aircraft from the detail sheet").font(.inter(12)).foregroundStyle(Palette.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TaggedRow: View {
    let item: TaggedAircraftItem
    let onUntag: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Circle()
                .fill(item.live != nil ? Palette.brassBright : Palette.textMuted.opacity(0.4))
                .frame(width: 8, height: 8)
            Spacer().frame(width: 10)
            VStack(alignment: .leading, spacing: 0) {
                Text(item.live?.displayCallsign ?? item.tag.hex.uppercased())
                    .font(.psMono(14)).foregroundStyle(Palette.textPrimary)
                HStack(spacing: 8) {
                    if let ac = item.live {
                        Text(ac.altitudeDisplay).font(.psMono(10, weight: .medium))
                            .foregroundStyle(Palette.textSecondary)
                        if let type = ac.type {
                            Text(type).font(.psMono(10, weight: .medium)).foregroundStyle(Palette.textMuted)
                        }
                    } else {
                        Text("Not overhead").font(.psMono(10, weight: .medium))
                            .foregroundStyle(Palette.textMuted)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(item.tag.category.label).font(.psMono(10, weight: .medium))
                .foregroundStyle(tagCategoryColor(item.tag.category))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(tagCategoryColor(item.tag.category).opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Button { HangarHaptics.reject(); onUntag() } label: {
                Image(systemName: "bookmark.slash").font(.system(size: 18))
                    .foregroundStyle(Palette.textMuted).frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(Palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
