import Foundation

/// Synthesizes a `ChainStatusDto` from PiAware-native data sources — port of
/// `ChainStatusSynthesizer.kt`. Stage shape and status vocabulary ("ok"/"warn"/"fail") preserved so
/// the existing chain-pulse UI renders unchanged.
///
/// Five stages, in flow order:
///   1. Antenna      — RF chain liveness from signal/noise/peak
///   2. RTL-SDR      — dongle enumeration count from pi-vitals.sdr.iface_count
///   3. readsb (or dump1090-fa fallback) — 1090 decoder service health
///   4. dump978-fa   — UAT decoder service health (warn if disabled, ok if active)
///   5. FlightAware  — piaware → FA cloud uplink
enum ChainStatusSynthesizer {

    static func synthesize(vitals: PiVitalsDto, stats: StatsDto?) -> ChainStatusDto {
        let local = stats?.last1min?.local
        let signal = local?.signal
        let noise = local?.noise
        let gain = local?.gainDb
        let peak = local?.peakSignal
        let strong = local?.strongSignals ?? 0
        let dropped = local?.samplesDropped ?? 0

        let snr: Double? = (signal != nil && noise != nil) ? signal! - noise! : nil

        let sdrIfaces = vitals.sdr?.ifaceCount ?? 0
        let piawareToFa = vitals.services?.piawareToFa ?? false
        // Post-2026-04-29: pi-vitals.sh emits services.readsb. decoderActive ORs both names.
        let decoderUp = vitals.services?.decoderActive ?? false
        let decoderName: String
        if vitals.services?.readsb == true {
            decoderName = "readsb"
        } else if vitals.services?.dump1090Fa == true {
            decoderName = "dump1090-fa"
        } else {
            decoderName = "1090 decoder"
        }
        let dump978 = vitals.services?.dump978Fa ?? false
        let mps1090 = vitals.bands?.band1090?.mps
        let ac1090 = vitals.bands?.band1090?.aircraftCount ?? 0
        let mps978 = vitals.bands?.band978?.mps
        let ac978 = vitals.bands?.band978?.aircraftCount ?? 0
        let temp = vitals.temp?.celsius

        // Mirror kotlinx putting an explicit JSON null when a value is absent.
        func num(_ v: Double?) -> JSONValue { v.map { .number($0) } ?? .null }

        let antennaStatus: String
        if signal == nil {
            antennaStatus = "warn"
        } else if let s = snr, s < 8.0 {
            antennaStatus = "warn"
        } else {
            antennaStatus = "ok"
        }

        let sdrStatus: String
        // Post-Ultrafeeder migration: counts USB devices (one per dongle). Dual-tuner = 2.
        if sdrIfaces >= 2 {
            sdrStatus = "ok"
        } else if sdrIfaces == 1 {
            sdrStatus = "warn"
        } else {
            sdrStatus = "fail"
        }

        let stages: [ChainStageDto] = [
            ChainStageDto(
                name: "Antenna",
                kind: "antenna",
                status: antennaStatus,
                details: [
                    "signal_dbfs": num(signal),
                    "noise_dbfs": num(noise),
                    "snr_db": num(snr),
                    "peak_dbfs": num(peak),
                ]
            ),
            ChainStageDto(
                name: "RTL-SDR",
                kind: "sdr",
                status: sdrStatus,
                details: [
                    "iface_count": .number(Double(sdrIfaces)),
                    "gain_db": num(gain),
                    "strong_signals": .number(Double(strong)),
                    "samples_dropped": .number(Double(dropped)),
                ]
            ),
            ChainStageDto(
                name: decoderName,
                kind: "decoder",
                status: decoderUp ? "ok" : "fail",
                details: [
                    "active": .bool(decoderUp),
                    // Keys the chain-pulse UI expects for kind == "decoder".
                    "msgs_per_sec": num(mps1090),
                    "aircraft": .number(Double(ac1090)),
                    "mps_1090": num(mps1090),
                    "aircraft_count": .number(Double(ac1090)),
                ]
            ),
            ChainStageDto(
                name: "dump978-fa",
                kind: "uat_decoder",
                status: dump978 ? "ok" : "warn",
                details: [
                    "active": .bool(dump978),
                    "mps_978": num(mps978),
                    "aircraft_count": .number(Double(ac978)),
                ]
            ),
            ChainStageDto(
                name: "FlightAware",
                kind: "uplink",
                status: piawareToFa ? "ok" : "fail",
                details: [
                    "connected": .bool(piawareToFa),
                    "pi_temp_celsius": num(temp),
                    "throttled": .string(vitals.throttled),
                ]
            ),
        ]

        return ChainStatusDto(ts: vitals.now, site: vitals.host, stages: stages)
    }
}
