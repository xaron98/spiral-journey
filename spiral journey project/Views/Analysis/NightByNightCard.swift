import SwiftUI
import SpiralKit

/// Editorial "noche por noche" breakdown: seven rows, one per night,
/// showing the actual sleep window as a colored bar on a 20h → 10h
/// time axis. Purple = within the user's consistency band, yellow =
/// outlier (late bedtime / very short duration).
struct NightByNightCard: View {
    /// Up to 7 records — callers pass `store.records.suffix(7)`.
    let records: [SleepRecord]
    /// Threshold in hours from the weekly median bedtime beyond which
    /// a night is flagged as inconsistent (yellow bar instead of purple).
    var consistencyToleranceHours: Double = 1.0

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "analysis.nightByNight.title", bundle: bundle))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .tracking(1.2)
                .foregroundStyle(SpiralColors.subtle)

            VStack(spacing: 0) {
                ForEach(Array(displayRecords.enumerated()), id: \.offset) { idx, entry in
                    row(entry)
                    if idx < displayRecords.count - 1 {
                        Divider().background(SpiralColors.border)
                    }
                }
            }

            axisLegend
        }
        .padding(14)
        .background(SpiralColors.surface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(SpiralColors.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Row

    private func row(_ entry: NightEntry) -> some View {
        HStack(spacing: 10) {
            Text(entry.dayLabel)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(SpiralColors.subtle)
                .frame(width: 32, alignment: .leading)

            Text(entry.bedtimeLabel)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(entry.consistent ? SpiralColors.text : SpiralColors.poor)
                .frame(width: 52, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(SpiralColors.border)
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 3)
                        .fill((entry.consistent ? SpiralColors.accent : SpiralColors.moderate)
                              .opacity(0.85))
                        .frame(
                            width: max(0, min(geo.size.width - entry.leftOffset * geo.size.width,
                                              entry.widthFraction * geo.size.width)),
                            height: 6)
                        .offset(x: entry.leftOffset * geo.size.width)
                }
            }
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            Text(entry.durationLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(SpiralColors.subtle)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.vertical, 8)
    }

    private var axisLegend: some View {
        HStack {
            Spacer().frame(width: 32 + 52 + 10 + 10)   // align with bar track
            Text("20h").font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.subtle)
            Spacer()
            Text("00h").font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.subtle)
            Spacer()
            Text("04h").font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.subtle)
            Spacer()
            Text("08h").font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.subtle)
            Spacer().frame(width: 34)
        }
    }

    // MARK: - Mapping

    private struct NightEntry {
        let dayLabel: String
        let bedtimeLabel: String
        let durationLabel: String
        let leftOffset: Double    // 0…1 inside the 14h window
        let widthFraction: Double
        let consistent: Bool
    }

    private var displayRecords: [NightEntry] {
        guard !records.isEmpty else { return [] }
        let medianBedtime = records.map { $0.bedtimeHour }.sorted()[records.count / 2]
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "EEE"
        return records.map { rec in
            // Map clock hours [20..24) ∪ [0..10) → [0..14).
            let startAbs = rec.bedtimeHour < 12
                ? rec.bedtimeHour + 24
                : rec.bedtimeHour
            let left = max(0, min(1, (startAbs - 20) / 14))
            let width = max(0.03, min(1 - left, rec.sleepDuration / 14))
            let consistent = abs(rec.bedtimeHour - medianBedtime) <= consistencyToleranceHours
                || abs(rec.bedtimeHour - medianBedtime) >= (24 - consistencyToleranceHours)
            return NightEntry(
                dayLabel: fmt.string(from: rec.date).capitalized,
                bedtimeLabel: formatHour(rec.bedtimeHour),
                durationLabel: String(format: "%.1fh", rec.sleepDuration),
                leftOffset: left,
                widthFraction: width,
                consistent: consistent)
        }
    }

    private func formatHour(_ h: Double) -> String {
        let hh = Int(h) % 24
        let mm = Int((h - Double(Int(h))) * 60)
        return String(format: "%02d:%02d", hh, mm)
    }
}
