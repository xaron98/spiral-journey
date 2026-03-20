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
    @Environment(\.languageBundle) private var bundle

    @State private var isInteractingWith3D = false
    @State private var showQuestionnaire = false
    @State private var questionnaireAvailable = false

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
            .navigationTitle(loc("dna.nav.title"))
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
                questionnaireAvailable = WeeklyQuestionnaireView.isAvailable(context: modelContext)
            }
            .sheet(isPresented: $showQuestionnaire) {
                WeeklyQuestionnaireView {
                    questionnaireAvailable = false
                }
            }
        }
    }

    // MARK: - Profile Content

    @ViewBuilder
    private func profileContent(_ profile: SleepDNAProfile) -> some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {
                // Weekly check-in banner
                if questionnaireAvailable {
                    questionnaireBanner
                }

                DNAStateSection(profile: profile)
                if #available(iOS 18.0, *), profile.helixGeometry.count >= 3 {
                    HelixRealityView(profile: profile, records: store.records, isInteractingWith3D: $isInteractingWith3D)
                }
                DNAMotifSection(profile: profile)
                DNAAlignmentSection(profile: profile)
                DNAHealthSection(profile: profile)
                DNABasePairsSection(profile: profile)
                DNATierSection(profile: profile)

                Text(loc("dna.disclaimer"))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollDisabled(isInteractingWith3D)
    }

    // MARK: - Questionnaire Banner

    private var questionnaireBanner: some View {
        Button {
            showQuestionnaire = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "list.clipboard")
                    .font(.system(size: 14))
                    .foregroundStyle(SpiralColors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc("questionnaire.banner.title"))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(SpiralColors.text)
                    Text(loc("questionnaire.banner.subtitle"))
                        .font(.system(size: 10))
                        .foregroundStyle(SpiralColors.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(SpiralColors.accent)
            }
            .padding(12)
            .background(SpiralColors.accent.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(SpiralColors.accent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Loading

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .tint(SpiralColors.accent)
            Text(loc("dna.loading"))
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
            Text(loc("dna.empty"))
                .font(.system(size: 15))
                .foregroundStyle(SpiralColors.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
