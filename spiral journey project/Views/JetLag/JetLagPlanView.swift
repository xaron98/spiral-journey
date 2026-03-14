import SwiftUI
import SpiralKit

/// Displays the generated jet lag adaptation plan as a day-by-day timeline.
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
                    .font(.system(size: 9))
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
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Summary

    private var summaryHeader: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: plan.direction == .east ? "airplane.departure" : "airplane.arrival")
                    .font(.system(size: 24))
                    .foregroundStyle(SpiralColors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(
                        format: String(localized: "jetlag.plan.summary", bundle: bundle),
                        abs(plan.timezoneOffsetHours),
                        plan.direction == .east
                            ? String(localized: "jetlag.direction.east", bundle: bundle)
                            : String(localized: "jetlag.direction.west", bundle: bundle)
                    ))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SpiralColors.text)

                    Text(String(
                        format: String(localized: "jetlag.plan.adaptDays", bundle: bundle),
                        plan.estimatedAdaptationDays
                    ))
                    .font(.system(size: 11, design: .monospaced))
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
            // Day label
            HStack {
                Text(dayLabel(day.dayOffset))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(day.dayOffset == 0 ? SpiralColors.accent : SpiralColors.text)
                Spacer()
                if day.dayOffset == 0 {
                    Text(String(localized: "jetlag.day.travel", bundle: bundle))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SpiralColors.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(SpiralColors.accent.opacity(0.15))
                        )
                }
            }

            // Schedule items
            if let bed = day.targetBedtime, let wake = day.targetWake {
                scheduleRow(icon: "bed.double.fill", color: SpiralColors.accent,
                           text: String(format: String(localized: "jetlag.day.sleep", bundle: bundle),
                                       formatHour(bed), formatHour(wake)))
            }

            if let lw = day.lightWindow {
                scheduleRow(icon: "sun.max.fill", color: SpiralColors.good,
                           text: String(format: String(localized: "jetlag.day.light", bundle: bundle),
                                       formatHour(lw.start), formatHour(lw.end)))
            }

            if let aw = day.avoidLightWindow {
                scheduleRow(icon: "eye.slash.fill", color: SpiralColors.poor,
                           text: String(format: String(localized: "jetlag.day.avoidLight", bundle: bundle),
                                       formatHour(aw.start), formatHour(aw.end)))
            }

            if let mel = day.melatoninTime {
                scheduleRow(icon: "pills.fill", color: SpiralColors.moderate,
                           text: String(format: String(localized: "jetlag.day.melatonin", bundle: bundle),
                                       formatHour(mel)))
            }

            if let caf = day.caffeineDeadline {
                scheduleRow(icon: "cup.and.saucer.fill", color: SpiralColors.muted,
                           text: String(format: String(localized: "jetlag.day.caffeine", bundle: bundle),
                                       formatHour(caf)))
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
                .font(.system(size: 10))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(SpiralColors.text.opacity(0.85))
        }
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

    private func formatHour(_ h: Double) -> String {
        let hour = Int(h) % 24
        let minute = Int((h - Double(Int(h))) * 60)
        return String(format: "%02d:%02d", hour, minute)
    }
}
