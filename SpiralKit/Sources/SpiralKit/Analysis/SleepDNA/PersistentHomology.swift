import Foundation

// MARK: - Types

/// A single topological feature tracked through a filtration.
public struct PersistenceFeature: Codable, Sendable {
    /// Topological dimension: 0 = connected component, 1 = loop.
    public let dimension: Int
    /// Filtration radius where this feature first appears.
    public let birth: Double
    /// Filtration radius where this feature merges/disappears.
    public let death: Double
    /// Lifetime of the feature; long persistence = real structure.
    public var persistence: Double { death - birth }
}

/// Result of persistent homology computation on a helix point cloud.
public struct PersistentHomologyResult: Codable, Sendable {
    /// All birth-death features detected during the filtration.
    public let features: [PersistenceFeature]
    /// Number of long-lived connected components (beta-0).
    public let beta0: Int
    /// Number of long-lived loops / cycles (beta-1).
    public let beta1: Int
    /// Mean persistence of the top features, normalized to [0, 1].
    public let structuralStability: Double
}

// MARK: - Computation

/// Persistent Circadian Homology (PCH): topological data analysis on the
/// SleepDNA helix point cloud.
///
/// Uses a simplified Rips filtration with Union-Find to track connected
/// components (beta-0) and an Euler-characteristic heuristic for loops (beta-1).
public enum PersistentHomology {

    /// Compute persistent homology from nucleotides and their helix geometry.
    ///
    /// Builds a 3D point cloud using the same cylindrical helix coordinates
    /// as HelixGeometryComputer, then runs a simplified Rips filtration.
    ///
    /// - Parameters:
    ///   - nucleotides: Per-day feature vectors.
    ///   - helixGeometry: Per-day helix visualization parameters.
    /// - Returns: Homology result with beta numbers and structural stability.
    public static func compute(
        nucleotides: [DayNucleotide],
        helixGeometry: [DayHelixParams]
    ) -> PersistentHomologyResult {
        let points = buildPointCloud(nucleotides: nucleotides, helixGeometry: helixGeometry)
        guard points.count >= 2 else {
            return PersistentHomologyResult(features: [], beta0: 0, beta1: 0, structuralStability: 0)
        }

        // Build sorted edge list (all pairwise distances)
        let edges = buildSortedEdges(points: points)
        guard !edges.isEmpty else {
            return PersistentHomologyResult(features: [], beta0: 0, beta1: 0, structuralStability: 0)
        }

        let maxDist = edges.last!.distance

        // Track beta-0 via Union-Find
        var features = [PersistenceFeature]()
        let uf = UnionFind(count: points.count)
        var edgeCount = 0
        var componentCount = points.count

        // Every point is born at radius 0 as its own component
        // We track deaths as components merge
        var beta1Features = [PersistenceFeature]()
        var previousEulerDeficit = 0  // edges - vertices + components (expect 0 for tree)

        for edge in edges {
            let eps = edge.distance
            let rootA = uf.find(edge.i)
            let rootB = uf.find(edge.j)

            if rootA != rootB {
                // Merging two components — the younger one "dies"
                uf.union(edge.i, edge.j)
                componentCount -= 1
                // The merged component was born at 0, dies now
                features.append(PersistenceFeature(dimension: 0, birth: 0, death: eps))
            } else {
                // Edge closes a cycle — a 1-dimensional feature is born
                edgeCount += 1
                let eulerDeficit = edgeCount - (points.count - componentCount)
                if eulerDeficit > previousEulerDeficit {
                    beta1Features.append(PersistenceFeature(dimension: 1, birth: eps, death: eps))
                    previousEulerDeficit = eulerDeficit
                }
            }
        }

        // The last surviving component never dies — add with death = infinity (use maxDist)
        // Already implicit: we have points.count - 1 death events for beta-0

        // For beta-1 features, estimate death by looking at when adding more edges
        // stops creating new cycles (use maxDist as death for all detected loops)
        let finalBeta1 = beta1Features.map { f in
            PersistenceFeature(dimension: 1, birth: f.birth, death: maxDist)
        }

        let allFeatures = features + finalBeta1

        // Count long-lived features (persistence > 25% of max distance)
        let persistenceThreshold = maxDist * 0.25
        let longLivedBeta0 = features.filter { $0.persistence > persistenceThreshold }.count + 1 // +1 for surviving component
        let longLivedBeta1 = finalBeta1.filter { $0.persistence > persistenceThreshold }.count

        // Structural stability: mean persistence of top features, normalized
        let topK = min(5, allFeatures.count)
        let sortedByPersistence = allFeatures.sorted { $0.persistence > $1.persistence }
        let topFeatures = Array(sortedByPersistence.prefix(topK))
        let meanPersistence = topFeatures.isEmpty ? 0 : topFeatures.reduce(0.0) { $0 + $1.persistence } / Double(topFeatures.count)
        let stability = maxDist > 0 ? min(meanPersistence / maxDist, 1.0) : 0

        return PersistentHomologyResult(
            features: allFeatures,
            beta0: longLivedBeta0,
            beta1: longLivedBeta1,
            structuralStability: stability
        )
    }

