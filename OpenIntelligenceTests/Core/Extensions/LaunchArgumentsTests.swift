import XCTest
@testable import OpenIntelligenceEngine

final class LaunchArgumentsTests: XCTestCase {
    func testHas() {
        let parser = LaunchArguments.Parser(arguments: ["--debug", "verbose", "--output=test.txt", "--format", "json"])

        XCTAssertTrue(parser.has("--debug"))
        XCTAssertTrue(parser.has("debug"))
        XCTAssertTrue(parser.has("verbose"))
        XCTAssertTrue(parser.has("--verbose"))
        XCTAssertFalse(parser.has("missing"))
        XCTAssertFalse(parser.has("--missing"))
    }

    func testValueFor() {
        let parser = LaunchArguments.Parser(arguments: ["--debug", "verbose", "--output=test.txt", "--format", "json"])

        XCTAssertEqual(parser.value(for: "output"), "test.txt")
        XCTAssertNil(parser.value(for: "debug"))
        XCTAssertNil(parser.value(for: "format"))
        XCTAssertNil(parser.value(for: "missing"))
    }

    func testValueAfter() {
        let parser = LaunchArguments.Parser(arguments: ["--debug", "verbose", "--output=test.txt", "--format", "json", "--empty"])

        XCTAssertEqual(parser.value(after: "format"), "json")
        XCTAssertEqual(parser.value(after: "--format"), "json")
        XCTAssertEqual(parser.value(after: "debug"), "verbose")
        XCTAssertNil(parser.value(after: "empty"))
        XCTAssertNil(parser.value(after: "missing"))
    }

    func testValueEither() {
        let parser = LaunchArguments.Parser(arguments: ["--output=file1.txt", "--format", "json", "--debug"])

        XCTAssertEqual(parser.valueEither(for: "output"), "file1.txt")
        XCTAssertEqual(parser.valueEither(for: "format"), "json")
        XCTAssertNil(parser.valueEither(for: "debug"))
        XCTAssertNil(parser.valueEither(for: "missing"))
    }
}
