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
                    .sheet(isPresented: $showExportShare) {
                        if let url = exportURL { ShareSheet(activityItems: [url]) }
                    }

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

                    // Clear manual
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
        .navigationBarTitleDisplayMode(.inline)
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