    // MARK: - Point Cloud

    /// Build 3D helix points from nucleotides and their geometry parameters.
    ///
    /// Uses cylindrical coordinates:
    ///   x = r * cos(theta)
    ///   y = dayIndex (vertical axis)
    ///   z = r * sin(theta)
    ///
    /// Where r = helixRadius and theta encodes the day's sleep timing.
    private static func buildPointCloud(
        nucleotides: [DayNucleotide],
        helixGeometry: [DayHelixParams]
    ) -> [SIMD3<Double>] {
        let count = min(nucleotides.count, helixGeometry.count)
        var points = [SIMD3<Double>]()
        points.reserveCapacity(count)

        for i in 0..<count {
            let nuc = nucleotides[i]
            let helix = helixGeometry[i]

            // Theta from bedtime circular encoding
            let theta = atan2(nuc[.bedtimeSin], nuc[.bedtimeCos])
            let r = max(0.1, helix.helixRadius)
            let y = Double(i)

            let x = r * cos(theta)
            let z = r * sin(theta)
            points.append(SIMD3<Double>(x, y, z))
        }

        return points
    }

    // MARK: - Edge List

    private struct Edge {
        let i: Int
        let j: Int
        let distance: Double
    }

    /// Compute all pairwise distances and return sorted edge list.
    private static func buildSortedEdges(points: [SIMD3<Double>]) -> [Edge] {
        let n = points.count
        var edges = [Edge]()
        edges.reserveCapacity(n * (n - 1) / 2)

        for i in 0..<n {
            for j in (i + 1)..<n {
                let diff = points[i] - points[j]
                let dist = sqrt(diff.x * diff.x + diff.y * diff.y + diff.z * diff.z)
                edges.append(Edge(i: i, j: j, distance: dist))
            }
        }

        edges.sort { $0.distance < $1.distance }
        return edges
    }

    // MARK: - Union-Find

    private final class UnionFind {
        private var parent: [Int]
        private var rank: [Int]

        init(count: Int) {
            parent = Array(0..<count)
            rank = Array(repeating: 0, count: count)
        }

        func find(_ x: Int) -> Int {
            if parent[x] != x {
                parent[x] = find(parent[x])
            }
            return parent[x]
        }

        func union(_ x: Int, _ y: Int) {
            let rx = find(x)
            let ry = find(y)
            guard rx != ry else { return }
            if rank[rx] < rank[ry] {
                parent[rx] = ry
            } else if rank[rx] > rank[ry] {
                parent[ry] = rx
            } else {
                parent[ry] = rx
                rank[rx] += 1
            }
        }
    }
}
