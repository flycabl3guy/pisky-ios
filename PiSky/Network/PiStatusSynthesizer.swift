import Foundation

/// Synthesize a `PiStatusDto` from PiAware-native sources — `pi-vitals.json` for system telemetry
/// and `skyaware/data/stats.json` (readsb) for decoder stats. Port of `PiStatusSynthesizer.kt`.
/// Replaces the retired pisky-troubleshooter dashboard so the Diagnostics screen renders unchanged.
enum PiStatusSynthesizer {

    static func synthesize(vitals: PiVitalsDto, stats: StatsDto?) -> PiStatusDto {
        let svcPiaware = ServiceDto(
            active: vitals.services?.piawareToFa == true,
            enabled: true,
            state: vitals.services?.piawareToFa == true ? "active (running)" : "inactive (dead)",
            status: ""
        )
        let svcDecoder = ServiceDto(
            active: vitals.services?.decoderActive == true,
            enabled: true,
            state: vitals.services?.decoderActive == true ? "active (running)" : "inactive (dead)",
            status: ""
        )
        let svcDump978 = ServiceDto(
            active: vitals.services?.dump978Fa == true,
            enabled: true,
            state: vitals.services?.dump978Fa == true ? "active (running)" : "inactive (dead)",
            status: ""
        )

        let temp = TempDto(
            celsius: vitals.temp?.celsius ?? 0.0,
            fahrenheit: vitals.temp?.fahrenheit ?? 0.0,
            status: ""
        )

        let throttle = ThrottleDto(
            flags: vitals.throttledOk ? [] : [vitals.throttled],
            ok: vitals.throttledOk,
            raw: vitals.throttled
        )

        let resources = ResourcesDto(
            load1m: vitals.load?.load1m,
            load5m: vitals.load?.load5m,
            load15m: vitals.load?.load15m,
            memTotalKb: vitals.mem?.totalKb,
            memAvailKb: vitals.mem?.availKb,
            diskTotalBytes: vitals.disk?.totalBytes,
            diskFreeBytes: vitals.disk?.freeBytes,
            diskUsedBytes: vitals.disk?.usedBytes
        )

        // RTL-SDR detected if pi-vitals reports at least one SDR iface.
        let ifaceCount = vitals.sdr?.ifaceCount ?? 0
        let rtlsdr = RtlSdrDto(
            detected: ifaceCount > 0,
            device: "Nooelec FlyCatcher (1090+978) — \(ifaceCount) iface(s)",
            status: ""
        )

        // Decoder stats from /skyaware/data/stats.json. readsb's last1min.local block has
        // signal/noise/peak/strong fields; aircraft count + messages come from last1min.
        let ll = stats?.last1min?.local
        let decoderStats = Dump1090StatsDto(
            aircraft: vitals.bands?.band1090?.aircraftCount ?? 0,
            messages: Int64(stats?.last1min?.messages ?? 0),
            noiseDbfs: ll?.noise ?? 0.0,
            peakSignalDbfs: ll?.peakSignal ?? 0.0,
            signalDbfs: ll?.signal ?? 0.0,
            strongSignals: ll?.strongSignals ?? 0,
            status: ""
        )

        let gain1090: String = ll?.gainDb.map { String(format: "%.1f", $0) } ?? "auto"

        return PiStatusDto(
            timestamp: String(vitals.now),
            rtlsdr: rtlsdr,
            piaware: svcPiaware,
            readsb: svcDecoder,
            dump1090: svcDecoder,
            dump978: svcDump978,
            temp: temp,
            throttle: throttle,
            readsbStats: decoderStats,
            dump1090Stats: decoderStats,
            resources: resources,
            gain1090: gain1090,
            gain978: "max",
            aircraftTracked24h: 0
        )
    }
}
