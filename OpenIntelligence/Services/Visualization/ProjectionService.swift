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
