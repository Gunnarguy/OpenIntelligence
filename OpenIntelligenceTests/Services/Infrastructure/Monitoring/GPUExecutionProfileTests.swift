import XCTest
@testable import OpenIntelligenceEngine

final class GPUExecutionProfileTests: XCTestCase {
    func testLegacyLevelsMapToDiscreteProfiles() {
        XCTAssertEqual(GPUExecutionProfile(legacyLevel: 0), .efficiency)
        XCTAssertEqual(GPUExecutionProfile(legacyLevel: 0.5), .balanced)
        XCTAssertEqual(GPUExecutionProfile(legacyLevel: 0.75), .performance)
        XCTAssertEqual(GPUExecutionProfile(legacyLevel: 1), .maximum)
    }

    func testExplicitZeroMigratesAsEfficiencyInsteadOfDefaultingToBalanced() throws {
        let suiteName = "GPUExecutionProfileTests.zero.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(0.0, forKey: "gpuAccelerationLevel")

        DeviceCapabilityService.migrateGPUExecutionProfile(in: defaults)

        XCTAssertEqual(defaults.string(forKey: "gpuAccelerationProfile"), GPUExecutionProfile.efficiency.rawValue)
        XCTAssertEqual(defaults.double(forKey: "gpuAccelerationLevel"), 0.0)
    }

    func testMissingPreferenceDefaultsToBalanced() throws {
        let suiteName = "GPUExecutionProfileTests.default.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        DeviceCapabilityService.migrateGPUExecutionProfile(in: defaults)

        XCTAssertEqual(defaults.string(forKey: "gpuAccelerationProfile"), GPUExecutionProfile.balanced.rawValue)
        XCTAssertEqual(defaults.double(forKey: "gpuAccelerationLevel"), GPUExecutionProfile.balanced.legacyLevel)
    }
}
