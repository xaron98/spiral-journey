import SwiftUI
import SpiralKit

/// DNA mode page — scrollable card layout reorganizing DNA/NeuroSpiral views.
/// Represents the "future" perspective: patterns, predictions, genomic sleep analysis.
struct DNAModeView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(SleepDNAService.self) private var dnaService
    @Environment(\.languageBundle) private var bundle

    /// True when this mode is the one the user is currently looking at in
    /// the pager. Forwarded to HelixRealityView so its 60fps CADisplayLink
    /// stops when the mode goes offscreen — otherwise TabView(.page) keeps
    /// the view alive and onDisappear never fires.
    var isActive: Bool = true

    // MARK: - Sheet states

    @State private var showPatterns = false
    @State private var showMutations = false
    @State private var showTriangle = false
    @State private var showHelix = false
    @State private var showPrediction = false
    @State private var showExport = false

    // MARK: - Action bar states

    @State private var showPatternArrows = false
    @State private var isAnalyzing = false
    @State private var showCalendar = false

    // MARK: - Shared with HelixRealityView

    /// Owned here so the phase legend overlay and the helix hero stay in
    /// sync when the user taps Ayer / Semana / Mi mejor inside the helix.
    @State private var helixComparisonMode: HelixComparisonMode = .yesterday

    var body: some View {
        LazyModeView(isActive: isActive) {
            activeBody
        }
    }

    @ViewBuilder
    private var activeBody: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Hero: 3D Helix at top, scrolls with cards.
                    // 500pt lets the helix dominate the vertical area
                    // so the model reads as centered on screen. The
                    // phase legend is no longer packed inside this
                    // frame — it now floats above the action bar as
                    // an overlay (see below), freeing this hero to be
                    // pure 3D canvas.
                    helixHeroView
                        .frame(height: 500)
                        .padding(.horizontal, 16)

                    // Cards below
                    patternsCard
                    mutationsCard
                    triangleCard
                    historyCard
                    circadianCard
                    predictionCard
                    exportCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 180)
            }

            bottomStack
        }
        .sheet(isPresented: $showPatterns) {
            patternsSheet
        }
        .sheet(isPresented: $showMutations) {
            mutationsSheet
        }
        .sheet(isPresented: $showTriangle) {
            SleepTriangleView()
        }
        #if !os(macOS)
        .fullScreenCover(isPresented: $showHelix) {
            helixSheet
        }
        #else
        .sheet(isPresented: $showHelix) {
            helixSheet
        }
        #endif
        .sheet(isPresented: $showPrediction) {
            predictionSheet
        }
        .sheet(isPresented: $showExport) {
            exportSheet
        }
    }

    // MARK: - Cards

    private var patternsCard: some View {
        DNACardView(loc("dna.card.patterns"), icon: "link") {
            if let profile = dnaProfile, !profile.motifs.isEmpty {
                HStack(spacing: 8) {
                    let topMotifs = Array(profile.motifs.prefix(3))
                    ForEach(topMotifs.indices, id: \.self) { i in
                        Text(topMotifs[i].name)
                            .font(.caption2.weight(.medium))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(SpiralColors.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(SpiralColors.accent)
                    }
                    if profile.motifs.count > 3 {
                        Text("+\(profile.motifs.count - 3)")
                            .font(.caption2)
                            .foregroundStyle(SpiralColors.muted)
                    }
                    Spacer()
                }
            } else {
                Text(loc("dna.card.patterns.description"))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
            }
        }
        .onTapGesture { showPatterns = true }
    }

    private var mutationsCard: some View {
        DNACardView(loc("dna.card.mutations"), icon: "bolt.trianglebadge.exclamationmark") {
            if let profile = dnaProfile, !profile.mutations.isEmpty {
                let silent = profile.mutations.filter { $0.classification == .silent }.count
                let missense = profile.mutations.filter { $0.classification == .missense }.count
                let nonsense = profile.mutations.filter { $0.classification == .nonsense }.count
                HStack(spacing: 16) {
                    mutationBadge(count: silent, label: loc("dna.mutation.badge.silent"), color: SpiralColors.good)
                    mutationBadge(count: missense, label: loc("dna.mutation.badge.missense"), color: SpiralColors.moderate)
                    mutationBadge(count: nonsense, label: loc("dna.mutation.badge.nonsense"), color: SpiralColors.poor)
                    Spacer()
                }
            } else {
                Text(loc("dna.card.mutations.description"))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
            }
        }
        .onTapGesture { showMutations = true }
    }

    private func mutationBadge(count: Int, label: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(SpiralColors.muted)
        }
    }

    private var triangleCard: some View {
        DNACardView(loc("dna.card.triangle"), icon: "triangle") {
            Text(loc("dna.card.triangle.description"))
                .font(.caption)
                .foregroundStyle(SpiralColors.muted)
        }
        .onTapGesture { showTriangle = true }
    }

    // MARK: - Helix Hero (3D, top area)

    @State private var isInteractingWith3D = false

    @ViewBuilder
    private var helixHeroView: some View {
        if let profile = dnaProfile {
            if #available(iOS 18.0, macOS 15.0, *) {
                HelixRealityView(
                    profile: profile,
                    records: store.records,
                    isInteractingWith3D: $isInteractingWith3D,
                    isActive: isActive,
                    comparisonMode: $helixComparisonMode
                )
            } else {
                helixPreview
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        } else {
            // No profile yet — show placeholder
            VStack(spacing: 12) {
                helixPreview
                    .frame(height: 120)
                Text(loc("dna.helix.needs_data"))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var dnaProfile: SleepDNAProfile? {
        dnaService.latestProfile
    }

    private var historyCard: some View {
        DNACardView(loc("dna.card.history"), icon: "chart.xyaxis.line", isLarge: true) {
            if let profile = dnaProfile, profile.nucleotides.count >= 7 {
                // Mini sparkline of sleep quality over last 14 days
                let qualityIdx = DayNucleotide.Feature.sleepQuality.rawValue
                let qualities = profile.nucleotides.suffix(14).map { $0.features[qualityIdx] }
                Canvas { ctx, size in
                    guard qualities.count >= 2 else { return }
                    let maxQ = qualities.max() ?? 1
                    let minQ = qualities.min() ?? 0
                    let range = max(0.01, maxQ - minQ)
                    var path = Path()
                    for (i, q) in qualities.enumerated() {
                        let x = CGFloat(i) / CGFloat(qualities.count - 1) * size.width
                        let y = (1 - (q - minQ) / range) * size.height
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    ctx.stroke(path, with: .color(SpiralColors.accent), lineWidth: 2)
                }
                .frame(height: 60)
            } else {
                Text(loc("dna.card.history.description"))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var circadianCard: some View {
        DNACardView(loc("dna.card.circadian"), icon: "heart.text.clipboard", isLarge: true) {
            if let profile = dnaProfile {
                let hm = profile.healthMarkers
                VStack(spacing: 8) {
                    healthRow(label: loc("dna.health.coherence"), value: hm.circadianCoherence)
                    healthRow(label: loc("dna.health.continuity"), value: hm.helicalContinuity)
                    healthRow(label: loc("dna.health.balance"), value: hm.homeostasisBalance)
                    healthRow(label: loc("dna.health.fragmentation"), value: 1.0 - hm.fragmentationScore)
                }
            } else {
                Text(loc("dna.card.circadian.description"))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func healthRow(label: String, value: Double) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(SpiralColors.muted)
            Spacer()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(SpiralColors.muted.opacity(0.15))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(value > 0.6 ? SpiralColors.good : value > 0.3 ? SpiralColors.moderate : SpiralColors.poor)
                        .frame(width: geo.size.width * min(1, max(0, value)))
                }
            }
            .frame(width: 80, height: 6)
            Text(String(format: "%.0f%%", value * 100))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(SpiralColors.text)
                .frame(width: 32, alignment: .trailing)
        }
    }

    private var predictionCard: some View {
        DNACardView(loc("dna.card.prediction"), icon: "sparkles") {
            if let pred = dnaProfile?.prediction {
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text(SleepStatistics.formatHour(pred.predictedBedtime))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(SpiralColors.text)
                        Text(loc("dna.prediction.label.bedtime"))
                            .font(.system(size: 9))
                            .foregroundStyle(SpiralColors.muted)
                    }
                    VStack(spacing: 2) {
                        Text(SleepStatistics.formatHour(pred.predictedWake))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(SpiralColors.text)
                        Text(loc("dna.prediction.label.wake"))
                            .font(.system(size: 9))
                            .foregroundStyle(SpiralColors.muted)
                    }
                    VStack(spacing: 2) {
                        Text(String(format: "%.1fh", pred.predictedDuration))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(SpiralColors.text)
                        Text(loc("dna.prediction.label.duration"))
                            .font(.system(size: 9))
                            .foregroundStyle(SpiralColors.muted)
                    }
                    Spacer()
                    // Confidence gauge
                    Text(String(format: "%.0f%%", pred.confidence * 100))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(pred.confidence > 0.6 ? SpiralColors.good : SpiralColors.moderate)
                }
            } else if let mlPred = store.latestPrediction {
                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Text(SleepStatistics.formatHour(mlPred.predictedBedtimeHour))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(SpiralColors.text)
                        Text(loc("dna.prediction.label.bedtime"))
                            .font(.system(size: 9))
                            .foregroundStyle(SpiralColors.muted)
                    }
                    VStack(spacing: 2) {
                        Text(SleepStatistics.formatHour(mlPred.predictedWakeHour))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(SpiralColors.text)
                        Text(loc("dna.prediction.label.wake"))
                            .font(.system(size: 9))
                            .foregroundStyle(SpiralColors.muted)
                    }
                    Spacer()
                }
            } else {
                Text(loc("dna.card.prediction.description"))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
            }
        }
        .onTapGesture { showPrediction = true }
    }

    private var exportCard: some View {
        DNACardView(loc("dna.card.export"), icon: "square.and.arrow.up") {
            Text(loc("dna.card.export.description"))
                .font(.caption)
                .foregroundStyle(SpiralColors.muted)
        }
        .onTapGesture { showExport = true }
    }

    // MARK: - Helix Preview

    private var helixPreview: some View {
        ZStack {
            // Placeholder double helix visualization
            Canvas { context, size in
                let w = size.width, h = size.height
                let midY = h / 2
                let amplitude: CGFloat = h * 0.3

                for strand in 0..<2 {
                    var path = Path()
                    let phaseOffset: CGFloat = strand == 0 ? 0 : .pi
                    for x in stride(from: CGFloat(0), through: w, by: 2) {
                        let t = x / w * 3 * .pi
                        let y = midY + sin(t + phaseOffset) * amplitude
                        if x == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    let color: Color = strand == 0
                        ? Color(hex: "d4a860")  // gold strand
                        : Color(hex: "c0c0c0")  // silver strand
                    context.stroke(path, with: .color(color.opacity(0.6)), lineWidth: 2)
                }

                // Connector bars
                for x in stride(from: CGFloat(20), through: w - 20, by: 30) {
                    let t = x / w * 3 * .pi
                    let y1 = midY + sin(t) * amplitude
                    let y2 = midY + sin(t + .pi) * amplitude
                    var bar = Path()
                    bar.move(to: CGPoint(x: x, y: y1))
                    bar.addLine(to: CGPoint(x: x, y: y2))
                    context.stroke(bar, with: .color(SpiralColors.accent.opacity(0.3)), lineWidth: 1)
                }
            }
            .frame(height: 80)
        }
    }

    // MARK: - Action Bar

    @ViewBuilder
    private var bottomStack: some View {
        VStack(spacing: 10) {
            if #available(iOS 18.0, macOS 15.0, *), dnaProfile != nil {
                HelixPhaseLegend(comparisonMode: helixComparisonMode)
            }
            actionBar
        }
    }

    private var actionBar: some View {
        HStack(spacing: 24) {
            // Left: Pattern connections
            Button {
                showPatternArrows.toggle()
            } label: {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title3)
                    .foregroundStyle(showPatternArrows ? SpiralColors.accent : SpiralColors.text)
                    .frame(width: 48, height: 48)
                    .liquidGlass(circular: true)
            }
            .buttonStyle(.plain)

            // Center: Analyze
            Button {
                isAnalyzing = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    isAnalyzing = false
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(Color(hex: "7c3aed"))
                        .frame(width: 64, height: 64)
                        .shadow(color: Color(hex: "7c3aed").opacity(0.5), radius: 10)
                    if isAnalyzing {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "wand.and.stars")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(.white)
                    }
                }
                .liquidGlass(circular: true)
            }
            .buttonStyle(.plain)
            .disabled(isAnalyzing)

            // Right: Calendar / range
            Button {
                showCalendar.toggle()
            } label: {
                Image(systemName: "calendar.badge.clock")
                    .font(.title3)
                    .foregroundStyle(SpiralColors.text)
                    .frame(width: 48, height: 48)
                    .liquidGlass(circular: true)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Sheet Views

    private var patternsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let profile = dnaProfile, !profile.motifs.isEmpty {
                        let sorted = profile.motifs.sorted { $0.instanceCount > $1.instanceCount }
                        ForEach(sorted) { motif in
                            patternRow(motif: motif)
                        }
                    } else {
                        // Two empty states: "not enough data yet" vs "analyzed
                        // but no clusters formed" (latter happens when the user
                        // has very regular habits — all weeks look the same and
                        // agglomerative clustering can't find distinct motifs).
                        let weeks = dnaProfile?.dataWeeks ?? 0
                        let pastThreshold = weeks >= 2
                        sheetEmptyState(
                            icon: "link",
                            text: pastThreshold
                                ? loc("dna.sheet.patterns.noClusters")
                                : String(format: loc("dna.sheet.patterns.empty"), weeks))
                        if let diag = dnaProfile?.motifDiagnostics {
                            motifDiagnosticsPanel(diag)
                        }
                    }
                }
                .padding(16)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(loc("dna.card.patterns"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { sheetCloseButton { showPatterns = false } }
        }
    }

    /// Collapsible diagnostic panel shown in the Patterns empty state when
    /// the pipeline ran but produced zero motifs. Exposes the raw DTW
    /// distance stats and cluster counts so the user (or me, over chat)
    /// can tell whether the clustering threshold is too strict, too loose,
    /// or the data really is uniformly regular.
    @ViewBuilder
    private func motifDiagnosticsPanel(_ diag: MotifDiagnostics) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                diagRow(label: loc("dna.sheet.diag.sequences"), value: "\(diag.sequencesAnalyzed)")
                diagRow(label: loc("dna.sheet.diag.clusters"), value: "\(diag.clustersFormed)")
                diagRow(label: loc("dna.sheet.diag.multimember"), value: "\(diag.multiMemberClusters)")
                diagRow(
                    label: loc("dna.sheet.diag.dtwRange"),
                    value: String(format: "%.2f – %.2f – %.2f",
                                  diag.minDistance, diag.medianDistance, diag.maxDistance))
                diagRow(
                    label: loc("dna.sheet.diag.threshold"),
                    value: String(format: "%.2f", diag.thresholdUsed))
                diagHint(diag)
            }
            .padding(.top, 6)
        } label: {
            HStack {
                Image(systemName: "stethoscope")
                    .font(.caption)
                    .foregroundStyle(SpiralColors.subtle)
                Text(loc("dna.sheet.diag.title"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SpiralColors.text)
            }
        }
        .padding(14)
        .background(SpiralColors.surface.opacity(0.5),
                    in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SpiralColors.border, lineWidth: 0.5))
    }

    private func diagRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2)
                .foregroundStyle(SpiralColors.subtle)
            Spacer()
            Text(value)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(SpiralColors.text)
        }
    }

    /// Human-readable diagnosis of why motif discovery returned no results.
    @ViewBuilder
    private func diagHint(_ diag: MotifDiagnostics) -> some View {
        let hint: String
        if diag.sequencesAnalyzed < 4 {
            hint = loc("dna.sheet.diag.hint.fewSequences")
        } else if diag.multiMemberClusters == 0 && diag.maxDistance < diag.thresholdUsed * 0.5 {
            hint = loc("dna.sheet.diag.hint.tooSimilar")
        } else if diag.multiMemberClusters == 0 && diag.minDistance > diag.thresholdUsed {
            hint = loc("dna.sheet.diag.hint.tooVaried")
        } else {
            hint = loc("dna.sheet.diag.hint.borderline")
        }
        Text(hint)
            .font(.caption2)
            .foregroundStyle(SpiralColors.muted)
            .padding(.top, 2)
    }

    private func patternRow(motif: SleepMotif) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "waveform.path.ecg")
                    .font(.body)
                    .foregroundStyle(SpiralColors.accent)
                Text(localizedMotifName(motif.name))
                    .font(.body.weight(.semibold))
                    .foregroundStyle(SpiralColors.text)
                Spacer()
                Text(String(format: loc("dna.sheet.patterns.instances"), motif.instanceCount))
                    .font(.caption.monospaced())
                    .foregroundStyle(SpiralColors.muted)
            }
            HStack {
                Text(loc("dna.sheet.patterns.avgQuality"))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.subtle)
                Spacer()
                Text(String(format: "%.0f%%", motif.avgQuality * 100))
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(motif.avgQuality > 0.6 ? SpiralColors.good
                                     : motif.avgQuality > 0.4 ? SpiralColors.moderate
                                     : SpiralColors.poor)
            }
        }
        .padding(14)
        .background(SpiralColors.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(SpiralColors.border, lineWidth: 0.5))
    }

    /// Translate motif engine keys (English) to localized names
    private func localizedMotifName(_ engineName: String) -> String {
        let key = "dna.motif.name.\(engineName.lowercased())"
        let result = loc(key)
        return result == key ? engineName : result
    }

    private var mutationsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if let profile = dnaProfile, !profile.mutations.isEmpty {
                        // Most recent first, cap at 30 rows.
                        let recent = Array(profile.mutations.suffix(30).reversed())
                        ForEach(recent) { mutation in
                            mutationRow(mutation: mutation)
                        }
                    } else {
                        let weeks = dnaProfile?.dataWeeks ?? 0
                        let pastThreshold = weeks >= 2
                        sheetEmptyState(
                            icon: "bolt.trianglebadge.exclamationmark",
                            text: pastThreshold
                                ? loc("dna.sheet.mutations.noClusters")
                                : String(format: loc("dna.sheet.mutations.empty"), weeks))
                    }
                }
                .padding(16)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(loc("dna.card.mutations"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { sheetCloseButton { showMutations = false } }
        }
    }

    private func mutationRow(mutation: SleepMutation) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(mutationRowColor(mutation.classification))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 2) {
                Text(mutationRowLabel(mutation.classification))
                    .font(.body.weight(.medium))
                    .foregroundStyle(SpiralColors.text)
                Text(String(format: loc("dna.sheet.mutations.week"), mutation.day))
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.subtle)
            }
            Spacer()
            Text(String(format: "%+.0f%%", mutation.qualityDelta * 100))
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(mutation.qualityDelta >= 0 ? SpiralColors.good : SpiralColors.poor)
        }
        .padding(12)
        .background(SpiralColors.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(SpiralColors.border, lineWidth: 0.5))
    }

    private func mutationRowColor(_ t: MutationType) -> Color {
        switch t {
        case .silent:   return SpiralColors.good
        case .missense: return SpiralColors.moderate
        case .nonsense: return SpiralColors.poor
        }
    }

    private func mutationRowLabel(_ t: MutationType) -> String {
        switch t {
        case .silent:   return loc("dna.motif.mutation.silent")
        case .missense: return loc("dna.motif.mutation.missense")
        case .nonsense: return loc("dna.motif.mutation.nonsense")
        }
    }

    @ToolbarContentBuilder
    private func sheetCloseButton(action: @escaping () -> Void) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(action: action) {
                Image(systemName: "xmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SpiralColors.muted)
            }
        }
    }

    private func sheetEmptyState(icon: String, text: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(SpiralColors.accent)
            Text(text)
                .font(.body)
                .foregroundStyle(SpiralColors.muted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var helixSheet: some View {
        NavigationStack {
            ZStack {
                SpiralColors.bg.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "circle.dotted.and.circle")
                        .font(.largeTitle)
                        .foregroundStyle(SpiralColors.accent)
                    Text(loc("dna.card.helix"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SpiralColors.text)
                    Text(loc("dna.sheet.helix.placeholder"))
                        .font(.body)
                        .foregroundStyle(SpiralColors.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .navigationTitle(loc("dna.card.helix"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showHelix = false } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
        }
    }

    private var predictionSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let profile = dnaProfile, let pred = profile.prediction {
                        predictionDetailCard(pred: pred, profile: profile)
                        if !profile.alignments.isEmpty {
                            alignmentsList(profile.alignments)
                        }
                    } else if let ml = store.latestPrediction {
                        mlPredictionCard(ml)
                    } else {
                        sheetEmptyState(
                            icon: "sparkles",
                            text: loc("dna.sheet.prediction.empty"))
                    }
                }
                .padding(16)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(loc("dna.card.prediction"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { sheetCloseButton { showPrediction = false } }
        }
    }

    private func predictionDetailCard(pred: SequencePrediction, profile: SleepDNAProfile) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                predictionMetric(
                    label: loc("dna.sheet.prediction.bedtime"),
                    value: SleepStatistics.formatHour(pred.predictedBedtime))
                predictionMetric(
                    label: loc("dna.sheet.prediction.wake"),
                    value: SleepStatistics.formatHour(pred.predictedWake))
                predictionMetric(
                    label: loc("dna.sheet.prediction.duration"),
                    value: String(format: "%.1fh", pred.predictedDuration))
                Spacer()
            }

            Divider().overlay(SpiralColors.border)

            HStack {
                Text(loc("dna.sheet.prediction.confidence"))
                    .font(.caption)
                    .foregroundStyle(SpiralColors.muted)
                Spacer()
                Text(String(format: "%.0f%%", pred.confidence * 100))
                    .font(.body.weight(.semibold).monospacedDigit())
                    .foregroundStyle(pred.confidence > 0.6 ? SpiralColors.good
                                     : pred.confidence > 0.4 ? SpiralColors.moderate
                                     : SpiralColors.poor)
            }

            if !pred.basedOnWeekIndices.isEmpty {
                Text(String(format: loc("dna.sheet.prediction.basedOn"), pred.basedOnWeekIndices.count))
                    .font(.caption2)
                    .foregroundStyle(SpiralColors.subtle)
            }
        }
        .padding(16)
        .background(SpiralColors.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(SpiralColors.border, lineWidth: 0.5))
    }

    private func predictionMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(SpiralColors.subtle)
                .textCase(.uppercase)
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(SpiralColors.text)
        }
    }

    private func mlPredictionCard(_ ml: PredictionOutput) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 18) {
                predictionMetric(
                    label: loc("dna.sheet.prediction.bedtime"),
                    value: SleepStatistics.formatHour(ml.predictedBedtimeHour))
                predictionMetric(
                    label: loc("dna.sheet.prediction.wake"),
                    value: SleepStatistics.formatHour(ml.predictedWakeHour))
                Spacer()
            }
        }
        .padding(16)
        .background(SpiralColors.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(SpiralColors.border, lineWidth: 0.5))
    }

    private func alignmentsList(_ alignments: [WeekAlignment]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(loc("dna.sheet.prediction.alignments"))
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SpiralColors.subtle)
                .textCase(.uppercase)

            let top = alignments.sorted { $0.similarity > $1.similarity }.prefix(5)
            ForEach(Array(top.enumerated()), id: \.offset) { _, alignment in
                HStack {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.footnote)
                        .foregroundStyle(SpiralColors.accent)
                    Text(String(format: loc("dna.sheet.mutations.week"), alignment.startDay))
                        .font(.caption)
                        .foregroundStyle(SpiralColors.text)
                    Spacer()
                    Text(String(format: "%.0f%%", alignment.similarity * 100))
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(alignment.similarity > 0.7 ? SpiralColors.good
                                         : alignment.similarity > 0.4 ? SpiralColors.moderate
                                         : SpiralColors.poor)
                }
                .padding(10)
                .background(SpiralColors.surface.opacity(0.6),
                            in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var exportSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let profile = dnaProfile, !profile.nucleotides.isEmpty {
                        exportSummaryCard(profile: profile)
                        exportPreviewCard(profile: profile)
                        exportShareButton(profile: profile)
                    } else {
                        sheetEmptyState(
                            icon: "square.and.arrow.up",
                            text: loc("dna.sheet.export.empty"))
                    }
                }
                .padding(16)
            }
            .background(SpiralColors.bg.ignoresSafeArea())
            .navigationTitle(loc("dna.card.export"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { sheetCloseButton { showExport = false } }
        }
    }

    private func exportSummaryCard(profile: SleepDNAProfile) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(loc("dna.sheet.export.description"))
                .font(.subheadline)
                .foregroundStyle(SpiralColors.text)
            HStack {
                Label(String(format: loc("dna.sheet.export.days"), profile.nucleotides.count),
                      systemImage: "calendar")
                Spacer()
                Label(String(format: loc("dna.sheet.export.features"), DayNucleotide.featureCount),
                      systemImage: "chart.bar")
            }
            .font(.caption)
            .foregroundStyle(SpiralColors.muted)
        }
        .padding(14)
        .background(SpiralColors.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(SpiralColors.border, lineWidth: 0.5))
    }

    private func exportPreviewCard(profile: SleepDNAProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(loc("dna.sheet.export.preview"))
                .font(.caption.weight(.medium))
                .foregroundStyle(SpiralColors.subtle)
            Text("day,bedtimeSin,bedtimeCos,...,sleepQuality")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(SpiralColors.muted)
            ForEach(profile.nucleotides.prefix(3), id: \.day) { n in
                Text(previewRow(for: n))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(SpiralColors.text.opacity(0.7))
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(SpiralColors.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(SpiralColors.border, lineWidth: 0.5))
    }

    private func exportShareButton(profile: SleepDNAProfile) -> some View {
        Group {
            if let url = makeCSV(profile: profile) {
                ShareLink(item: url) {
                    Label(loc("dna.sheet.export.share"), systemImage: "square.and.arrow.up")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(SpiralColors.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(.white)
                }
            } else {
                ProgressView().padding()
            }
        }
    }

    private func previewRow(for n: DayNucleotide) -> String {
        let head = n.features.prefix(3).map { String(format: "%.2f", $0) }.joined(separator: ",")
        let tail = n.features.last.map { String(format: "%.2f", $0) } ?? "—"
        return "\(n.day),\(head),…,\(tail)"
    }

    /// Writes the profile's nucleotides to a temp-dir CSV file and returns the URL.
    /// Returns nil only when the file write fails.
    private func makeCSV(profile: SleepDNAProfile) -> URL? {
        let header = ["day"] + DayNucleotide.Feature.allCases.map { "\($0)" }
        var csv = header.joined(separator: ",") + "\n"
        for n in profile.nucleotides {
            let values = n.features.map { String(format: "%.4f", $0) }
            csv += "\(n.day)," + values.joined(separator: ",") + "\n"
        }
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent("sleepdna_\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try csv.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
