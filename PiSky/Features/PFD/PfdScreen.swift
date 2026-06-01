import SwiftUI

/// Boeing 737NG/MAX-style Primary Flight Display, driven entirely by what the
/// selected aircraft is broadcasting over ADS-B.
///
/// Layout (landscape, full-screen):
///
///   ┌─ FMA strip ───────────────────────────────────────────────────┐
///   │  A/T  │  ROLL    │  PITCH   │  AP                              │
///   ├───────┼──────────┴──────────┴──────────┬───────────┬───────────┤
///   │  GS   │   ADI (derived) over            │  ALT      │   VSI     │
///   │  tape │   HSI compass (track-up)        │  + MCP    │  (±6000)  │
///   │       │                                 │  + QNH    │           │
///   ├───────┴─────────────────────────────────┴───────────┴───────────┤
///   │  Bottom info bar — callsign / squawk / integrity / pos / range  │
///   └────────────────────────────────────────────────────────────────┘
///
/// Honest gaps:
///  - ADI is *derived*, not transmitted: horizon pitch = flight-path angle
///    (VS/GS), bank = broadcast roll or a coordinated-turn estimate. Labelled
///    "DERIVED ATT" + "EST" so it's never mistaken for a real IRU attitude.
///  - GS labeled GS, not IAS (BDS 5,0 not decoded on this rig).
///  - FMA shows "NO MODE DATA" amber when the aircraft is a pre-DO-260B
///    transponder (~86% of traffic — see FmaMapper docstring).
///
/// Ports `feature/pfd/PfdScreen.kt`.
struct PfdScreen: View {
    let hex: String

    @Environment(AppContainer.self) private var container
    @State private var vm = PfdViewModel()

    var body: some View {
        Group {
            if let ac = vm.aircraft {
                content(ac)
            } else {
                // Empty state — aircraft not (yet) in the live feed
                Text("WAITING FOR \(hex.uppercased())")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(PfdColors.amber)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(PfdColors.background)
        .ignoresSafeArea(edges: .bottom)
        .task { vm.start(container, hex: hex) }
    }

    @ViewBuilder
    private func content(_ ac: Aircraft) -> some View {
        let attitude = derivedAttitude(ac, turnRate: vm.turnRateDegSec)

        VStack(spacing: 0) {
            // ── FMA strip ─────────────────────────────────────────────────
            FmaStrip(state: FmaMapper.derive(ac))

            // ── Main row: SpeedTape | (ADI / HSI) | AltTape | VSI ──────────
            HStack(spacing: 0) {
                SpeedTape(groundSpeedKt: ac.groundSpeed)
                    .frame(width: 88)
                    .frame(maxHeight: .infinity)

                // Center cluster: artificial horizon (ADI) over the HSI compass.
                VStack(spacing: 0) {
                    AttitudeIndicator(
                        pitchDeg: attitude.fpaDeg,
                        bankDeg: attitude.bankDeg,
                        fpaValid: attitude.fpaValid,
                        bankEstimated: attitude.bankEstimated
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(0.60)

                    HsiCompass(
                        trackDeg: ac.track,
                        navHeadingDeg: ac.navHeading,
                        turnRateDegSec: vm.turnRateDegSec
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .layoutPriority(0.40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                AltitudeTape(
                    altBaroFt: ac.altitudeBaro,
                    altMcpFt: ac.navAltitudeMcp,
                    qnhHpa: ac.navQnh
                )
                .frame(width: 110)
                .frame(maxHeight: .infinity)

                VsiArc(verticalRateFpm: ac.verticalRate)
                    .frame(width: 60)
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // ── Bottom info bar ───────────────────────────────────────────
            BottomInfoBar(aircraft: ac)
        }
    }

    /// Derived attitude (honest — ADS-B carries no pitch/roll).
    /// Pitch = flight-path angle from VS/GS. Bank = broadcast roll if present,
    /// else a coordinated-turn estimate from the derived turn rate.
    private struct DerivedAttitude {
        let fpaDeg: Double
        let bankDeg: Double
        let fpaValid: Bool
        let bankEstimated: Bool
    }

    private func derivedAttitude(_ ac: Aircraft, turnRate: Double) -> DerivedAttitude {
        let gsKt = ac.groundSpeed ?? 0.0
        let vsFpm = ac.verticalRate
        let fpaValid = !ac.isOnGround && gsKt > 30.0 && vsFpm != nil
        let fpaDeg = fpaValid
            ? atan2(Double(vsFpm!) / 60.0, gsKt * 1.68781) * 180.0 / .pi
            : 0.0

        let hasRoll = ac.roll != nil
        let canEstimateBank = !ac.isOnGround && gsKt > 30.0
        let bankEstimated = !hasRoll && canEstimateBank
        let bankDeg: Double
        if hasRoll {
            bankDeg = ac.roll!
        } else if canEstimateBank {
            // φ = atan(ω·V/g) — ω in rad/s, V in m/s, g = 9.80665, clamped ±67°.
            let omegaRad = turnRate * .pi / 180.0
            let v = gsKt * 0.514444
            let raw = atan(omegaRad * v / 9.80665) * 180.0 / .pi
            bankDeg = max(-67.0, min(67.0, raw))
        } else {
            bankDeg = 0.0
        }

        return DerivedAttitude(fpaDeg: fpaDeg, bankDeg: bankDeg, fpaValid: fpaValid, bankEstimated: bankEstimated)
    }
}
