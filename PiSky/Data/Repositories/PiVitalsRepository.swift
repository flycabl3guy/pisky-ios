import Foundation
import Combine

/// Centralized telemetry hub — port of the Android `PiVitalsRepository`. Single poller for every
/// receiver-wide data category at its own cadence, plus a live 180-sample trend ring buffer
/// (~30 min @ 10 s) for the Trends dashboard:
///
///   - vitals   (`/pi-vitals.json`)       every  5 s
///   - stats+prom (`/data/stats.json` + `/data/stats.prom`)  every 10 s (atomic, one trend sample)
///   - rolling  (`/pi-rolling-24h.json`)  every 30 s
///   - outline  (`/data/outline.json`)    every 30 s
///   - receiver (`/data/receiver.json`)   every 60 s
///
/// `startPolling()` is idempotent — first call wins. All published values are delivered on the main
/// thread via `@MainActor`-confined `CurrentValueSubject`s.
@MainActor
final class PiVitalsRepository {
    private let connection: ConnectionRepository

    // MARK: - Published state (AnyPublisher, replays latest)

    private let vitalsSubject      = CurrentValueSubject<PiVitalsDto?, Never>(nil)
    private let statsSubject       = CurrentValueSubject<StatsDto?, Never>(nil)
    private let promSubject        = CurrentValueSubject<PromMetrics?, Never>(nil)
    private let feedsSubject       = CurrentValueSubject<[FeedConnector], Never>([])
    private let rollingSubject     = CurrentValueSubject<Rolling24hResponseDto?, Never>(nil)
    private let coverageSubject    = CurrentValueSubject<CoverageOutline?, Never>(nil)
    private let receiverSubject    = CurrentValueSubject<ReceiverStats?, Never>(nil)
    private let trendSubject       = CurrentValueSubject<[TrendSample], Never>([])
    private let vitalsErrorSubject = CurrentValueSubject<String?, Never>(nil)
    private let statsErrorSubject  = CurrentValueSubject<String?, Never>(nil)

    var vitals:      AnyPublisher<PiVitalsDto?, Never>          { vitalsSubject.eraseToAnyPublisher() }
    var stats:       AnyPublisher<StatsDto?, Never>             { statsSubject.eraseToAnyPublisher() }
    var prom:        AnyPublisher<PromMetrics?, Never>          { promSubject.eraseToAnyPublisher() }
    var feeds:       AnyPublisher<[FeedConnector], Never>       { feedsSubject.eraseToAnyPublisher() }
    var rolling:     AnyPublisher<Rolling24hResponseDto?, Never>{ rollingSubject.eraseToAnyPublisher() }
    var coverage:    AnyPublisher<CoverageOutline?, Never>      { coverageSubject.eraseToAnyPublisher() }
    var receiver:    AnyPublisher<ReceiverStats?, Never>        { receiverSubject.eraseToAnyPublisher() }
    var trend:       AnyPublisher<[TrendSample], Never>         { trendSubject.eraseToAnyPublisher() }
    var vitalsError: AnyPublisher<String?, Never>              { vitalsErrorSubject.eraseToAnyPublisher() }
    var statsError:  AnyPublisher<String?, Never>             { statsErrorSubject.eraseToAnyPublisher() }

    // Receiver coords for projecting the coverage polygon to bearing/range.
    private var recvLat = Self.cowdenLat
    private var recvLon = Self.cowdenLon

    private var started = false
    private var tasks: [Task<Void, Never>] = []

    private static let trendCap = 180
    private static let cowdenLat = 39.24554
    private static let cowdenLon = -88.85792

    init(connection: ConnectionRepository) {
        self.connection = connection
    }

    /// Start every poll loop. Idempotent — repeated calls are no-ops once started.
    func startPolling() {
        guard !started else { return }
        started = true
        ErrorLog.shared.log(level: "I", tag: "PiVitals", message: "starting telemetry poll loops")

        tasks.append(loop(intervalSec: 5)  { await self.refreshVitalsOnce() })
        tasks.append(loop(intervalSec: 10) { await self.refreshStatsAndProm() })
        tasks.append(loop(intervalSec: 30) { await self.refreshRollingOnce() })
        tasks.append(loop(intervalSec: 30) { await self.refreshOutlineOnce() })
        tasks.append(loop(intervalSec: 60) { await self.refreshReceiverOnce() })
    }

    func stopPolling() {
        for t in tasks { t.cancel() }
        tasks.removeAll()
        started = false
    }

