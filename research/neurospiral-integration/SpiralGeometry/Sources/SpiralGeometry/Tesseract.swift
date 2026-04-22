import Foundation
import simd

// MARK: - Tesseract vertex

/// A vertex of the 4D tesseract (hypercube) with coordinates in {-1, +1}⁴.
///
/// The 16 vertices of a tesseract centered at the origin lie on a Clifford
/// torus 𝕋_{√2} embedded in S³(2) ⊂ ℝ⁴. This is not an approximation —
/// every vertex satisfies x²+y² = 2 and z²+w² = 2 exactly.
public struct TesseractVertex: Hashable, Codable, Sendable {
    public let code: SIMD4<Int>  // each component ∈ {-1, +1}
    public let index: Int         // 0...15

    /// Position on the Clifford torus as a 4D point
    public var position: SIMD4<Double> {
        SIMD4<Double>(code)
    }

    /// Torus angles (θ₀, φ₀) where θ₀ = atan2(s₂, s₁), φ₀ = atan2(s₄, s₃)
    public var torusAngles: (theta: Double, phi: Double) {
        let theta = atan2(Double(code.y), Double(code.x))
        let phi = atan2(Double(code.w), Double(code.z))
        return (theta, phi)
    }
}

// MARK: - Tesseract

/// The 16-vertex tesseract as a topological discretizer.
///
/// Used to partition the Clifford torus into 16 angular quadrants.
/// Each quadrant corresponds to a unique sign pattern in {±1}⁴.
/// Transitions between adjacent vertices (Hamming distance 1)
/// correspond to a single physiological marker changing state.
public enum Tesseract {

    /// All 16 vertices of the tesseract, precomputed.
    public static let vertices: [TesseractVertex] = {
        var result: [TesseractVertex] = []
        var idx = 0
        for s1 in [-1, 1] {
            for s2 in [-1, 1] {
                for s3 in [-1, 1] {
                    for s4 in [-1, 1] {
                        result.append(TesseractVertex(
                            code: SIMD4(s1, s2, s3, s4),
                            index: idx
                        ))
                        idx += 1
                    }
                }
            }
        }
        return result
    }()

    /// Sign-quadrant discretizer Q: ℝ⁴ → {±1}⁴
    ///
    /// Maps a continuous 4D point to the nearest tesseract vertex
    /// by taking the sign of each coordinate. On the torus
    /// parameterization, this partitions 𝕋² into 4×4 = 16 cells.
    public static func discretize(_ point: SIMD4<Double>) -> TesseractVertex {
        let signs = SIMD4<Int>(
            point.x >= 0 ? 1 : -1,
            point.y >= 0 ? 1 : -1,
            point.z >= 0 ? 1 : -1,
            point.w >= 0 ? 1 : -1
        )
        return vertices.first { $0.code == signs }!
    }

    /// Find the nearest vertex by Euclidean distance.
    public static func nearestVertex(to point: SIMD4<Double>) -> TesseractVertex {
        vertices.min(by: { a, b in
            simd_distance(point, a.position) < simd_distance(point, b.position)
        })!
    }

    /// Hamming distance between two vertices (number of sign flips).
    /// Distance 1 = edge traversal (smooth transition).
    /// Distance 2+ = jump (possibly missed intermediate state).
    public static func hammingDistance(_ a: TesseractVertex, _ b: TesseractVertex) -> Int {
        var dist = 0
        if a.code.x != b.code.x { dist += 1 }
        if a.code.y != b.code.y { dist += 1 }
        if a.code.z != b.code.z { dist += 1 }
        if a.code.w != b.code.w { dist += 1 }
        return dist
    }

    /// Vertices adjacent to the given vertex (Hamming distance = 1).
    /// These represent the 4 possible single-marker transitions.
    public static func neighbors(of vertex: TesseractVertex) -> [TesseractVertex] {
        vertices.filter { hammingDistance($0, vertex) == 1 }
    }
}

// MARK: - Clifford torus

/// Operations on the Clifford torus 𝕋_R = {(x,y,z,w) : x²+y²=R², z²+w²=R²}.
///
/// The Clifford torus is a flat 2-torus embedded in S³ ⊂ ℝ⁴.
/// For tesseract vertices, R = √2.
public enum CliffordTorus {

    /// Default radius for tesseract vertices.
    public static let defaultRadius = sqrt(2.0)

    /// Extract torus angles (θ, φ) from a 4D point.
    ///
    /// θ = atan2(y, x) — angle in the xy-plane
    /// φ = atan2(w, z) — angle in the zw-plane
    public static func angles(of point: SIMD4<Double>) -> (theta: Double, phi: Double) {
        (atan2(point.y, point.x), atan2(point.w, point.z))
    }

    /// Project a raw 4D point onto the Clifford torus of radius R.
    ///
    /// Extracts angles from the xy and zw subspaces, reconstructs
    /// on the torus. Discards radial information — what remains is
    /// pure phase geometry.
    public static func project(_ point: SIMD4<Double>, radius R: Double = defaultRadius) -> SIMD4<Double> {
        let (theta, phi) = angles(of: point)
        return SIMD4(
            R * cos(theta),
            R * sin(theta),
            R * cos(phi),
            R * sin(phi)
        )
    }

