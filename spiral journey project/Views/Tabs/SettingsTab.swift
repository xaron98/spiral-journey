import SwiftUI
import SpiralKit

/// Settings tab: appearance, language, spiral controls, HealthKit, data management.
struct SettingsTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(\.languageBundle) private var bundle
    @State private var isRefreshing = false

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(spacing: 14) {

                // ── Appearance ──────────────────────────────────────────────
                SettingsSection(title: String(localized: "settings.appearance.title", bundle: bundle), icon: "circle.lefthalf.filled") {
                    HStack(spacing: 6) {
                        ForEach(AppAppearance.allCases, id: \.self) { mode in
                            PillButton(
                                label: mode == .dark
                                    ? String(localized: "settings.appearance.dark",   bundle: bundle)
                                    : mode == .light
                                    ? String(localized: "settings.appearance.light",  bundle: bundle)
                                    : String(localized: "settings.appearance.system", bundle: bundle),
                                isActive: store.appearance == mode
                            ) { store.appearance = mode }
                        }
                    }
                }

                // ── Language ────────────────────────────────────────────────
                SettingsSection(title: String(localized: "settings.language.title", bundle: bundle), icon: "globe") {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Button { store.language = lang } label: {
                            HStack {
                                Text(lang.nativeName)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundStyle(store.language == lang ? SpiralColors.accent : SpiralColors.text)
                                Spacer()
                                if store.language == lang {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(SpiralColors.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // ── Spiral visualization ────────────────────────────────────
                SettingsSection(title: String(localized: "spiral.controls.title", bundle: bundle), icon: "hurricane") {
                    // Spiral type
                    HStack(spacing: 6) {
                        PillButton(label: String(localized: "spiral.controls.archimedean", bundle: bundle), isActive: store.spiralType == .archimedean) { store.spiralType = .archimedean }
                        PillButton(label: String(localized: "spiral.controls.logarithmic", bundle: bundle), isActive: store.spiralType == .logarithmic)  { store.spiralType = .logarithmic }
                    }

                    // Period slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "spiral.controls.period", bundle: bundle))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(SpiralColors.muted)
                            Spacer()
                            Text(String(format: "%.1fh", store.period))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(SpiralColors.accent)
                        }
                        Slider(value: $store.period, in: 23.0...25.5, step: 0.1).tint(SpiralColors.accent)
                    }

                    // Depth / zoom slider
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(String(localized: "spiral.controls.zoom", bundle: bundle))
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundStyle(SpiralColors.muted)
                            Spacer()
                            Text(String(format: "%.1f×", store.depthScale))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(SpiralColors.accent)
                        }
                        Slider(value: $store.depthScale, in: 0.5...3.0, step: 0.1).tint(SpiralColors.accent)
                    }

                    // Grid guides toggle
                    Toggle(isOn: $store.showGrid) {
                        Text(String(localized: "spiral.controls.grid", bundle: bundle))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(SpiralColors.text)
                    }
                    .toggleStyle(.button)
                    .tint(SpiralColors.accentDim)

                    // Link τ growth toggle
                    Toggle(isOn: $store.linkGrowthToTau) {
                        Text(String(localized: "spiral.controls.linkTau", bundle: bundle))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(SpiralColors.text)
                    }
                    .toggleStyle(.button)
                    .tint(SpiralColors.accentDim)
                }

                // ── HealthKit ───────────────────────────────────────────────
                SettingsSection(title: String(localized: "settings.healthData.title", bundle: bundle), icon: "heart.fill") {
                    if !healthKit.isAvailable {
                        Text(String(localized: "settings.healthData.notAvailable", bundle: bundle))
                            .font(.system(size: 11))
                            .foregroundStyle(SpiralColors.muted)
                    } else if !healthKit.isAuthorized {
                        Button {
                            Task { await healthKit.requestAuthorization() }
                        } label: {
                            Label(String(localized: "settings.healthData.connect", bundle: bundle), systemImage: "heart.fill")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(SpiralColors.poor.opacity(0.15))
                                .foregroundStyle(SpiralColors.poor)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    } else {
                        HStack {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(SpiralColors.good)
                            Text(String(localized: "settings.healthData.connected", bundle: bundle))
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(SpiralColors.text)
                            Spacer()
                            Button {
                                isRefreshing = true
                                Task {
                                    let episodes = await healthKit.fetchRecentSleepEpisodes(days: store.numDays, epoch: store.startDate)
                                    store.mergeHealthKitEpisodes(episodes)
                                    isRefreshing = false
                                }
                            } label: {
                                Label(
                                    isRefreshing
                                        ? String(localized: "settings.healthData.syncing", bundle: bundle)
                                        : String(localized: "settings.healthData.syncNow", bundle: bundle),
                                    systemImage: "arrow.clockwise"
                                )
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(SpiralColors.accent)
                            }
                            .buttonStyle(.plain)
                            .disabled(isRefreshing)
                        }
                    }
                    if let err = healthKit.errorMessage {
                        Text(err).font(.system(size: 9)).foregroundStyle(SpiralColors.poor)
                    }
                }

                // ── Date range ──────────────────────────────────────────────
                SettingsSection(title: String(localized: "settings.dataRange.title", bundle: bundle), icon: "calendar") {
                    DatePicker(
                        String(localized: "settings.dataRange.startDate", bundle: bundle),
                        selection: $store.startDate,
                        displayedComponents: .date
                    )
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SpiralColors.text)
                    .datePickerStyle(.compact)
                    .tint(SpiralColors.accent)

                    HStack {
                        Text(String(localized: "settings.dataRange.days", bundle: bundle))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)
                        Spacer()
                        Stepper("\(store.numDays)", value: $store.numDays, in: 3...90).labelsHidden()
                        Text(String(format: String(localized: "settings.dataRange.daysValue", bundle: bundle), store.numDays))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(SpiralColors.text)
                    }
                }

                // ── Data management ─────────────────────────────────────────
                SettingsSection(title: String(localized: "settings.data.title", bundle: bundle), icon: "tray.full") {
                    HStack(spacing: 12) {
                        Text(String(format: String(localized: "settings.data.episodeCount", bundle: bundle), store.sleepEpisodes.count))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)
                        Text(String(format: String(localized: "settings.data.eventCount", bundle: bundle), store.events.count))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)
                        Spacer()
                    }
                    Button(role: .destructive) {
                        store.sleepEpisodes.removeAll { $0.source == .manual }
                        store.recompute()
                    } label: {
                        Label(String(localized: "settings.data.clearManual", bundle: bundle), systemImage: "trash")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SpiralColors.poor)
                    }
                    .buttonStyle(.plain)

                    Button(role: .destructive) {
                        store.resetAllData()
                    } label: {
                        Label(String(localized: "settings.data.resetAll", bundle: bundle), systemImage: "arrow.counterclockwise")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SpiralColors.poor)
                    }
                    .buttonStyle(.plain)
                }

                // ── About ───────────────────────────────────────────────────
                SettingsSection(title: String(localized: "settings.about.title", bundle: bundle), icon: "info.circle") {
                    Text("Spiral Journey")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SpiralColors.text)
                    Text(String(localized: "settings.about.description", bundle: bundle))
                        .font(.system(size: 10))
                        .foregroundStyle(SpiralColors.muted)
                        .lineSpacing(3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 100)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
    }
}

// MARK: - Settings section container

private struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(SpiralColors.accent)
                Text(title.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(SpiralColors.muted)
            }
            content()
        }
        .panelStyle()
    }
}
