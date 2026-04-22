import Foundation
import simd

// MARK: - Wearable sleep sample

/// A single time-windowed sample from Apple Watch sensors.
///
/// This is the bridge between HealthKit data and the 4D tesseract space.
/// Each sample represents ~30 seconds of aggregated sensor data.
public struct WearableSleepSample: Sendable {
    /// HRV (RMSSD or SDNN) in milliseconds
    public let hrv: Double

    /// Heart rate in BPM
    public let heartRate: Double

    /// Motion intensity (accelerometer magnitude, 0 = still)
    public let motionIntensity: Double

    /// Respiratory rate (breaths per minute, if available)
    public let respiratoryRate: Double?

    /// Apple Watch sleep stage (if available): awake, core, deep, rem
    public let sleepStage: SleepStage?

    /// Timestamp
    public let timestamp: Date

    public init(
        hrv: Double,
        heartRate: Double,
        motionIntensity: Double,
        respiratoryRate: Double? = nil,
        sleepStage: SleepStage? = nil,
        timestamp: Date
    ) {
        self.hrv = hrv
        self.heartRate = heartRate
        self.motionIntensity = motionIntensity
        self.respiratoryRate = respiratoryRate
        self.sleepStage = sleepStage
        self.timestamp = timestamp
    }
}

/// Apple Watch sleep stages (from HealthKit)
public enum SleepStage: Int, Codable, Sendable {
    case awake = 0
    case core = 1    // N1 + N2 equivalent
    case deep = 2    // N3 equivalent (the glymphatic target)
    case rem = 3
}

// MARK: - 4D feature mapping

/// Maps wearable sensor data to a 4D point on the Clifford torus.
///
/// The four dimensions are chosen to be:
///
///   x₁: Autonomic depth — normalized HRV deviation from baseline
///        (high HRV → parasympathetic → deeper sleep → positive)
///
///   x₂: Stillness — inverse of motion intensity
///        (no motion → deep sleep → positive)
///
///   x₃: Cardiac slowing — normalized deviation of HR from wake baseline
///        (lower HR → deeper sleep → negative HR deviation → positive x₃)
///
///   x₄: Circadian phase — cos(2π · hourOfDay / 24)
///        (night = negative, day = positive)
///
/// After computing raw 4D coordinates, we project onto 𝕋_{√2}
/// so the tesseract discretization Q(x) applies directly.
public struct WearableTo4DMapper: Sendable {

    /// Running statistics for normalization (personalized per user)
    public struct PersonalBaseline: Codable, Sendable {
        public var hrvMean: Double
        public var hrvStd: Double
        public var hrMean: Double
        public var hrStd: Double
        public var motionMax: Double

        public init(
            hrvMean: Double = 50,
            hrvStd: Double = 20,
            hrMean: Double = 65,
            hrStd: Double = 10,
            motionMax: Double = 1.0
        ) {
            self.hrvMean = hrvMean
            self.hrvStd = hrvStd
            self.hrMean = hrMean
            self.hrStd = hrStd
            self.motionMax = motionMax
        }
    }

    public var baseline: PersonalBaseline

    public init(baseline: PersonalBaseline = .init()) {
        self.baseline = baseline
    }

    /// Map a single wearable sample to a 4D point and project to the torus.
    ///
    /// Returns a point on 𝕋_{√2} where the tesseract discretizer
    /// assigns it to one of 16 micro-states.
    public func map(_ sample: WearableSleepSample) -> SIMD4<Double> {
        let raw = rawCoordinates(sample)
        return CliffordTorus.project(raw)
    }

