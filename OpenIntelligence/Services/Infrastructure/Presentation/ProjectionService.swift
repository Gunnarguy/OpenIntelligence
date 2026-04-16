//  ProjectionService.swift
//  OpenIntelligence
//
//  Provides 3D projection utilities for high-dimensional embeddings.
//  - PCA (approximate randomized power iteration) for stable, interpretable axes
//  - RP (Random Projection) fallback/alternative
//  - Centralized service so views can stay lightweight
//
//  Notes:
//  - We use an approximate PCA via power iterations on the covariance (X^T X) to avoid
//    heavy dependencies. This is usually sufficient for visualization.
//  - If Accelerate-backed SVD is added later, we can swap implementations behind this API.

import Foundation
import simd

// Avoid importing SwiftUI/SceneKit here; service is platform-agnostic.

enum ProjectionMethodKind: String {
    case pca
    case rp
    case tsne
    case umap
}

final class ProjectionService {
    static let shared = ProjectionService()
    private init() {}

    // Entry point
    func project3D(
        embeddings: [[Float]],
        method: ProjectionMethodKind,
        seed: UInt64
    ) -> [SIMD3<Float>] {
        guard !embeddings.isEmpty, let dim = embeddings.first?.count, dim > 0 else {
            return []
        }
        // Filter malformed rows
        let X = embeddings.filter { $0.count == dim }
        guard !X.isEmpty else { return [] }

        switch method {
        case .pca:
            return pca3D_powerIteration(X: X, seed: seed)
        case .rp:
            return randomProjection3D(X: X, seed: seed)
        case .tsne:
            return tsne3D(X: X, seed: seed)
        case .umap:
            return umap3D(X: X, seed: seed)
        }
    }

    // MARK: - PCA (Approximate via Power Iteration)

    // Computes top-3 eigenvectors of covariance(X) using power iterations with Gram-Schmidt.
    // Steps:
    //   - Mean-center X (N x D)
    //   - For k in {1,2,3}:
    //       - initialize random v
    //       - for t iterations: v <- (X^T X) v, then orthonormalize vs previous vectors
    //       - store as component
    //   - Project X onto the 3 components
    // Complexity roughly O(iters * N * D * 3), acceptable for visualization sampling.
    private func pca3D_powerIteration(
        X rawX: [[Float]],
        seed: UInt64,
        iters: Int = 6
    ) -> [SIMD3<Float>] {
        let N = rawX.count
        let D = rawX.first?.count ?? 0
        if N == 0 || D == 0 { return [] }

        // Mean center
        var mean = [Float](repeating: 0, count: D)
        for v in rawX {
            for i in 0..<D { mean[i] += v[i] }
        }
        let invN = 1.0 / Float(N)
        for i in 0..<D { mean[i] *= invN }

        var X = rawX // copy
        for n in 0..<N {
            for i in 0..<D { X[n][i] -= mean[i] }
        }

        // Helper: y = (X^T X) * v = X^T * (X * v)
        func covMatVec(v: [Float]) -> [Float] {
            // t = X * v  (N)
            var t = [Float](repeating: 0, count: N)
            for n in 0..<N {
                var acc: Float = 0
                let row = X[n]
                for i in 0..<D { acc += row[i] * v[i] }
                t[n] = acc
            }
            // y = X^T * t (D)
            var y = [Float](repeating: 0, count: D)
            for i in 0..<D {
                var acc: Float = 0
                for n in 0..<N { acc += X[n][i] * t[n] }
                y[i] = acc
            }
            return y
        }

        // Orthonormalize vectors v against list U using Gram-Schmidt
        func orthonormalize(_ vIn: [Float], against U: inout [[Float]]) -> [Float] {
            var v = vIn
            for u in U {
                let dot = dotProduct(u, v)
                for i in 0..<v.count { v[i] -= dot * u[i] }
            }
            let n = l2norm(v)
            if n > 0 {
                for i in 0..<v.count { v[i] /= n }
            }
            return v
        }

        // Power iteration to get k-th component
        var components: [[Float]] = []
        var rng = VizLCG(seed: seed ^ 0xA5A5A5A5A5A5A5A5)

        for _ in 0..<3 {
            // Initialize random vector
            var v = (0..<D).map { _ in Float.vizNormal(&rng) }
            v = orthonormalize(v, against: &components)

            // Iterate
            for _ in 0..<iters {
                var y = covMatVec(v: v)
                // Orthonormalize vs existing components
                y = orthonormalize(y, against: &components)
                let n = l2norm(y)
                if n > 0 {
                    for i in 0..<D { y[i] /= n }
                }
                v = y
            }
            // Canonicalize sign: ensure the element with largest absolute value
            // is positive. This prevents eigenvectors from flipping direction
            // between runs, keeping axis labels stable.
            if let maxIdx = v.indices.max(by: { abs(v[$0]) < abs(v[$1]) }), v[maxIdx] < 0 {
                for i in 0..<D { v[i] = -v[i] }
            }
            components.append(v)
        }

        // Project X onto components -> 3D coords
        var out: [SIMD3<Float>] = []
        out.reserveCapacity(N)
        for n in 0..<N {
            let row = X[n]
            var x: Float = 0, y: Float = 0, z: Float = 0
            let c0 = components[0], c1 = components[1], c2 = components[2]
            for i in 0..<D {
                let xi = row[i]
                x += xi * c0[i]
                y += xi * c1[i]
                z += xi * c2[i]
            }
            out.append(SIMD3<Float>(x, y, z))
        }
        return out
    }

