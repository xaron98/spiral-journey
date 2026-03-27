import Foundation
import Accelerate
import simd

// MARK: - SPD covariance matrix (4×4)

/// A 4×4 symmetric positive definite covariance matrix.
///
/// Represents the "shape" of a trajectory window in the 4D
/// Clifford torus space. The Bures-Wasserstein distance between
/// two SPDMatrix4 instances respects the Riemannian geometry of
/// the SPD manifold — geodesics stay within the cone of valid
/// covariances, unlike Euclidean distance which cuts through.
///
/// For 4×4 matrices, eigendecomposition is O(1) — making this
/// viable for real-time computation on Apple Watch.
public struct SPDMatrix4: Sendable {
    /// Row-major storage: [a00,a01,a02,a03, a10,a11,a12,a13, ...]
    public var elements: [Double]  // 16 elements (4×4)

    public init(elements: [Double]) {
        precondition(elements.count == 16, "SPDMatrix4 requires exactly 16 elements")
        self.elements = elements
    }

    /// Identity matrix
    public static var identity: SPDMatrix4 {
        SPDMatrix4(elements: [
            1, 0, 0, 0,
            0, 1, 0, 0,
            0, 0, 1, 0,
            0, 0, 0, 1,
        ])
    }

    /// Access element at (row, col)
    public subscript(row: Int, col: Int) -> Double {
        get { elements[row * 4 + col] }
        set { elements[row * 4 + col] = newValue }
    }

    /// Trace: sum of diagonal elements
    public var trace: Double {
        elements[0] + elements[5] + elements[10] + elements[15]
    }

    /// Eigenvalues (sorted descending) using Accelerate.
    /// For 4×4 symmetric matrices, this is essentially O(1).
    public var eigenvalues: [Double] {
        var matrix = elements
        var n = __CLPK_integer(4)
        var lda = n
        var eigenvals = [Double](repeating: 0, count: 4)
        var work = [Double](repeating: 0, count: 12)
        var lwork = __CLPK_integer(12)
        var info = __CLPK_integer(0)
        var jobz: Int8 = 0x4E  // 'N' — eigenvalues only

        // LAPACK symmetric eigenvalue decomposition
        var uplo: Int8 = 0x55  // 'U'
        dsyev_(&jobz, &uplo, &n, &matrix, &lda, &eigenvals, &work, &lwork, &info)

        return eigenvals.sorted(by: >)
    }

    /// Condition number (ratio of largest to smallest eigenvalue).
    /// Low = nearly spherical attractor. High = elongated/degenerate.
    public var conditionNumber: Double {
        let eigs = eigenvalues
        guard let last = eigs.last, last > 1e-12 else { return .infinity }
        return eigs[0] / last
    }
}

// MARK: - Construct SPD from trajectory

extension SPDMatrix4 {

    /// Build a covariance matrix from a trajectory window.
    ///
    /// Computes the sample covariance of the 4D points,
    /// adds small regularization to ensure strict positive definiteness.
    public static func fromTrajectory(
        _ points: [SIMD4<Double>],
        regularize: Double = 1e-8
    ) -> (mean: SIMD4<Double>, cov: SPDMatrix4) {
        let n = Double(points.count)
        guard n > 1 else {
            return (points.first ?? .zero, .identity)
        }

        // Mean
        var mean = SIMD4<Double>.zero
        for p in points { mean += p }
        mean /= n

        // Covariance
        var cov = [Double](repeating: 0, count: 16)
        for p in points {
            let d = p - mean
            let components = [d.x, d.y, d.z, d.w]
            for i in 0..<4 {
                for j in 0..<4 {
                    cov[i * 4 + j] += components[i] * components[j]
                }
            }
        }

        for i in 0..<16 { cov[i] /= (n - 1) }

        // Symmetrize + regularize
        for i in 0..<4 {
            for j in (i+1)..<4 {
                let avg = (cov[i * 4 + j] + cov[j * 4 + i]) / 2
                cov[i * 4 + j] = avg
                cov[j * 4 + i] = avg
            }
            cov[i * 4 + i] += regularize
        }

        return (mean, SPDMatrix4(elements: cov))
    }
}

