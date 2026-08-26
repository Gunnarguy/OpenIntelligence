import CoreML
import Foundation
import XCTest

@testable import OpenIntelligenceEngine

/// The execution profile ladder must never remove hardware as it climbs.
///
/// It used to. `Maximum` returned `.cpuAndGPU` for Core ML while `Performance`
/// returned `.all`, so the highest setting *excluded* the Neural Engine and was
/// strictly less capable than the one below it. For embeddings the inversion sat a
/// step lower still: `Balanced` returned `.all` while both `Performance` and
/// `Maximum` returned `.cpuAndGPU`, which meant turning the profile up made
/// document ingestion worse — the workload where it matters most.
///
/// These are pure functions over the profile enum, so the branch under test is the
/// branch that ships.
final class ExecutionProfileLadderTests: XCTestCase {
    /// Ascending order of the ladder as presented to the user.
    private let ladder: [GPUExecutionProfile] = [.efficiency, .balanced, .performance, .maximum]

    // MARK: - The inversion that prompted this

    func testMaximumDoesNotDropTheNeuralEngine() {
        XCTAssertEqual(DeviceCapabilityService.coreMLComputeUnits(for: .maximum), .all)
        XCTAssertNotEqual(DeviceCapabilityService.coreMLComputeUnits(for: .maximum), .cpuAndGPU)
    }

    func testTurningTheProfileUpNeverWorsensEmbedding() {
        // Balanced was the only profile using every engine. Everything above it must
        // now be at least as capable.
        let balanced = DeviceCapabilityService.embeddingComputeUnits(for: .balanced)
        XCTAssertEqual(balanced, .all)
        XCTAssertEqual(DeviceCapabilityService.embeddingComputeUnits(for: .performance), .all)
        XCTAssertEqual(DeviceCapabilityService.embeddingComputeUnits(for: .maximum), .all)
    }

    // MARK: - Monotonicity
    //
    // `.cpuAndGPU` is deliberately absent from both ladders: it is the only option
    // that excludes the Neural Engine, and excluding a unit is never an upgrade.

    func testNoProfileExcludesTheNeuralEngine() {
        for profile in ladder {
            XCTAssertNotEqual(
                DeviceCapabilityService.coreMLComputeUnits(for: profile), .cpuAndGPU,
                "\(profile.displayName) excludes the Neural Engine for Core ML"
            )
            XCTAssertNotEqual(
                DeviceCapabilityService.embeddingComputeUnits(for: profile), .cpuAndGPU,
                "\(profile.displayName) excludes the Neural Engine for embedding"
            )
        }
    }

    /// Ranks the options by how much silicon they permit. `.all` is the ceiling.
    private func breadth(_ units: MLComputeUnits) -> Int {
        switch units {
        case .cpuOnly: return 1
        case .cpuAndNeuralEngine, .cpuAndGPU: return 2
        case .all: return 3
        @unknown default: return 0
        }
    }

    func testBreadthNeverDecreasesGoingUpTheLadder() {
        for (lower, higher) in zip(ladder, ladder.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                breadth(DeviceCapabilityService.coreMLComputeUnits(for: higher)),
                breadth(DeviceCapabilityService.coreMLComputeUnits(for: lower)),
                "Core ML narrows going from \(lower.displayName) to \(higher.displayName)"
            )
            XCTAssertGreaterThanOrEqual(
                breadth(DeviceCapabilityService.embeddingComputeUnits(for: higher)),
                breadth(DeviceCapabilityService.embeddingComputeUnits(for: lower)),
                "Embedding narrows going from \(lower.displayName) to \(higher.displayName)"
            )
        }
    }

    // MARK: - What the picker promises
    //
    // The cards show CPU / ANE / GPU badges per profile. Those must describe the
    // routes above rather than drift from them.

    func testEveryProfileUsesCPUAndNeuralEngine() {
        for profile in ladder {
            XCTAssertTrue(profile.engagement.usesCPU, "\(profile.displayName) claims no CPU")
            XCTAssertTrue(
                profile.engagement.usesNeuralEngine,
                "\(profile.displayName) claims no Neural Engine"
            )
        }
    }

    func testOnlyEfficiencyLeavesTheGPUAlone() {
        XCTAssertFalse(GPUExecutionProfile.efficiency.engagement.usesGPU)
        XCTAssertTrue(GPUExecutionProfile.balanced.engagement.usesGPU)
        XCTAssertTrue(GPUExecutionProfile.performance.engagement.usesGPU)
        XCTAssertTrue(GPUExecutionProfile.maximum.engagement.usesGPU)
    }

    func testEngagedUnitCountNeverDecreases() {
        for (lower, higher) in zip(ladder, ladder.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                higher.engagement.unitCount, lower.engagement.unitCount,
                "\(higher.displayName) engages fewer units than \(lower.displayName)"
            )
        }
    }

    /// Every card needs something to say, and the expanded row needs something to
    /// list. An empty string would render as a blank card.
    func testEveryProfileExplainsItself() {
        for profile in ladder {
            XCTAssertFalse(
                profile.engagement.summary.isEmpty,
                "\(profile.displayName) has no summary"
            )
            XCTAssertFalse(
                profile.engagement.effects.isEmpty,
                "\(profile.displayName) lists no effects"
            )
        }
    }

    /// Climbing the ladder should add detail, not lose it.
    func testEffectCountNeverDecreases() {
        for (lower, higher) in zip(ladder, ladder.dropFirst()) {
            XCTAssertGreaterThanOrEqual(
                higher.engagement.effects.count, lower.engagement.effects.count,
                "\(higher.displayName) lists fewer effects than \(lower.displayName)"
            )
        }
    }
}
