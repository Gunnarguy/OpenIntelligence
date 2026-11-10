//
//  XRayPlacementTests.swift
//  OpenIntelligenceTests
//
//  The X-Ray's outlines (5.8): which layout a model identifier gets, and where a portrait outline lands in each
//  interface orientation. Until 5.8 the two landscape cases were swapped, and the non-Pro iPhone 17 and iPhone Air
//  were mapped to the 17 Pro and 17 Pro Max.
//

import CoreGraphics
import XCTest

@testable import OpenIntelligence

@MainActor
final class XRayPlacementTests: XCTestCase {

    // MARK: Identifiers

    func testIdentifiersMapToTheirOwnModels() {
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPhone18,3"), .iPhone17)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPhone18,4"), .iPhoneAir)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPhone19,2"), .iPhone18Pro)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPhone18,1"), .iPhone17Pro)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPhone18,2"), .iPhone17ProMax)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPhone18,5"), .iPhone17e)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPhone17,5"), .iPhone16e)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPhone19,3"), .iPhone18ProMax)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPhone19,7"), .iPhone18ProMax)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPad16,1"), .iPadMini)
        // iPad sizes, by Xcode 27's Simulator device profiles: 16,4 and 17,2 are 11-inch, 16,6 and 17,4 are 13-inch.
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPad16,3"), .iPadPro11)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPad16,4"), .iPadPro11)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPad16,6"), .iPadPro13)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPad17,2"), .iPadPro11)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPad17,4"), .iPadPro13)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPad14,8"), .iPadAir11)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPad14,11"), .iPadAir13)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPad15,3"), .iPadAir11)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPad15,5"), .iPadAir13)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPad16,9"), .iPadAir11)
        XCTAssertEqual(DeviceComponentLayout.layout(forIdentifier: "iPad16,11"), .iPadAir13)
    }

    /// iPhone Duo's insides are not mapped, so it draws nothing rather than an outline in the wrong place.
    func testUnmappedModelsDrawNoOutline() {
        for identifier in ["iPhone19,4", "iPhone99,1", "iPad99,1", "arm64", ""] {
            let layout = DeviceComponentLayout.layout(forIdentifier: identifier)
            XCTAssertEqual(layout, .unknown, identifier)
            XCTAssertNil(layout.socPlacement, identifier)
            XCTAssertNil(layout.tapticRect, identifier)
        }
    }

    /// Where the chip was measured, and nothing where it was not: no estimate is ever drawn. iPads have no Taptic Engine.
    func testChipsAreWhereTheyWereMeasured() throws {
        // 16 Pro Max (iFixit chip ID fitted on 5 screw holes of the CT): left column, a third of the way down.
        let proMax = try XCTUnwrap(DeviceComponentLayout.iPhone16ProMax.socPlacement)
        XCTAssertLessThan(proMax.rect.maxX, 0.35)
        XCTAssertGreaterThan(proMax.rect.minY, 0.25)
        // iPhone Air: in the camera plateau at the top, not the lower band.
        let air = try XCTUnwrap(DeviceComponentLayout.iPhoneAir.socPlacement)
        XCTAssertLessThan(air.rect.maxY, 0.2)
        // 17 Pro: right of centre, about a third of the way down (the plate under the display is the NAND, left of it).
        let pro17 = try XCTUnwrap(DeviceComponentLayout.iPhone17Pro.socPlacement)
        XCTAssertGreaterThan(pro17.rect.minX, 0.3)
        // iPad mini: in the right-hand board column, below the middle.
        let mini = try XCTUnwrap(DeviceComponentLayout.iPadMini.socPlacement)
        XCTAssertGreaterThan(mini.rect.minX, 0.7)
        XCTAssertGreaterThan(mini.rect.minY, 0.5)
        // No photo of the chip on these boards: no outline at all.
        XCTAssertNil(DeviceComponentLayout.iPadProM1M2.socPlacement)
        XCTAssertNil(DeviceComponentLayout.iPadAirM1.socPlacement)
        XCTAssertNil(DeviceComponentLayout.iPadPro13.tapticRect)
        XCTAssertNotNil(DeviceComponentLayout.iPhone17.tapticRect)
    }

    /// Two independent passes measured these from different images; the code's value must sit within 0.02 of both.
    func testPlacementsAgreeWithTheSecondPass() throws {
        let second: [(DeviceComponentLayout, CGRect)] = [
            (.iPhone18Pro, DeviceComponentLayout.displayRect(x: 0.29...0.50, y: 0.29...0.40)),
            (.iPhone18ProMax, DeviceComponentLayout.displayRect(x: 0.35...0.54, y: 0.27...0.37)),
            (.iPadPro13, DeviceComponentLayout.displayRect(x: 0.467...0.605, y: 0.424...0.529)),
            (.iPadMini, DeviceComponentLayout.displayRect(x: 0.77...0.89, y: 0.59...0.66)),
            (.iPhone16e, DeviceComponentLayout.displayRect(x: 0.09...0.28, y: 0.39...0.51)),
        ]
        for (layout, other) in second {
            let rect = try XCTUnwrap(layout.socPlacement?.rect, layout.displayName)
            XCTAssertEqual(rect.midX, other.midX, accuracy: 0.02, layout.displayName)
            XCTAssertEqual(rect.midY, other.midY, accuracy: 0.02, layout.displayName)
        }
    }

    /// Every outline lies inside the display.
    func testEveryOutlineIsInsideTheDisplay() {
        // A hair larger than the display, for rounding at a clamped edge.
        let unit = CGRect(x: 0, y: 0, width: 1, height: 1).insetBy(dx: -1e-9, dy: -1e-9)
        let layouts: [DeviceComponentLayout] = [
            .iPhone15Pro, .iPhone15ProMax, .iPhone16, .iPhone16Plus, .iPhone16Pro, .iPhone16ProMax, .iPhone16e,
            .iPhone17, .iPhoneAir, .iPhone17e, .iPhone17Pro, .iPhone17ProMax, .iPhone18Pro, .iPhone18ProMax,
            .iPadMini, .iPadAir11, .iPadAir13, .iPadPro11, .iPadPro13,
        ]
        for layout in layouts {
            let name = layout.displayName
            if let rect = layout.socPlacement?.rect {
                XCTAssertTrue(unit.contains(rect), "\(name) chip \(rect)")
                XCTAssertGreaterThan(rect.width, 0, name)
                XCTAssertGreaterThan(rect.height, 0, name)
            } else {
                XCTFail("\(name) has no chip outline")
            }
            if let rect = layout.tapticRect {
                XCTAssertTrue(unit.contains(rect), "\(name) Taptic \(rect)")
            }
        }
    }

    /// A 2% inset on each side of the device outline: its edges map to the display's, its middle stays put.
    func testOutlineMeasurementsConvertToTheDisplay() {
        let whole = DeviceComponentLayout.displayRect(x: 0.02...0.98, y: 0.02...0.98)
        assertEqual(whole, CGRect(x: 0, y: 0, width: 1, height: 1))
        let middle = DeviceComponentLayout.displayRect(x: 0.5...0.5, y: 0.5...0.5)
        XCTAssertEqual(middle.minX, 0.5, accuracy: 1e-9)
        XCTAssertEqual(middle.minY, 0.5, accuracy: 1e-9)
        // Past the display's edge is clamped to it.
        let past = DeviceComponentLayout.displayRect(x: 0.0...1.0, y: 0.0...1.0)
        assertEqual(past, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    // MARK: Orientation

    /// A portrait screen 100 wide and 200 tall, and an outline near the device's top left.
    private let screen = CGSize(width: 100, height: 200)
    private let topLeft = CGRect(x: 0.1, y: 0.1, width: 0.3, height: 0.2)  // 10, 20, 30 x 40 points in portrait

    func testPortraitIsUnchanged() {
        let rect = XRayPlacement.interfaceRect(
            forPortraitRect: topLeft, orientation: .portrait, portraitScreenSize: screen)
        assertEqual(rect, CGRect(x: 10, y: 20, width: 30, height: 40))
    }

    func testUpsideDownTurnsHalfway() {
        let rect = XRayPlacement.interfaceRect(
            forPortraitRect: topLeft, orientation: .portraitUpsideDown, portraitScreenSize: screen)
        assertEqual(rect, CGRect(x: 60, y: 140, width: 30, height: 40))
    }

    /// Landscape left: the Home button side on the left, so the device's top is on the right of a 200 by 100 screen
    /// and its left side at the top. An outline near the device's top left lands at the top right.
    func testLandscapeLeftPutsTheDeviceTopOnTheRight() {
        let rect = XRayPlacement.interfaceRect(
            forPortraitRect: topLeft, orientation: .landscapeLeft, portraitScreenSize: screen)
        assertEqual(rect, CGRect(x: 140, y: 10, width: 40, height: 30))
        XCTAssertGreaterThan(rect.midX, 100, "the device's top is on the right")
        XCTAssertLessThan(rect.midY, 50, "the device's left side is at the top")
    }

    /// Landscape right: the device's top on the left and its left side at the bottom.
    func testLandscapeRightPutsTheDeviceTopOnTheLeft() {
        let rect = XRayPlacement.interfaceRect(
            forPortraitRect: topLeft, orientation: .landscapeRight, portraitScreenSize: screen)
        assertEqual(rect, CGRect(x: 20, y: 60, width: 40, height: 30))
        XCTAssertLessThan(rect.midX, 100, "the device's top is on the left")
        XCTAssertGreaterThan(rect.midY, 50, "the device's left side is at the bottom")
    }

    private func assertEqual(_ a: CGRect, _ b: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.minX, b.minX, accuracy: 1e-9, "minX", file: file, line: line)
        XCTAssertEqual(a.minY, b.minY, accuracy: 1e-9, "minY", file: file, line: line)
        XCTAssertEqual(a.width, b.width, accuracy: 1e-9, "width", file: file, line: line)
        XCTAssertEqual(a.height, b.height, accuracy: 1e-9, "height", file: file, line: line)
    }
}