// MARK: - Bures-Wasserstein distance

/// Bures-Wasserstein distance between two SPD matrices.
///
///     W₂(Σ₁, Σ₂) = [tr(Σ₁) + tr(Σ₂) - 2·tr((Σ₁^½ Σ₂ Σ₁^½)^½)]^½
///
/// This is the 2-Wasserstein distance between N(0, Σ₁) and N(0, Σ₂).
/// It follows geodesics on the SPD manifold — every intermediate point
/// is a valid covariance matrix.
///
/// For 4×4 matrices: eigendecomposition is 4 eigenvalues → O(1).
/// Viable for real-time on Apple Watch.
///
/// - Parameters:
///   - a: First SPD covariance matrix
///   - b: Second SPD covariance matrix (e.g., reference N3 state)
/// - Returns: Non-negative distance on the SPD manifold
public func buresWassersteinDistance(_ a: SPDMatrix4, _ b: SPDMatrix4) -> Double {
    // For 4×4 SPD matrices, use the equivalent eigenvalue formula:
    // W₂² = tr(A) + tr(B) - 2 Σᵢ √(λᵢ)
    // where λᵢ are eigenvalues of A^{1/2} B A^{1/2}
    //
    // Equivalently (for SPD): eigenvalues of A·B give the squared
    // eigenvalues of A^{1/2} B A^{1/2} in a different basis.
    // We use the direct formula via matrix product eigenvalues.

    // Compute A·B (not symmetric, but eigenvalues are real and non-negative for SPD)
    var ab = [Double](repeating: 0, count: 16)
    for i in 0..<4 {
        for j in 0..<4 {
            var sum = 0.0
            for k in 0..<4 {
                sum += a[i, k] * b[k, j]
            }
            ab[i * 4 + j] = sum
        }
    }

    // Eigenvalues of A·B (use general eigenvalue solver for non-symmetric)
    var n = __CLPK_integer(4)
    var lda = n
    var wr = [Double](repeating: 0, count: 4)  // real parts
    var wi = [Double](repeating: 0, count: 4)  // imaginary parts (should be ~0 for SPD·SPD)
    var work = [Double](repeating: 0, count: 32)
    var lwork = __CLPK_integer(32)
    var info = __CLPK_integer(0)
    var jobvl: Int8 = 0x4E  // 'N'
    var jobvr: Int8 = 0x4E  // 'N'
    var vl = [Double](repeating: 0, count: 1)
    var vr = [Double](repeating: 0, count: 1)
    var ldvl = __CLPK_integer(1)
    var ldvr = __CLPK_integer(1)

    dgeev_(&jobvl, &jobvr, &n, &ab, &lda, &wr, &wi,
           &vl, &ldvl, &vr, &ldvr, &work, &lwork, &info)

    // W₂² = tr(A) + tr(B) - 2 Σ √(eigenvalue of A·B)
    var sqrtSum = 0.0
    for eigenval in wr {
        sqrtSum += sqrt(max(eigenval, 0))
    }

    let w2squared = a.trace + b.trace - 2 * sqrtSum
    return sqrt(max(w2squared, 0))
}

/// Extended Bures-Wasserstein including mean shift.
///
///     W₂²(N(μ₁,Σ₁), N(μ₂,Σ₂)) = ‖μ₁-μ₂‖² + BW²(Σ₁,Σ₂)
public func buresWassersteinExtended(
    mean1: SIMD4<Double>, cov1: SPDMatrix4,
    mean2: SIMD4<Double>, cov2: SPDMatrix4
) -> Double {
    let meanDist = simd_distance(mean1, mean2)
    let bw = buresWassersteinDistance(cov1, cov2)
    return sqrt(meanDist * meanDist + bw * bw)
}
