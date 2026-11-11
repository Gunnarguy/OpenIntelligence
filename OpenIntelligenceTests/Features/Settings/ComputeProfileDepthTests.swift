//
//  ComputeProfileDepthTests.swift
//  OpenIntelligenceTests
//
//  The compute profile's ramp (5.8): depth never drops below Balanced's 5.7 values and climbs from Performance to
//  Maximum; Efficiency saves energy only by doing fewer things at once.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class ComputeProfileDepthTests: XCTestCase {
    typealias Depth = DeviceCapabilityService.Depth

    func testBalancedKeepsTheValuesFiveSevenShipped() {
        let standard = Depth.forProfile(.balanced)
        XCTAssertEqual(standard.rescueRegions, 12)
        XCTAssertEqual(standard.rerankCeiling, 250)
        XCTAssertEqual(standard.rerankFloor, 100)
        XCTAssertEqual(standard.keywordLimit, 60)
        XCTAssertFalse(standard.fullDetailPages)
        XCTAssertEqual(Depth.forProfile(.efficiency), standard, "Efficiency must not read or search less than Balanced")
    }

    func testDepthClimbsEveryStepFromPerformance() {
        let ladder = GPUExecutionProfile.allCases.map(Depth.forProfile)
        for (lower, higher) in zip(ladder, ladder.dropFirst()) {
            XCTAssertLessThanOrEqual(lower.rescueRegions, higher.rescueRegions)
            XCTAssertLessThanOrEqual(lower.rerankCeiling, higher.rerankCeiling)
            XCTAssertLessThanOrEqual(lower.rerankFloor, higher.rerankFloor)
            XCTAssertLessThanOrEqual(lower.keywordLimit, higher.keywordLimit)
        }
        let performance = Depth.forProfile(.performance)
        XCTAssertGreaterThan(performance.rerankCeiling, Depth.standard.rerankCeiling)
        XCTAssertLessThan(performance.rerankCeiling, Depth.maximum.rerankCeiling)
        XCTAssertTrue(Depth.forProfile(.maximum).fullDetailPages)
        XCTAssertEqual(Depth.maximum.rerankCeiling, DeviceCapabilityService.MaximumFidelity.rerankCeiling)
    }

    func testEfficiencyHalvesWhatRunsAtOnceAndNothingElseChanges() {
        XCTAssertEqual(DeviceCapabilityService.paced(4, for: .efficiency), 2)
        XCTAssertEqual(DeviceCapabilityService.paced(3, for: .efficiency), 2)
        XCTAssertEqual(DeviceCapabilityService.paced(1, for: .efficiency), 1)
        for profile in [GPUExecutionProfile.balanced, .performance, .maximum] {
            XCTAssertEqual(DeviceCapabilityService.paced(12, for: profile), 12, "\(profile) keeps the chip's ceiling")
        }
    }
}
