import SwiftUI

/// Slim red emergency banner shown above the aircraft list / alerts. Ported from
/// `feature/aircraft/EmergencyBanner.kt`.
///
/// Auto-dismisses 6 s after a new set of emergency hexes appears; tapping it pushes the first
/// offending aircraft (and dismisses). The dismiss state is keyed to the *set* of emergency hexes
/// (joined), so a brand-new emergency re-shows the banner even after a prior auto-dismiss.
struct EmergencyBanner: View {
    let emergencyAircraft: [Aircraft]
    let onTap: (Aircraft) -> Void

    @State private var dismissedSignature: String? = nil

    /// Comma-joined hex list — identity of the current emergency set.
    private var signature: String { emergencyAircraft.map(\.hex).joined(separator: ",") }

    private var isVisible: Bool {
        !emergencyAircraft.isEmpty && dismissedSignature != signature
    }

    var body: some View {
        Group {
            if isVisible, let ac = emergencyAircraft.first {
                let extra = emergencyAircraft.count - 1
                Button {
                    onTap(ac)
                    dismissedSignature = signature
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Palette.emergencyRed)
                        Text(bannerText(ac: ac, extra: extra))
                            .font(.psMono(12, weight: .bold))
                            .foregroundStyle(Palette.emergencyRed)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.emergencyRed)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Palette.emergencyRed.opacity(0.15))
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isVisible)
        // Re-arm + 6 s auto-dismiss whenever the emergency set changes.
        .task(id: signature) {
            guard !signature.isEmpty else { return }
            dismissedSignature = nil
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            dismissedSignature = signature
        }
    }

    private func bannerText(ac: Aircraft, extra: Int) -> String {
        var s = "EMERGENCY • \(ac.displayCallsign) (\(ac.emergency.rawValue.uppercased()))"
        if extra > 0 { s += " +\(extra) more" }
        return s
    }
}
