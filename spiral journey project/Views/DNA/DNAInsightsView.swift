import SwiftUI
import SwiftData
import SpiralKit

/// Full-screen DNA insights panel — "Tu ADN del Sueno".
/// Shows the SleepDNA profile broken into narrative sections.
struct DNAInsightsView: View {

    @Environment(SleepDNAService.self) private var dnaService
    @Environment(SpiralStore.self) private var store
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                SpiralColors.bg.ignoresSafeArea()

                if let profile = dnaService.latestProfile {
                    profileContent(profile)
                } else if dnaService.isComputing {
                    loadingState
                } else {
                    emptyState
                }
            }
            .navigationTitle("Tu ADN del Sueno")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
            .refreshable {
                await dnaService.forceRefresh(store: store, context: modelContext)
            }
            .task {
                await dnaService.refreshIfNeeded(store: store, context: modelContext)
            }
        }
    }

    // MARK: - Profile Content

    @ViewBuilder
    private func profileContent(_ profile: SleepDNAProfile) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                DNAStateSection(profile: profile)
                DNAMotifSection(profile: profile)
                DNAAlignmentSection(profile: profile)
                DNAHealthSection(profile: profile)
                DNABasePairsSection(profile: profile)
                DNATierSection(profile: profile)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(SpiralColors.accent)
            Text("Analizando tu ADN del sueno...")
                .font(.system(size: 15))
                .foregroundStyle(SpiralColors.muted)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dna")
                .font(.system(size: 40))
                .foregroundStyle(SpiralColors.subtle)
            Text("Registra al menos una semana de sueno\npara desbloquear tu ADN.")
                .font(.system(size: 15))
                .foregroundStyle(SpiralColors.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }
}
