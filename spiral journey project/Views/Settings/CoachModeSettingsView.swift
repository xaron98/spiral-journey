import SwiftUI
import SpiralKit

struct CoachModeSettingsView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    private func coachModeLabel(_ mode: CoachMode) -> String {
        switch mode {
        case .generalHealth:  return String(localized: "settings.coachMode.generalHealth", bundle: bundle)
        case .shiftWork:      return String(localized: "settings.coachMode.shiftWork", bundle: bundle)
        case .customSchedule: return String(localized: "settings.coachMode.customSchedule", bundle: bundle)
        case .rephase:        return String(localized: "settings.coachMode.rephase", bundle: bundle)
        }
    }

    private func formatHour(_ h: Double) -> String {
        let total = Int((h * 60).rounded())
        let hh = (total / 60) % 24
        let mm = total % 60
        return String(format: "%02d:%02d", hh, mm)
    }

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(spacing: 16) {
                // Mode picker
                VStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "settings.coachMode.title", bundle: bundle).uppercased())
                            .font(.caption2.weight(.semibold).monospaced())
                            .foregroundStyle(SpiralColors.muted)
                            .tracking(1.5)
                        HStack(spacing: 6) {
                            ForEach(CoachMode.allCases, id: \.self) { mode in
                                PillButton(
                                    label: coachModeLabel(mode),
                                    isActive: store.sleepGoal.mode == mode && !store.rephasePlan.isEnabled
                                ) {
                                    var goal = store.sleepGoal
                                    goal.mode = mode
                                    store.sleepGoal = goal
                                }
                                .disabled(store.rephasePlan.isEnabled)
                            }
                        }
                    }
                    .padding(16)
                }
                .liquidGlass(cornerRadius: 16)

                // Conditional content
                if store.rephasePlan.isEnabled {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(SpiralColors.accent)
                        Text(String(localized: "settings.coachMode.rephaseNote", bundle: bundle))
                            .font(.subheadline)
                            .foregroundStyle(SpiralColors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .liquidGlass(cornerRadius: 16)
                } else if store.sleepGoal.mode == .shiftWork || store.sleepGoal.mode == .customSchedule {
                    VStack(spacing: 0) {
                        // Bed time slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(localized: "settings.coachMode.targetBed", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Spacer()
                                Text(formatHour(store.sleepGoal.targetBedHour))
                                    .font(.subheadline.weight(.semibold).monospaced())
                                    .foregroundStyle(SpiralColors.accent)
                            }
                            Slider(
                                value: Binding(
                                    get: { store.sleepGoal.targetBedHour },
                                    set: { v in var g = store.sleepGoal; g.targetBedHour = v; store.sleepGoal = g }
                                ),
                                in: 0...23.75, step: 0.25
                            ).tint(SpiralColors.accent)
                        }
                        .padding(.vertical, 12)

                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Wake time slider
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(localized: "settings.coachMode.targetWake", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Spacer()
                                Text(formatHour(store.sleepGoal.targetWakeHour))
                                    .font(.subheadline.weight(.semibold).monospaced())
                                    .foregroundStyle(SpiralColors.accent)
                            }
                            Slider(
                                value: Binding(
                                    get: { store.sleepGoal.targetWakeHour },
                                    set: { v in var g = store.sleepGoal; g.targetWakeHour = v; store.sleepGoal = g }
                                ),
                                in: 0...23.75, step: 0.25
                            ).tint(SpiralColors.accent)
                        }
                        .padding(.vertical, 12)
                    }
                    .padding(.horizontal, 16)
                    .liquidGlass(cornerRadius: 16)
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .font(.subheadline)
                            .foregroundStyle(SpiralColors.accent)
                        Text(String(localized: "settings.coachMode.generalHealthNote", bundle: bundle))
                            .font(.subheadline)
                            .foregroundStyle(SpiralColors.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .liquidGlass(cornerRadius: 16)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "settings.coachMode.title", bundle: bundle))
        .navigationBarTitleDisplayMode(.inline)
    }
}
