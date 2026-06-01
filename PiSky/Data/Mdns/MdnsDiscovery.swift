import Foundation
import Network
import Combine

/// Bonjour/mDNS discovery — port of the Android `MdnsDiscovery` (NsdManager). Browses `_http._tcp`
/// for services that look like a PiAware/readsb receiver and emits `DiscoveryResult` values on a
/// Combine publisher (the shape both `ConnectionViewModel` and `SettingsViewModel` consume).
/// `NWBrowser` replaces NsdManager; gated by the local-network permission (Info.plist).
final class MdnsDiscovery: @unchecked Sendable {
    private static let serviceType = "_http._tcp"
    private static let piawareNames = ["readsb", "tar1090", "piaware", "flightaware"]

    private let lock = NSLock()
    private var browser: NWBrowser?
    private var subject: PassthroughSubject<DiscoveryResult, Never>?
    private var seen = Set<String>()

    init() {}

    /// Start a browse. Emits `.searching` immediately, then `.found(hostname:port:)` per distinct
    /// match, and `.error` if the browser fails. Call `stop()` (or drop the subscription) to end it.
    func discover() -> AnyPublisher<DiscoveryResult, Never> {
        stop()
        let subject = PassthroughSubject<DiscoveryResult, Never>()
        lock.withLock { self.subject = subject; self.seen.removeAll() }

        let params = NWParameters()
        params.includePeerToPeer = true
        let browser = NWBrowser(for: .bonjour(type: Self.serviceType, domain: nil), using: params)
        lock.withLock { self.browser = browser }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            guard let self else { return }
            for result in results {
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                let lower = name.lowercased()
                guard Self.piawareNames.contains(where: { lower.contains($0) }) else { continue }
                let (host, port) = Self.resolved(result.endpoint)
                guard let host else { continue }
                let isNew: Bool = self.lock.withLock {
                    guard !self.seen.contains(host) else { return false }
                    self.seen.insert(host); return true
                }
                if isNew { subject.send(.found(hostname: host, port: port)) }
            }
        }
        browser.stateUpdateHandler = { state in
            if case let .failed(err) = state {
                subject.send(.error(message: err.localizedDescription))
            }
        }
        browser.start(queue: .global(qos: .utility))
        subject.send(.searching)
        return subject.eraseToAnyPublisher()
    }

    /// Stop the active browse session and complete the publisher.
    func stop() {
        let (b, s): (NWBrowser?, PassthroughSubject<DiscoveryResult, Never>?) = lock.withLock {
            let cb = browser, cs = subject
            browser = nil; subject = nil
            return (cb, cs)
        }
        b?.cancel()
        s?.send(completion: .finished)
    }

    /// Best-effort (host, port) from a resolved endpoint; falls back to a `.local` hint + the default
    /// port (mirrors the Android resolve-failed fallback). Bonjour browse results are usually
    /// unresolved `.service` endpoints, so the hostname is the actionable part.
    private static func resolved(_ endpoint: NWEndpoint) -> (String?, Int) {
        switch endpoint {
        case let .hostPort(host, port):
            let p = Int(port.rawValue)
            switch host {
            case let .name(name, _): return (name, p)
            case let .ipv4(addr):    return ("\(addr)", p)
            case let .ipv6(addr):    return ("\(addr)", p)
            @unknown default:        return (nil, p)
            }
        case let .service(name, _, _, _):
            let h = name.hasSuffix(".local") ? name : "\(name).local"
            return (h, ConnectionConfig.default.port)
        default:
            return (nil, ConnectionConfig.default.port)
        }
    }
}
