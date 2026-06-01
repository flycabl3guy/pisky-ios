import Foundation

/// DTO → domain bridges that the Mappers.swift note left to the Data layer (they read DTO shapes
/// the telemetry repositories consume). Ports `Rolling24hStatsDto.kt`'s `toDomain()` and the
/// military-history / unique-aircraft conversions.

// MARK: - ISO-8601 parsing (mirrors Kotlin's Instant.parse, EPOCH on failure)

private let iso8601WithFractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

private let iso8601Plain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

/// `Instant.parse(iso)` with `Instant.EPOCH` fallback. Accepts the with/without fractional-seconds
/// variants the L2 aggregator emits.
func parseInstantSafe(_ iso: String) -> Date {
    if iso.isEmpty { return Date(timeIntervalSince1970: 0) }
    if let d = iso8601WithFractional.date(from: iso) { return d }
    if let d = iso8601Plain.date(from: iso) { return d }
    return Date(timeIntervalSince1970: 0)
}

// MARK: - Rolling24hDto → Rolling24hStats

extension Rolling24hDto {
    func toDomain() -> Rolling24hStats {
        Rolling24hStats(
            aircraftSeen: aircraftSeen,
            adsbSeen: adsbSeen,
            uatSeen: uatSeen,
            mlatSeen: mlatSeen,
            otherSeen: otherSeen,
            militarySeen: militarySeen,
            messagesReceived: messagesReceived,
            positionsLogged: positionsLogged,
            windowStart: parseInstantSafe(windowStartUtc),
            windowEnd: parseInstantSafe(windowEndUtc),
            lastUpdated: parseInstantSafe(lastUpdatedUtc)
        )
    }
}

extension Rolling24hResponseDto {
    /// Convenience: map the `.preferred` block straight to the domain stats.
    func toDomain() -> Rolling24hStats { preferred.toDomain() }
}

// MARK: - MilitaryHistoryEntryDto → MilitaryHistoryEntry / UniqueAircraft

extension MilitaryHistoryEntryDto {
    func toDomain() -> MilitaryHistoryEntry {
        MilitaryHistoryEntry(
            hex: hex,
            callsign: callsign,
            registration: registration,
            type: type,
            band: band,
            firstSeenMs: firstSeenMs,
            lastSeenMs: lastSeenMs
        )
    }

    func toUniqueAircraft() -> UniqueAircraft {
        UniqueAircraft(
            hex: hex,
            type: type,
            callsign: callsign,
            registration: registration,
            firstSeenMs: firstSeenMs,
            isMilitary: true
        )
    }
}

// MARK: - FeedConnectorDto → FeedConnector

extension FeedConnectorDto {
    func toDomain() -> FeedConnector {
        FeedConnector(host: host, port: port, secondsConnected: secondsConnected)
    }
}
