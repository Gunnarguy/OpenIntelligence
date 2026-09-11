//
//  LiveObjectDetectionTests.swift
//  OpenIntelligenceTests
//
//  Covers the one piece of `LiveObjectDetectionService` that can be tested without a camera.
//
//  The detectors themselves cannot be exercised here: they need real frames, and nothing in this
//  app presents a camera, so there is no fixture path that reaches them. What IS testable is the
//  phrase that gets attached to a captured image, and the distinction the whole rewrite turns on
//  — that a scene label is not a located object.
//

import XCTest

@testable import OpenIntelligence

final class LiveObjectDetectionTests: XCTestCase {

    private func located(_ label: String) -> DetectedObject {
        DetectedObject(
            label: label,
            confidence: 0.9,
            boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        )
    }

    private func scene(_ label: String) -> DetectedObject {
        DetectedObject(label: label, confidence: 0.8, boundingBox: .zero, isSceneLevel: true)
    }

    // MARK: - A scene label is not a thing you can count

    func testSceneLabelsAreNotPluralised() {
        // "Office" describes the frame once, however many times the classifier names it.
        // Counting scene labels the way located objects are counted produced "2 Offices".
        let description = LiveObjectDetectionService.shared.describeObjects([
            scene("Office"), scene("Office"),
        ])
        XCTAssertEqual(description, "Office")
    }

    func testASceneLabelDoesNotRepeatSomethingAlreadyLocated() {
        // `ClassifyImageRequest` can return "Person" for a frame `DetectHumanRectanglesRequest`
        // has already boxed twice. Without the guard this read "2 Persons, Person".
        let description = LiveObjectDetectionService.shared.describeObjects([
            located("Person"), located("Person"), scene("Person"),
        ])
        XCTAssertEqual(description, "2 Persons")
    }

    func testLocatedObjectsAreCountedAndSceneLabelsFollow() {
        let description = LiveObjectDetectionService.shared.describeObjects([
            located("Person"), located("Person"), located("Dog"), scene("Park"),
        ])
        XCTAssertEqual(description, "2 Persons, Dog, Park")
    }

    func testOrderOfFirstAppearanceIsKept() {
        // A dictionary would have reordered these arbitrarily between runs, which makes the
        // attached description of one image unstable across ingests of the same photo.
        let description = LiveObjectDetectionService.shared.describeObjects([
            located("Zebra"), located("Apple"), located("Monitor"),
        ])
        XCTAssertEqual(description, "Zebra, Apple, Monitor")
    }

    func testNothingDetectedProducesAnEmptyStringRatherThanPunctuation() {
        XCTAssertEqual(LiveObjectDetectionService.shared.describeObjects([]), "")
    }

    // MARK: - The flag that replaced a fabricated bounding box

    func testSceneLevelResultsCarryNoGeometry() {
        // The previous implementation gave scene labels CGRect(0, 0, 1, 1) so they would satisfy
        // the overlay's box-drawing code. That is what would have drawn a rectangle around the
        // entire frame, once per label. A scene label must not carry a box a renderer can use.
        let sceneLabel = scene("Kitchen")
        XCTAssertTrue(sceneLabel.isSceneLevel)
        XCTAssertEqual(sceneLabel.boundingBox, .zero)
        XCTAssertNotEqual(sceneLabel.boundingBox, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testLocatedResultsDefaultToNotSceneLevel() {
        // The `isSceneLevel` parameter is defaulted so the three-argument call sites that existed
        // before this type gained the flag still compile and still mean "this has a real box".
        XCTAssertFalse(located("Face").isSceneLevel)
    }
}
