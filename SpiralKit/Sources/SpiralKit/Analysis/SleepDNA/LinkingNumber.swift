import Foundation

// MARK: - Types

/// Result of the discrete Gauss linking integral between two helix strands.
public struct LinkingNumberResult: Codable, Sendable {
    /// Total linking number (Gauss integral value).
    public let linkingNumber: Double
    /// Linking Number Density: |linkingNumber| / numSegments.
    public let density: Double
    /// Whether the density exceeds the coherence threshold (strands are tightly intertwined).
    public let isCoherent: Bool
}

// MARK: - Computation

/// Linking Number Density (LND): measures how tightly the two helix strands
/// of the SleepDNA double helix are intertwined.
///
/// Uses the discrete Gauss linking integral:
///   L = (1/4pi) sum_i sum_j (dR_i x dR_j) . (R_i - R_j) / |R_i - R_j|^3
///
/// High LND indicates coherent, tightly wound structure. Low LND indicates
/// loose or disordered strand relationships.
public enum LinkingNumber {

    /// Coherence threshold: density above this indicates tightly intertwined strands.
    private static let coherenceThreshold = 0.1

    /// Compute the linking number between the two helix strands.
    ///
    /// Strand 1: (r*cos(theta), y, r*sin(theta))
    /// Strand 2: (r*cos(theta + pi + twist), y, r*sin(theta + pi + twist))
    ///
    /// - Parameters:
    ///   - nucleotides: Per-day feature vectors (used for theta via bedtime encoding).
    ///   - helixGeometry: Per-day helix parameters (radius, twist angle).
    /// - Returns: Linking number result with density and coherence flag.
    public static func compute(
        nucleotides: [DayNucleotide],
        helixGeometry: [DayHelixParams]
    ) -> LinkingNumberResult {
        let count = min(nucleotides.count, helixGeometry.count)
        guard count >= 2 else {
            return LinkingNumberResult(linkingNumber: 0, density: 0, isCoherent: false)
        }

        // Build the two strand point arrays
        let (strand1, strand2) = buildStrands(nucleotides: nucleotides, helixGeometry: helixGeometry, count: count)

        let numSegments = count - 1
        guard numSegments >= 1 else {
            return LinkingNumberResult(linkingNumber: 0, density: 0, isCoherent: false)
        }

        // Compute discrete Gauss linking integral
        var linkingSum = 0.0

        for i in 0..<numSegments {
            let dR1 = strand1[i + 1] - strand1[i]  // segment vector on strand 1

            for j in 0..<numSegments {
                let dR2 = strand2[j + 1] - strand2[j]  // segment vector on strand 2
                let r = strand1[i] - strand2[j]         // vector between segment starts
                let rNorm = length(r)

                guard rNorm > 1e-10 else { continue }

                // (dR1 x dR2) . r / |r|^3
                let crossProduct = cross(dR1, dR2)
                let tripleProduct = dot(crossProduct, r)
                linkingSum += tripleProduct / (rNorm * rNorm * rNorm)
            }
        }

        let linkingNumber = linkingSum / (4.0 * .pi)
        let density = abs(linkingNumber) / Double(numSegments)
        let isCoherent = density > coherenceThreshold

        return LinkingNumberResult(
            linkingNumber: linkingNumber,
            density: density,
            isCoherent: isCoherent
        )
    }

    // MARK: - Strand Construction

    /// Build 3D point arrays for both helix strands.
    private static func buildStrands(
        nucleotides: [DayNucleotide],
        helixGeometry: [DayHelixParams],
        count: Int
    ) -> ([SIMD3<Double>], [SIMD3<Double>]) {
        var strand1 = [SIMD3<Double>]()
        var strand2 = [SIMD3<Double>]()
        strand1.reserveCapacity(count)
        strand2.reserveCapacity(count)

        for i in 0..<count {
            let nuc = nucleotides[i]
            let helix = helixGeometry[i]

            let theta = atan2(nuc[.bedtimeSin], nuc[.bedtimeCos])
            let r = max(0.1, helix.helixRadius)
            let twist = helix.twistAngle
            let y = Double(i)

            // Strand 1: (r*cos(theta), y, r*sin(theta))
            strand1.append(SIMD3<Double>(
                r * cos(theta),
                y,
                r * sin(theta)
            ))

            // Strand 2: offset by pi + twist
            let theta2 = theta + .pi + twist
            strand2.append(SIMD3<Double>(
                r * cos(theta2),
                y,
                r * sin(theta2)
            ))
        }

        return (strand1, strand2)
    }

    // MARK: - Vector Math

    private static func cross(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> SIMD3<Double> {
        SIMD3<Double>(
            a.y * b.z - a.z * b.y,
            a.z * b.x - a.x * b.z,
            a.x * b.y - a.y * b.x
        )
    }

    private static func dot(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> Double {
        a.x * b.x + a.y * b.y + a.z * b.z
    }

    private static func length(_ v: SIMD3<Double>) -> Double {
        sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    }
}
