import XCTest

@testable import OpenIntelligence

#if canImport(SceneKit)

final class EmbeddingNormalizationBoundsTests: XCTestCase {

    private typealias Bounds = (min: SIMD3<Float>, max: SIMD3<Float>)

    // Reference: the pre-optimization six-pass prefix/map/min()/max() implementation,
    // preserved verbatim so the single-pass helper is checked against stdlib semantics.
    private func naiveBounds(coords: [SIMD3<Float>], count: Int) -> Bounds? {
        let limit = min(count, coords.count)
        guard limit > 0 else { return nil }
        let xs = coords.prefix(limit).map { $0.x }
        let ys = coords.prefix(limit).map { $0.y }
        let zs = coords.prefix(limit).map { $0.z }
        guard let minX = xs.min(), let maxX = xs.max(),
            let minY = ys.min(), let maxY = ys.max(),
            let minZ = zs.min(), let maxZ = zs.max()
        else { return nil }
        return (min: SIMD3(minX, minY, minZ), max: SIMD3(maxX, maxY, maxZ))
    }

    // Bit-level comparison so NaN payloads and zero signs must match exactly.
    private func assertSameBounds(
        _ actual: Bounds?,
        _ expected: Bounds?,
        _ message: String = "",
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch (actual, expected) {
        case (nil, nil):
            return
        case let (a?, e?):
            for lane in 0..<3 {
                XCTAssertEqual(
                    a.min[lane].bitPattern, e.min[lane].bitPattern,
                    "min lane \(lane) \(message)", file: file, line: line)
                XCTAssertEqual(
                    a.max[lane].bitPattern, e.max[lane].bitPattern,
                    "max lane \(lane) \(message)", file: file, line: line)
            }
        default:
            XCTFail(
                "nil mismatch: actual=\(String(describing: actual)) expected=\(String(describing: expected)) \(message)",
                file: file, line: line)
        }
    }

