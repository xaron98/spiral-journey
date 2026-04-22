import SwiftUI
import SpiralKit

/// Expanded motif overview that appears under the 3D helix when the user
/// toggles pattern highlights. Each motif renders as its own horizontal
/// lane on the user's full day timeline — so you see at a glance *which*
/// weeks belong to each recurring pattern rather than just an abstract
/// color sprinkled on the helix bars.
///
/// Intentionally separate from the compact `motifLegend` inside
/// `HelixRealityView`'s overlay — that one stays as a minimal color/name
/// key; this card is the dedicated "who fell where" visualisation.
struct MotifTimelineCard: View {

    let profile: SleepDNAProfile
    let records: [SleepRecord]

    @Environment(\.languageBundle) private var bundle

    /// Same palette as `HelixSceneBuilder.motifColorPalette` so the lane
    /// colors match the helix bar tints exactly. Duplicated rather than
    /// referenced because `HelixSceneBuilder` is gated on iOS 18+ for
    /// RealityKit reasons and this card needs to render everywhere.
    private static let palette: [Color] = [
        Color(hex: "22d3ee"),
        Color(hex: "a78bfa"),
        Color(hex: "34d399"),
        Color(hex: "fb923c"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            VStack(spacing: 12) {
                ForEach(Array(profile.motifs.enumerated()), id: \.offset) { idx, motif in
                    motifLane(
                        motif: motif,
                        color: Self.palette[idx % Self.palette.count]
                    )
                }
            }
        }
        .padding(16)
        .background(SpiralColors.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(SpiralColors.border, lineWidth: 0.5))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.bar.doc.horizontal")
                .font(.caption)
                .foregroundStyle(SpiralColors.accent)
            Text(loc("dna.patterns.timeline.title"))
                .font(.caption.weight(.semibold).monospaced())
                .foregroundStyle(SpiralColors.subtle)
                .textCase(.uppercase)
            Spacer()
            Text(String(format: loc("dna.patterns.timeline.count"), profile.motifs.count))
                .font(.caption2.monospaced())
                .foregroundStyle(SpiralColors.muted)
        }
    }

    // MARK: - Per-Motif Lane

    @ViewBuilder
    private func motifLane(motif: SleepMotif, color: Color) -> some View {
        let instanceDates = instanceStartDates(for: motif)
        VStack(alignment: .leading, spacing: 6) {
            // Lane header: name + count
            HStack(spacing: 6) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                Text(localizedMotifName(motif.name))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                Spacer()
                Text(String(format: loc("dna.patterns.timeline.instances"), motif.instanceCount))
                    .font(.caption2.weight(.medium).monospaced())
                    .foregroundStyle(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.15), in: Capsule())
            }

            // Visual timeline — every day of history, motif weeks filled.
            timeline(motif: motif, color: color)

            // Date chips: one per instance, monospaced so they align.
            dateChips(dates: instanceDates, color: color)
        }
    }

    // MARK: - Timeline Strip

    private func timeline(motif: SleepMotif, color: Color) -> some View {
        let totalDays = max(profile.nucleotides.count, 1)
        // Build the set of days that belong to any of this motif's weeks.
        // Each week index `w` covers the 7-day sliding window starting
        // at `nucleotides[w].day` — we just fill that 7-day span.
        var highlighted = Set<Int>()
        for wi in motif.instanceWeekIndices where wi < profile.nucleotides.count {
            let startDay = profile.nucleotides[wi].day
            for d in startDay...(startDay + 6) {
                highlighted.insert(d)
            }
        }
        let firstDay = profile.nucleotides.first?.day ?? 0
        let lastDay = (profile.nucleotides.last?.day ?? 0) + 6 // account for final week span
        let dayRange = max(1, lastDay - firstDay + 1)

        return GeometryReader { geo in
            let dayWidth = geo.size.width / CGFloat(dayRange)
            Canvas { ctx, size in
                // Base line — all days as faint dashes.
                let baseRect = CGRect(x: 0, y: size.height / 2 - 1, width: size.width, height: 2)
                ctx.fill(
                    Path(roundedRect: baseRect, cornerRadius: 1),
                    with: .color(SpiralColors.border)
                )

                // Filled segments for highlighted days.
                for day in highlighted {
                    let x = CGFloat(day - firstDay) * dayWidth
                    let segRect = CGRect(
                        x: max(0, x),
                        y: size.height / 2 - 4,
                        width: max(2, dayWidth),
                        height: 8
                    )
                    ctx.fill(
                        Path(roundedRect: segRect, cornerRadius: 2),
                        with: .color(color.opacity(0.85))
                    )
                }
            }
        }
        .frame(height: 14)
    }

    // MARK: - Date Chips

    private func dateChips(dates: [Date], color: Color) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(dates, id: \.self) { date in
                    Text(formatShort(date))
                        .font(.caption2.monospaced())
                        .foregroundStyle(SpiralColors.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(color.opacity(0.15), in: Capsule())
                        .overlay(
                            Capsule().stroke(color.opacity(0.4), lineWidth: 0.5))
                }
            }
        }
        .scrollClipDisabled()
    }

    // MARK: - Helpers

    /// Convert a motif's week indices into the start Dates of each instance
    /// by matching day index to the actual `records` array (sorted by day).
    private func instanceStartDates(for motif: SleepMotif) -> [Date] {
        let recordsByDay = Dictionary(uniqueKeysWithValues: records.map { ($0.day, $0.date) })
        var seen = Set<Int>()
        var dates: [Date] = []
        for wi in motif.instanceWeekIndices where wi < profile.nucleotides.count {
            let startDay = profile.nucleotides[wi].day
            guard !seen.contains(startDay), let date = recordsByDay[startDay] else { continue }
            seen.insert(startDay)
            dates.append(date)
        }
        return dates.sorted()
    }

    private func formatShort(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.locale = Locale.current
        fmt.dateFormat = "d MMM"
        return fmt.string(from: date)
    }

    private func localizedMotifName(_ engineName: String) -> String {
        let key = "dna.motif.name.\(engineName.lowercased())"
        let result = loc(key)
        return result == key ? engineName : result
    }

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
