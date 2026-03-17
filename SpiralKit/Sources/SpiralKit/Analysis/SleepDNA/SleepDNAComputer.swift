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

        // Step 11: Assemble profile
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
