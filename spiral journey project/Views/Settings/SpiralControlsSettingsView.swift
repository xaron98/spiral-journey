import SwiftUI
import SpiralKit

struct SpiralControlsSettingsView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(\.languageBundle) private var bundle

    @State private var previewVisibleSpan: Double = 4.0

    // MARK: - Effective params (mirrors SpiralTab)

    private var isLog3D: Bool {
        store.spiralType == .logarithmic && !store.flatMode
    }

    private var effectiveStartRadius: Double {
        guard store.spiralType == .logarithmic else { return 75.0 }
        return store.flatMode ? 15.0 : 60.0
    }

    private var effectiveDepthScale: Double {
        guard isLog3D else { return store.depthScale }
        return max(store.depthScale, 0.5)
    }

    private var effectivePerspectivePower: Double {
        isLog3D ? 0.5 : 1.0
    }

    private var maxTurns: Double {
        let lastEnd = store.sleepEpisodes.map(\.end).max() ?? 0
        return max(1.0, lastEnd / store.period)
    }

    private var effectiveSpiralExtent: Double {
        if store.spiralType == .logarithmic {
            let dataDays = max(Double(store.records.count), 1)
            return max(dataDays + 1, 7)
        }
        return maxTurns
    }

    private var effectiveLinkGrowthToTau: Bool {
        if store.spiralType == .logarithmic && store.linkGrowthToTau {
            let tauRate = log(max(store.period, 23) / 24) / (2 * .pi)
            if abs(tauRate) < 0.001 { return false }
        }
        return store.linkGrowthToTau
    }

    /// Mirrors SpiralTab: log 3D scales to actual data, other modes use fixed 30-day scale.
    private var effectiveNumDaysHint: Int {
        if store.spiralType == .logarithmic && !store.flatMode {
            return max(Int(ceil(maxTurns)), 7)
        }
        return max(store.numDays, 1)
    }

    /// Latest absolute hour from data — positions cursor at most recent data.
    private var latestAbsHour: Double {
        store.sleepEpisodes.map(\.end).max() ?? 0
    }

    // MARK: - Body

    var body: some View {
        @Bindable var store = store
        ScrollView(showsIndicators: false) {
            VStack(spacing: 16) {

                // ── Mini spiral preview ───────────────────────────────────
                ZStack(alignment: .bottom) {
                    SpiralColors.bg

                    SpiralView(
                        records: store.records,
                        events: [],
                        spiralType: store.spiralType,
                        period: store.period,
                        linkGrowthToTau: effectiveLinkGrowthToTau,
                        showCosinor: false,
                        showBiomarkers: false,
                        showTwoProcess: false,
                        selectedDay: nil,
                        onSelectDay: { _ in },
                        contextBlocks: [],
                        cursorAbsHour: latestAbsHour,
                        numDaysHint: effectiveNumDaysHint,
                        spiralExtentTurns: effectiveSpiralExtent,
                        viewportCenterTurns: maxTurns,
                        visibleSpanTurns: min(previewVisibleSpan, maxTurns),
                        depthScale: store.flatMode ? 0 : effectiveDepthScale,
                        perspectivePower: effectivePerspectivePower,
                        showGrid: store.showGrid,
                        startRadius: effectiveStartRadius,
                        glowIntensity: store.glowIntensity
                    )
                    .simultaneousGesture(
                        MagnifyGesture(minimumScaleDelta: 0.03)
                            .onChanged { value in
                                previewVisibleSpan = max(1.0, min(maxTurns, previewVisibleSpan / Double(value.magnification)))
                            }
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.easeOut(duration: 0.3)) { previewVisibleSpan = 4.0 }
                    }

                    // Zoom hint
                    Text(String(localized: "rephase.spiral.dragHint", bundle: bundle))
                        .font(.caption2)
                        .foregroundStyle(SpiralColors.muted.opacity(0.5))
                        .padding(.bottom, 8)
                }
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(SpiralColors.border.opacity(0.3), lineWidth: 0.8)
                )

                // ── Controls ──────────────────────────────────────────────
                VStack(spacing: 0) {
                    // Spiral type
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "spiral.controls.archimedean", bundle: bundle).uppercased() + " / " + String(localized: "spiral.controls.logarithmic", bundle: bundle).uppercased())
                            .font(.caption2.weight(.semibold).monospaced())
                            .foregroundStyle(SpiralColors.muted)
                            .tracking(1)
                        HStack(spacing: 6) {
                            PillButton(label: String(localized: "spiral.controls.archimedean", bundle: bundle), isActive: store.spiralType == .archimedean) { store.spiralType = .archimedean }
                            PillButton(label: String(localized: "spiral.controls.logarithmic", bundle: bundle), isActive: store.spiralType == .logarithmic) { store.spiralType = .logarithmic }
                        }
                    }
                    .padding(.vertical, 12)

                    Divider().background(SpiralColors.border.opacity(0.5))

                    // 3D / 2D mode
                    VStack(alignment: .leading, spacing: 6) {
                        Text("3D / 2D")
                            .font(.caption2.weight(.semibold).monospaced())
                            .foregroundStyle(SpiralColors.muted)
                            .tracking(1)
                        HStack(spacing: 6) {
                            PillButton(label: "3D", isActive: !store.flatMode) { store.flatMode = false }
                            PillButton(label: "2D", isActive: store.flatMode) { store.flatMode = true }
                        }
                    }
                    .padding(.vertical, 12)

                    Divider().background(SpiralColors.border.opacity(0.5))

                    // Period
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(localized: "spiral.controls.period", bundle: bundle))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(SpiralColors.text)
                            Spacer()
                            Text(String(format: "%.1fh", store.period))
                                .font(.subheadline.weight(.semibold).monospaced())
                                .foregroundStyle(SpiralColors.accent)
                        }
                        HStack(spacing: 6) {
                            PillButton(label: "24h", isActive: abs(store.period - 24.0) < 0.5) { store.period = 24.0 }
                            PillButton(label: String(localized: "spiral.controls.weekly", bundle: bundle), isActive: abs(store.period - 168.0) < 1) { store.period = 168.0 }
                        }
                        Slider(value: $store.period, in: 23.0...168.0, step: 0.1).tint(SpiralColors.accent)
                    }
                    .padding(.vertical, 12)

                    // Depth (3D only)
                    if !store.flatMode {
                        Divider().background(SpiralColors.border.opacity(0.5))
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(String(localized: "spiral.controls.zoom", bundle: bundle))
                                    .font(.subheadline.monospaced())
                                    .foregroundStyle(SpiralColors.text)
                                Spacer()
                                Text(store.depthScale < 0.2 ? String(format: "%.2f×", store.depthScale) : String(format: "%.1f×", store.depthScale))
                                    .font(.subheadline.weight(.semibold).monospaced())
                                    .foregroundStyle(SpiralColors.accent)
                            }
                            Slider(value: $store.depthScale, in: 0.05...3.0, step: 0.05).tint(SpiralColors.accent)
                        }
                        .padding(.vertical, 12)
                    }

                    Divider().background(SpiralColors.border.opacity(0.5))

                    // Glow intensity
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(String(localized: "spiral.controls.glow", bundle: bundle))
                                .font(.subheadline.monospaced())
                                .foregroundStyle(SpiralColors.text)
                            Spacer()
                            Text(store.glowIntensity < 0.01 ? "OFF" : String(format: "%.0f%%", store.glowIntensity * 100))
                                .font(.subheadline.weight(.semibold).monospaced())
                                .foregroundStyle(store.glowIntensity < 0.01 ? SpiralColors.muted : SpiralColors.accent)
                        }
                        Slider(value: $store.glowIntensity, in: 0...1, step: 0.05).tint(SpiralColors.accent)
                    }
                    .padding(.vertical, 12)

                    Divider().background(SpiralColors.border.opacity(0.5))

                    // Grid guides toggle
                    HStack {
                        Text(String(localized: "spiral.controls.grid", bundle: bundle))
                            .font(.subheadline.monospaced())
                            .foregroundStyle(SpiralColors.text)
                        Spacer()
                        Toggle("", isOn: $store.showGrid)
                            .labelsHidden()
                            .tint(SpiralColors.accent)
                    }
                    .padding(.vertical, 12)

                    Divider().background(SpiralColors.border.opacity(0.5))

                    // Link τ growth toggle
                    HStack {
                        Text(String(localized: "spiral.controls.linkTau", bundle: bundle))
                            .font(.subheadline.monospaced())
                            .foregroundStyle(SpiralColors.text)
                        Spacer()
                        Toggle("", isOn: $store.linkGrowthToTau)
                            .labelsHidden()
                            .tint(SpiralColors.accent)
                    }
                    .padding(.vertical, 12)
                }
                .padding(.horizontal, 16)
                .liquidGlass(cornerRadius: 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 40)
            .frame(maxWidth: 540)
            .frame(maxWidth: .infinity)
        }
        .background(SpiralColors.bg.ignoresSafeArea())
        .navigationTitle(String(localized: "spiral.controls.title", bundle: bundle))
        .navigationBarTitleDisplayMode(.inline)
    }
}