    // MARK: - Random Projection (RP)

    private func randomProjection3D(X: [[Float]], seed: UInt64) -> [SIMD3<Float>] {
        let N = X.count
        let D = X.first?.count ?? 0
        if N == 0 || D == 0 { return [] }

        // Mean center
        var mean = [Float](repeating: 0, count: D)
        for v in X {
            for i in 0..<D { mean[i] += v[i] }
        }
        let invN = 1.0 / Float(N)
        for i in 0..<D { mean[i] *= invN }

        var rng = VizLCG(seed: seed ^ 0x9E3779B97F4A7C15)
        // Build 3 random unit vectors and orthonormalize
        var R: [[Float]] = (0..<3).map { _ in
            var v = (0..<D).map { _ in Float.vizNormal(&rng) }
            normalize(&v)
            return v
        }
        gramSchmidt(&R)

        var out: [SIMD3<Float>] = []
        out.reserveCapacity(N)
        for n in 0..<N {
            var x: Float = 0, y: Float = 0, z: Float = 0
            for i in 0..<D {
                let centered = X[n][i] - mean[i]
                x += centered * R[0][i]
                y += centered * R[1][i]
                z += centered * R[2][i]
            }
            out.append(SIMD3<Float>(x, y, z))
        }
        return out
    }

    // MARK: - t-SNE (Optimized with adaptive iterations and sampling)

