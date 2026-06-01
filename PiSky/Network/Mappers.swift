import Foundation

extension String {
    /// Kotlin `?.trim()?.ifBlank { null }` — trimmed, or nil if blank after trimming.
    var trimmedNonBlank: String? {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}

// MARK: - AircraftDto → Aircraft  (ported from Mappers.kt `AircraftDto.toDomain`)

extension AircraftDto {
    func toDomain(receiverLat: Double?,
                  receiverLon: Double?,
                  favoriteHexes: Set<String> = [],
                  dataSource: DataSource = .adsb1090,
                  milCsvHexes: Set<String> = [],
                  milCsvNames: [String: String] = [:]) -> Aircraft {

        let isGround = altBaro?.isGround ?? false
        let altFeet  = altBaro?.feetValue

        // Prefer readsb's server-computed r_dst/r_dir over a client haversine; fall back to a
        // local great-circle when both the aircraft and receiver positions are known.
        let distNm: Double?
        let bearing: Double?
        if let rDst, let rDir {
            distNm = rDst; bearing = rDir
        } else if let lat, let lon, let rLat = receiverLat, let rLon = receiverLon {
            distNm = Geo.haversineNm(rLat, rLon, lat, lon)
            bearing = Geo.bearingDeg(rLat, rLon, lat, lon)
        } else {
            distNm = nil; bearing = nil
        }

        // readsb classifies source per-aircraft via `type`; the legacy mlat[]/tisb[] arrays are
        // only populated for non-position contributors.
        let readsbMlat = adsbType?.hasPrefix("mlat") ?? false
        let readsbTisb = adsbType?.hasPrefix("tisb") ?? false

        // L2's /enrich dbFlags is UNRELIABLE (flagged a civilian Global Express military). Ignore it
        // entirely — the hex-range + mil-CSV + heuristic classifier identifies military reliably.
        let trustedDbFlags: Int? = nil

        let cs        = flight?.trimmedNonBlank
        let descTrim  = desc?.trimmedNonBlank
        let ownOpTrim = ownOp?.trimmedNonBlank

        return Aircraft(
            hex: hex,
            callsign: cs,
            registration: registration,
            type: aircraftType,
            category: category,
            squawk: squawk,
            emergency: Emergency.from(emergency, squawk: squawk),
            latitude: lat,
            longitude: lon,
            altitudeBaro: altFeet,
            altitudeGeom: altGeom,
            groundSpeed: groundSpeed,
            indicatedAirSpeed: ias,
            trueAirSpeed: tas,
            mach: mach,
            track: track ?? calcTrack,
            trackRate: trackRate,
            roll: roll,
            verticalRate: baroRate,
            geomRate: geomRate,
            magHeading: magHeading,
            trueHeading: trueHeading,
            navAltitudeMcp: navAltMcp,
            navAltitudeFms: navAltFms,
            navHeading: navHeading,
            navQnh: navQnh,
            nic: nic,
            nacP: nacP,
            nacV: nacV,
            sil: sil,
            version: version,
            rc: rc,
            nicBaro: nicBaro,
            silType: silType,
            gva: gva,
            sda: sda,
            rssi: rssi,
            seen: seen,
            seenPos: seenPos,
            messages: messages,
            distanceNm: distNm,
            bearingDeg: bearing,
            isOnGround: isGround,
            isMlat: readsbMlat || !(mlat?.isEmpty ?? true),
            isTisb: readsbTisb || !(tisb?.isEmpty ?? true),
            isFavorite: favoriteHexes.contains(hex),
            dataSource: dataSource,
            dbFlags: trustedDbFlags,
            description: descTrim,
            operatorName: ownOpTrim,
            year: year?.trimmedNonBlank,
            navModes: navModes ?? [],
            routeFrom: routeset?.from?.trimmedNonBlank,
            routeTo: routeset?.to?.trimmedNonBlank,
            classification: AircraftClassifier.classify(
                hex: hex,
                callsign: cs,
                type: aircraftType,
                category: category,
                registration: registration,
                dbFlags: trustedDbFlags,
                squawk: squawk,
                isInMilCsv: milCsvHexes.contains(hex.uppercased()),
                milCsvName: milCsvNames[hex.uppercased()],
                desc: descTrim,
                ownOp: ownOpTrim
            )
        )
    }
}

// MARK: - ReceiverDto → ReceiverStats

extension ReceiverDto {
    func toDomain() -> ReceiverStats {
        ReceiverStats(
            version: version,
            refreshIntervalMs: refresh,
            latitude: lat,
            longitude: lon,
            antenna: antenna
        )
    }
}

// MARK: - StatsDto → LiveStats  (ported from Mappers.kt `StatsDto.toLiveStats`)

extension StatsDto {
    func toLiveStats() -> LiveStats {
        guard let p = last1min ?? latest ?? total else {
            return LiveStats(aircraftTotal: 0, aircraftWithPos: 0, aircraftWithMlat: 0,
                             messagesTotal: 0, messagesLastMinute: 0, strongSignals: 0,
                             signalDbfs: nil, noiseDbfs: nil, maxRangeNm: nil, trackedPositions: 0)
        }
        let local = p.local
        return LiveStats(
            aircraftTotal: p.tracks?.all ?? 0,
            aircraftWithPos: 0,
            aircraftWithMlat: 0,
            messagesTotal: Int64(total?.messages ?? 0),
            messagesLastMinute: p.messages,
            strongSignals: local?.strongSignals ?? 0,
            signalDbfs: local?.signal,
            noiseDbfs: local?.noise,
            maxRangeNm: nil,
            trackedPositions: (p.cpr?.airborne ?? 0) + (p.cpr?.surface ?? 0)
        )
    }
}

// NOTE: Rolling24hResponseDto → Rolling24hStats, OutlineDto → CoverageOutline, and
// FeedConnectorDto → FeedConnector bridges live with the repositories that consume them
// (the Data layer), since they read those DTOs' exact shapes.
