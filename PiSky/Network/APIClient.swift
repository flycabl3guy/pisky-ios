import Foundation

/// HTTP errors surfaced by `APIClient`.
enum APIClientError: Error, Sendable {
    case invalidURL(String)
    case badStatus(Int)
    case notHTTPResponse
}

/// URLSession-backed network client — ports both Retrofit services (`PiAwareApiService` +
/// `SkyAwareApiService`) onto one actor. JSON paths come straight from the Kotlin `@GET`
/// annotations. All requests are built from `ConnectionConfig.baseUrl` (the L2 :8088 front door,
/// which reverse-proxies /skyaware, /pi-vitals.json and /pi-rolling-24h.json).
///
/// Decoding is lenient by design: the DTO `init(from:)` implementations supply defaults for missing
/// keys, mirroring kotlinx's `ignoreUnknownKeys` + `coerceInputValues`.
actor APIClient {
    private let config: ConnectionConfig
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(config: ConnectionConfig, session: URLSession? = nil) {
        self.config = config
        if let session {
            self.session = session
        } else {
            let cfg = URLSessionConfiguration.default
            cfg.timeoutIntervalForRequest = 10     // connect
            cfg.timeoutIntervalForResource = 15    // resource
            cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
            self.session = URLSession(configuration: cfg)
        }
    }

    // MARK: - PiAwareApiService

    /// `skyaware/data/aircraft.json`
    func getAircraft() async throws -> AircraftResponseDto {
        try await getJSON("skyaware/data/aircraft.json")
    }

    /// `enrich/aircraft.json` — L2-side enriched feed (registration/type/desc/dbFlags/routeset).
    func getEnrichedAircraft() async throws -> AircraftResponseDto {
        try await getJSON("enrich/aircraft.json")
    }

    /// `skyaware978/data/aircraft.json` — UAT band (404 until dump978-fa is installed).
    func getUatAircraft() async throws -> AircraftResponseDto {
        try await getJSON("skyaware978/data/aircraft.json")
    }

    /// `data/outline.json` — actual coverage polygon (furthest decode per bearing, last 24 h).
    func getOutline() async throws -> OutlineDto {
        try await getJSON("data/outline.json")
    }

    /// `data/stats.prom` — raw Prometheus exposition text (parse with `PromMetrics.parse`).
    func getStatsProm() async throws -> String {
        try await getText("data/stats.prom")
    }

    /// `skyaware/data/receiver.json`
    func getReceiver() async throws -> ReceiverDto {
        try await getJSON("skyaware/data/receiver.json")
    }

    /// `skyaware/data/stats.json`
    func getStats() async throws -> StatsDto {
        try await getJSON("skyaware/data/stats.json")
    }

    /// `skyaware/pisky_mil_db.json` — gone on PiAware native; callers treat a 404 as "no DB".
    func getMilDb() async throws -> MilDbResponseDto {
        try await getJSON("skyaware/pisky_mil_db.json")
    }

    // MARK: - SkyAwareApiService

    /// `pi-vitals.json`
    func getVitals() async throws -> PiVitalsDto {
        try await getJSON("pi-vitals.json")
    }

    /// `pi-rolling-24h.json`
    func getRolling24h() async throws -> Rolling24hResponseDto {
        try await getJSON("pi-rolling-24h.json")
    }

    // MARK: - Transport

    private func getJSON<T: Decodable>(_ path: String) async throws -> T {
        let data = try await getData(path)
        return try decoder.decode(T.self, from: data)
    }

    private func getText(_ path: String) async throws -> String {
        let data = try await getData(path)
        return String(decoding: data, as: UTF8.self)
    }

    private func getData(_ path: String) async throws -> Data {
        let request = try makeRequest(path)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIClientError.notHTTPResponse }
        guard (200..<300).contains(http.statusCode) else { throw APIClientError.badStatus(http.statusCode) }
        return data
    }

    private func makeRequest(_ relativePath: String) throws -> URLRequest {
        let base = config.baseUrl.hasSuffix("/") ? config.baseUrl : config.baseUrl + "/"
        guard let url = URL(string: base + relativePath) else {
            throw APIClientError.invalidURL(base + relativePath)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if config.useBasicAuth, !config.username.isEmpty {
            let raw = "\(config.username):\(config.password)"
            let token = Data(raw.utf8).base64EncodedString()
            request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}
