import SwiftUI
import SpiralKit

struct PredictionSettingsView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(spacing: 16) {
                // Toggles panel
                VStack(spacing: 0) {
                    HStack {
                        Text(String(localized: "settings.prediction.enable", bundle: bundle))
                            .font(.subheadline.monospaced())
                            .foregroundStyle(SpiralColors.text)
                        Spacer()
                        Toggle("", isOn: $store.predictionEnabled)
                            .labelsHidden()
                            .accessibilityLabel(String(localized: "accessibility.toggle.prediction", defaultValue: "Sleep prediction"))
                            .tint(SpiralColors.accent)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)

                    if store.predictionEnabled {
                        Divider().background(SpiralColors.border.opacity(0.5))
                        HStack {
                            Text(String(localized: "settings.prediction.overlay", bundle: bundle))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(SpiralColors.text)
                            Spacer()
                            Toggle("", isOn: $store.predictionOverlayEnabled)
                                .labelsHidden()
                                .accessibilityLabel(String(localized: "accessibility.toggle.predictionOverlay", defaultValue: "Prediction overlay"))
                                .tint(SpiralColors.accent)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                        Divider().background(SpiralColors.border.opacity(0.5))
                        HStack {
                            Text(String(localized: "settings.prediction.ml", bundle: bundle))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(SpiralColors.text)
                            Spacer()
                            Toggle("", isOn: $store.mlPredictionEnabled)
                                .labelsHidden()
                                .accessibilityLabel(String(localized: "accessibility.toggle.mlPrediction", defaultValue: "ML prediction"))
                                .tint(SpiralColors.accent)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                    }
                }
                .liquidGlass(cornerRadius: 16)

                // ML Model info (when ml enabled)
                if store.predictionEnabled && store.mlPredictionEnabled {
                    let evaluatedCount = store.predictionHistory.filter { $0.actual != nil }.count
                    VStack(spacing: 0) {
                        // Engine status
                        HStack {
                            Text(String(localized: "settings.prediction.engine", bundle: bundle))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(SpiralColors.muted)
                            Spacer()
                            Text(MLPredictionEngine.isAvailable
                                 ? (MLPredictionEngine.isPersonalised
                                    ? String(localized: "settings.prediction.personalised", bundle: bundle)
                                    : String(localized: "settings.prediction.generic", bundle: bundle))
                                 : String(localized: "settings.prediction.heuristic", bundle: bundle))
                                .font(.subheadline.weight(.medium).monospaced())
                                .foregroundStyle(MLPredictionEngine.isPersonalised ? SpiralColors.good : SpiralColors.text)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                        Divider().background(SpiralColors.border.opacity(0.5))

                        // Ground truth count
                        HStack {
                            Text(String(localized: "settings.prediction.groundTruth", bundle: bundle))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(SpiralColors.muted)
                            Spacer()
                            Text("\(evaluatedCount) / \(ModelTrainingService.minimumSamples)")
                                .font(.subheadline.weight(.medium).monospaced())
                                .foregroundStyle(evaluatedCount >= ModelTrainingService.minimumSamples ? SpiralColors.good : SpiralColors.text)
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                        // Progress bar
                        if evaluatedCount < ModelTrainingService.minimumSamples {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2).fill(SpiralColors.border.opacity(0.3)).frame(height: 4)
                                    RoundedRectangle(cornerRadius: 2).fill(SpiralColors.accent)
                                        .frame(width: geo.size.width * min(1.0, Double(evaluatedCount) / Double(ModelTrainingService.minimumSamples)), height: 4)
                                }
                            }
                            .frame(height: 4)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 12)
                        }

                        if let lastTrained = store.lastModelTrainedDate {
                            Divider().background(SpiralColors.border.opacity(0.5))
                            HStack {
                                Text(String(localized: "settings.prediction.lastTrained", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.muted)
                                Spacer()
                                Text(lastTrained, style: .relative)
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                            }
                            .padding(.vertical, 12)
                            .padding(.horizontal, 16)

                            if store.modelTrainingSampleCount > 0 {
                                Divider().background(SpiralColors.border.opacity(0.5))
                                HStack {
                                    Text(String(localized: "settings.prediction.samplesUsed", bundle: bundle))
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(SpiralColors.muted)
                                    Spacer()
                                    Text("\(store.modelTrainingSampleCount)")
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(SpiralColors.text)
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 16)
                            }
                        }
                    }
                    .liquidGlass(cornerRadius: 16)

                    // Privacy note
                    Text(String(localized: "settings.prediction.privacyNote", bundle: bundle))
                        .font(.caption)
                        .foregroundStyle(SpiralColors.muted)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "settings.prediction.title", bundle: bundle))
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }
}
