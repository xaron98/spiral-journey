import SwiftUI
import SpiralKit

/// Manual sleep episode logging tab.
struct InputTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    @State private var fellAsleepHour: Double = 23.5
    @State private var wokeUpHour:     Double = 7.0
    @State private var selectedDay:    Int    = 0
    @State private var cursorAbsHour:  Double = 0
    @State private var showEventPanel  = false

    private var currentAbsStart: Double {
        Double(selectedDay) * 24 + fellAsleepHour
    }
    private var currentAbsEnd: Double {
        let endHour = wokeUpHour < fellAsleepHour ? wokeUpHour + 24 : wokeUpHour
        return Double(selectedDay) * 24 + endHour
    }

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(spacing: 12) {
                // Spiral preview
                SpiralView(
                    records: store.records,
                    events: store.events,
                    spiralType: store.spiralType,
                    period: store.period,
                    linkGrowthToTau: store.linkGrowthToTau,
                    showCosinor: false,
                    showBiomarkers: false,
                    showTwoProcess: false,
                    selectedDay: selectedDay,
                    onSelectDay: { if let d = $0 { selectedDay = d } }
                )
                .frame(height: 300)

                // Sleep logging panel
                VStack(alignment: .leading, spacing: 12) {
                    PanelTitle(title: String(localized: "input.logSleep.title", bundle: bundle))

                    // Day selector
                    HStack {
                        Text(String(localized: "input.day.label", bundle: bundle)).font(.system(size: 10, design: .monospaced)).foregroundStyle(SpiralColors.muted)
                        Spacer()
                        Stepper("\(selectedDay + 1)", value: $selectedDay, in: 0...(store.numDays - 1))
                            .labelsHidden()
                        Text(String(format: String(localized: "input.day.value", bundle: bundle), selectedDay + 1))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SpiralColors.text)
                    }

                    // Bedtime
                    timeRow(label: String(localized: "input.fellAsleep", bundle: bundle), value: $fellAsleepHour, range: 18...30)

                    // Wakeup
                    timeRow(label: String(localized: "input.wokeUp", bundle: bundle), value: $wokeUpHour, range: 3...15)

                    // Duration preview
                    let dur = currentAbsEnd - currentAbsStart
                    Text(String(format: String(localized: "input.duration.value", bundle: bundle), max(0, dur)))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SpiralColors.muted)

                    // Add button
                    Button {
                        guard currentAbsEnd > currentAbsStart else { return }
                        let episode = SleepEpisode(
                            start: currentAbsStart,
                            end: currentAbsEnd,
                            source: .manual
                        )
                        store.sleepEpisodes.append(episode)
                        store.sleepEpisodes.sort { $0.start < $1.start }
                        store.recompute()
                    } label: {
                        Label(String(localized: "input.addEpisode", bundle: bundle), systemImage: "plus.circle.fill")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(SpiralColors.accentDim)
                            .foregroundStyle(SpiralColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                }
                .panelStyle()

                // Episode list
                if !store.sleepEpisodes.isEmpty {
                    episodeList
                }

                // Events
                EventPanelView(
                    events: Binding(
                        get: { store.events },
                        set: { store.events = $0 }
                    ),
                    cursorAbsoluteHour: cursorAbsHour
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle("Input")
    }

    private func timeRow(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)
                .frame(width: 80, alignment: .leading)
            Slider(value: value, in: range, step: 0.25)
                .tint(SpiralColors.accent)
            let displayHour = value.wrappedValue.truncatingRemainder(dividingBy: 24)
            Text(SleepStatistics.formatHour(displayHour < 0 ? displayHour + 24 : displayHour))
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundStyle(SpiralColors.accent)
                .frame(width: 44, alignment: .trailing)
        }
    }

    private var episodeList: some View {
        VStack(alignment: .leading, spacing: 8) {
            PanelTitle(title: String(format: String(localized: "input.episodes.title", bundle: bundle), store.sleepEpisodes.count))
            ForEach(store.sleepEpisodes) { ep in
                HStack {
                    Image(systemName: ep.source == .healthKit ? "heart.fill" : "pencil")
                        .font(.system(size: 9))
                        .foregroundStyle(ep.source == .healthKit ? SpiralColors.poor : SpiralColors.accentDim)
                    Text(String(format: "Day %d  %@→%@  %.1fh",
                                Int(ep.start / 24),
                                SleepStatistics.formatHour(ep.start.truncatingRemainder(dividingBy: 24)),
                                SleepStatistics.formatHour(ep.end.truncatingRemainder(dividingBy: 24)),
                                ep.duration))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(SpiralColors.text)
                    Spacer()
                    Button {
                        store.removeEpisode(id: ep.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundStyle(SpiralColors.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panelStyle()
    }
}
