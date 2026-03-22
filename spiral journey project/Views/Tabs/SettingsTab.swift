import SwiftUI
import SpiralKit

/// Settings tab — Apple-style grouped sections with NavigationLinks for complex sub-screens.
struct SettingsTab: View {

    @Environment(SpiralStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(LLMService.self) private var llm
    @Environment(\.languageBundle) private var bundle

    @State private var isRefreshing = false

    // MARK: - Helpers

    private func chronotypeLabel(_ ct: Chronotype) -> String {
        let key = "chronotype.result.\(ct.rawValue)"
        return String(localized: String.LocalizationValue(key), bundle: bundle)
    }

    // MARK: - Body

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {

                    // ── ASPECTO ──────────────────────────────────────────────
                    SettingsGroup(
                        title: String(localized: "settings.appearance.title", bundle: bundle),
                        icon: "circle.lefthalf.filled"
                    ) {
                        // Appearance pills
                        VStack(alignment: .leading, spacing: 6) {
                            Text(String(localized: "settings.appearance.title", bundle: bundle).uppercased())
                                .font(.caption2.weight(.semibold).monospaced())
                                .foregroundStyle(SpiralColors.muted)
                                .tracking(1)
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

                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Theme picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text(String(localized: "settings.theme.title", bundle: bundle).uppercased())
                                .font(.caption2.weight(.semibold).monospaced())
                                .foregroundStyle(SpiralColors.muted)
                                .tracking(1)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(ThemeLibrary.all) { theme in
                                        Button {
                                            withAnimation(.easeInOut(duration: 0.3)) {
                                                store.selectedTheme = theme.id
                                            }
                                        } label: {
                                            VStack(spacing: 6) {
                                                Circle()
                                                    .fill(Color(hex: theme.accentHex))
                                                    .frame(width: 36, height: 36)
                                                    .overlay(
                                                        Circle()
                                                            .stroke(store.selectedTheme == theme.id
                                                                    ? Color(hex: theme.accentHex)
                                                                    : Color.clear,
                                                                    lineWidth: 2)
                                                            .frame(width: 42, height: 42)
                                                    )
                                                Text(String(localized: String.LocalizationValue(theme.nameKey), bundle: bundle))
                                                    .font(.caption2)
                                                    .foregroundStyle(store.selectedTheme == theme.id
                                                                     ? SpiralColors.text
                                                                     : SpiralColors.muted)
                                            }
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }

                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Language → NavigationLink
                        NavigationLink {
                            LanguagePickerView()
                        } label: {
                            HStack {
                                Text(String(localized: "settings.language.title", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Spacer()
                                Text(store.language == .system
                                     ? String(localized: "settings.language.system", bundle: bundle)
                                     : store.language.nativeName)
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.muted)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SpiralColors.muted.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // ── ESPIRAL ───────────────────────────────────────────────
                    SettingsGroup(
                        title: String(localized: "spiral.controls.title", bundle: bundle),
                        icon: "hurricane"
                    ) {
                        NavigationLink {
                            SpiralControlsSettingsView()
                        } label: {
                            HStack {
                                Text(String(localized: "spiral.controls.title", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Spacer()
                                // Quick summary: type + mode
                                Text("\(store.spiralType == .archimedean ? "Arch" : "Log") · \(store.flatMode ? "2D" : "3D")")
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.muted)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SpiralColors.muted.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // ── GENERAL ────────────────────────────────────────────────
                    SettingsGroup(
                        title: String(localized: "settings.general.title", bundle: bundle),
                        icon: "ellipsis.circle"
                    ) {
                        // Chronotype row
                        Button {
                            store.hasCompletedChronotype = false
                        } label: {
                            HStack(spacing: 8) {
                                if let ct = store.chronotypeResult {
                                    Text(ct.chronotype.emoji).font(.title3)
                                    Text(chronotypeLabel(ct.chronotype))
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(SpiralColors.text)
                                } else {
                                    Text(String(localized: "settings.chronotype.take", bundle: bundle))
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(SpiralColors.accent)
                                }
                                Spacer()
                                if store.chronotypeResult != nil {
                                    Text(String(localized: "settings.chronotype.retake", bundle: bundle))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(SpiralColors.muted)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Notifications toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "settings.notifications.weekly", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Text(String(localized: "settings.notifications.weekly.desc", bundle: bundle))
                                    .font(.caption)
                                    .foregroundStyle(SpiralColors.muted)
                            }
                            Spacer()
                            Toggle("", isOn: $store.notificationsEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: SpiralColors.accent))
                                .onChange(of: store.notificationsEnabled) { _, newValue in
                                    if newValue {
                                        Task {
                                            let granted = await NotificationManager.shared.requestPermission()
                                            if !granted { store.notificationsEnabled = false }
                                        }
                                    }
                                }
                        }


                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Morning summary toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "settings.notifications.morning", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Text(String(localized: "settings.notifications.morning.desc", bundle: bundle))
                                    .font(.caption)
                                    .foregroundStyle(SpiralColors.muted)
                            }
                            Spacer()
                            Toggle("", isOn: $store.morningSummaryEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: SpiralColors.accent))
                                .onChange(of: store.morningSummaryEnabled) { _, newValue in
                                    if newValue {
                                        Task {
                                            let granted = await NotificationManager.shared.requestPermission()
                                            if !granted { store.morningSummaryEnabled = false }
                                        }
                                    } else {
                                        Task { await NotificationManager.shared.cancelMorningSummary() }
                                    }
                                }
                        }

                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Predictive alerts toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "settings.notifications.predictive", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Text(String(localized: "settings.notifications.predictive.desc", bundle: bundle))
                                    .font(.caption)
                                    .foregroundStyle(SpiralColors.muted)
                            }
                            Spacer()
                            Toggle("", isOn: $store.predictiveAlertsEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: SpiralColors.accent))
                                .onChange(of: store.predictiveAlertsEnabled) { _, newValue in
                                    if newValue {
                                        Task {
                                            let granted = await NotificationManager.shared.requestPermission()
                                            if !granted { store.predictiveAlertsEnabled = false }
                                        }
                                    } else {
                                        Task { await NotificationManager.shared.cancelPredictiveAlert() }
                                    }
                                }
                        }

                        Divider().background(SpiralColors.border.opacity(0.5))

                        // About → NavigationLink
                        NavigationLink {
                            AboutView()
                        } label: {
                            HStack {
                                Text(String(localized: "settings.about.title", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SpiralColors.muted.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // ── CONTEXTO DIARIO ───────────────────────────────────────
                    SettingsGroup(
                        title: String(localized: "settings.context.title", bundle: bundle),
                        icon: "list.bullet.rectangle.portrait"
                    ) {
                        // Master toggle
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(String(localized: "settings.context.enable", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Text(String(localized: "settings.context.enable.desc", bundle: bundle))
                                    .font(.caption)
                                    .foregroundStyle(SpiralColors.muted)
                            }
                            Spacer()
                            Toggle("", isOn: $store.contextBlocksEnabled)
                                .labelsHidden()
                                .toggleStyle(SwitchToggleStyle(tint: SpiralColors.contextPrimary))
                        }

                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Manage blocks
                        NavigationLink {
                            ContextSettingsView()
                        } label: {
                            HStack {
                                Text(String(localized: "settings.context.title", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Spacer()
                                let activeCount = store.contextBlocks.filter(\.isEnabled).count
                                let total = store.contextBlocks.count
                                Text(total == 0 ? "—" : "\(activeCount)/\(total)")
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.contextPrimary)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SpiralColors.muted.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // ── SUEÑO ─────────────────────────────────────────────────
                    SettingsGroup(
                        title: String(localized: "settings.coachMode.title", bundle: bundle),
                        icon: "bed.double.fill"
                    ) {
                        // Coach Mode
                        NavigationLink {
                            CoachModeSettingsView()
                        } label: {
                            HStack {
                                Text(String(localized: "settings.coachMode.title", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SpiralColors.muted.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)

                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Prediction
                        NavigationLink {
                            PredictionSettingsView()
                        } label: {
                            HStack {
                                Text(String(localized: "settings.prediction.title", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Spacer()
                                Text(store.predictionEnabled
                                     ? String(localized: "settings.aiCoach.enable", bundle: bundle)
                                     : String(localized: "settings.prediction.off", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.muted)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SpiralColors.muted.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // ── DATOS ─────────────────────────────────────────────────
                    SettingsGroup(
                        title: String(localized: "settings.data.title", bundle: bundle),
                        icon: "tray.full"
                    ) {
                        // HealthKit inline
                        if !healthKit.isAvailable {
                            Text(String(localized: "settings.healthData.notAvailable", bundle: bundle))
                                .font(.subheadline)
                                .foregroundStyle(SpiralColors.muted)
                        } else if !healthKit.isAuthorized {
                            Button {
                                Task {
                                    await healthKit.requestAuthorization()
                                    if let result = await healthKit.importAndAdjustEpoch() {
                                        store.applyHealthKitResult(epoch: result.epoch, episodes: result.episodes)
                                    }
                                }
                            } label: {
                                Label(String(localized: "settings.healthData.connect", bundle: bundle), systemImage: "heart.fill")
                                    .font(.subheadline.weight(.medium).monospaced())
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(SpiralColors.poor.opacity(0.12))
                                    .foregroundStyle(SpiralColors.poor)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(SpiralColors.good)
                                Text(String(localized: "settings.healthData.connected", bundle: bundle))
                                    .font(.subheadline.monospaced())
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
                                    .font(.caption.monospaced())
                                    .foregroundStyle(SpiralColors.accent)
                                }
                                .buttonStyle(.plain)
                                .disabled(isRefreshing)
                            }
                        }

                        if let err = healthKit.errorMessage {
                            Text(err).font(.caption2).foregroundStyle(SpiralColors.poor)
                        }

                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Date range
                        NavigationLink {
                            DateRangeSettingsView()
                        } label: {
                            HStack {
                                Text(String(localized: "settings.dataRange.title", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Spacer()
                                Text(store.startDate, style: .date)
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.muted)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SpiralColors.muted.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)

                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Data management
                        NavigationLink {
                            DataSettingsView()
                        } label: {
                            HStack {
                                Text(String(localized: "settings.data.title", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Spacer()
                                Text(String(format: "%d", store.sleepEpisodes.count))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.muted)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SpiralColors.muted.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    // ── COACH IA ──────────────────────────────────────────────
                    aiCoachGroup
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 100)
                .frame(maxWidth: 540)
                .frame(maxWidth: .infinity)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
        }
    }

    // MARK: - AI Coach Group (separate @ViewBuilder for LLMService access)

    @ViewBuilder
    private var aiCoachGroup: some View {
        @Bindable var store = store

        SettingsGroup(
            title: String(localized: "settings.aiCoach.title", bundle: bundle),
            icon: "brain.head.profile"
        ) {
            // Enable toggle
            HStack {
                Text(String(localized: "settings.aiCoach.enable", bundle: bundle))
                    .font(.subheadline.monospaced())
                    .foregroundStyle(SpiralColors.text)
                Spacer()
                Toggle("", isOn: $store.llmEnabled)
                    .labelsHidden()
                    .tint(SpiralColors.accent)
            }

            if store.llmEnabled {
                Divider().background(SpiralColors.border.opacity(0.5))

                // Status
                HStack {
                    Text(String(localized: "settings.aiCoach.status", bundle: bundle))
                        .font(.subheadline.monospaced())
                        .foregroundStyle(SpiralColors.muted)
                    Spacer()
                    Text(llm.state.statusText)
                        .font(.subheadline.monospaced())
                        .foregroundStyle(SpiralColors.subtle)
                }

                // Size info
                if let _ = llm.modelFileSize {
                    Divider().background(SpiralColors.border.opacity(0.5))
                    HStack {
                        Text(String(localized: "settings.aiCoach.space", bundle: bundle))
                            .font(.subheadline.monospaced())
                            .foregroundStyle(SpiralColors.muted)
                        Spacer()
                        Text(llm.modelFileSizeString)
                            .font(.subheadline.monospaced())
                            .foregroundStyle(SpiralColors.subtle)
                    }
                }

                Divider().background(SpiralColors.border.opacity(0.5))

                // Download / Delete / Progress
                switch llm.state {
                case .notDownloaded, .error:
                    Button {
                        Task { await llm.downloadModel() }
                    } label: {
                        Label(String(localized: "settings.aiCoach.download", bundle: bundle), systemImage: "arrow.down.to.line")
                            .font(.subheadline.monospaced())
                            .foregroundStyle(SpiralColors.accent)
                    }
                    .buttonStyle(.plain)
                case .downloading(let progress):
                    ProgressView(value: progress).tint(SpiralColors.accent)
                case .downloaded, .ready:
                    Button(role: .destructive) {
                        llm.deleteModel()
                        store.chatHistory = []
                    } label: {
                        Label(String(localized: "settings.aiCoach.delete", bundle: bundle), systemImage: "trash")
                            .font(.subheadline.monospaced())
                            .foregroundStyle(SpiralColors.poor)
                    }
                    .buttonStyle(.plain)
                case .loading:
                    ProgressView().controlSize(.small)
                }

                Divider().background(SpiralColors.border.opacity(0.5))

                // Privacy note
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield").font(.caption2)
                    Text(String(localized: "settings.aiCoach.privacy", bundle: bundle)).font(.caption)
                }
                .foregroundStyle(SpiralColors.faint)
            }
        }
    }
}

// MARK: - Settings Group Container

/// Apple-style glass card with title + icon + content rows.
struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Group title
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(SpiralColors.accent)
                Text(title.uppercased())
                    .font(.caption2.weight(.semibold).monospaced())
                    .tracking(1.5)
                    .foregroundStyle(SpiralColors.muted)
            }

            content()
        }
        .padding(16)
        .liquidGlass(cornerRadius: 16)
    }
}
