//
//  DeviceFiguresTests.swift
//  OpenIntelligenceTests
//
//  The device audit of 2026-11-16: every figure the app shows or acts on must be true for the device it runs on, on
//  every device Apple lists for Apple Intelligence (support.apple.com/en-us/121115, published 2026-11-05). These pin the
//  three rules that were wrong: chip generations compare as numbers (an M6 matched no "M5"/"M4" branch), answer quality
//  is the same on every device (the tiers set it from a table that disagreed with itself), and the eligible-device copy
//  names every device on Apple's list.
//

import XCTest

@testable import OpenIntelligence

final class DeviceFiguresTests: XCTestCase {
    func testChipFamilyAndGenerationReadsEveryNameShape() {
        let cases: [(String, Character, Int)] = [
            ("Apple M6 Max", "M", 6), ("Apple M5 Ultra", "M", 5), ("Apple M1", "M", 1), ("Apple M12 Pro", "M", 12),
            ("Apple A18 Pro GPU", "A", 18), ("Apple A20 Pro", "A", 20), ("A17 Pro", "A", 17),
        ]
        for (name, family, generation) in cases {
            let parsed = DeviceCapabilityService.chipFamilyAndGeneration(in: name)
            XCTAssertEqual(parsed?.family, family, name)
            XCTAssertEqual(parsed?.generation, generation, name)
        }
        XCTAssertNil(DeviceCapabilityService.chipFamilyAndGeneration(in: "Apple Silicon"))
        XCTAssertNil(DeviceCapabilityService.chipFamilyAndGeneration(in: "iPad"))
    }

    func testAnswerQualityIsTheSameOnEverySupportedTier() {
        let measured = AdaptivePipelineConfig.base(for: .ultraAdvanced)
        for tier in [DeviceCapabilityTier.baseline, .enhanced, .advanced, .ultraAdvanced] {
            let config = AdaptivePipelineConfig.base(for: tier)
            XCTAssertEqual(config.maxRetrievalCandidates, measured.maxRetrievalCandidates, "\(tier)")
            XCTAssertEqual(config.enableIterativeRetrieval, measured.enableIterativeRetrieval, "\(tier)")
            XCTAssertEqual(config.enableParentDocumentRetrieval, measured.enableParentDocumentRetrieval, "\(tier)")
            XCTAssertEqual(config.enableContextualCompression, measured.enableContextualCompression, "\(tier)")
            XCTAssertEqual(config.minSimilarityThreshold, measured.minSimilarityThreshold, "\(tier)")
            XCTAssertEqual(config.mmrLambda, measured.mmrLambda, "\(tier)")
        }
    }

    func testDeepThinkAimsForOneTargetOnThisDevice() {
        let config = DeviceCapabilityService.shared.optimizedAgenticConfig()
        XCTAssertEqual(config.confidenceThreshold, 0.95, accuracy: 0.0001)
        XCTAssertGreaterThanOrEqual(config.maxSteps, 12)
    }

    func testTheEligibleDeviceCopyNamesEveryDeviceOnApplesList() {
        let copy = AppleIntelligenceCopy.supportedDevices
        for name in ["iPhone 15 Pro", "iPhone Air", "iPhone Duo", "A17 Pro", "A20 Pro", "M1", "MacBook Neo"] {
            XCTAssertTrue(copy.contains(name), "missing \(name)")
        }
    }

    func testAnUnknownNewIPadGetsTheAirsPowerSettings() {
        let (_, _, formFactor) = DeviceCapabilityService.detectiPadCapabilityFull(identifier: "iPad20,1")
        XCTAssertEqual(formFactor, .iPadAir)
    }

    func testNeuralEngineCoresFollowApplesSpecPages() {
        XCTAssertEqual(AppleDeviceCatalog.neuralEngineCores(forChip: "A18 Pro"), "16 cores")
        XCTAssertEqual(AppleDeviceCatalog.neuralEngineCores(forChip: "A17 Pro"), "16 cores")
        XCTAssertEqual(AppleDeviceCatalog.neuralEngineCores(forChip: "A19"), "16 cores")
        XCTAssertEqual(AppleDeviceCatalog.neuralEngineCores(forChip: "M3 Pro"), "16 cores")
        XCTAssertEqual(AppleDeviceCatalog.neuralEngineCores(forChip: "M5 Ultra"), "32 cores")
        XCTAssertEqual(AppleDeviceCatalog.neuralEngineCores(forChip: "M6"), "2 × 16 cores")
        XCTAssertEqual(AppleDeviceCatalog.neuralEngineCores(forChip: "A20 Pro"), "2 × 16 cores")
        XCTAssertEqual(AppleDeviceCatalog.neuralEngineCores(forChip: "A20 Pro", iPadMiniStorageGB: 512), "2 × 16 cores")
        XCTAssertEqual(AppleDeviceCatalog.neuralEngineCores(forChip: "A20 Pro", iPadMiniStorageGB: 128), "16 cores")
        XCTAssertNil(AppleDeviceCatalog.neuralEngineCores(forChip: "Chip not identified"))
    }
}
