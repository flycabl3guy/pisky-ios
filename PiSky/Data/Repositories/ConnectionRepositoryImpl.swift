import Foundation
import Combine

/// `ConnectionRepository` over `ConnectionStore` — port of `ConnectionRepositoryImpl`. Applies the
/// post-Ultrafeeder `migrate()` coercion: stale `192.168.1.54:80` (Pi lighttpd) and
/// `192.168.1.207:8000` (deprecated CENTRAL FastAPI) configs snap back to `ConnectionConfig.default`
/// (L2 nginx :8088), preserving credentials. Idempotent.
@MainActor
final class ConnectionRepositoryImpl: ConnectionRepository {
    private let store: ConnectionStore

    init(store: ConnectionStore) {
        self.store = store
    }

    private func migrate(_ c: ConnectionConfig) -> ConnectionConfig {
        let stale = (c.hostname == "192.168.1.54" && c.port == 80)
                 || (c.hostname == "192.168.1.207" && c.port == 8000)
        guard stale else { return c }
        var migrated = c
        migrated.hostname = ConnectionConfig.default.hostname
        migrated.port = ConnectionConfig.default.port
        return migrated   // credentials (username/password/useBasicAuth) preserved
    }

    func observeConfig() -> AnyPublisher<ConnectionConfig, Never> {
        store.observeConfig().map { [weak self] in self?.migrate($0) ?? $0 }.eraseToAnyPublisher()
    }

    func saveConfig(_ config: ConnectionConfig) async {
        await store.saveConfig(config)
    }

    func getConfig() async -> ConnectionConfig {
        migrate(await store.getConfig())
    }

    func setOnboarded(_ value: Bool) async {
        await store.setOnboarded(value)
    }

    func isOnboarded() async -> Bool {
        await store.isOnboarded()
    }
}
