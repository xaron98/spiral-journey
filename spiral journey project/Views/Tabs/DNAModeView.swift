import SwiftUI
import SpiralKit

/// DNA mode page — scrollable card layout reorganizing DNA/NeuroSpiral views.
/// Represents the "future" perspective: patterns, predictions, genomic sleep analysis.
struct DNAModeView: View {
    @Environment(SpiralStore.self) private var store
    @Environment(SleepDNAService.self) private var dnaService
    @Environment(\.languageBundle) private var bundle

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

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 12) {
                    // Hero: 3D Helix at top, scrolls with cards
                    helixHeroView
                        .frame(height: 350)
                        .padding(.horizontal, 16)
                        .padding(.top, 20)

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
                .padding(.bottom, 100)
            }

            actionBar
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
                    mutationBadge(count: silent, label: "Silent", color: SpiralColors.good)
                    mutationBadge(count: missense, label: "Missense", color: SpiralColors.moderate)
                    mutationBadge(count: nonsense, label: "Nonsense", color: SpiralColors.poor)
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
                    isInteractingWith3D: $isInteractingWith3D
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
                    healthRow(label: "Coherence", value: hm.circadianCoherence)
                    healthRow(label: "Continuity", value: hm.helicalContinuity)
                    healthRow(label: "Balance", value: hm.homeostasisBalance)
                    healthRow(label: "Fragmentation", value: 1.0 - hm.fragmentationScore)
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
                        Text("Bedtime")
                            .font(.system(size: 9))
                            .foregroundStyle(SpiralColors.muted)
                    }
                    VStack(spacing: 2) {
                        Text(SleepStatistics.formatHour(pred.predictedWake))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(SpiralColors.text)
                        Text("Wake")
                            .font(.system(size: 9))
                            .foregroundStyle(SpiralColors.muted)
                    }
                    VStack(spacing: 2) {
                        Text(String(format: "%.1fh", pred.predictedDuration))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(SpiralColors.text)
                        Text("Duration")
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
                        Text("Bedtime")
                            .font(.system(size: 9))
                            .foregroundStyle(SpiralColors.muted)
                    }
                    VStack(spacing: 2) {
                        Text(SleepStatistics.formatHour(mlPred.predictedWakeHour))
                            .font(.title3.weight(.bold).monospacedDigit())
                            .foregroundStyle(SpiralColors.text)
                        Text("Wake")
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
            ZStack {
                SpiralColors.bg.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "link")
                        .font(.largeTitle)
                        .foregroundStyle(SpiralColors.accent)
                    Text(loc("dna.card.patterns"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SpiralColors.text)
                    Text(loc("dna.sheet.patterns.placeholder"))
                        .font(.body)
                        .foregroundStyle(SpiralColors.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .navigationTitle(loc("dna.card.patterns"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showPatterns = false } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
        }
    }

    private var mutationsSheet: some View {
        NavigationStack {
            ZStack {
                SpiralColors.bg.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "bolt.trianglebadge.exclamationmark")
                        .font(.largeTitle)
                        .foregroundStyle(SpiralColors.accent)
                    Text(loc("dna.card.mutations"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SpiralColors.text)
                    Text(loc("dna.sheet.mutations.placeholder"))
                        .font(.body)
                        .foregroundStyle(SpiralColors.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .navigationTitle(loc("dna.card.mutations"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showMutations = false } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
        }
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
            ZStack {
                SpiralColors.bg.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.largeTitle)
                        .foregroundStyle(SpiralColors.accent)
                    Text(loc("dna.card.prediction"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SpiralColors.text)
                    Text(loc("dna.sheet.prediction.placeholder"))
                        .font(.body)
                        .foregroundStyle(SpiralColors.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .navigationTitle(loc("dna.card.prediction"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showPrediction = false } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
        }
    }

    private var exportSheet: some View {
        NavigationStack {
            ZStack {
                SpiralColors.bg.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.largeTitle)
                        .foregroundStyle(SpiralColors.accent)
                    Text(loc("dna.card.export"))
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SpiralColors.text)
                    Text(loc("dna.sheet.export.placeholder"))
                        .font(.body)
                        .foregroundStyle(SpiralColors.muted)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }
            .navigationTitle(loc("dna.card.export"))
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { showExport = false } label: {
                        Image(systemName: "xmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(SpiralColors.muted)
                    }
                }
            }
        }
    }

    // MARK: - Localization

    private func loc(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }
}
