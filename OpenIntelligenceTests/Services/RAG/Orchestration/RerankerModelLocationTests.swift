//
//  RerankerModelLocationTests.swift
//  OpenIntelligenceTests
//
//  The reranker loads from one fixed path, so Core ML's compiled form is found again (5.8).
//

import XCTest

@testable import OpenIntelligence

final class RerankerModelLocationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "rml-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func makeModel(_ name: String, weights: String, program: String = "program v1") throws -> URL {
        let model = root.appendingPathComponent("bundle/\(name).mlmodelc", isDirectory: true)
        try? FileManager.default.removeItem(at: model)
        try FileManager.default.createDirectory(
            at: model.appendingPathComponent("weights"), withIntermediateDirectories: true)
        try Data(program.utf8).write(to: model.appendingPathComponent("model.mil"))
        try Data(weights.utf8).write(to: model.appendingPathComponent("weights/weight.bin"))
        return model
    }

    func testSameModelGivesTheSamePathEveryTime() throws {
        let model = try makeModel("ReRankerModel", weights: "w1")
        let support = root.appendingPathComponent("support")
        let first = try XCTUnwrap(RerankerModelLocation.stableCopy(of: model, under: support))
        let second = try XCTUnwrap(RerankerModelLocation.stableCopy(of: model, under: support))
        XCTAssertEqual(first, second)
        XCTAssertNotEqual(first.deletingLastPathComponent(), model.deletingLastPathComponent())
        XCTAssertEqual(try Data(contentsOf: first.appendingPathComponent("weights/weight.bin")), Data("w1".utf8))
    }

    func testTheCopyIsNotMadeAgain() throws {
        let model = try makeModel("ReRankerModel", weights: "w1")
        let support = root.appendingPathComponent("support")
        let first = try XCTUnwrap(RerankerModelLocation.stableCopy(of: model, under: support))
        let stamp = try FileManager.default.attributesOfItem(atPath: first.path)[.creationDate] as? Date
        _ = try XCTUnwrap(RerankerModelLocation.stableCopy(of: model, under: support))
        let again = try FileManager.default.attributesOfItem(atPath: first.path)[.creationDate] as? Date
        XCTAssertEqual(stamp, again)
    }

    func testANewModelGetsANewPathAndTheOldCopyGoes() throws {
        let support = root.appendingPathComponent("support")
        let old = try XCTUnwrap(
            RerankerModelLocation.stableCopy(of: try makeModel("ReRankerModel", weights: "w1"), under: support))
        let new = try XCTUnwrap(
            RerankerModelLocation.stableCopy(
                of: try makeModel("ReRankerModel", weights: "w1", program: "program v2"), under: support))
        XCTAssertNotEqual(old, new)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.path))
    }

    func testAWeightsSizeChangeIsANewModel() throws {
        let a = try XCTUnwrap(RerankerModelLocation.fingerprint(of: try makeModel("M", weights: "w1")))
        let b = try XCTUnwrap(RerankerModelLocation.fingerprint(of: try makeModel("M", weights: "w12")))
        XCTAssertNotEqual(a, b)
    }

    func testACopyCutShortIsMadeAgain() throws {
        let model = try makeModel("ReRankerModel", weights: "w1")
        let support = root.appendingPathComponent("support")
        let copy = try XCTUnwrap(RerankerModelLocation.stableCopy(of: model, under: support))
        try FileManager.default.removeItem(at: copy.appendingPathComponent("weights/weight.bin"))
        try FileManager.default.removeItem(atPath: copy.path + ".complete")
        let again = try XCTUnwrap(RerankerModelLocation.stableCopy(of: model, under: support))
        XCTAssertEqual(again, copy)
        XCTAssertTrue(FileManager.default.fileExists(atPath: again.appendingPathComponent("weights/weight.bin").path))
    }

    func testAPackageLoadsFromTheBundle() {
        let package = root.appendingPathComponent("ReRankerModel.mlpackage")
        let result = RerankerModelLocation.loadURL(for: package)
        XCTAssertEqual(result.url, package)
        XCTAssertFalse(result.fixedPath)
    }
}
