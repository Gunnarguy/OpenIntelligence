//
//  ChunkingLimitsTests.swift
//  OpenIntelligenceTests
//
//  Pins the chunking ceilings that Library Settings presents to users.
//
//  Why this exists. The Library Settings sliders offered a 100...600 target and a 0...200
//  overlap while `DocumentProcessor` built its config as `min(value, 260)` and `min(value, 50)`,
//  so more than half of each track was discarded in silence and the Balanced preset promised a
//  "280-400 word target" the clamp made unreachable. Both sides were literals typed near each
//  other rather than derived from one another.
//
//  The fix was to name the ceilings on `ChunkingConfig` and have both the pipeline and the
//  sliders read them. That removes the drift by construction, so what is left to test is the
//  arithmetic between the constants, which is the part a future edit can still get wrong: raising
//  `safeMaxSize` without revisiting `maxTargetSize` would quietly reintroduce a target the
//  embedding step cannot hold.
//

@testable import OpenIntelligence
import XCTest

final class ChunkingLimitsTests: XCTestCase {
    private typealias Limits = SemanticChunker.ChunkingConfig

    /// The target ceiling must stay below the hard ceiling, with room for variance.
    ///
    /// `safeMaxSize` is itself bounded by the Core ML model's 510 token limit minus the roughly
    /// 30 word contextual prefix the embedding step prepends. If these ever meet, a chunk at the
    /// target size can be truncated during embedding, which loses text with no error.
    func testTargetCeilingLeavesHeadroomUnderTheHardCeiling() {
        XCTAssertLessThan(
            Limits.maxTargetSize, Limits.safeMaxSize,
            "A target at or above the hard ceiling can be truncated during embedding."
        )
        XCTAssertEqual(
            Limits.maxTargetSize, Limits.safeMaxSize - 50,
            "The 50 word gap is the variance allowance. Change it deliberately, not by accident."
        )
    }

    /// The slider's lower bound must be below its upper bound and produce usable chunks.
    func testTargetRangeIsUsable() {
        XCTAssertLessThan(Limits.minTargetSize, Limits.maxTargetSize)
        XCTAssertGreaterThan(
            Limits.minTargetSize, Limits.maxOverlap,
            "A target at or below the overlap would repeat more than it advances."
        )
    }

    /// Overlap must stay a fraction of the target rather than approaching it.
    func testOverlapStaysAFractionOfTheTarget() {
        XCTAssertLessThan(
            Limits.maxOverlap, Limits.maxTargetSize / 2,
            "Overlap at half the target roughly doubles the index for no retrieval gain."
        )
    }

    /// The shipped defaults must be values the pipeline will actually honour.
    ///
    /// This is the direct regression: a default above the clamp is a setting the app reports and
    /// then discards, which is exactly what the sliders were doing.
    func testDefaultsSurviveTheClampUnchanged() {
        let config = SemanticChunker.ChunkingConfig()

        XCTAssertEqual(
            min(config.targetSize, Limits.maxTargetSize), config.targetSize,
            "The default target is above the ceiling the pipeline enforces."
        )
        XCTAssertEqual(
            min(config.overlap, Limits.maxOverlap), config.overlap,
            "The default overlap is above the ceiling the pipeline enforces."
        )
        XCTAssertLessThanOrEqual(config.maxSize, Limits.safeMaxSize)
        XCTAssertLessThan(config.minSize, config.targetSize)
    }

    /// Every shipped preset must declare values the pipeline will honour.
    ///
    /// This is the check the previous test was missing, and it found a real one: `narrative`,
    /// which `recommended(for:)` selects for Word, Excel, PowerPoint, audio and video, declared a
    /// 280 word target and 55 words of overlap against enforced ceilings of 260 and 50. Those
    /// documents were already being chunked at 260/50, so the preset was asking for numbers it
    /// never got. A preset that cannot be honoured is the same defect as a slider that cannot be
    /// honoured, one layer down.
    func testEveryPresetSurvivesTheClampUnchanged() {
        let presets: [(String, SemanticChunker.ChunkingConfig)] = [
            ("balanced", SemanticChunker.ChunkingConfig()),
            ("technicalReference", .technicalReference),
            ("narrative", .narrative),
            ("code", .code),
        ]

        for (name, config) in presets {
            XCTAssertEqual(
                min(config.targetSize, Limits.maxTargetSize), config.targetSize,
                "Preset \(name) asks for a \(config.targetSize) word target, which the pipeline clamps to \(Limits.maxTargetSize)."
            )
            XCTAssertEqual(
                min(config.overlap, Limits.maxOverlap), config.overlap,
                "Preset \(name) asks for \(config.overlap) words of overlap, which the pipeline clamps to \(Limits.maxOverlap)."
            )
            XCTAssertLessThanOrEqual(
                config.maxSize, Limits.safeMaxSize,
                "Preset \(name) exceeds the hard ceiling, so its chunks can be truncated during embedding."
            )
            XCTAssertLessThan(config.overlap, config.targetSize, "Preset \(name) overlaps more than it advances.")
        }
    }

    /// The per-file-type defaults must stay genuinely different from each other.
    ///
    /// This is what makes the manual sliders unnecessary for almost everyone: the app already
    /// picks a different shape per document type, and code specifically turns topic detection off
    /// because source files have no prose transitions. If these ever collapse to one value, the
    /// "leave it alone" guidance on the settings screen stops being true.
    func testPerFileTypeDefaultsRemainDistinct() {
        let code = SemanticChunker.ChunkingConfig.code
        let technical = SemanticChunker.ChunkingConfig.technicalReference

        XCTAssertLessThan(
            code.targetSize, technical.targetSize,
            "Code should chunk smaller than prose; it tokenizes worse per word."
        )
        XCTAssertFalse(
            code.useTopicDetection,
            "Topic detection looks for English prose transitions, which source files do not have."
        )
        XCTAssertTrue(technical.useTopicDetection)
    }
}
