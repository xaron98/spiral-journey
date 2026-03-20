import SwiftUI
import SpiralKit

/// Manual sleep episode logging tab.
struct InputTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @Environment(HealthKitManager.self) private var healthKit

    @State private var isRefreshingHK = false
    @State private var fellAsleepHour: Double = 23.5
    @State private var wokeUpHour:     Double = 7.0
    @State private var selectedDay:    Int    = 0
    @State private var cursorAbsHour:  Double = 0
    @State private var showEventPanel  = false

    /// Returns the bedtime/wakeup hours for `day` from stored episodes, or nil if none exist.
    private func storedHours(for day: Int) -> (bedtime: Double, wakeup: Double)? {
        let eps = store.sleepEpisodes.filter { Int($0.start / 24) == day }
        guard let ep = eps.first else { return nil }
        let bedtime = ep.start.truncatingRemainder(dividingBy: 24)
        let rawWakeup = ep.end.truncatingRemainder(dividingBy: 24)
        // Keep wakeup in [3,22] range expected by the slider
        let wakeup = rawWakeup < 3 ? rawWakeup + 24 : rawWakeup
        return (bedtime, min(wakeup, 22))
    }

    /// Updates sliders to reflect stored data (or sensible defaults) for `day`, with animation.
    private func syncSliders(to day: Int) {
        let bedtime: Double
        let wakeup: Double
        if let stored = storedHours(for: day) {
            bedtime = stored.bedtime
            wakeup  = stored.wakeup
        } else {
            // Default: current wall-clock hour for bedtime, +8h for wakeup, clamped to slider ranges
            let now = Calendar.current.dateComponents([.hour, .minute], from: Date())
            let currentHour = Double(now.hour ?? 23) + Double(now.minute ?? 30) / 60.0
            bedtime = min(max(currentHour, 18), 30)
            // Wakeup defaults to bedtime + 8h, wrapped into the wakeup slider range (3–22)
            let rawWakeup = (currentHour + 8.0).truncatingRemainder(dividingBy: 24)
            wakeup = min(max(rawWakeup, 3), 22)
        }
        withAnimation(.easeInOut(duration: 0.4)) {
            fellAsleepHour = bedtime
            wokeUpHour     = wakeup
        }
    }

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
                    onSelectDay: { if let d = $0 { selectedDay = d } },
                    contextBlocks: store.contextBlocksEnabled ? store.contextBlocks : []
                )
                .frame(height: 300)

                // HealthKit sync button — lets the user manually pull latest Watch sleep data
                if healthKit.isAuthorized {
                    Button {
                        guard !isRefreshingHK else { return }
                        isRefreshingHK = true
                        Task {
                            if let result = await healthKit.importAndAdjustEpoch() {
                                store.applyHealthKitResult(epoch: result.epoch, episodes: result.episodes)
                            }
                            isRefreshingHK = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if isRefreshingHK {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise.heart.fill")
                                    .font(.footnote)
                                    .foregroundStyle(SpiralColors.poor)
                            }
                            Text(String(localized: "input.syncHealthKit", bundle: bundle))
                                .font(.footnote.weight(.medium).monospaced())
                                .foregroundStyle(SpiralColors.text)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(SpiralColors.muted)
                        }
                        .padding(12)
                        .background(SpiralColors.surface.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(SpiralColors.border.opacity(0.4), lineWidth: 0.8))
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshingHK)
                }

                // Sleep logging panel
                VStack(alignment: .leading, spacing: 12) {
                    PanelTitle(title: String(localized: "input.logSleep.title", bundle: bundle))

                    // Day selector
                    HStack {
                        Text(String(localized: "input.day.label", bundle: bundle)).font(.caption.monospaced()).foregroundStyle(SpiralColors.muted)
                        Spacer()
                        Stepper("\(selectedDay + 1)", value: $selectedDay, in: 0...(store.numDays - 1))
                            .labelsHidden()
                        Text(String(format: String(localized: "input.day.value", bundle: bundle), selectedDay + 1))
                            .font(.caption.monospaced())
                            .foregroundStyle(SpiralColors.text)
                    }

                    // Bedtime
                    timeRow(label: String(localized: "input.fellAsleep", bundle: bundle), value: $fellAsleepHour, range: 18...30)

                    // Wakeup
                    timeRow(label: String(localized: "input.wokeUp", bundle: bundle), value: $wokeUpHour, range: 3...22)

                    // Duration preview
                    let dur = currentAbsEnd - currentAbsStart
                    Text(String(format: String(localized: "input.duration.value", bundle: bundle), max(0, dur)))
                        .font(.caption.monospaced())
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
                            .font(.footnote.weight(.semibold).monospaced())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(SpiralColors.accent)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: SpiralColors.accent.opacity(0.5), radius: 8, x: 0, y: 3)
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
                    events: store.events,
                    cursorAbsoluteHour: cursorAbsHour,
                    onAdd: { store.addEvent($0) },
                    onRemove: { store.removeEvent(id: $0) }
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "Input", bundle: bundle))
        .onAppear { syncSliders(to: selectedDay) }
        .onChange(of: selectedDay) { syncSliders(to: selectedDay) }
    }

    private func timeRow(label: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.caption2.monospaced())
                .foregroundStyle(SpiralColors.muted)
                .frame(width: 80, alignment: .leading)
            Slider(value: value, in: range, step: 0.25)
                .tint(SpiralColors.accent)
            let displayHour = value.wrappedValue.truncatingRemainder(dividingBy: 24)
            Text(SleepStatistics.formatHour(displayHour < 0 ? displayHour + 24 : displayHour))
                .font(.caption.weight(.semibold).monospaced())
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
                        .font(.caption2)
                        .foregroundStyle(ep.source == .healthKit ? SpiralColors.poor : SpiralColors.accentDim)
                    Text(String(format: "Day %d  %@→%@  %.1fh",
                                Int(ep.start / 24),
                                SleepStatistics.formatHour(ep.start.truncatingRemainder(dividingBy: 24)),
                                SleepStatistics.formatHour(ep.end.truncatingRemainder(dividingBy: 24)),
                                ep.duration))
                        .font(.caption.monospaced())
                        .foregroundStyle(SpiralColors.text)
                    Spacer()
                    Button {
                        store.removeEpisode(id: ep.id)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundStyle(SpiralColors.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .panelStyle()
    }
}