    /// Raw (un-projected) 4D coordinates before torus projection.
    /// Useful for computing torus deviation as a quality metric.
    public func rawCoordinates(_ sample: WearableSleepSample) -> SIMD4<Double> {
        // x₁: Autonomic depth (HRV z-score, clamped to [-3, 3])
        let hrvZ = clamp((sample.hrv - baseline.hrvMean) / max(baseline.hrvStd, 1), -3, 3)

        // x₂: Stillness (inverted motion, normalized to [-1, 1])
        let stillness = 1.0 - 2.0 * clamp(sample.motionIntensity / max(baseline.motionMax, 0.01), 0, 1)

        // x₃: Cardiac slowing (inverted HR z-score)
        let hrZ = -clamp((sample.heartRate - baseline.hrMean) / max(baseline.hrStd, 1), -3, 3)

        // x₄: Circadian phase
        let hour = Calendar.current.component(.hour, from: sample.timestamp)
        let minute = Calendar.current.component(.minute, from: sample.timestamp)
        let dayFraction = (Double(hour) + Double(minute) / 60.0) / 24.0
        let circadian = cos(2.0 * .pi * dayFraction)  // negative at night

        return SIMD4(hrvZ, stillness, hrZ, circadian)
    }

    /// Update baseline with a new batch of wake-period samples.
    public mutating func updateBaseline(from wakeSamples: [WearableSleepSample]) {
        guard !wakeSamples.isEmpty else { return }

        let hrvs = wakeSamples.map(\.hrv)
        let hrs = wakeSamples.map(\.heartRate)
        let motions = wakeSamples.map(\.motionIntensity)

        baseline.hrvMean = hrvs.reduce(0, +) / Double(hrvs.count)
        baseline.hrvStd = standardDeviation(hrvs)
        baseline.hrMean = hrs.reduce(0, +) / Double(hrs.count)
        baseline.hrStd = standardDeviation(hrs)
        baseline.motionMax = motions.max() ?? 1.0
    }

    private func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(value, lo), hi)
    }

    private func standardDeviation(_ values: [Double]) -> Double {
        let n = Double(values.count)
        guard n > 1 else { return 1.0 }
        let mean = values.reduce(0, +) / n
        let variance = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / (n - 1)
        return max(sqrt(variance), 1e-6)
    }
}

// MARK: - Sleep trajectory analysis

/// Analyzes a night's trajectory through the tesseract.
public struct SleepTrajectoryAnalysis: Sendable {
    /// The 4D trajectory on the Clifford torus
    public let trajectory: [SIMD4<Double>]

    /// Vertex residence for the full night
    public let residence: VertexResidence

    /// Per-vertex residence fractions (which micro-states were visited)
    public let vertexFractions: [Int: Double]

    /// Estimated ω₁/ω₂ ratio (winding number)
    public let windingRatio: Double?

    /// Angular velocities (rad/sample) in each torus plane
    public let omega1Mean: Double
    public let omega2Mean: Double

    /// Transition graph: which edges were traversed and how often
    public let edgeTraversals: [String: Int]  // "V03→V07" → count

    /// Time-resolved vertex sequence with timestamps
    public let stateSequence: [(vertex: Int, startIndex: Int, duration: Int)]

    // Extended toroidal features (experimental — ClaudiaApp validation)

    /// arctan2(ω₁, ω₂) — balance between torus dimensions
    public let omegaRatio: Double
    /// Circular dispersion in θ (0=focused, 1=uniform spread)
    public let thetaDispersion: Double
    /// Circular dispersion in φ (0=focused, 1=uniform spread)
    public let phiDispersion: Double
    /// Fraction of time at dominant vertex (0-1)
    public let residenceFraction: Double
    /// Mean distance from ideal Clifford torus surface (‖p‖ vs R√2)
    public let torusDeviation: Double
}

extension WearableTo4DMapper {

