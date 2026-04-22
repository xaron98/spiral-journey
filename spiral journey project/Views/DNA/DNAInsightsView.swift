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
    @State private var helixComparisonMode: HelixComparisonMode = .yesterday
    @State private var showQuestionnaire = false
    @State private var questionnaireAvailable = false
    @State private var showNeuroSpiral = false
    @State private var showDNAInfo = false
    @State private var showTriangle = false

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
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    HStack(spacing: 16) {
                        Button { showDNAInfo = true } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(SpiralColors.accent)
                        }
                        .accessibilityLabel(loc("dna.info.button.label"))
                        Button { showTriangle = true } label: {
                            Image(systemName: "triangle")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(SpiralColors.accent)
                        }
                        .accessibilityLabel(loc("triangle.button.label"))
                        Button { showNeuroSpiral = true } label: {
                            Image(systemName: "cube.transparent")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(SpiralColors.accent)
                        }
                        .accessibilityLabel(loc("neurospiral.button.label"))
                    }
                }
            }
            .sheet(isPresented: $showDNAInfo) {
                DNAInfoSheetView()
            }
            .sheet(isPresented: $showTriangle) {
                SleepTriangleView()
            }
            .sheet(isPresented: $showNeuroSpiral) {
                NeuroSpiralView()
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
                    HelixRealityView(profile: profile, records: store.records, isInteractingWith3D: $isInteractingWith3D, comparisonMode: $helixComparisonMode)
                }
                DNAMotifSection(profile: profile)
                DNAAlignmentSection(profile: profile)
                DNAHealthSection(profile: profile)
                DNABasePairsSection(profile: profile)
                if let codons = profile.codonAnalysis {
                    DNACodonSection(codonResult: codons)
                }
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
                    .font(.body)
                    .foregroundStyle(SpiralColors.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text(loc("questionnaire.banner.title"))
                        .font(.caption.weight(.medium).monospaced())
                        .foregroundStyle(SpiralColors.text)
                    Text(loc("questionnaire.banner.subtitle"))
                        .font(.caption)
                        .foregroundStyle(SpiralColors.muted)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
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
                .font(.subheadline)
                .foregroundStyle(SpiralColors.muted)
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "dna")
                .font(.largeTitle)
                .foregroundStyle(SpiralColors.subtle)
            Text(loc("dna.empty"))
                .font(.subheadline)
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
