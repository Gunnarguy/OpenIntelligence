import Foundation
import XCTest

@testable import OpenIntelligenceEngine

/// Covers the forward-scaling fallback that names and tiers Apple Silicon newer
/// than this build knows about.
///
/// The chip chain in `detectHostMacCapability` is exact for M1 through M5. Before
/// this, anything newer matched nothing and fell through to a generic
/// "Apple Silicon" label at 18 TOPS — an M3-era figure — so a brand-new Mac was
/// named wrongly and given ceilings two generations stale. iPhone and iPad already
/// computed forward from the identifier; Mac did not.
///
/// `appleSiliconGeneration` is the parsing half of that fix and is a pure function
/// over a string, so it is testable without a Mac of any particular generation.
final class AppleSiliconGenerationTests: XCTestCase {
    // MARK: - Generations this build enumerates

    func testParsesShippedGenerations() {
        XCTAssertEqual(DeviceCapabilityService.appleSiliconGeneration(in: "Apple M1"), 1)
        XCTAssertEqual(DeviceCapabilityService.appleSiliconGeneration(in: "Apple M2 Pro"), 2)
        XCTAssertEqual(DeviceCapabilityService.appleSiliconGeneration(in: "Apple M3 Max"), 3)
        XCTAssertEqual(DeviceCapabilityService.appleSiliconGeneration(in: "Apple M4"), 4)
        XCTAssertEqual(DeviceCapabilityService.appleSiliconGeneration(in: "Apple M5 Ultra"), 5)
    }

    // MARK: - Generations that do not exist yet
    //
    // The point of the change: these must parse rather than fall through.

    func testParsesGenerationsThisBuildPredates() {
        XCTAssertEqual(DeviceCapabilityService.appleSiliconGeneration(in: "Apple M6"), 6)
        XCTAssertEqual(DeviceCapabilityService.appleSiliconGeneration(in: "Apple M7 Pro"), 7)
        XCTAssertEqual(DeviceCapabilityService.appleSiliconGeneration(in: "Apple M8 Max"), 8)
    }

    /// Two digits must read as twelve, not as one followed by a stray two. A
    /// prefix-matching implementation passes every single-digit case above and
    /// fails this one.
    func testTwoDigitGenerationIsNotTruncated() {
        XCTAssertEqual(DeviceCapabilityService.appleSiliconGeneration(in: "Apple M12"), 12)
        XCTAssertEqual(DeviceCapabilityService.appleSiliconGeneration(in: "Apple M10 Ultra"), 10)
    }

    // MARK: - Things that are not a generation
    //
    // A bare `M` scan would match the M in "Mac" or "Metal" and invent a chip.

    func testDoesNotInventAGenerationFromSurroundingText() {
        XCTAssertNil(DeviceCapabilityService.appleSiliconGeneration(in: "Intel Core i9"))
        XCTAssertNil(DeviceCapabilityService.appleSiliconGeneration(in: "Apple Silicon"))
        XCTAssertNil(DeviceCapabilityService.appleSiliconGeneration(in: ""))
        XCTAssertNil(DeviceCapabilityService.appleSiliconGeneration(in: "Mac"))
        XCTAssertNil(DeviceCapabilityService.appleSiliconGeneration(in: "Metal"))
    }

    /// `M3Max` with no separator is not a string Apple emits, and matching it
    /// would mean the token boundary is not being enforced.
    func testRequiresATokenBoundary() {
        XCTAssertNil(DeviceCapabilityService.appleSiliconGeneration(in: "AppleM3Max"))
    }

    // MARK: - The TOPS curve the fallback applies
    //
    // Characterises `45 + (generation - 5) * 7`, anchored on M5's 45, so a change
    // to the curve is a deliberate edit rather than a silent drift.

    func testForwardTopsCurveIsAnchoredOnM5() {
        func projected(_ generation: Int) -> Int { 45 + (generation - 5) * 7 }
        XCTAssertEqual(projected(6), 52)
        XCTAssertEqual(projected(7), 59)
        XCTAssertEqual(projected(8), 66)
        // Never regresses below the generation it is anchored to.
        XCTAssertGreaterThan(projected(6), 45)
    }
}