    private func tsne3D(X: [[Float]], seed: UInt64, perplexity: Float = 30) -> [SIMD3<Float>] {
        let N = X.count
        guard N > 1 else { return X.isEmpty ? [] : [SIMD3<Float>(0, 0, 0)] }

        // OPTIMIZATION: Adaptive iterations based on point count
        // Fewer points = more iterations (quality), many points = fewer (speed)
        let iterations: Int
        if N > 1500 {
            iterations = 100  // Fast for large datasets
        } else if N > 500 {
            iterations = 150
        } else if N > 100 {
            iterations = 200
        } else {
            iterations = 250  // Original quality for small sets
        }

        // Initialize with PCA for better starting point
        var Y = pca3D_powerIteration(X: X, seed: seed)

        // OPTIMIZATION: For large N, use k-nearest neighbors instead of full pairwise
        // This reduces O(n²) to O(n*k) for similarity computation
        let useApproximate = N > 300
        let kNeighbors = min(50, N - 1)  // Only consider nearest neighbors

        var P: [[Float]]
        if useApproximate {
            // Build sparse P matrix using only k-nearest neighbors
            P = Array(repeating: Array(repeating: Float(0), count: N), count: N)
            let sigma = perplexity / 3.0
            let sigmaSq2 = 2 * sigma * sigma

            for i in 0..<N {
                // Find k-nearest neighbors
                var dists: [(Int, Float)] = []
                dists.reserveCapacity(N)
                for j in 0..<N where i != j {
                    var dist: Float = 0
                    for d in 0..<X[i].count {
                        let diff = X[i][d] - X[j][d]
                        dist += diff * diff
                    }
                    dists.append((j, dist))
                }
                dists.sort { $0.1 < $1.1 }

                // Only compute P for k-nearest neighbors
                var rowSum: Float = 0
                for (j, distSq) in dists.prefix(kNeighbors) {
                    P[i][j] = exp(-distSq / sigmaSq2)
                    rowSum += P[i][j]
                }
                if rowSum > 0 {
                    for (j, _) in dists.prefix(kNeighbors) {
                        P[i][j] /= rowSum
                    }
                }
            }
        } else {
            // Original full pairwise for small datasets
            P = Array(repeating: Array(repeating: Float(0), count: N), count: N)
            let sigma = perplexity / 3.0
            let sigmaSq2 = 2 * sigma * sigma
            for i in 0..<N {
                for j in 0..<N where i != j {
                    var dist: Float = 0
                    for d in 0..<(X[i].count) {
                        let diff = X[i][d] - X[j][d]
                        dist += diff * diff
                    }
                    P[i][j] = exp(-dist / sigmaSq2)
                }
                let rowSum = P[i].reduce(0, +)
                if rowSum > 0 {
                    for j in 0..<N { P[i][j] /= rowSum }
                }
            }
        }

        // Symmetrize
        let invN2 = 1.0 / (2 * Float(N))
        for i in 0..<N {
            for j in (i+1)..<N {
                let sym = (P[i][j] + P[j][i]) * invN2
                P[i][j] = sym
                P[j][i] = sym
            }
        }

        // Gradient descent with optimizations
        var velocity = Array(repeating: SIMD3<Float>(0, 0, 0), count: N)
        let momentum: Float = 0.5
        let eta: Float = 200.0

        for iter in 0..<iterations {
            // OPTIMIZATION: Sample-based Q computation for large N
            let computeEveryJ = useApproximate && N > 500 ? 2 : 1  // Skip every other point

            var Q = Array(repeating: Array(repeating: Float(0), count: N), count: N)
            var Z: Float = 0
            for i in 0..<N {
                for j in stride(from: 0, to: N, by: computeEveryJ) where i != j {
                    let diff = Y[i] - Y[j]
                    let distSq = simd_length_squared(diff)
                    Q[i][j] = 1.0 / (1.0 + distSq)
                    Z += Q[i][j] * Float(computeEveryJ)  // Adjust for sampling
                }
            }
            if Z > 0 {
                let invZ = 1.0 / Z
                for i in 0..<N {
                    for j in 0..<N {
                        Q[i][j] *= invZ
                    }
                }
            }

            // Compute gradients (sample for very large N)
            var grad = Array(repeating: SIMD3<Float>(0, 0, 0), count: N)
            let gradSampleStep = useApproximate && N > 800 ? 2 : 1

            for i in 0..<N {
                for j in stride(from: 0, to: N, by: gradSampleStep) where i != j {
                    let pij = max(P[i][j], 1e-12)
                    let qij = max(Q[i][j], 1e-12)
                    let mult = (pij - qij) * Q[i][j] * Float(gradSampleStep)
                    let diff = Y[i] - Y[j]
                    grad[i] += 4 * mult * diff
                }
            }

            // Update positions with momentum
            let effectiveEta = iter < 50 ? eta * 4 : eta
            for i in 0..<N {
                velocity[i] = momentum * velocity[i] - effectiveEta * grad[i]
                Y[i] += velocity[i]
            }
        }

        return Y
    }

    // MARK: - UMAP (Proper implementation with fuzzy set membership)