    /// Analyze a full night of wearable samples.
    ///
    /// Maps each sample to the Clifford torus, computes vertex residence,
    /// angular velocities, transition graph, and state sequence.
    public func analyzeNight(_ samples: [WearableSleepSample]) -> SleepTrajectoryAnalysis {
        let trajectory = samples.map { map($0) }
        let residence = Tesseract.analyzeResidence(of: trajectory)

        // Vertex fractions
        var fractions: [Int: Double] = [:]
        let n = Double(trajectory.count)
        for (idx, count) in residence.histogram {
            fractions[idx] = Double(count) / n
        }

        // Angular velocities
        var dthetas: [Double] = []
        var dphis: [Double] = []
        for i in 1..<trajectory.count {
            let (t1, p1) = CliffordTorus.angles(of: trajectory[i - 1])
            let (t2, p2) = CliffordTorus.angles(of: trajectory[i])
            dthetas.append(abs(CliffordTorus.wrapAngle(t2 - t1)))
            dphis.append(abs(CliffordTorus.wrapAngle(p2 - p1)))
        }

        let omega1 = dthetas.isEmpty ? 0 : dthetas.reduce(0, +) / Double(dthetas.count)
        let omega2 = dphis.isEmpty ? 0 : dphis.reduce(0, +) / Double(dphis.count)
        let winding = omega2 > 1e-10 ? omega1 / omega2 : nil

        // Edge traversals
        var edges: [String: Int] = [:]
        let seq = residence.transitionSequence
        for i in 1..<seq.count {
            let key = "V\(String(format: "%02d", seq[i-1]))→V\(String(format: "%02d", seq[i]))"
            edges[key, default: 0] += 1
        }

        // State sequence with durations
        var stateSeq: [(vertex: Int, startIndex: Int, duration: Int)] = []
        let assignments = trajectory.map { Tesseract.nearestVertex(to: $0).index }
        if !assignments.isEmpty {
            var currentVertex = assignments[0]
            var startIdx = 0
            for i in 1..<assignments.count {
                if assignments[i] != currentVertex {
                    stateSeq.append((currentVertex, startIdx, i - startIdx))
                    currentVertex = assignments[i]
                    startIdx = i
                }
            }
            stateSeq.append((currentVertex, startIdx, assignments.count - startIdx))
        }

        // --- Extended toroidal features (experimental) ---

        // Omega ratio: balance between torus dimensions
        let omegaRatio = atan2(omega1, omega2)

        // Circular dispersion = 1 - |mean(e^{iθ})| (0 = all same angle, 1 = uniform spread)
        let sampleCount = Double(max(1, trajectory.count))

        let thetaAngles = trajectory.map { CliffordTorus.angles(of: $0).theta }
        let thetaCosSum = thetaAngles.map { cos($0) }.reduce(0, +) / sampleCount
        let thetaSinSum = thetaAngles.map { sin($0) }.reduce(0, +) / sampleCount
        let thetaDispersion = 1.0 - sqrt(thetaCosSum * thetaCosSum + thetaSinSum * thetaSinSum)

        let phiAngles = trajectory.map { CliffordTorus.angles(of: $0).phi }
        let phiCosSum = phiAngles.map { cos($0) }.reduce(0, +) / sampleCount
        let phiSinSum = phiAngles.map { sin($0) }.reduce(0, +) / sampleCount
        let phiDispersion = 1.0 - sqrt(phiCosSum * phiCosSum + phiSinSum * phiSinSum)

        // Residence fraction: time at dominant vertex (from VertexResidence)
        let resFraction = residence.residenceFraction

        // Torus deviation: mean |‖p‖ - R√2| where R√2 is ideal Clifford torus radius
        let idealRadius = sqrt(2.0)
        let deviationSum = trajectory.reduce(0.0) { acc, p in
            let norm = sqrt(p.x * p.x + p.y * p.y + p.z * p.z + p.w * p.w)
            return acc + abs(norm - idealRadius)
        }
        let torusDeviation = deviationSum / sampleCount

        #if DEBUG
        print("[NeuroSpiral] 8 features: ω₁=\(String(format: "%.3f", omega1)) ω₂=\(String(format: "%.3f", omega2)) ratio=\(String(format: "%.3f", omegaRatio)) θ-disp=\(String(format: "%.3f", thetaDispersion)) φ-disp=\(String(format: "%.3f", phiDispersion)) res=\(String(format: "%.3f", resFraction)) stab=\(String(format: "%.3f", residence.stabilityScore)) dev=\(String(format: "%.3f", torusDeviation))")
        #endif

        return SleepTrajectoryAnalysis(
            trajectory: trajectory,
            residence: residence,
            vertexFractions: fractions,
            windingRatio: winding,
            omega1Mean: omega1,
            omega2Mean: omega2,
            edgeTraversals: edges,
            stateSequence: stateSeq,
            omegaRatio: omegaRatio,
            thetaDispersion: thetaDispersion,
            phiDispersion: phiDispersion,
            residenceFraction: resFraction,
            torusDeviation: torusDeviation
        )
    }
}