    private func loop(intervalSec: UInt64, _ body: @escaping () async -> Void) -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                await body()
                if self == nil { return }
                try? await Task.sleep(nanoseconds: intervalSec * 1_000_000_000)
            }
        }
    }

    // MARK: - One-shots

    func refreshVitalsOnce() async {
        let cfg = await connection.getConfig()
        guard !cfg.hostname.isEmpty else { return }
        do {
            vitalsSubject.send(try await APIClient(config: cfg).getVitals())
            vitalsErrorSubject.send(nil)
        } catch {
            ErrorLog.shared.log(level: "D", tag: "PiVitals", message: "vitals fetch failed", error: error)
            vitalsErrorSubject.send("\(error)")
        }
    }

    /// Back-compat manual refresh (Wrench / Diagnostics pull-to-refresh).
    func refreshStatsOnce() async { await refreshStatsAndProm() }

    /// Stats + prom together so the appended trend sample is internally consistent.
    func refreshStatsAndProm() async {
        let cfg = await connection.getConfig()
        guard !cfg.hostname.isEmpty else { return }
        let api = APIClient(config: cfg)

        var fetchedStats: StatsDto? = nil
        do {
            let s = try await api.getStats()
            statsErrorSubject.send(nil)
            fetchedStats = s
            statsSubject.send(s)
        } catch {
            ErrorLog.shared.log(level: "D", tag: "PiVitals", message: "stats fetch failed", error: error)
            statsErrorSubject.send("\(error)")
        }

        do {
            let text = try await api.getStatsProm()
            let pm = PromMetrics.parse(text)
            promSubject.send(pm)
            feedsSubject.send(pm.connectors.map { $0.toDomain() })
        } catch {
            ErrorLog.shared.log(level: "D", tag: "PiVitals", message: "stats.prom fetch failed", error: error)
        }

        appendTrendSample(v: vitalsSubject.value, s: fetchedStats ?? statsSubject.value, p: promSubject.value)
    }

    func refreshRollingOnce() async {
        let cfg = await connection.getConfig()
        guard !cfg.hostname.isEmpty else { return }
        do {
            rollingSubject.send(try await APIClient(config: cfg).getRolling24h())
        } catch {
            ErrorLog.shared.log(level: "D", tag: "PiVitals", message: "rolling-24h fetch failed", error: error)
        }
    }

    func refreshOutlineOnce() async {
        let cfg = await connection.getConfig()
        guard !cfg.hostname.isEmpty else { return }
        do {
            let pts = try await APIClient(config: cfg).getOutline().actualRange?.last24h?.points ?? []
            coverageSubject.send(CoverageOutline.from(rawPoints: pts, recvLat: recvLat, recvLon: recvLon))
        } catch {
            ErrorLog.shared.log(level: "D", tag: "PiVitals", message: "outline fetch failed", error: error)
        }
    }

    func refreshReceiverOnce() async {
        let cfg = await connection.getConfig()
        guard !cfg.hostname.isEmpty else { return }
        do {
            let dto = try await APIClient(config: cfg).getReceiver()
            receiverSubject.send(dto.toDomain())
            if let lat = dto.lat { recvLat = lat }
            if let lon = dto.lon { recvLon = lon }
        } catch {
            ErrorLog.shared.log(level: "D", tag: "PiVitals", message: "receiver fetch failed", error: error)
        }
    }

    // MARK: - Trend ring buffer

    private func appendTrendSample(v: PiVitalsDto?, s: StatsDto?, p: PromMetrics?) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let last1 = s?.last1min
        let signal = last1?.local?.signal
        let noise = last1?.local?.noise
        let snr: Double? = (signal != nil && noise != nil) ? signal! - noise! : nil
        let mps: Double? = v?.bands?.band1090?.mps
            ?? last1.flatMap { $0.durationSec > 0 ? Double($0.messagesValid) / $0.durationSec : nil }
        let total = (s?.aircraftWithPos ?? 0) + (s?.aircraftWithoutPos ?? 0)
        // Per-window (last1min) only — the lifetime-cumulative prom distance_max would make the line
        // jump on quiet ticks, so don't blend it in.
        let maxRangeNm = last1.map(\.maxDistanceNm).flatMap { $0 > 0 ? $0 : nil }

        let sample = TrendSample(
            tsMs: nowMs,
            aircraftTotal: total > 0 ? total : v?.bands?.band1090?.aircraftCount,
            aircraftWithPos: s?.aircraftWithPos,
            messagesPerSec: mps,
            signalDbfs: signal,
            noiseDbfs: noise,
            snrDb: snr,
            cpuTempC: v?.temp?.celsius,
            gainDb: s?.gainDb,
            maxRangeNm: maxRangeNm,
            cpuLoad1m: v?.load?.load1m
        )
        var ring = trendSubject.value
        ring.append(sample)
        if ring.count > Self.trendCap { ring.removeFirst(ring.count - Self.trendCap) }
        trendSubject.send(ring)
    }
}
