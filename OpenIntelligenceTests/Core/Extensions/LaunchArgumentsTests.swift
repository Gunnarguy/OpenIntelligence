import XCTest
@testable import OpenIntelligenceEngine

final class LaunchArgumentsTests: XCTestCase {
    func testHas() {
        let args = ["--debug", "verbose", "--output=test.txt", "--format", "json"]

        XCTAssertTrue(LaunchArguments.has("--debug", in: args))
        XCTAssertTrue(LaunchArguments.has("debug", in: args))
        XCTAssertTrue(LaunchArguments.has("verbose", in: args))
        XCTAssertTrue(LaunchArguments.has("--verbose", in: args))
        XCTAssertFalse(LaunchArguments.has("missing", in: args))
        XCTAssertFalse(LaunchArguments.has("--missing", in: args))
    }

    func testValueFor() {
        let args = ["--debug", "verbose", "--output=test.txt", "--format", "json"]

        XCTAssertEqual(LaunchArguments.value(for: "output", in: args), "test.txt")
        XCTAssertNil(LaunchArguments.value(for: "debug", in: args))
        XCTAssertNil(LaunchArguments.value(for: "format", in: args))
        XCTAssertNil(LaunchArguments.value(for: "missing", in: args))
    }

    func testValueAfter() {
        let args = ["--debug", "verbose", "--output=test.txt", "--format", "json", "--empty"]

        XCTAssertEqual(LaunchArguments.value(after: "format", in: args), "json")
        XCTAssertEqual(LaunchArguments.value(after: "--format", in: args), "json")
        XCTAssertEqual(LaunchArguments.value(after: "debug", in: args), "verbose")
        XCTAssertNil(LaunchArguments.value(after: "empty", in: args))
        XCTAssertNil(LaunchArguments.value(after: "missing", in: args))
    }

    func testValueEither() {
        let args = ["--output=file1.txt", "--format", "json", "--debug"]

        XCTAssertEqual(LaunchArguments.valueEither(for: "output", in: args), "file1.txt")
        XCTAssertEqual(LaunchArguments.valueEither(for: "format", in: args), "json")
        XCTAssertNil(LaunchArguments.valueEither(for: "debug", in: args))
        XCTAssertNil(LaunchArguments.valueEither(for: "missing", in: args))
    }
}