    // Deterministic RNG so failures reproduce; SystemRandomNumberGenerator is not seedable.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    func testEmptyInputReturnsNil() {
        XCTAssertNil(EmbeddingSpaceRenderer.normalizationBounds(coords: [], count: 0))
        XCTAssertNil(EmbeddingSpaceRenderer.normalizationBounds(coords: [], count: 5))
        XCTAssertNil(
            EmbeddingSpaceRenderer.normalizationBounds(coords: [SIMD3<Float>(1, 2, 3)], count: 0))
        XCTAssertNil(
            EmbeddingSpaceRenderer.normalizationBounds(coords: [SIMD3<Float>(1, 2, 3)], count: -1))
    }

    func testSingleElement() {
        let element = SIMD3<Float>(1.5, -2.25, 3.75)
        let bounds = EmbeddingSpaceRenderer.normalizationBounds(coords: [element], count: 1)
        XCTAssertNotNil(bounds)
        XCTAssertEqual(bounds?.min, element)
        XCTAssertEqual(bounds?.max, element)
        assertSameBounds(bounds, naiveBounds(coords: [element], count: 1))
    }

    func testPrefixLimitExcludesTrailingElements() {
        let coords: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(1, 2, 3),
            SIMD3(-99, 99, -99),
        ]
        let bounds = EmbeddingSpaceRenderer.normalizationBounds(coords: coords, count: 2)
        XCTAssertEqual(bounds?.min, SIMD3<Float>(0, 0, 0))
        XCTAssertEqual(bounds?.max, SIMD3<Float>(1, 2, 3))
        assertSameBounds(bounds, naiveBounds(coords: coords, count: 2))
    }

    func testCountLargerThanArrayIsClamped() {
        let coords: [SIMD3<Float>] = [SIMD3(2, -1, 0.5), SIMD3(-3, 4, 0.25)]
        let clamped = EmbeddingSpaceRenderer.normalizationBounds(coords: coords, count: 99)
        let exact = EmbeddingSpaceRenderer.normalizationBounds(coords: coords, count: 2)
        assertSameBounds(clamped, exact)
        assertSameBounds(clamped, naiveBounds(coords: coords, count: 99))
    }

    func testNaNAfterFirstElementIsIgnored() {
        let coords: [SIMD3<Float>] = [
            SIMD3(0, 1, 2),
            SIMD3(Float.nan, Float.nan, Float.nan),
            SIMD3(3, -4, 5),
        ]
        let bounds = EmbeddingSpaceRenderer.normalizationBounds(coords: coords, count: 3)
        XCTAssertEqual(bounds?.min, SIMD3<Float>(0, -4, 2))
        XCTAssertEqual(bounds?.max, SIMD3<Float>(3, 1, 5))
        assertSameBounds(bounds, naiveBounds(coords: coords, count: 3))
    }

    func testNaNSeedPropagatesPerLane() {
        let coords: [SIMD3<Float>] = [
            SIMD3(Float.nan, 1, Float.nan),
            SIMD3(-2, -3, 4),
            SIMD3(5, 6, -7),
        ]
        let bounds = EmbeddingSpaceRenderer.normalizationBounds(coords: coords, count: 3)
        XCTAssertNotNil(bounds)
        XCTAssertTrue(bounds?.min.x.isNaN ?? false)
        XCTAssertTrue(bounds?.max.x.isNaN ?? false)
        XCTAssertTrue(bounds?.min.z.isNaN ?? false)
        XCTAssertTrue(bounds?.max.z.isNaN ?? false)
        XCTAssertEqual(bounds?.min.y, -3)
        XCTAssertEqual(bounds?.max.y, 6)
        assertSameBounds(bounds, naiveBounds(coords: coords, count: 3))
    }

    func testInfinitiesAreOrderedNormally() {
        let coords: [SIMD3<Float>] = [
            SIMD3(0, 0, 0),
            SIMD3(-.infinity, .infinity, 1),
            SIMD3(.infinity, -.infinity, -1),
        ]
        let bounds = EmbeddingSpaceRenderer.normalizationBounds(coords: coords, count: 3)
        XCTAssertEqual(bounds?.min, SIMD3<Float>(-.infinity, -.infinity, -1))
        XCTAssertEqual(bounds?.max, SIMD3<Float>(.infinity, .infinity, 1))
        assertSameBounds(bounds, naiveBounds(coords: coords, count: 3))
    }

    func testResultIsOrderingIndependentForFiniteValues() {
        var rng = SplitMix64(state: 0x5EED_0001)
        let base: [SIMD3<Float>] = (0..<32).map { i -> SIMD3<Float> in
            let x = Float(i) * 1.25 - 20.0
            let y = Float(31 - i) * -0.75 + 3.0
            let z = Float((i * i) % 37) - 18.0
            return SIMD3<Float>(x, y, z)
        }
        guard
            let reference = EmbeddingSpaceRenderer.normalizationBounds(
                coords: base, count: base.count)
        else {
            XCTFail("expected bounds for non-empty input")
            return
        }
        for permutation in 0..<10 {
            let shuffled = base.shuffled(using: &rng)
            let bounds = EmbeddingSpaceRenderer.normalizationBounds(
                coords: shuffled, count: shuffled.count)
            assertSameBounds(bounds, reference, "permutation \(permutation)")
        }
    }

    func testMatchesNaiveImplementationOnRandomArrays() {
        var rng = SplitMix64(state: 0xDEAD_BEEF_0BAD_F00D)
        for iteration in 0..<100 {
            let size = Int.random(in: 1...64, using: &rng)
            var coords: [SIMD3<Float>] = (0..<size).map { _ in
                SIMD3(
                    Float.random(in: -1000...1000, using: &rng),
                    Float.random(in: -1000...1000, using: &rng),
                    Float.random(in: -1000...1000, using: &rng))
            }
            // Every third iteration injects non-finite values, possibly at index 0,
            // so seed-NaN propagation is exercised against the naive reference.
            if iteration % 3 == 0 {
                let specials: [Float] = [.nan, .infinity, -.infinity]
                for _ in 0..<Int.random(in: 1...4, using: &rng) {
                    let index = Int.random(in: 0..<size, using: &rng)
                    let lane = Int.random(in: 0..<3, using: &rng)
                    coords[index][lane] = specials[Int.random(in: 0..<specials.count, using: &rng)]
                }
            }
            let count = Int.random(in: 1...size, using: &rng)
            assertSameBounds(
                EmbeddingSpaceRenderer.normalizationBounds(coords: coords, count: count),
                naiveBounds(coords: coords, count: count),
                "iteration \(iteration) size \(size) count \(count)")
        }
    }
}

#endif
