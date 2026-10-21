//
//  VisionThermalLimitTests.swift
//  OpenIntelligenceTests
//
//  Pins `DeviceCapabilityService.thermallyLimitedVisionConcurrency`.
//  It lowers the Vision concurrency ceiling on a Mac that heats up, since the chip alone cannot say whether
//  the Mac has a fan (5.7).
//

import Foundation
import XCTest

@testable import OpenIntelligenceEngine

final class VisionThermalLimitTests: XCTestCase {

    func testNominalThermalStateKeepsTheCeiling() {
        XCTAssertEqual(DeviceCapabilityService.thermallyLimitedVisionConcurrency(ceiling: 8, thermalState: .nominal), 8)
    }

    func testFairHalvesAndSeriousAndCriticalLower() {
        XCTAssertEqual(DeviceCapabilityService.thermallyLimitedVisionConcurrency(ceiling: 8, thermalState: .fair), 4)
        XCTAssertEqual(DeviceCapabilityService.thermallyLimitedVisionConcurrency(ceiling: 8, thermalState: .serious), 2)
        XCTAssertEqual(
            DeviceCapabilityService.thermallyLimitedVisionConcurrency(ceiling: 8, thermalState: .critical), 1)
    }

    func testNeverRaisesALowCeiling() {
        XCTAssertEqual(DeviceCapabilityService.thermallyLimitedVisionConcurrency(ceiling: 1, thermalState: .fair), 1)
        XCTAssertEqual(DeviceCapabilityService.thermallyLimitedVisionConcurrency(ceiling: 2, thermalState: .serious), 2)
        XCTAssertEqual(DeviceCapabilityService.thermallyLimitedVisionConcurrency(ceiling: 4, thermalState: .fair), 2)
    }
}
