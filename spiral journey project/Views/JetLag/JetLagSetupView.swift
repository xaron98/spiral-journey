import SwiftUI
import SpiralKit

/// Jet lag planner setup: pick timezone offset and travel date.
///
/// The slider represents the TIME DIFFERENCE between origin and destination
/// (not the destination's raw UTC offset). For example, if the user is in
/// UTC+1 (Spain) and travels to UTC+7 (Thailand), they should set +6h.
struct JetLagSetupView: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @Environment(\.dismiss) private var dismiss

    @State private var offset: Int = 1
    @State private var travelDate = Date()
    @State private var showPlan = false

    /// User's current UTC offset in whole hours (used for contextual info).
    private var userUTCOffset: Int {
        TimeZone.current.secondsFromGMT() / 3600
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "airplane.departure")
                            .font(.largeTitle)
                            .foregroundStyle(SpiralColors.accent)
                        Text(String(localized: "jetlag.setup.title", bundle: bundle))
                            .font(.title2.weight(.light))
                            .foregroundStyle(SpiralColors.text)
                        Text(String(localized: "jetlag.setup.subtitle", bundle: bundle))
                            .font(.footnote)
                            .foregroundStyle(SpiralColors.muted)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 16)

                    // Timezone offset picker
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "jetlag.setup.offset", bundle: bundle))
                            .font(.caption.weight(.semibold).monospaced())
                            .tracking(1.5)
                            .foregroundStyle(SpiralColors.muted)
                            .textCase(.uppercase)

                        HStack(alignment: .firstTextBaseline) {
                            Text(offsetLabel)
                                .font(.title2.weight(.semibold).monospaced())
                                .foregroundStyle(SpiralColors.accent)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(directionLabel)
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(SpiralColors.muted)
                                Text(destinationUTCLabel)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(SpiralColors.muted.opacity(0.7))
                            }
                        }

                        Slider(value: Binding(
                            get: { Double(offset) },
                            set: { offset = Int($0) }
                        ), in: -12...12, step: 1)
                        .tint(SpiralColors.accent)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(SpiralColors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(SpiralColors.border, lineWidth: 0.8)
                            )
                    )

                    // Travel date
                    VStack(alignment: .leading, spacing: 8) {
                        Text(String(localized: "jetlag.setup.date", bundle: bundle))
                            .font(.caption.weight(.semibold).monospaced())
                            .tracking(1.5)
                            .foregroundStyle(SpiralColors.muted)
                            .textCase(.uppercase)

                        DatePicker("", selection: $travelDate, displayedComponents: .date)
                            .datePickerStyle(.graphical)
                            .tint(SpiralColors.accent)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(SpiralColors.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(SpiralColors.border, lineWidth: 0.8)
                            )
                    )

                    // Generate button
                    Button {
                        generatePlan()
                    } label: {
                        Text(String(localized: "jetlag.setup.generate", bundle: bundle))
                            .font(.body.weight(.semibold).monospaced())
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(offset == 0 ? SpiralColors.surface : SpiralColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .buttonStyle(.plain)
                    .disabled(offset == 0)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(String(localized: "jetlag.nav.title", bundle: bundle))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "jetlag.close", bundle: bundle)) { dismiss() }
                        .foregroundStyle(SpiralColors.muted)
                }
            }
            .navigationDestination(isPresented: $showPlan) {
                if let plan = store.jetLagPlan {
                    JetLagPlanView(plan: plan)
                }
            }
        }
    }

    /// Main label: shows the time difference, e.g. "+7h"
    private var offsetLabel: String {
        let sign = offset >= 0 ? "+" : ""
        return "\(sign)\(offset)h"
    }

    /// Direction indicator (east/west).
    private var directionLabel: String {
        if offset > 0 {
            return String(localized: "jetlag.direction.east", bundle: bundle)
        } else if offset < 0 {
            return String(localized: "jetlag.direction.west", bundle: bundle)
        }
        return ""
    }

    /// Shows the computed destination UTC, e.g. "UTC+1 → UTC+8"
    private var destinationUTCLabel: String {
        let destUTC = userUTCOffset + offset
        let originSign = userUTCOffset >= 0 ? "+" : ""
        let destSign = destUTC >= 0 ? "+" : ""
        return "UTC\(originSign)\(userUTCOffset) → UTC\(destSign)\(destUTC)"
    }

    private func generatePlan() {
        let bedtime = store.sleepGoal.targetBedHour
        let wake = store.sleepGoal.targetWakeHour
        let plan = JetLagEngine.generatePlan(
            offset: offset,
            travelDate: travelDate,
            currentBedtime: bedtime,
            currentWake: wake
        )
        store.jetLagPlan = plan
        showPlan = true
    }
}
