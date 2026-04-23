import SwiftUI
import SwiftData
import SpiralKit

struct DataSettingsView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(HealthKitManager.self) private var healthKit
    @Environment(SleepDNAService.self) private var dnaService
    @Environment(\.modelContext) private var modelContext
    @Environment(\.languageBundle) private var bundle

    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var showExportShare = false
    @State private var showClearManualConfirm = false
    @State private var showResetAllConfirm = false
    @State private var isImporting = false
    @State private var showManualEpisodes = false

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(spacing: 16) {
                // Stats
                HStack(spacing: 12) {
                    Text(String(format: String(localized: "settings.data.episodeCount", bundle: bundle), store.sleepEpisodes.count))
                        .font(.caption.monospaced())
                        .foregroundStyle(SpiralColors.muted)
                    Text(String(format: String(localized: "settings.data.eventCount", bundle: bundle), store.events.count))
                        .font(.caption.monospaced())
                        .foregroundStyle(SpiralColors.muted)
                    Spacer()
                }
                .padding(.horizontal, 4)

                // Export + Import + Reset actions
                VStack(spacing: 0) {
                    // CSV Export
                    Button {
                        isExporting = true
                        Task {
                            exportURL = DataExporter.exportAll(
                                store: store,
                                dnaProfile: dnaService.latestProfile,
                                context: modelContext
                            )
                            isExporting = false
                            if exportURL != nil { showExportShare = true }
                        }
                    } label: {
                        HStack {
                            if isExporting { ProgressView().scaleEffect(0.7) }
                            Label(String(localized: "settings.data.exportCSV", bundle: bundle), systemImage: "square.and.arrow.up")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(SpiralColors.accent)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    #if os(iOS)
                    .sheet(isPresented: $showExportShare) {
                        if let url = exportURL { ShareSheet(activityItems: [url]) }
                    }
                    #endif

                    if healthKit.isAuthorized {
                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Import from HealthKit
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
                                .font(.subheadline.monospaced())
                                .foregroundStyle(SpiralColors.poor)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isImporting)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }

                    Divider().background(SpiralColors.border.opacity(0.5))

                    // Manage manual episodes (individual delete)
                    Button { showManualEpisodes = true } label: {
                        HStack {
                            Label(String(localized: "settings.data.manageManual", bundle: bundle),
                                  systemImage: "list.bullet")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(SpiralColors.accent)
                            Spacer()
                            let count = store.sleepEpisodes.filter { $0.source == .manual }.count
                            Text("\(count)")
                                .font(.caption.monospaced())
                                .foregroundStyle(SpiralColors.muted)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(SpiralColors.muted)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .disabled(store.sleepEpisodes.allSatisfy { $0.source != .manual })

                    Divider().background(SpiralColors.border.opacity(0.5))

                    // Clear manual (bulk)
                    Button(role: .destructive) { showClearManualConfirm = true } label: {
                        HStack {
                            Label(String(localized: "settings.data.clearManual", bundle: bundle), systemImage: "trash")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(SpiralColors.poor)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .confirmationDialog(
                        String(localized: "settings.confirm.title", bundle: bundle),
                        isPresented: $showClearManualConfirm, titleVisibility: .visible
                    ) {
                        Button(String(localized: "settings.confirm.yes", bundle: bundle), role: .destructive) {
                            store.sleepEpisodes.removeAll { $0.source == .manual }
                            store.recompute()
                        }
                        Button(String(localized: "settings.confirm.cancel", bundle: bundle), role: .cancel) {}
                    }

                    Divider().background(SpiralColors.border.opacity(0.5))

                    // Reset all
                    Button(role: .destructive) { showResetAllConfirm = true } label: {
                        HStack {
                            Label(String(localized: "settings.data.resetAll", bundle: bundle), systemImage: "arrow.counterclockwise")
                                .font(.subheadline.monospaced())
                                .foregroundStyle(SpiralColors.poor)
                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .confirmationDialog(
                        String(localized: "settings.confirm.title", bundle: bundle),
                        isPresented: $showResetAllConfirm, titleVisibility: .visible
                    ) {
                        Button(String(localized: "settings.confirm.yes", bundle: bundle), role: .destructive) {
                            store.resetAllData()
                        }
                        Button(String(localized: "settings.confirm.cancel", bundle: bundle), role: .cancel) {}
                    }
                }
                .liquidGlass(cornerRadius: 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "settings.data.title", bundle: bundle))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showManualEpisodes) {
            ManualEpisodesSheet()
        }
    }
}

// MARK: - Manual Episodes Sheet

/// Per-episode delete UI for manually logged sleep. Fills the gap
/// between the undo toast (disappears after a few seconds) and the
/// bulk "Clear manual" option (kills all manual episodes at once) —
/// now the user can target the one bad entry without losing the rest.
private struct ManualEpisodesSheet: View {
    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle
    @Environment(\.dismiss) private var dismiss

    /// Shared formatter — @ViewBuilder doesn't allow mutating statements
    /// after `let` declarations, so configuring the DateFormatter inline
    /// fails to compile. Build once as a static and reuse.
    private static let rowDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        f.locale = Locale.current
        return f
    }()

    private var manualEpisodes: [SleepEpisode] {
        store.sleepEpisodes
            .filter { $0.source == .manual }
            .sorted { $0.start > $1.start }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if manualEpisodes.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "checkmark.circle")
                                .font(.largeTitle)
                                .foregroundStyle(SpiralColors.good)
                            Text(String(localized: "settings.manual.empty",
                                        defaultValue: "No manual entries",
                                        bundle: bundle))
                                .font(.subheadline)
                                .foregroundStyle(SpiralColors.muted)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                    } else {
                        ForEach(manualEpisodes) { ep in
                            episodeRow(ep)
                        }
                    }
                }
                .padding(16)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(String(localized: "settings.data.manageManual", bundle: bundle))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "common.done",
                                  defaultValue: "Done",
                                  bundle: bundle)) {
                        dismiss()
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func episodeRow(_ ep: SleepEpisode) -> some View {
        let startHour = ep.start.truncatingRemainder(dividingBy: 24)
        let endHour = ep.end.truncatingRemainder(dividingBy: 24)
        let dayIndex = Int(ep.start / 24)
        let date = Calendar.current.date(byAdding: .day, value: dayIndex, to: store.startDate) ?? store.startDate
        let dateLabel = Self.rowDateFormatter.string(from: date).capitalized

        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(dateLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                Text("\(SleepStatistics.formatHour(startHour < 0 ? startHour + 24 : startHour))  →  \(SleepStatistics.formatHour(endHour < 0 ? endHour + 24 : endHour))")
                    .font(.caption.monospaced())
                    .foregroundStyle(SpiralColors.muted)
                Text(String(format: "%.1f h", ep.duration))
                    .font(.caption2.monospaced())
                    .foregroundStyle(SpiralColors.subtle)
            }
            Spacer()
            Button(role: .destructive) {
                store.removeEpisode(id: ep.id)
            } label: {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundStyle(SpiralColors.poor)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(SpiralColors.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(SpiralColors.border, lineWidth: 0.5))
    }
}

// MARK: - Share Sheet
#if os(iOS)
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
