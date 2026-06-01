import SwiftUI

/// 737-style Flight Mode Annunciator strip — four columns:
///   A/T | Roll | Pitch | AP Status
/// Each column shows engaged (green) on top, armed (white, smaller) below,
/// caution string (amber) overlaid when present.
///
/// Empty-data state: amber "NO MODE DATA" banner across the strip when the
/// source aircraft emits no DO-260B TSS subtype 1 (~86% of traffic).
///
/// Ports `feature/pfd/instruments/FmaStrip.kt`.
struct FmaStrip: View {
    let state: FmaState

    var body: some View {
        ZStack {
            PfdColors.background
            if state.noData {
                Text("NO MODE DATA")
                    .font(.system(size: 14, weight: .bold))
                    .tracking(2.0)
                    .foregroundColor(PfdColors.amber)
            } else {
                HStack(spacing: 0) {
                    FmaColumn(label: "A/T", cell: state.autothrottle)
                    FmaDivider()
                    FmaColumn(label: "ROLL", cell: state.roll)
                    FmaDivider()
                    FmaColumn(label: "PCH", cell: state.pitch)
                    FmaDivider()
                    FmaColumn(label: "AP", cell: state.apStatus)
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .overlay(Rectangle().stroke(PfdColors.fmaBorder, lineWidth: 0.5))
    }
}

private struct FmaDivider: View {
    var body: some View {
        Rectangle()
            .fill(PfdColors.fmaBorder)
            .frame(width: 1, height: 40)
    }
}

private struct FmaColumn: View {
    let label: String
    let cell: FmaCell

    var body: some View {
        VStack(spacing: 2) {
            // Tiny column header (gray) so user knows which axis they're reading.
            Text(label)
                .font(.system(size: 7))
                .tracking(1.4)
                .foregroundColor(PfdColors.fmaBorder)
            // Engaged row — large, green
            Text(cell.engaged)
                .font(.system(size: 14, weight: .bold))
                .tracking(0.6)
                .foregroundColor(PfdColors.green)
            // Armed row — smaller, white (amber when a caution is present)
            if !armedLine.isEmpty {
                Text(armedLine)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(cell.caution.isEmpty ? PfdColors.white : PfdColors.amber)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var armedLine: String {
        [cell.armed, cell.caution]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