    /// Geodesic distance on the flat torus 𝕋_R.
    ///
    /// d(p, q) = R × √(wrap(Δθ)² + wrap(Δφ)²)
    ///
    /// This is the mathematically correct intrinsic distance —
    /// it follows the torus surface, not the Euclidean shortcut
    /// through the interior.
    public static func geodesicDistance(
        from a: SIMD4<Double>,
        to b: SIMD4<Double>,
        radius R: Double = defaultRadius
    ) -> Double {
        let (ta, pa) = angles(of: a)
        let (tb, pb) = angles(of: b)

        let dtheta = wrapAngle(ta - tb)
        let dphi = wrapAngle(pa - pb)

        return R * sqrt(dtheta * dtheta + dphi * dphi)
    }

    /// Sub-radii r₁ = √(x²+y²) and r₂ = √(z²+w²).
    /// On a perfect Clifford torus, both equal R.
    public static func subRadii(of point: SIMD4<Double>) -> (r1: Double, r2: Double) {
        let r1 = sqrt(point.x * point.x + point.y * point.y)
        let r2 = sqrt(point.z * point.z + point.w * point.w)
        return (r1, r2)
    }

    /// How far a point deviates from the ideal torus.
    public static func torusDeviation(_ point: SIMD4<Double>, radius R: Double = defaultRadius) -> Double {
        let (r1, r2) = subRadii(of: point)
        let d1 = r1 - R
        let d2 = r2 - R
        return sqrt(d1 * d1 + d2 * d2)
    }

    /// Wrap angle to [-π, π].
    @inline(__always)
    public static func wrapAngle(_ angle: Double) -> Double {
        var a = angle.truncatingRemainder(dividingBy: 2 * .pi)
        if a > .pi { a -= 2 * .pi }
        if a < -.pi { a += 2 * .pi }
        return a
    }
}

// MARK: - Double rotation R(α, β) ∈ SO(4)

/// SO(4) double rotation acting on the xy and zw planes.
///
/// When parameterized as R(ω₁t, ω₂t):
///   ω₁ ↔ Process S (homeostatic sleep pressure)
///   ω₂ ↔ Process C (circadian rhythm)
///
/// The orbit of any tesseract vertex under this rotation
/// lies exactly on the Clifford torus 𝕋_{√2} for all t.
public struct DoubleRotation: Sendable {
    public let alpha: Double  // angle in xy-plane
    public let beta: Double   // angle in zw-plane

    public init(alpha: Double, beta: Double) {
        self.alpha = alpha
        self.beta = beta
    }

    /// Create from angular velocities and time.
    public init(omega1: Double, omega2: Double, t: Double) {
        self.alpha = omega1 * t
        self.beta = omega2 * t
    }

    /// Apply the rotation to a 4D point.
    public func apply(to point: SIMD4<Double>) -> SIMD4<Double> {
        let ca = cos(alpha), sa = sin(alpha)
        let cb = cos(beta), sb = sin(beta)
        return SIMD4(
            point.x * ca - point.y * sa,
            point.x * sa + point.y * ca,
            point.z * cb - point.w * sb,
            point.z * sb + point.w * cb
        )
    }

    /// Winding number q = α/β (ratio of rotation angles).
    /// Rational → closed orbit (torus knot).
    /// Irrational → dense orbit (ergodic coverage).
    public var windingRatio: Double? {
        guard abs(beta) > 1e-12 else { return nil }
        return alpha / beta
    }
}

// MARK: - Vertex residence analysis

/// Tracks which tesseract vertex a trajectory visits over time.
public struct VertexResidence: Sendable {
    public let dominantVertex: TesseractVertex
    public let residenceFraction: Double
    public let histogram: [Int: Int]      // vertex index → visit count
    public let transitionCount: Int
    public let transitionSequence: [Int]  // collapsed sequence of vertex indices
    public let stabilityScore: Double     // 1 - entropy/maxEntropy
}

extension Tesseract {

    /// Analyze vertex residence over a trajectory.
    ///
    /// For each point in the trajectory, assigns it to the nearest
    /// vertex and computes residence statistics.
    public static func analyzeResidence(
        of trajectory: [SIMD4<Double>]
    ) -> VertexResidence {
        guard !trajectory.isEmpty else {
            return VertexResidence(
                dominantVertex: vertices[0],
                residenceFraction: 0,
                histogram: [:],
                transitionCount: 0,
                transitionSequence: [],
                stabilityScore: 0
            )
        }

        let assignments = trajectory.map { nearestVertex(to: $0).index }

        // Histogram
        var histogram: [Int: Int] = [:]
        for a in assignments {
            histogram[a, default: 0] += 1
        }

        let dominant = histogram.max(by: { $0.value < $1.value })!.key
        let residence = Double(histogram[dominant]!) / Double(trajectory.count)

        // Transition sequence (collapse consecutive duplicates)
        var sequence = [assignments[0]]
        for a in assignments.dropFirst() {
            if a != sequence.last { sequence.append(a) }
        }
        let transitions = sequence.count - 1

        // Stability: 1 - normalized entropy
        let n = Double(trajectory.count)
        let maxEntropy = log2(16.0)
        var entropy = 0.0
        for count in histogram.values {
            let p = Double(count) / n
            if p > 0 { entropy -= p * log2(p) }
        }
        let stability = 1.0 - entropy / maxEntropy

        return VertexResidence(
            dominantVertex: vertices[dominant],
            residenceFraction: residence,
            histogram: histogram,
            transitionCount: transitions,
            transitionSequence: sequence,
            stabilityScore: stability
        )
    }
}
