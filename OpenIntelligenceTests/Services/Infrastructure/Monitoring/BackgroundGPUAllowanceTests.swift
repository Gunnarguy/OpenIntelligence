import XCTest

@testable import OpenIntelligenceEngine

/// Which GPU profiles let an import that goes on in the background ask iOS for the GPU, on each device (5.7).
///
/// Settings states this for the device it runs on and `BackgroundTaskService` applies it, and both read
/// `BackgroundGPUAllowance`. Until 5.7 the rule lived only in `BackgroundTaskService`, and the profile list in Settings
/// said nothing about the background at all.
final class BackgroundGPUAllowanceTests: XCTestCase {
    private func profiles(_ formFactor: DeviceFormFactor, _ tier: DeviceCapabilityTier) -> [GPUExecutionProfile] {
        BackgroundGPUAllowance.profiles(formFactor: formFactor, tier: tier)
    }

    private func allowance(_ formFactor: DeviceFormFactor, _ tier: DeviceCapabilityTier) -> BackgroundGPUAllowance {
        BackgroundGPUAllowance.forDevice(formFactor: formFactor, tier: tier)
    }

    /// An iPhone 15 Pro (A17 Pro) is capped at 0.9 and needs 0.85, so only Maximum reaches it, and only on charge.
    func testIPhone15ProNeedsMaximumAndACharger() {
        XCTAssertEqual(profiles(.iPhone, .baseline), [.maximum])
        XCTAssertTrue(allowance(.iPhone, .baseline).chargingOnly)
    }

    func testIPhone16AndLaterTakePerformanceAndMaximum() {
        XCTAssertEqual(profiles(.iPhone, .enhanced), [.performance, .maximum])
        XCTAssertEqual(profiles(.iPhone, .advanced), [.performance, .maximum])
        XCTAssertFalse(allowance(.iPhone, .enhanced).chargingOnly)
        XCTAssertFalse(allowance(.iPhone, .advanced).chargingOnly)
    }

    /// The iPad mini's ceiling (0.7) is under its background threshold (0.8), so no profile reaches it.
    func testIPadMiniNeverGetsTheGPUInTheBackground() {
        XCTAssertEqual(DeviceCapabilityService.maxSafeGPUAccelerationLevel(formFactor: .iPadMini, tier: .baseline), 0.7)
        XCTAssertEqual(profiles(.iPadMini, .baseline), [])
    }

    func testIPadAirAndProTakePerformanceAndMaximum() {
        XCTAssertEqual(profiles(.iPadAir, .ultraAdvanced), [.performance, .maximum])
        XCTAssertEqual(profiles(.iPadPro, .ultraAdvanced), [.performance, .maximum])
    }

    func testEfficiencyAndBalancedNeverAskForTheGPU() {
        for formFactor in [DeviceFormFactor.iPhone, .iPadMini, .iPadAir, .iPadPro, .mac, .unknown] {
            for tier in [DeviceCapabilityTier.unsupported, .baseline, .enhanced, .advanced, .ultraAdvanced] {
                let admitted = profiles(formFactor, tier)
                XCTAssertFalse(admitted.contains(.efficiency), "\(formFactor) \(tier)")
                XCTAssertFalse(admitted.contains(.balanced), "\(formFactor) \(tier)")
            }
        }
    }

    func testUnsupportedAndUnknownDevicesNeverAsk() {
        XCTAssertEqual(profiles(.iPhone, .unsupported), [])
        XCTAssertEqual(profiles(.unknown, .ultraAdvanced), [])
    }

    /// The thresholds and battery floors `BackgroundTaskService` applied before they moved here, unchanged.
    func testThresholdsAndBatteryFloorsAreTheOnesTheImportUsed() {
        XCTAssertEqual(allowance(.iPhone, .baseline).requiredLevel, 0.85)
        XCTAssertEqual(allowance(.iPhone, .enhanced).requiredLevel, 0.75)
        XCTAssertEqual(allowance(.iPhone, .advanced).requiredLevel, 0.65)
        XCTAssertEqual(allowance(.iPadMini, .baseline).requiredLevel, 0.8)
        XCTAssertEqual(allowance(.iPadAir, .ultraAdvanced).requiredLevel, 0.7)
        XCTAssertEqual(allowance(.iPadPro, .ultraAdvanced).requiredLevel, 0.6)
        XCTAssertEqual(allowance(.iPhone, .baseline).minimumBatteryPercent, 50)
        XCTAssertEqual(allowance(.iPhone, .enhanced).minimumBatteryPercent, 35)
        XCTAssertEqual(allowance(.iPhone, .unsupported).minimumBatteryPercent, 35)
        XCTAssertEqual(allowance(.iPadMini, .baseline).minimumBatteryPercent, 40)
        XCTAssertEqual(allowance(.iPadAir, .ultraAdvanced).minimumBatteryPercent, 30)
        XCTAssertEqual(allowance(.iPadPro, .ultraAdvanced).minimumBatteryPercent, 25)
        XCTAssertEqual(allowance(.mac, .ultraAdvanced).minimumBatteryPercent, -1)
        XCTAssertEqual(allowance(.unknown, .baseline).minimumBatteryPercent, 50)
    }

    /// The ceilings the instance property applied before it became a pure function.
    func testCeilingsAreUnchanged() {
        let ceiling = DeviceCapabilityService.maxSafeGPUAccelerationLevel(formFactor:tier:)
        XCTAssertEqual(ceiling(.mac, .ultraAdvanced), 1.0)
        XCTAssertEqual(ceiling(.iPadPro, .ultraAdvanced), 1.0)
        XCTAssertEqual(ceiling(.iPadAir, .ultraAdvanced), 1.0)
        XCTAssertEqual(ceiling(.iPadAir, .advanced), 1.0)
        XCTAssertEqual(ceiling(.iPadAir, .enhanced), 0.9)
        XCTAssertEqual(ceiling(.iPhone, .unsupported), 0.6)
        XCTAssertEqual(ceiling(.iPhone, .baseline), 0.9)
        XCTAssertEqual(ceiling(.iPhone, .enhanced), 1.0)
        XCTAssertEqual(ceiling(.unknown, .baseline), 0.6)
    }
}
