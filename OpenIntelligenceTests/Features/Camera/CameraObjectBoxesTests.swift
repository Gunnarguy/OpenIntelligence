//
//  CameraObjectBoxesTests.swift
//  OpenIntelligenceTests
//
//  The rules added on 2026-11-16 after the owner's iPhone, pointed at a MacBook on a counter,
//  showed one box around the laptop, the counter and the chair, named "Computer", and the chips
//  "Plant, Structure, Decorative Plant" ahead of any object. A live camera cannot run in a test,
//  so these check the pure parts: boxes read off an instance mask, which scene words are shown,
//  and the order of the chips.
//

import XCTest

@testable import OpenIntelligence

// Debug builds only, as is the camera code these tests check.
#if os(iOS) && DEBUG

    final class CameraObjectBoxesTests: XCTestCase {

        /// A 10x10 mask, row-major from the top, with `label` filling the given cells.
        private func mask(_ fills: [(label: UInt8, columns: ClosedRange<Int>, rows: ClosedRange<Int>)]) -> [UInt8] {
            var labels = [UInt8](repeating: 0, count: 100)
            for fill in fills {
                for row in fill.rows {
                    for column in fill.columns { labels[row * 10 + column] = fill.label }
                }
            }
            return labels
        }

        private func assertRect(_ a: CGRect, _ b: CGRect, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(a.minX, b.minX, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(a.minY, b.minY, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(a.width, b.width, accuracy: 0.0001, file: file, line: line)
            XCTAssertEqual(a.height, b.height, accuracy: 0.0001, file: file, line: line)
        }

        // MARK: - One box per object

        func testTwoObjectsGiveTwoSeparateBoxesLargestFirst() {
            // A laptop (label 1) in the middle and a jug (label 2) at the top left.
            let labels = mask([(1, 3...8, 4...7), (2, 0...1, 0...2)])
            let boxes = InstanceBoxes.boxes(labels: labels, width: 10, height: 10)
            XCTAssertEqual(boxes.count, 2)
            // The laptop: columns 3 to 8, rows 4 to 7 from the top. Vision's y counts up from the
            // bottom, so its lowest edge is 1 - 8/10 = 0.2.
            assertRect(boxes[0], CGRect(x: 0.3, y: 0.2, width: 0.6, height: 0.4))
            // The jug: rows 0 to 2 from the top, so it sits at the top of Vision's space.
            assertRect(boxes[1], CGRect(x: 0.0, y: 0.7, width: 0.2, height: 0.3))
        }

        func testTheBackgroundIsNeverABox() {
            XCTAssertEqual(InstanceBoxes.boxes(labels: [UInt8](repeating: 0, count: 100), width: 10, height: 10), [])
        }

        func testAnObjectCoveringMostOfTheFrameIsTheSceneNotABox() {
            let labels = mask([(1, 0...9, 0...9)])
            XCTAssertEqual(InstanceBoxes.boxes(labels: labels, width: 10, height: 10), [])
        }

        func testASliverIsDropped() {
            let labels = mask([(1, 0...9, 5...5)])
            // One row of ten: full width, 0.1 high, kept at the default 0.05 floor.
            XCTAssertEqual(InstanceBoxes.boxes(labels: labels, width: 10, height: 10).count, 1)
            // Raise the floor above its height and it goes.
            XCTAssertEqual(InstanceBoxes.boxes(labels: labels, width: 10, height: 10, minimumSide: 0.15), [])
        }

        func testAShortMaskBufferYieldsNothingRatherThanReadingPastIt() {
            XCTAssertEqual(InstanceBoxes.boxes(labels: [1, 1, 1], width: 10, height: 10), [])
        }

        // MARK: - Scene chips

        func testParentsAndVagueWordsAreNotSceneChips() {
            XCTAssertFalse(ObjectLabelPolicy.isShownAsScene("plant"))
            XCTAssertFalse(ObjectLabelPolicy.isShownAsScene("structure"))
            XCTAssertFalse(ObjectLabelPolicy.isShownAsScene("machine"))
        }

        func testSpecificThingsAndInformativePlacesAreSceneChips() {
            XCTAssertTrue(ObjectLabelPolicy.isShownAsScene("decorative_plant"))
            XCTAssertTrue(ObjectLabelPolicy.isShownAsScene("computer"))
            XCTAssertTrue(ObjectLabelPolicy.isShownAsScene("kitchen_room"))
        }

        func testEveryInformativePlaceIsShown() {
            for identifier in ObjectLabelPolicy.informativeSceneIdentifiers {
                XCTAssertTrue(ObjectLabelPolicy.isShownAsScene(identifier), identifier)
            }
        }

        // MARK: - Chip order

        func testObjectsComeBeforeSceneWords() {
            let chips = ObjectLabelPolicy.chips(
                objects: ["Computer", "Jug"], scenes: ["Decorative Plant", "Kitchen Room"])
            XCTAssertEqual(chips.map(\.text), ["Computer", "Jug", "Decorative Plant", "Kitchen Room"])
            XCTAssertEqual(chips.map(\.isObject), [true, true, false, false])
        }

        func testASceneWordRepeatingAnObjectIsDropped() {
            let chips = ObjectLabelPolicy.chips(objects: ["Computer"], scenes: ["computer", "Kitchen Room"])
            XCTAssertEqual(chips.map(\.text), ["Computer", "Kitchen Room"])
        }

        func testRepeatedObjectNamesShowOnce() {
            let chips = ObjectLabelPolicy.chips(objects: ["Mug", "Mug", "Laptop"], scenes: [])
            XCTAssertEqual(chips.map(\.text), ["Mug", "Laptop"])
        }

        func testTheChipCountsAreCapped() {
            let chips = ObjectLabelPolicy.chips(
                objects: ["A", "B", "C", "D", "E"], scenes: ["S1", "S2", "S3"])
            XCTAssertEqual(chips.filter(\.isObject).count, 4)
            XCTAssertEqual(chips.filter { !$0.isObject }.count, 2)
        }
    }

#endif
