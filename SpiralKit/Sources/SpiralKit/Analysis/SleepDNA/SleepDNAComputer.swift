import Foundation

/// Orchestrator that runs the full SleepDNA analysis pipeline.
///
/// Usage:
/// ```swift
/// let computer = SleepDNAComputer()
/// let profile = try await computer.compute(records: records, events: events, ...)
/// ```
///
/// The pipeline is tier-gated: expensive stages (motif discovery, mutation
/// classification, BLOSUM learning) only run when sufficient data is available.
/// Calling `compute` again cancels any in-flight previous computation.
public actor SleepDNAComputer {

    /// The currently running computation task, if any.
    private var currentTask: Task<SleepDNAProfile, Error>?

    public init() {}

    // MARK: - Public API

    /// Run the full SleepDNA pipeline and return a consolidated profile.
    ///
    /// - Parameters:
    ///   - records: All sleep records, in any order.
    ///   - events: All circadian events (caffeine, exercise, etc.).
    ///   - chronotype: Optional chronotype result for helix geometry.
    ///   - goalDuration: Target sleep duration in hours.
    ///   - period: Hours per day (default 24).
    ///   - existingBLOSUM: Previously learned BLOSUM to reuse when data is insufficient.
    /// - Returns: A fully assembled `SleepDNAProfile`.
    /// - Throws: `CancellationError` if a newer computation supersedes this one,
    ///           or `SleepDNAError.insufficientData` if records is empty.
    public func compute(
        records: [SleepRecord],
        events: [CircadianEvent],
        chronotype: ChronotypeResult?,
        goalDuration: Double,
        period: Double = 24,
        existingBLOSUM: SleepBLOSUM? = nil
    ) async throws -> SleepDNAProfile {
        // Cancel any previous in-flight computation
        currentTask?.cancel()

        let task = Task<SleepDNAProfile, Error> {
            try Self.runPipeline(
                records: records,
                events: events,
                chronotype: chronotype,
                goalDuration: goalDuration,
                period: period,
                existingBLOSUM: existingBLOSUM
            )
        }
        currentTask = task

        return try await task.value
    }

    // MARK: - Pipeline

    /// The actual pipeline implementation, run inside a Task for cancellation support.
    private static func runPipeline(
        records: [SleepRecord],
        events: [CircadianEvent],
        chronotype: ChronotypeResult?,
        goalDuration: Double,
        period: Double,
        existingBLOSUM: SleepBLOSUM?
    ) throws -> SleepDNAProfile {
        guard !records.isEmpty else {
            throw SleepDNAError.insufficientData
        }

        // Step 1: Determine tier
        let dataWeeks = records.count / 7
        let tier: AnalysisTier
        if dataWeeks >= 8 {
            tier = .full
        } else if dataWeeks >= 4 {
            tier = .intermediate
        } else {
            tier = .basic
        }

        // Step 2: Encode all records as DayNucleotides
        let sortedRecords = records.sorted { $0.day < $1.day }
        let nucleotides = sortedRecords.map { record in
            DayNucleotide.encode(
                record: record,
                events: events,
                processS: 0.5, // Two-process integration deferred
                period: period,
                goalDuration: goalDuration
            )
        }

        try Task.checkCancellation()

        // Step 3: Generate WeekSequences
        let sequences = WeekSequence.generateSequences(from: nucleotides)

        // Step 4: Compute base pairs via HilbertPhaseAnalyzer
        let basePairs = HilbertPhaseAnalyzer.analyze(nucleotides: nucleotides)

        try Task.checkCancellation()

        // Step 5: Learn SleepBLOSUM (full tier only, else reuse existing or .initial)
        let blosum: SleepBLOSUM
        if tier == .full {
            blosum = SleepBLOSUM.learn(from: nucleotides)
        } else {
            blosum = existingBLOSUM ?? .initial
        }

        try Task.checkCancellation()

        // Step 6: Motif discovery (full tier only)
        let motifs: [SleepMotif]
        if tier == .full {
            motifs = MotifDiscovery.discover(
                sequences: sequences,
                weights: blosum.weights
            )
        } else {
            motifs = []
        }

        try Task.checkCancellation()

        // Step 7: Mutation classification (full tier only)
        let mutations: [SleepMutation]
        let expressionRules: [ExpressionRule]
        if tier == .full && !motifs.isEmpty {
            mutations = MutationClassifier.classifyMutations(
                sequences: sequences,
                motifs: motifs,
                weights: blosum.weights
            )
            expressionRules = MutationClassifier.discoverExpressionRules(
                sequences: sequences,
                motifs: motifs,
                weights: blosum.weights
            )
        } else {
            mutations = []
            expressionRules = []
        }

        // Step 7b: Build clusters from motifs
        let clusters: [WeekCluster] = motifs.map { motif in
            WeekCluster(
                label: motif.name,
                memberWeekIndices: motif.instanceWeekIndices,
                avgQuality: motif.avgQuality
            )
        }

        try Task.checkCancellation()

        // Step 8: Health markers
        let healthMarkers = HealthMarkerDetector.analyze(records: sortedRecords)

        // Step 9: Helix geometry
        let helixGeometry = HelixGeometryComputer.compute(
            records: sortedRecords,
            basePairs: basePairs,
            chronotype: chronotype
        )

        // Step 9b: Poisson fragmentation (intermediate+ tier, >= 14 nights)
        let poissonResult: PoissonFragmentationResult?
        if tier != .basic && sortedRecords.count >= 14 {
            poissonResult = PoissonFragmentation.analyze(records: sortedRecords)
        } else {
            poissonResult = nil
        }

        // Step 9c: Hawkes event-impact model (full tier only)
        let hawkesResult: HawkesAnalysisResult?
        if tier == .full {
            hawkesResult = HawkesEventModel.analyze(records: sortedRecords, events: events)
        } else {
            hawkesResult = nil
        }

        // Step 9d: Advanced metrics (full tier only)
        let pchResult: PersistentHomologyResult?
        let lndResult: LinkingNumberResult?
        let misResult: MISResult?

        if tier == .full {
            pchResult = PersistentHomology.compute(
                nucleotides: nucleotides,
                helixGeometry: helixGeometry
            )
            lndResult = LinkingNumber.compute(
                nucleotides: nucleotides,
                helixGeometry: helixGeometry
            )
            misResult = MutualInformationSpectrum.compute(records: sortedRecords)
        } else {
            pchResult = nil
            lndResult = nil
            misResult = nil
        }

        try Task.checkCancellation()

        // Step 10: Sequence alignment prediction (intermediate+ tier, needs >= 4 weeks)
        let prediction: SequencePrediction?
        let alignments: [WeekAlignment]
        if tier != .basic && sequences.count >= 4 {
            // Use the last partial week (up to 6 days) as the query
            let currentWeekDays = Array(nucleotides.suffix(min(6, nucleotides.count)))
            if let result = SequenceAlignmentEngine.predict(
                currentDays: currentWeekDays,
                history: sequences,
                weights: blosum.weights,
                targetDate: Date()
            ) {
                prediction = result.prediction
                alignments = result.alignments
            } else {
                prediction = nil
                alignments = []
            }
        } else {
            prediction = nil
            alignments = []
        }

        // Step 11: Compute Helix Alignment Scores
        let hasScore: Double?
        let baselineHAS: Double?

        if let currentWeek = sequences.last, sequences.count >= 2 {
            // HAS: current week vs most similar historical week
            let history = Array(sequences.dropLast())
            var bestScore = 0.0
            for past in history {
                let score = DTWEngine.helixAlignmentScore(currentWeek, past, weights: blosum.weights)
                if score > bestScore { bestScore = score }
            }
            hasScore = bestScore
        } else {
            hasScore = nil
        }

        if sequences.count >= 4, nucleotides.count >= 28 {
            // Baseline: average WeekSequence from the last 28 days
            let baselineNucs = Array(nucleotides.suffix(28))
            let baselineWeekNucs = (0..<7).map { dayIdx -> DayNucleotide in
                // Average features across all 4 occurrences of this weekday slot
                var avgFeatures = [Double](repeating: 0, count: DayNucleotide.featureCount)
                var count = 0
                for weekOffset in 0..<4 {
                    let nucIdx = weekOffset * 7 + dayIdx
                    guard nucIdx < baselineNucs.count else { continue }
                    let nuc = baselineNucs[nucIdx]
                    for f in 0..<DayNucleotide.featureCount {
                        avgFeatures[f] += nuc.features[f]
                    }
                    count += 1
                }
                if count > 0 {
                    for f in 0..<DayNucleotide.featureCount {
                        avgFeatures[f] /= Double(count)
                    }
                }
                return DayNucleotide(day: dayIdx, features: avgFeatures)
            }
            let baselineSeq = WeekSequence(startDay: 0, nucleotides: baselineWeekNucs)

            if let currentWeek = sequences.last {
                baselineHAS = DTWEngine.helixAlignmentScore(currentWeek, baselineSeq, weights: blosum.weights)
            } else {
                baselineHAS = nil
            }
        } else {
            baselineHAS = nil
        }

        // Step 12: Assemble profile
        return SleepDNAProfile(
            nucleotides: nucleotides,
            sequences: sequences,
            basePairs: basePairs,
            motifs: motifs,
            mutations: mutations,
            clusters: clusters,
            expressionRules: expressionRules,
            alignments: alignments,
            prediction: prediction,
            scoringMatrix: blosum,
            healthMarkers: healthMarkers,
            helixGeometry: helixGeometry,
            persistentHomology: pchResult,
            linkingNumber: lndResult,
            mutualInfoSpectrum: misResult,
            hasScore: hasScore,
            baselineHAS: baselineHAS,
            poissonFragmentation: poissonResult,
            hawkesAnalysis: hawkesResult,
            tier: tier,
            computedAt: Date(),
            dataWeeks: dataWeeks
        )
    }
}

// MARK: - Errors

/// Errors thrown by the SleepDNA pipeline.
public enum SleepDNAError: Error, Sendable {
    /// No records were provided.
    case insufficientData
}