    private func umap3D(X: [[Float]], seed: UInt64, nNeighbors: Int = 15) -> [SIMD3<Float>] {
        let N = X.count
        guard N > 1 else { return X.isEmpty ? [] : [SIMD3<Float>(0, 0, 0)] }

        // Adaptive iterations
        let iterations: Int
        if N > 1500 { iterations = 200 }
        else if N > 500 { iterations = 300 }
        else { iterations = 400 }

        Log.info("UMAP starting with N=\(N) points, k=\(nNeighbors), iters=\(iterations)")

        let D = X[0].count
        let k = min(nNeighbors, N - 1)

        // Step 1: Build k-NN with distances
        var neighborIndices: [[Int]] = Array(repeating: [], count: N)
        var neighborDists: [[Float]] = Array(repeating: [], count: N)

        for i in 0..<N {
            var dists: [(Int, Float)] = []
            dists.reserveCapacity(N)
            for j in 0..<N where i != j {
                var distSq: Float = 0
                for d in 0..<D {
                    let diff = X[i][d] - X[j][d]
                    distSq += diff * diff
                }
                dists.append((j, sqrt(distSq)))
            }
            dists.sort { $0.1 < $1.1 }
            neighborIndices[i] = dists.prefix(k).map { $0.0 }
            neighborDists[i] = dists.prefix(k).map { $0.1 }
        }

        // Step 2: Compute local connectivity (sigma) for smooth kNN
        var sigma = Array(repeating: Float(1.0), count: N)
        var rho = Array(repeating: Float(0.0), count: N)  // Distance to nearest neighbor

        for i in 0..<N {
            if !neighborDists[i].isEmpty {
                rho[i] = neighborDists[i][0]
                // Binary search for sigma that gives target sum
                let target = log2(Float(k))
                var lo: Float = 0.001, hi: Float = 100.0
                for _ in 0..<20 {  // Binary search iterations
                    let mid = (lo + hi) / 2
                    var sum: Float = 0
                    for d in neighborDists[i] {
                        sum += exp(-max(0, d - rho[i]) / mid)
                    }
                    if sum > target { lo = mid } else { hi = mid }
                }
                sigma[i] = (lo + hi) / 2
            }
        }

        // Step 3: Build symmetric fuzzy graph (high-D membership weights)
        var graph: [Int: Float] = [:]  // Sparse: key = i*N+j, value = weight

        for i in 0..<N {
            for (idx, j) in neighborIndices[i].enumerated() {
                let d = neighborDists[i][idx]
                let w_ij = exp(-max(0, d - rho[i]) / sigma[i])
                let key_ij = i * N + j
                let key_ji = j * N + i

                // Symmetric: w = w_ij + w_ji - w_ij * w_ji
                let existing_ij = graph[key_ij] ?? 0
                let existing_ji = graph[key_ji] ?? 0
                let symWeight = w_ij + existing_ji - w_ij * existing_ji
                graph[key_ij] = max(existing_ij, symWeight)
                graph[key_ji] = max(existing_ji, symWeight)
            }
        }

        Log.info("UMAP graph built with \(graph.count) edges")

        // Step 4: Initialize with spectral-like layout (use PCA as init)
        var Y: [SIMD3<Float>]
        let pcaInit = pca3D_powerIteration(X: X, seed: seed)
        if pcaInit.count == N {
            // Scale PCA init to small range
            Y = pcaInit.map { $0 * 0.01 }
        } else {
            var rng = VizLCG(seed: seed)
            Y = (0..<N).map { _ in
                SIMD3<Float>(
                    Float.vizNormal(&rng) * 0.01,
                    Float.vizNormal(&rng) * 0.01,
                    Float.vizNormal(&rng) * 0.01
                )
            }
        }

        // Step 5: Optimize layout
        let a: Float = 1.929
        let b: Float = 0.7915
        let minDist: Float = 0.1

        // Pre-compute edges as array for faster iteration
        var edges: [(i: Int, j: Int, w: Float)] = []
        for (key, w) in graph where w > 0.01 {
            let i = key / N
            let j = key % N
            if i < j {  // Only store each edge once
                edges.append((i, j, w))
            }
        }
        Log.info("UMAP optimizing \(edges.count) unique edges")

        var epochsPerSample = edges.map { 1.0 / max($0.w, 0.01) }
        let maxEpochsPerSample = epochsPerSample.max() ?? 1.0
        epochsPerSample = epochsPerSample.map { $0 / maxEpochsPerSample * Float(iterations) }
        var epochOfNextSample = epochsPerSample

        let negativeSampleRate = 5
        var rng = VizLCG(seed: seed ^ 0xDEAD)

        for epoch in 0..<iterations {
            let alpha = 1.0 - Float(epoch) / Float(iterations)

            // Process edges scheduled for this epoch
            for (edgeIdx, edge) in edges.enumerated() {
                if epochOfNextSample[edgeIdx] <= Float(epoch) {
                    let i = edge.i
                    let j = edge.j

                    // Attractive force
                    let diff = Y[i] - Y[j]
                    let distSq = simd_length_squared(diff) + 0.001
                    let dist = sqrt(distSq)

                    if dist > minDist {
                        let gradCoef = -2.0 * a * b * pow(dist, 2 * b - 2) / (1.0 + a * pow(dist, 2 * b))
                        let grad = gradCoef * diff / dist * alpha
                        Y[i] += grad
                        Y[j] -= grad
                    }

                    // Negative sampling (repulsion)
                    for _ in 0..<negativeSampleRate {
                        let k = Int(rng.next() % UInt64(N))
                        if k != i {
                            let diffNeg = Y[i] - Y[k]
                            let distNegSq = simd_length_squared(diffNeg) + 0.001
                            let distNeg = sqrt(distNegSq)

                            if distNeg > 0.01 {
                                let gradCoef = 2.0 * b / ((0.001 + distNegSq) * (1.0 + a * pow(distNeg, 2 * b)))
                                let grad = min(gradCoef, 4.0) * diffNeg / distNeg * alpha
                                Y[i] += grad
                            }
                        }
                    }

                    epochOfNextSample[edgeIdx] += epochsPerSample[edgeIdx]
                }
            }

            if epoch % 100 == 0 {
                let spread = Y.map { simd_length($0) }.max() ?? 0
                Log.info("UMAP epoch \(epoch): spread=\(spread)")
            }
        }

        Log.info("UMAP optimization complete")

        // Normalize to [-1, 1] range
        var minVals = Y[0], maxVals = Y[0]
        for y in Y {
            minVals = simd_min(minVals, y)
            maxVals = simd_max(maxVals, y)
        }
        let span = maxVals - minVals
        let scale = simd_max(span.x, simd_max(span.y, span.z))
        if scale > 0.001 {
            for i in 0..<N {
                Y[i] = (Y[i] - (minVals + maxVals) * 0.5) * (2.0 / scale)
            }
        }

        Log.info("UMAP final normalized positions range: \(Y.map { simd_length($0) }.min() ?? 0)...\(Y.map { simd_length($0) }.max() ?? 0)")
        return Y
    }

