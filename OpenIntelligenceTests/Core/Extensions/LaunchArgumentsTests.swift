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

    func testNoArguments() {
        let parser = LaunchArguments.Parser(arguments: [])

        XCTAssertFalse(parser.has("debug"))
        XCTAssertFalse(parser.has("--debug"))
        XCTAssertNil(parser.value(for: "output"))
        XCTAssertNil(parser.value(after: "output"))
        XCTAssertNil(parser.valueEither(for: "output"))
    }

    func testDuplicateFlagsUseFirstOccurrence() {
        let equalsForm = LaunchArguments.Parser(arguments: ["--mode=first", "--mode=second"])
        XCTAssertEqual(equalsForm.value(for: "mode"), "first")
        XCTAssertEqual(equalsForm.valueEither(for: "mode"), "first")

        let spacedForm = LaunchArguments.Parser(arguments: ["--mode", "first", "--mode", "second"])
        XCTAssertEqual(spacedForm.value(after: "mode"), "first")
        XCTAssertEqual(spacedForm.valueEither(for: "mode"), "first")

        let repeatedFlag = LaunchArguments.Parser(arguments: ["--debug", "--debug"])
        XCTAssertTrue(repeatedFlag.has("--debug"))
    }

    func testEmptyValue() {
        // `--key=` yields an empty string, never nil.
        let equalsForm = LaunchArguments.Parser(arguments: ["--output="])
        XCTAssertEqual(equalsForm.value(for: "output"), "")
        XCTAssertEqual(equalsForm.valueEither(for: "output"), "")

        // An empty positional token is a valid value because it lacks a `--` prefix.
        let spacedForm = LaunchArguments.Parser(arguments: ["--output", ""])
        XCTAssertEqual(spacedForm.value(after: "output"), "")
        XCTAssertEqual(spacedForm.valueEither(for: "output"), "")
    }

    func testValueAfterStopsAtNextFlag() {
        let parser = LaunchArguments.Parser(arguments: ["--format", "--verbose", "json"])

        XCTAssertNil(parser.value(after: "format"))
        XCTAssertNil(parser.valueEither(for: "format"))
    }

    func testDoubleDashHasNoTerminatorHandling() {
        // `--` is an ordinary flag-shaped token: it blocks a preceding key's positional
        // value, can itself take a positional value, and does not stop parsing of
        // arguments that follow it.
        let parser = LaunchArguments.Parser(arguments: ["--format", "--", "json", "--output=test.txt"])

        XCTAssertNil(parser.value(after: "format"))
        XCTAssertTrue(parser.has("--"))
        XCTAssertEqual(parser.value(after: "--"), "json")
        XCTAssertEqual(parser.value(for: "output"), "test.txt")
    }

    func testCaseSensitivity() {
        let parser = LaunchArguments.Parser(arguments: ["--Debug", "--Output=Test.TXT"])

        XCTAssertTrue(parser.has("--Debug"))
        XCTAssertFalse(parser.has("--debug"))
        XCTAssertFalse(parser.has("debug"))
        XCTAssertEqual(parser.value(for: "Output"), "Test.TXT")
        XCTAssertNil(parser.value(for: "output"))
    }

    func testMalformedInput() {
        let parser = LaunchArguments.Parser(arguments: ["--path=/tmp/a=b", "-single", "---triple", "--=orphan", "key=value"])

        // Only the first `=` after the key delimits the value.
        XCTAssertEqual(parser.value(for: "path"), "/tmp/a=b")
        // Single-dash tokens match only literally.
        XCTAssertTrue(parser.has("-single"))
        XCTAssertFalse(parser.has("--single"))
        // A bare-name query is prefixed with `--`, so `-triple` matches `---triple`.
        XCTAssertTrue(parser.has("-triple"))
        // An empty key matches the degenerate `--=` prefix.
        XCTAssertEqual(parser.value(for: ""), "orphan")
        // Dashless key=value tokens are not key/value pairs, only literal flags.
        XCTAssertNil(parser.value(for: "key"))
        XCTAssertTrue(parser.has("key=value"))
    }

    func testValueEitherPrefersEqualsForm() {
        // The `--key=value` form wins over `--key value` regardless of argument order.
        let spacedFirst = LaunchArguments.Parser(arguments: ["--output", "spaced.txt", "--output=equals.txt"])
        XCTAssertEqual(spacedFirst.valueEither(for: "output"), "equals.txt")

        let equalsFirst = LaunchArguments.Parser(arguments: ["--output=equals.txt", "--output", "spaced.txt"])
        XCTAssertEqual(equalsFirst.valueEither(for: "output"), "equals.txt")
    }

    func testStaticAPIDelegatesToProcessArguments() {
        XCTAssertEqual(LaunchArguments.all, ProcessInfo.processInfo.arguments)

        // The static API must agree with a Parser over the live process arguments
        // for every entry point, preserving the pre-refactor global behavior.
        let parser = LaunchArguments.Parser(arguments: LaunchArguments.all)
        for probe in ["xctest", "--xctest", "nonexistent-flag-4c1f9e"] {
            XCTAssertEqual(LaunchArguments.has(probe), parser.has(probe))
            XCTAssertEqual(LaunchArguments.value(for: probe), parser.value(for: probe))
            XCTAssertEqual(LaunchArguments.value(after: probe), parser.value(after: probe))
            XCTAssertEqual(LaunchArguments.valueEither(for: probe), parser.valueEither(for: probe))
        }
        XCTAssertFalse(LaunchArguments.has("--nonexistent-flag-4c1f9e"))
        XCTAssertNil(LaunchArguments.valueEither(for: "nonexistent-flag-4c1f9e"))
    }
}
