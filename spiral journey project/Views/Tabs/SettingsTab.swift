import SwiftUI
import SwiftData
import SpiralKit

/// Settings tab: appearance, language, spiral controls, HealthKit, data management.
struct SettingsTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(CalendarManager.self) private var calendarManager
    @Environment(LLMService.self) private var llm
    @Environment(SleepDNAService.self) private var dnaService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.languageBundle) private var bundle
    @State private var isRefreshing = false
    @State private var isImporting = false
    @State private var isImportingCalendar = false
    @State private var showClearManualConfirm = false
    @State private var showResetAllConfirm = false
    @State private var showContextBlockEditor = false
    @State private var editingBlock: ContextBlock? = nil
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showExportShare = false

    // MARK: - Helpers

    private func coachModeLabel(_ mode: CoachMode) -> String {
        switch mode {
        case .generalHealth:    return String(localized: "settings.coachMode.generalHealth", bundle: bundle)
        case .shiftWork:        return String(localized: "settings.coachMode.shiftWork", bundle: bundle)
        case .customSchedule:   return String(localized: "settings.coachMode.customSchedule", bundle: bundle)
        case .rephase:          return String(localized: "settings.coachMode.rephase", bundle: bundle)
        }
    }

    private func chronotypeLabel(_ ct: Chronotype) -> String {
        let key = "chronotype.result.\(ct.rawValue)"
        return String(localized: String.LocalizationValue(key), bundle: bundle)
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
                        Button {
                            store.language = lang
                            // Mark that the user explicitly chose a language.
                            // This prevents the migration from resetting it to .system on next launch.
                            UserDefaults(suiteName: "group.xaron.spiral-journey-project")?
                                .set(true, forKey: "userChoseLanguageExplicitly")
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(lang == .system
                                         ? String(localized: "settings.language.system", bundle: bundle)
                                         : lang.nativeName)
                                        .font(.system(size: 12, design: .monospaced))
                                        .foregroundStyle(store.language == lang ? SpiralColors.accent : SpiralColors.text)
                                    if lang == .system {
                                        Text(Locale.current.localizedString(forLanguageCode: AppLanguage.resolvedSystemLocale) ?? AppLanguage.resolvedSystemLocale)
                                            .font(.system(size: 10, design: .monospaced))
                                            .foregroundStyle(SpiralColors.muted)
                                    }
                                }
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

                    // 2D / 3D mode toggle
                    HStack(spacing: 6) {
                        PillButton(label: "3D", isActive: !store.flatMode) { store.flatMode = false }
                        PillButton(label: "2D", isActive: store.flatMode) { store.flatMode = true }
                    }

                    // Period presets
                    HStack(spacing: 6) {
                        PillButton(label: "24h", isActive: abs(store.period - 24.0) < 0.5) {
                            store.period = 24.0
                        }
                        PillButton(label: String(localized: "spiral.controls.weekly", bundle: bundle), isActive: abs(store.period - 168.0) < 1) {
                            store.period = 168.0
                        }
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
                        Slider(value: $store.period, in: 23.0...168.0, step: 0.1).tint(SpiralColors.accent)
                    }

                    // Depth / zoom slider — only shown in 3D mode
                    if !store.flatMode {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(String(localized: "spiral.controls.zoom", bundle: bundle))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(SpiralColors.muted)
                                Spacer()
                                Text(store.depthScale < 0.2 ? String(format: "%.2f×", store.depthScale) : String(format: "%.1f×", store.depthScale))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(SpiralColors.accent)
                            }
                            Slider(value: $store.depthScale, in: 0.05...3.0, step: 0.05).tint(SpiralColors.accent)
                        }
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

                // ── Coach Mode ──────────────────────────────────────────────
                SettingsSection(title: String(localized: "settings.coachMode.title", bundle: bundle), icon: "lightbulb.min") {
                    // Mode picker
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

                    if store.rephasePlan.isEnabled {
                        // Rephase mode is managed in the Rephase Editor
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(SpiralColors.accent)
                            Text(String(localized: "settings.coachMode.rephaseNote", bundle: bundle))
                                .font(.system(size: 10))
                                .foregroundStyle(SpiralColors.muted)
                        }
                    } else if store.sleepGoal.mode == .shiftWork || store.sleepGoal.mode == .customSchedule {
                        // Bed / wake pickers
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(localized: "settings.coachMode.targetBed", bundle: bundle))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(SpiralColors.muted)
                                Spacer()
                                Text(formatHour(store.sleepGoal.targetBedHour))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(SpiralColors.accent)
                            }
                            Slider(
                                value: Binding(
                                    get: { store.sleepGoal.targetBedHour },
                                    set: { v in var g = store.sleepGoal; g.targetBedHour = v; store.sleepGoal = g }
                                ),
                                in: 0...23.75, step: 0.25
                            ).tint(SpiralColors.accent)

                            HStack {
                                Text(String(localized: "settings.coachMode.targetWake", bundle: bundle))
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(SpiralColors.muted)
                                Spacer()
                                Text(formatHour(store.sleepGoal.targetWakeHour))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
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
                    } else {
                        // General health note
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 10))
                                .foregroundStyle(SpiralColors.accent)
                            Text(String(localized: "settings.coachMode.generalHealthNote", bundle: bundle))
                                .font(.system(size: 10))
                                .foregroundStyle(SpiralColors.muted)
                        }
                    }
                }

                // ── Daily Context ─────────────────────────────────────────
                SettingsSection(title: String(localized: "settings.context.title", bundle: bundle), icon: "briefcase.fill") {
                    Toggle(isOn: $store.contextBlocksEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "settings.context.enable", bundle: bundle))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(SpiralColors.text)
                            Text(String(localized: "settings.context.enable.desc", bundle: bundle))
                                .font(.system(size: 10))
                                .foregroundStyle(SpiralColors.muted)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: SpiralColors.contextPrimary))

                    if store.contextBlocksEnabled {
                        // Existing blocks list
                        if !store.contextBlocks.isEmpty {
                            ForEach(store.contextBlocks) { block in
                                HStack(spacing: 8) {
                                    Image(systemName: block.type.sfSymbol)
                                        .font(.system(size: 12))
                                        .foregroundStyle(SpiralColors.contextPrimary.opacity(block.isEnabled ? 1 : 0.4))
                                        .frame(width: 20)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(block.label)
                                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                                            .foregroundStyle(block.isEnabled ? SpiralColors.text : SpiralColors.muted)
                                        HStack(spacing: 4) {
                                            Text(block.timeRangeString)
                                            if let days = block.activeDaysShort {
                                                Text("·")
                                                Text(days)
                                            }
                                        }
                                        .font(.system(size: 9, design: .monospaced))
                                        .foregroundStyle(SpiralColors.muted)
                                    }

                                    Spacer()

                                    // Toggle enable/disable
                                    Button {
                                        var updated = block
                                        updated.isEnabled.toggle()
                                        store.updateContextBlock(updated)
                                    } label: {
                                        Image(systemName: block.isEnabled ? "eye.fill" : "eye.slash")
                                            .font(.system(size: 10))
                                            .foregroundStyle(block.isEnabled ? SpiralColors.contextPrimary : SpiralColors.muted)
                                    }
                                    .buttonStyle(.plain)

                                    // Edit
                                    Button {
                                        editingBlock = block
                                    } label: {
                                        Image(systemName: "pencil")
                                            .font(.system(size: 10))
                                            .foregroundStyle(SpiralColors.accent)
                                    }
                                    .buttonStyle(.plain)

                                    // Delete
                                    Button {
                                        store.removeContextBlock(id: block.id)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundStyle(SpiralColors.poor)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(.vertical, 2)
                            }
                        }

                        // Add block button
                        Button {
                            editingBlock = nil
                            showContextBlockEditor = true
                        } label: {
                            Label(String(localized: "settings.context.addBlock", bundle: bundle), systemImage: "plus.circle")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(SpiralColors.contextPrimary)
                        }
                        .buttonStyle(.plain)

                        // Buffer slider
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(String(localized: "settings.context.buffer", bundle: bundle))
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundStyle(SpiralColors.muted)
                                Spacer()
                                Text(String(format: "%.0f min", store.contextBufferMinutes))
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(SpiralColors.contextPrimary)
                            }
                            Slider(value: $store.contextBufferMinutes, in: 15...120, step: 15)
                                .tint(SpiralColors.contextPrimary)
                        }

                        // Calendar import
                        Divider().background(SpiralColors.border)

                        if calendarManager.isAuthorized {
                            Button {
                                isImportingCalendar = true
                                let newBlocks = calendarManager.importBlocks(existingBlocks: store.contextBlocks)
                                for block in newBlocks {
                                    store.addContextBlock(block)
                                }
                                isImportingCalendar = false
                            } label: {
                                HStack {
                                    if isImportingCalendar { ProgressView().scaleEffect(0.7) }
                                    Label(
                                        String(localized: "settings.context.importCalendar", bundle: bundle),
                                        systemImage: "calendar.badge.plus"
                                    )
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(SpiralColors.contextPrimary)
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isImportingCalendar)
                        } else {
                            Button {
                                Task { await calendarManager.requestAuthorization() }
                            } label: {
                                Label(
                                    String(localized: "settings.context.connectCalendar", bundle: bundle),
                                    systemImage: "calendar"
                                )
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(SpiralColors.muted)
                            }
                            .buttonStyle(.plain)
                        }

                        if let err = calendarManager.errorMessage {
                            Text(err)
                                .font(.system(size: 9))
                                .foregroundStyle(SpiralColors.poor)
                        }
                    }
                }
                .sheet(isPresented: $showContextBlockEditor) {
                    ContextBlockEditorView { block in
                        store.addContextBlock(block)
                    }
                }
                .sheet(item: $editingBlock) { block in
                    ContextBlockEditorView(existing: block) { updated in
                        store.updateContextBlock(updated)
                    }
                }

                // ── Prediction ─────────────────────────────────────────────
                SettingsSection(title: String(localized: "settings.prediction.title", bundle: bundle), icon: "moon.stars") {
                    Toggle(isOn: $store.predictionEnabled) {
                        Text(String(localized: "settings.prediction.enable", bundle: bundle))
                            .font(.system(size: 13))
                            .foregroundStyle(SpiralColors.text)
                    }
                    .tint(Color(hex: "a78bfa"))
                    if store.predictionEnabled {
                        Toggle(isOn: $store.predictionOverlayEnabled) {
                            Text(String(localized: "settings.prediction.overlay", bundle: bundle))
                                .font(.system(size: 13))
                                .foregroundStyle(SpiralColors.text)
                        }
                        .tint(Color(hex: "a78bfa"))

                        // ML model toggle
                        Toggle(isOn: $store.mlPredictionEnabled) {
                            Text(String(localized: "settings.prediction.ml", bundle: bundle))
                                .font(.system(size: 13))
                                .foregroundStyle(SpiralColors.text)
                        }
                        .tint(Color(hex: "a78bfa"))

                        // ML model info
                        if store.mlPredictionEnabled {
                            mlModelInfoView
                        }
                    }
                }

                // ── AI Coach ───────────────────────────────────────────────
                aiCoachSection

                // ── HealthKit ───────────────────────────────────────────────
                SettingsSection(title: String(localized: "settings.healthData.title", bundle: bundle), icon: "heart.fill") {
                    if !healthKit.isAvailable {
                        Text(String(localized: "settings.healthData.notAvailable", bundle: bundle))
                            .font(.system(size: 11))
                            .foregroundStyle(SpiralColors.muted)
                    } else if !healthKit.isAuthorized {
                        Button {
                            Task {
                                await healthKit.requestAuthorization()
                                // Import immediately after authorization
                                if let result = await healthKit.importAndAdjustEpoch() {
                                    store.applyHealthKitResult(epoch: result.epoch, episodes: result.episodes)
                                }
                            }
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
                                    if let result = await healthKit.importAndAdjustEpoch() {
                                        store.applyHealthKitResult(epoch: result.epoch, episodes: result.episodes)
                                    }
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
                    let hasHealthKitData = store.sleepEpisodes.contains { $0.source == .healthKit }
                    if hasHealthKitData {
                        // startDate and numDays are managed automatically from HealthKit data
                        HStack {
                            Text(String(localized: "settings.dataRange.startDate", bundle: bundle))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(SpiralColors.muted)
                            Spacer()
                            Text(store.startDate, style: .date)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(SpiralColors.text)
                        }
                        HStack {
                            Text(String(localized: "settings.dataRange.days", bundle: bundle))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(SpiralColors.muted)
                            Spacer()
                            Text(String(format: String(localized: "settings.dataRange.daysValue", bundle: bundle), store.numDays))
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(SpiralColors.text)
                        }
                        Text(String(localized: "settings.dataRange.autoNote", bundle: bundle))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    } else {
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

                    // CSV export for scientific validation
                    Button {
                        isExporting = true
                        Task {
                            exportURL = DataExporter.exportAll(
                                store: store,
                                dnaProfile: dnaService.latestProfile,
                                context: modelContext
                            )
                            isExporting = false
                            if exportURL != nil {
                                showExportShare = true
                            }
                        }
                    } label: {
                        HStack {
                            if isExporting { ProgressView().scaleEffect(0.7) }
                            Label(
                                String(localized: "settings.data.exportCSV", bundle: bundle),
                                systemImage: "square.and.arrow.up"
                            )
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SpiralColors.accent)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting)
                    .sheet(isPresented: $showExportShare) {
                        if let url = exportURL {
                            ShareSheet(activityItems: [url])
                        }
                    }

                    Button(role: .destructive) {
                        showClearManualConfirm = true
                    } label: {
                        Label(String(localized: "settings.data.clearManual", bundle: bundle), systemImage: "trash")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SpiralColors.poor)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        String(localized: "settings.confirm.title", bundle: bundle),
                        isPresented: $showClearManualConfirm,
                        titleVisibility: .visible
                    ) {
                        Button(String(localized: "settings.confirm.yes", bundle: bundle), role: .destructive) {
                            store.sleepEpisodes.removeAll { $0.source == .manual }
                            store.recompute()
                        }
                        Button(String(localized: "settings.confirm.cancel", bundle: bundle), role: .cancel) {}
                    }

                    // Fresh start: wipe everything and import directly from HealthKit
                    if healthKit.isAuthorized {
                        Button {
                            isImporting = true
                            Task {
                                store.resetAllData()
                                if let result = await healthKit.importAndAdjustEpoch() {
                                    store.applyHealthKitResult(epoch: result.epoch, episodes: result.episodes)
                                }
                                isImporting = false
                            }
                        } label: {
                            HStack {
                                if isImporting { ProgressView().scaleEffect(0.7) }
                                Label(
                                    isImporting
                                        ? String(localized: "settings.data.importing", bundle: bundle)
                                        : String(localized: "settings.data.importHealthKit", bundle: bundle),
                                    systemImage: "arrow.clockwise.heart.fill"
                                )
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(SpiralColors.poor)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting)
                    }

                    Button(role: .destructive) {
                        showResetAllConfirm = true
                    } label: {
                        Label(String(localized: "settings.data.resetAll", bundle: bundle), systemImage: "arrow.counterclockwise")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SpiralColors.poor)
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog(
                        String(localized: "settings.confirm.title", bundle: bundle),
                        isPresented: $showResetAllConfirm,
                        titleVisibility: .visible
                    ) {
                        Button(String(localized: "settings.confirm.yes", bundle: bundle), role: .destructive) {
                            store.resetAllData()
                        }
                        Button(String(localized: "settings.confirm.cancel", bundle: bundle), role: .cancel) {}
                    }
                }

                // ── Chronotype ─────────────────────────────────────────────
                SettingsSection(title: String(localized: "settings.chronotype.title", bundle: bundle), icon: "person.crop.circle") {
                    if let ct = store.chronotypeResult {
                        HStack(spacing: 8) {
                            Text(ct.chronotype.emoji)
                                .font(.system(size: 20))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(chronotypeLabel(ct.chronotype))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundStyle(SpiralColors.text)
                                Text(String(
                                    format: String(localized: "settings.chronotype.score", bundle: bundle),
                                    ct.totalScore
                                ))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(SpiralColors.muted)
                            }
                            Spacer()
                        }
                    }

                    Button {
                        store.hasCompletedChronotype = false
                    } label: {
                        Label(
                            store.chronotypeResult != nil
                                ? String(localized: "settings.chronotype.retake", bundle: bundle)
                                : String(localized: "settings.chronotype.take", bundle: bundle),
                            systemImage: "arrow.counterclockwise"
                        )
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SpiralColors.accent)
                    }
                    .buttonStyle(.plain)
                }

                // ── Notifications ──────────────────────────────────────────
                SettingsSection(title: String(localized: "settings.notifications.title", bundle: bundle), icon: "bell.badge") {
                    Toggle(isOn: $store.notificationsEnabled) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(localized: "settings.notifications.weekly", bundle: bundle))
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(SpiralColors.text)
                            Text(String(localized: "settings.notifications.weekly.desc", bundle: bundle))
                                .font(.system(size: 10))
                                .foregroundStyle(SpiralColors.muted)
                        }
                    }
                    .toggleStyle(SwitchToggleStyle(tint: SpiralColors.accent))
                    .onChange(of: store.notificationsEnabled) { _, newValue in
                        if newValue {
                            Task {
                                let granted = await NotificationManager.shared.requestPermission()
                                if !granted {
                                    store.notificationsEnabled = false
                                }
                            }
                        }
                    }
                }

                // ── Background Processing ─────────────────────────────────
                SettingsSection(title: String(localized: "settings.background.title", bundle: bundle), icon: "gearshape.2") {
                    Toggle(isOn: Binding(
                        get: { store.bgRetrainEnabled },
                        set: { store.bgRetrainEnabled = $0 }
                    )) {
                        Text(String(localized: "settings.background.retrain", bundle: bundle))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(SpiralColors.text)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: SpiralColors.accent))

                    Toggle(isOn: Binding(
                        get: { store.bgDNARefreshEnabled },
                        set: { store.bgDNARefreshEnabled = $0 }
                    )) {
                        Text(String(localized: "settings.background.dna", bundle: bundle))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(SpiralColors.text)
                    }
                    .toggleStyle(SwitchToggleStyle(tint: SpiralColors.accent))
                }

                // ── About ───────────────────────────────────────────────────

                SettingsSection(title: String(localized: "settings.about.title", bundle: bundle), icon: "info.circle") {
                    Text("Spiral Journey v1.0")
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(SpiralColors.text)
                    Text(String(localized: "settings.about.description", bundle: bundle))
                        .font(.system(size: 10))
                        .foregroundStyle(SpiralColors.muted)
                        .lineSpacing(3)
                    Text(String(localized: "settings.about.philosophy", bundle: bundle))
                        .font(.system(size: 10))
                        .foregroundStyle(SpiralColors.muted)
                        .lineSpacing(3)
                        .padding(.top, 4)

                    // Legal links
                    VStack(alignment: .leading, spacing: 6) {
                        if let privacyURL = URL(string: "https://xaron98.github.io/spiral-journey/privacy-policy.html") {
                            Link(destination: privacyURL) {
                                HStack(spacing: 6) {
                                    Image(systemName: "lock.shield")
                                        .font(.system(size: 10))
                                    Text(String(localized: "about.privacy", bundle: bundle))
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(SpiralColors.accent)
                            }
                        }
                        if let supportURL = URL(string: "https://github.com/xaron98/spiral-journey/issues") {
                            Link(destination: supportURL) {
                                HStack(spacing: 6) {
                                    Image(systemName: "envelope")
                                        .font(.system(size: 10))
                                    Text(String(localized: "about.support", bundle: bundle))
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(SpiralColors.accent)
                            }
                        }
                        if let websiteURL = URL(string: "https://xaron98.github.io/spiral-journey/") {
                            Link(destination: websiteURL) {
                                HStack(spacing: 6) {
                                    Image(systemName: "globe")
                                        .font(.system(size: 10))
                                    Text(String(localized: "about.website", bundle: bundle))
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(SpiralColors.accent)
                            }
                        }
                    }
                    .padding(.top, 6)

                    // Medical disclaimer
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                        Text(String(localized: "about.disclaimer", bundle: bundle))
                            .font(.system(size: 10))
                            .foregroundStyle(SpiralColors.muted)
                            .lineSpacing(3)
                    }
                    .padding(.top, 6)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 100)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
    }

    // MARK: - ML Model Info

    @ViewBuilder
    private var mlModelInfoView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Engine status
            HStack {
                Text(String(localized: "settings.prediction.engine", bundle: bundle))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
                Spacer()
                Text(MLPredictionEngine.isAvailable
                     ? (MLPredictionEngine.isPersonalised
                        ? String(localized: "settings.prediction.personalised", bundle: bundle)
                        : String(localized: "settings.prediction.generic", bundle: bundle))
                     : String(localized: "settings.prediction.heuristic", bundle: bundle))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(MLPredictionEngine.isPersonalised
                                    ? Color(hex: "34d399")
                                    : SpiralColors.text)
            }

            // Ground truth count
            let evaluatedCount = store.predictionHistory.filter { $0.actual != nil }.count
            HStack {
                Text(String(localized: "settings.prediction.groundTruth", bundle: bundle))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(SpiralColors.muted)
                Spacer()
                Text("\(evaluatedCount) / \(ModelTrainingService.minimumSamples)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(evaluatedCount >= ModelTrainingService.minimumSamples
                                    ? Color(hex: "34d399")
                                    : SpiralColors.text)
            }

            // Progress bar toward minimum samples
            if evaluatedCount < ModelTrainingService.minimumSamples {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color(hex: "a78bfa"))
                            .frame(
                                width: geo.size.width * min(1.0, Double(evaluatedCount) / Double(ModelTrainingService.minimumSamples)),
                                height: 4
                            )
                    }
                }
                .frame(height: 4)
            }

            // Last trained info
            if let lastTrained = store.lastModelTrainedDate {
                HStack {
                    Text(String(localized: "settings.prediction.lastTrained", bundle: bundle))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SpiralColors.muted)
                    Spacer()
                    Text(lastTrained, style: .relative)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SpiralColors.text)
                }
                if store.modelTrainingSampleCount > 0 {
                    HStack {
                        Text(String(localized: "settings.prediction.samplesUsed", bundle: bundle))
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SpiralColors.muted)
                        Spacer()
                        Text("\(store.modelTrainingSampleCount)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SpiralColors.text)
                    }
                }
            }

            // Privacy note
            Text(String(localized: "settings.prediction.privacyNote", bundle: bundle))
                .font(.system(size: 10))
                .foregroundStyle(SpiralColors.muted)
                .lineSpacing(2)
                .padding(.top, 2)
        }
        .padding(.top, 4)
    }

    // MARK: - AI Coach Section

    @ViewBuilder
    private var aiCoachSection: some View {
        @Bindable var store = store
        SettingsSection(title: String(localized: "settings.aiCoach.title", bundle: bundle), icon: "brain.head.profile") {
            Toggle(isOn: $store.llmEnabled) {
                Text(String(localized: "settings.aiCoach.enable", bundle: bundle))
                    .font(.system(size: 13))
                    .foregroundStyle(SpiralColors.text)
            }
            .tint(SpiralColors.accent)

            if store.llmEnabled {
                // Model status
                HStack {
                    Text(String(localized: "settings.aiCoach.status", bundle: bundle))
                        .font(.system(size: 11))
                        .foregroundStyle(SpiralColors.muted)
                    Spacer()
                    Text(llm.state.statusText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(SpiralColors.subtle)
                }

                // Size info
                if let _ = llm.modelFileSize {
                    HStack {
                        Text(String(localized: "settings.aiCoach.space", bundle: bundle))
                            .font(.system(size: 11))
                            .foregroundStyle(SpiralColors.muted)
                        Spacer()
                        Text(llm.modelFileSizeString)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(SpiralColors.subtle)
                    }
                }

                // Download / Delete buttons
                switch llm.state {
                case .notDownloaded, .error:
                    Button {
                        Task { await llm.downloadModel() }
                    } label: {
                        Label(String(localized: "settings.aiCoach.download", bundle: bundle), systemImage: "arrow.down.to.line")
                            .font(.system(size: 12))
                            .foregroundStyle(SpiralColors.accent)
                    }
                case .downloading(let progress):
                    ProgressView(value: progress)
                        .tint(SpiralColors.accent)
                case .downloaded, .ready:
                    Button(role: .destructive) {
                        llm.deleteModel()
                        store.chatHistory = []
                    } label: {
                        Label(String(localized: "settings.aiCoach.delete", bundle: bundle), systemImage: "trash")
                            .font(.system(size: 12))
                            .foregroundStyle(SpiralColors.poor)
                    }
                case .loading:
                    ProgressView()
                        .controlSize(.small)
                }

                // Privacy note
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 9))
                    Text(String(localized: "settings.aiCoach.privacy", bundle: bundle))
                        .font(.system(size: 10))
                }
                .foregroundStyle(SpiralColors.faint)
            }
        }
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

// MARK: - Share Sheet

#if os(iOS)
/// Minimal UIKit wrapper to present a UIActivityViewController via SwiftUI `.sheet`.
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