    // MARK: - LinAlg Utilities

    private func dotProduct(_ a: [Float], _ b: [Float]) -> Float {
        var s: Float = 0
        let c = min(a.count, b.count)
        for i in 0..<c { s += a[i] * b[i] }
        return s
    }

    private func l2norm(_ v: [Float]) -> Float {
        var s: Float = 0
        for x in v { s += x * x }
        return sqrt(max(s, 0))
    }

    private func normalize(_ v: inout [Float]) {
        let n = l2norm(v)
        if n > 0 {
            for i in 0..<v.count { v[i] /= n }
        }
    }

    private func gramSchmidt(_ R: inout [[Float]]) {
        if R.isEmpty { return }
        normalize(&R[0])
        subtractProjection(&R[1], onto: R[0]); normalize(&R[1])
        subtractProjection(&R[2], onto: R[0]); subtractProjection(&R[2], onto: R[1]); normalize(&R[2])
    }

    private func subtractProjection(_ v: inout [Float], onto u: [Float]) {
        let dot = dotProduct(v, u)
        for i in 0..<v.count { v[i] -= dot * u[i] }
    }
}

// MARK: - Deterministic Seed from UUID
// Swift's .hashValue is randomized per process launch (ASLR).
// This FNV-1a hash produces the SAME seed for the SAME UUID every time.

func deterministicSeed(from uuidString: String) -> UInt64 {
    var hash: UInt64 = 14695981039346656037 // FNV offset basis
    for byte in uuidString.utf8 {
        hash ^= UInt64(byte)
        hash &*= 1099511628211 // FNV prime
    }
    return hash
}

// MARK: - Deterministic RNG (same as used in Embedding3DView)

struct VizLCG {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
    mutating func nextFloat() -> Float {
        return Float(next() & 0xFFFFFFFF) / Float(UInt32.max)
    }
}
extension Float {
    // Normal approx using Box-Muller transform on [0,1)
    static func vizNormal(_ rng: inout VizLCG) -> Float {
        let u1 = max(rng.nextFloat(), 1e-7)
        let u2 = rng.nextFloat()
        let r = sqrt(-2.0 * log(u1))
        let theta = 2 * Float.pi * u2
        return r * cos(theta)
    }
}
