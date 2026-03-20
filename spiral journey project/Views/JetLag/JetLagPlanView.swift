import SwiftUI
import SpiralKit

/// Displays the generated jet lag adaptation plan as a day-by-day timeline.
///
/// Pre-travel days show times in the user's HOME timezone.
/// Travel day (0) and post-travel days show times in DESTINATION timezone
/// so the user can directly read clock times at their location.
struct JetLagPlanView: View {

    let plan: JetLagPlan

    @Environment(\.languageBundle) private var bundle

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Summary header
                summaryHeader

                // Day-by-day timeline
                ForEach(plan.days) { day in
                    dayCard(day)
                }

                // Disclaimer
                Text(String(localized: "jetlag.disclaimer", bundle: bundle))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "jetlag.plan.title", bundle: bundle))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Summary

    private var summaryHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: plan.direction == .east ? "airplane.departure" : "airplane.arrival")
                    .font(.title)
                    .foregroundStyle(SpiralColors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(
                        format: String(localized: "jetlag.plan.summary", bundle: bundle),
                        abs(plan.timezoneOffsetHours),
                        plan.direction == .east
                            ? String(localized: "jetlag.direction.east", bundle: bundle)
                            : String(localized: "jetlag.direction.west", bundle: bundle)
                    ))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SpiralColors.text)

                    Text(String(
                        format: String(localized: "jetlag.plan.adaptDays", bundle: bundle),
                        plan.estimatedAdaptationDays
                    ))
                    .font(.caption.monospaced())
                    .foregroundStyle(SpiralColors.muted)
                }
                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(SpiralColors.accent.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(SpiralColors.accent.opacity(0.18), lineWidth: 0.8)
                )
        )
    }

    // MARK: - Day Card

    private func dayCard(_ day: JetLagDay) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // Day label + timezone badge
            HStack(spacing: 6) {
                Text(dayLabel(day.dayOffset))
                    .font(.caption.weight(.semibold).monospaced())
                    .foregroundStyle(day.dayOffset == 0 ? SpiralColors.accent : SpiralColors.text)

                timezoneBadge(for: day.dayOffset)

                Spacer()

                if day.dayOffset == 0 {
                    Text(String(localized: "jetlag.day.travel", bundle: bundle))
                        .font(.caption.weight(.semibold).monospaced())
                        .foregroundStyle(SpiralColors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(SpiralColors.accent.opacity(0.15))
                        )
                }
            }

            // Schedule items — times converted to the relevant timezone
            if let bed = day.targetBedtime, let wake = day.targetWake {
                scheduleRow(icon: "bed.double.fill", color: SpiralColors.accent,
                           text: String(format: String(localized: "jetlag.day.sleep", bundle: bundle),
                                       displayHour(bed, dayOffset: day.dayOffset),
                                       displayHour(wake, dayOffset: day.dayOffset)))
            }

            if let lw = day.lightWindow {
                scheduleRow(icon: "sun.max.fill", color: SpiralColors.good,
                           text: String(format: String(localized: "jetlag.day.light", bundle: bundle),
                                       displayHour(lw.start, dayOffset: day.dayOffset),
                                       displayHour(lw.end, dayOffset: day.dayOffset)))
            }

            if let aw = day.avoidLightWindow {
                scheduleRow(icon: "eye.slash.fill", color: SpiralColors.poor,
                           text: String(format: String(localized: "jetlag.day.avoidLight", bundle: bundle),
                                       displayHour(aw.start, dayOffset: day.dayOffset),
                                       displayHour(aw.end, dayOffset: day.dayOffset)))
            }

            if let mel = day.melatoninTime {
                scheduleRow(icon: "pills.fill", color: SpiralColors.moderate,
                           text: String(format: String(localized: "jetlag.day.melatonin", bundle: bundle),
                                       displayHour(mel, dayOffset: day.dayOffset)))
            }

            if let caf = day.caffeineDeadline {
                scheduleRow(icon: "cup.and.saucer.fill", color: SpiralColors.muted,
                           text: String(format: String(localized: "jetlag.day.caffeine", bundle: bundle),
                                       displayHour(caf, dayOffset: day.dayOffset)))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(SpiralColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(day.dayOffset == 0 ? SpiralColors.accent.opacity(0.3) : SpiralColors.border, lineWidth: 0.8)
                )
        )
    }

    private func scheduleRow(icon: String, color: Color, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(SpiralColors.text.opacity(0.85))
        }
    }

    /// Timezone badge indicating whether times are shown in home or destination tz.
    private func timezoneBadge(for dayOffset: Int) -> some View {
        let isDestination = dayOffset >= 0
        let label = isDestination
            ? String(localized: "jetlag.tz.destination", bundle: bundle)
            : String(localized: "jetlag.tz.home", bundle: bundle)
        let icon = isDestination ? "airplane" : "house.fill"

        return HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.caption2)
            Text(label)
                .font(.caption2.weight(.medium))
        }
        .foregroundStyle(SpiralColors.muted)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(SpiralColors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(SpiralColors.border, lineWidth: 0.5)
                )
        )
    }

    // MARK: - Helpers

    private func dayLabel(_ offset: Int) -> String {
        if offset < 0 {
            return String(format: String(localized: "jetlag.day.pre", bundle: bundle), abs(offset))
        } else if offset == 0 {
            return String(localized: "jetlag.day.zero", bundle: bundle)
        } else {
            return String(format: String(localized: "jetlag.day.post", bundle: bundle), offset)
        }
    }

    /// Convert engine hour (home timezone) to the display timezone.
    /// Pre-travel (dayOffset < 0): home time as-is.
    /// Travel day & post (dayOffset >= 0): destination time.
    private func displayHour(_ h: Double, dayOffset: Int) -> String {
        if dayOffset >= 0 {
            return formatHour(normalizeHour(h + Double(plan.timezoneOffsetHours)))
        }
        return formatHour(h)
    }

    private func normalizeHour(_ h: Double) -> Double {
        var result = h.truncatingRemainder(dividingBy: 24)
        if result < 0 { result += 24 }
        return result
    }

    private func formatHour(_ h: Double) -> String {
        let normalized = normalizeHour(h)
        let hour = Int(normalized) % 24
        let minute = Int((normalized - Double(Int(normalized))) * 60)
        return String(format: "%02d:%02d", hour, minute)
    }
}
