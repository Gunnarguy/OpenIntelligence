//
//  AppleDeviceCatalogTests.swift
//  OpenIntelligenceTests
//
//  The device facts the Active Device card, About, the metrics bar and onboarding show (5.8): only what Apple
//  published or the hardware reports. Until 5.8 every chip had a Neural Engine figure (Apple gives one for ten),
//  the iPhone 18 Pro Max and Duo were called "A20" and the iPhone Air "A19", and four iPad families were named as
//  other iPads.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class AppleDeviceCatalogTests: XCTestCase {

    // MARK: Neural Engine figures

    func testOnlyApplesPublishedFiguresAreReturned() {
        let published: [String: Double] = [
            "A14": 11, "A14 Bionic": 11, "A15 Bionic": 15.8, "A16": 17, "A16 Bionic": 17,
            "M1": 11, "M1 Ultra": 22, "M2": 15.8, "M2 Pro": 15.8, "M2 Max": 15.8, "M2 Ultra": 31.6, "M4": 38,
        ]
        for (chip, tops) in published {
            XCTAssertEqual(AppleDeviceCatalog.neuralEngineTOPS(forChip: chip), tops, chip)
        }
        for chip in [
            "A17 Pro", "A18", "A18 Pro", "A19", "A19 Pro", "A20 Pro", "M1 Pro", "M1 Max", "M3", "M3 Pro",
            "M3 Max", "M3 Ultra", "M4 Pro", "M4 Max", "M5", "M5 Pro", "M5 Max", "M5 Ultra", "M6",
        ] {
            XCTAssertNil(AppleDeviceCatalog.neuralEngineTOPS(forChip: chip), "Apple publishes no figure for \(chip)")
        }
        XCTAssertEqual(AppleDeviceCatalog.neuralEngineFigure(forChip: "A16")?.text, "nearly 17", "Apple's own words")
        XCTAssertEqual(AppleDeviceCatalog.topsDescription(38), "38")
        XCTAssertEqual(AppleDeviceCatalog.topsDescription(15.8), "15.8")
    }

    // MARK: Chip names

    func testChipComesFromTheMetalDeviceName() {
        XCTAssertEqual(AppleDeviceCatalog.chipName(fromMetalDeviceName: "Apple A18 Pro GPU"), "A18 Pro")
        XCTAssertEqual(AppleDeviceCatalog.chipName(fromMetalDeviceName: "Apple M3 Pro"), "M3 Pro")
        XCTAssertNil(AppleDeviceCatalog.chipName(fromMetalDeviceName: "Metal unavailable"))
        XCTAssertNil(AppleDeviceCatalog.chipName(fromMetalDeviceName: "Apple Paravirtual device"))
        XCTAssertEqual(
            DeviceCapabilityService.resolvedChipName(
                tableName: "A18 Pro", metalDeviceName: "Apple M3 Pro", isSimulator: true),
            "A18 Pro", "The Simulator's Metal device is the Mac's, so the simulated device keeps its own chip")
        XCTAssertEqual(
            DeviceCapabilityService.resolvedChipName(
                tableName: "iPhone", metalDeviceName: "Apple A21 Pro GPU", isSimulator: false),
            "A21 Pro", "A device newer than the table is named as Metal names it")
    }

    func testModelsAndChipsMatchApplesSpecs() {
        let expected: [String: (String, String)] = [
            "iPhone16,1": ("iPhone 15 Pro", "A17 Pro"),
            "iPhone17,2": ("iPhone 16 Pro Max", "A18 Pro"),
            "iPhone17,5": ("iPhone 16e", "A18"),
            "iPhone18,3": ("iPhone 17", "A19"),
            "iPhone18,4": ("iPhone Air", "A19 Pro"),
            "iPhone18,5": ("iPhone 17e", "A19"),
            "iPhone19,3": ("iPhone 18 Pro Max", "A20 Pro"),
            "iPhone19,4": ("iPhone Duo", "A20 Pro"),
            "iPad13,16": ("iPad Air (5th generation)", "M1"),
            "iPad13,18": ("iPad (10th generation)", "A14 Bionic"),
            "iPad15,7": ("iPad (A16)", "A16"),
            "iPad16,9": ("iPad Air 11-inch (M4)", "M4"),
            "iPad19,1": ("iPad mini (A20 Pro)", "A20 Pro"),
        ]
        for (identifier, (name, chip)) in expected {
            XCTAssertEqual(
                AppleDeviceCatalog.model(forIdentifier: identifier), .init(name: name, chip: chip), identifier)
        }
        XCTAssertNil(AppleDeviceCatalog.model(forIdentifier: "iPhone99,1"))
    }

    func testIPhonesKeepTheirTiersAndGetApplesChipNames() {
        XCTAssertEqual(DeviceCapabilityService.detectiPhoneCapability(identifier: "iPhone16,2").1, "A17 Pro")
        XCTAssertEqual(DeviceCapabilityService.detectiPhoneCapability(identifier: "iPhone19,3").1, "A20 Pro")
        XCTAssertEqual(DeviceCapabilityService.detectiPhoneCapability(identifier: "iPhone19,3").0, .ultraAdvanced)
        XCTAssertEqual(DeviceCapabilityService.detectiPhoneCapability(identifier: "iPhone15,4").0, .unsupported)
        XCTAssertEqual(DeviceCapabilityService.detectiPhoneCapability(identifier: "iPhone17,1").0, .enhanced)
        XCTAssertEqual(
            DeviceCapabilityService.detectiPhoneCapability(identifier: "iPhone21,1").1, "iPhone",
            "An unknown model is not given an invented chip name")
    }

    func testIPadFamiliesAreNotMistakenForOthers() {
        let air5 = DeviceCapabilityService.detectiPadCapabilityFull(identifier: "iPad13,16")
        XCTAssertEqual(air5.2, .iPadAir)
        XCTAssertEqual(air5.0, .enhanced)
        XCTAssertEqual(DeviceCapabilityService.detectiPadCapabilityFull(identifier: "iPad13,18").0, .unsupported)
        XCTAssertEqual(DeviceCapabilityService.detectiPadCapabilityFull(identifier: "iPad15,7").0, .unsupported)
        XCTAssertEqual(DeviceCapabilityService.detectiPadCapabilityFull(identifier: "iPad15,3").0, .advanced)
        XCTAssertEqual(DeviceCapabilityService.detectiPadCapabilityFull(identifier: "iPad16,9").2, .iPadAir)
        XCTAssertEqual(DeviceCapabilityService.detectiPadCapabilityFull(identifier: "iPad16,4").2, .iPadPro)
        let mini = DeviceCapabilityService.detectiPadCapabilityFull(identifier: "iPad19,2")
        XCTAssertEqual(mini.1, "A20 Pro")
        XCTAssertEqual(mini.2, .iPadMini)
    }

    func testMacTiersAreUnchangedForKnownChips() {
        XCTAssertEqual(DeviceCapabilityService.macTier(forChip: "M1"), .enhanced)
        XCTAssertEqual(DeviceCapabilityService.macTier(forChip: "M1 Max"), .enhanced)
        XCTAssertEqual(DeviceCapabilityService.macTier(forChip: "M1 Ultra"), .ultraAdvanced)
        XCTAssertEqual(DeviceCapabilityService.macTier(forChip: "M3 Pro"), .ultraAdvanced)
        XCTAssertEqual(DeviceCapabilityService.macTier(forChip: "M6"), .ultraAdvanced)
        XCTAssertEqual(DeviceCapabilityService.macTier(forChip: "A18 Pro"), .advanced, "MacBook Neo")
    }

    // MARK: Memory

    func testMemoryIsShownAsReported() {
        XCTAssertEqual(AppleDeviceCatalog.memoryDescription(gigabytes: 7.47), "7.5 GB")
        XCTAssertEqual(AppleDeviceCatalog.memoryDescription(gigabytes: 18.0), "18 GB")
        XCTAssertEqual(AppleDeviceCatalog.memoryDescription(gigabytes: 11.98), "12 GB")
    }
}
