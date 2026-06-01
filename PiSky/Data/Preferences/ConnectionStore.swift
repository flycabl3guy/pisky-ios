import Foundation
import Combine

/// UserDefaults + Keychain backing for the connection settings — port of `ConnectionPreferences`.
/// hostname/port/username/useBasicAuth + onboarded live in UserDefaults; the password lives in the
/// Keychain. Exposes an `observeConfig` publisher (hot, replays latest) plus async get/save matching
/// the Kotlin `getConfig`/`saveConfig`/`isOnboarded`/`setOnboarded` surface.
@MainActor
final class ConnectionStore {
    private let defaults: UserDefaults

    private enum Key {
        static let hostname  = "hostname"
        static let port      = "port"
        static let username  = "username"
        static let basicAuth = "use_basic_auth"
        static let onboarded = "onboarded"
        static let passwordKeychain = "connection_password"
    }

    private let configSubject: CurrentValueSubject<ConnectionConfig, Never>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.configSubject = .init(ConnectionConfig.default)
        // Seed with the persisted config now that `self` is initialized.
        self.configSubject.send(readConfig())
    }

    /// Live config stream — replays latest. Callers (and `ConnectionRepositoryImpl`) map `migrate`.
    func observeConfig() -> AnyPublisher<ConnectionConfig, Never> {
        configSubject.eraseToAnyPublisher()
    }

    func getConfig() async -> ConnectionConfig { readConfig() }

    func saveConfig(_ config: ConnectionConfig) async {
        defaults.set(config.hostname, forKey: Key.hostname)
        defaults.set(config.port, forKey: Key.port)
        defaults.set(config.username, forKey: Key.username)
        defaults.set(config.useBasicAuth, forKey: Key.basicAuth)
        if config.password.isEmpty {
            Keychain.delete(Key.passwordKeychain)
        } else {
            Keychain.set(config.password, for: Key.passwordKeychain)
        }
        configSubject.send(config)
    }

    func isOnboarded() async -> Bool {
        defaults.object(forKey: Key.onboarded) == nil ? false : defaults.bool(forKey: Key.onboarded)
    }

    func setOnboarded(_ value: Bool) async {
        defaults.set(value, forKey: Key.onboarded)
    }

    // MARK: - Private

    private func readConfig() -> ConnectionConfig {
        let def = ConnectionConfig.default
        let hostname = defaults.string(forKey: Key.hostname) ?? def.hostname
        let port = defaults.object(forKey: Key.port) == nil ? def.port : defaults.integer(forKey: Key.port)
        let username = defaults.string(forKey: Key.username) ?? ""
        let password = Keychain.get(Key.passwordKeychain) ?? ""
        let useBasicAuth = defaults.object(forKey: Key.basicAuth) == nil ? false : defaults.bool(forKey: Key.basicAuth)
        return ConnectionConfig(
            hostname: hostname,
            port: port,
            username: username,
            password: password,
            useBasicAuth: useBasicAuth,
            serverType: .piaware
        )
    }
}
