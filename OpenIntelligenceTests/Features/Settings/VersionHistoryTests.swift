//
//  VersionHistoryTests.swift
//  OpenIntelligenceTests
//
//  Guards the two copies of the changelog against drift, and pins the parser.
//

@testable import OpenIntelligence
import XCTest

final class VersionHistoryTests: XCTestCase {
    /// The bundled copy must match `Docs/USER_CHANGELOG.md` exactly.
    ///
    /// `OpenIntelligence/Resources/VersionHistory.md` exists because the app cannot read a
    /// file outside its bundle, and adding a build phase to copy it would mean editing
    /// `project.pbxproj`, which is a hard-boundary file. The copy is therefore mechanical
    /// duplication, and duplication is exactly how the claims in this repository have
    /// drifted before. This test is the enforcement: update one without the other and the
    /// suite fails rather than the app quietly showing a stale history.
    func testBundledHistoryMatchesTheWrittenChangelog() throws {
        let bundled = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "VersionHistory", withExtension: "md")
                ?? Bundle.main.url(forResource: "VersionHistory", withExtension: "md"),
            "VersionHistory.md is not in the app bundle. It lives in OpenIntelligence/Resources, which is a synchronized folder, so it should be copied automatically."
        )

        // Walk up from this file to the repository root rather than hardcoding a path,
        // so the test survives being run from a worktree or a different checkout.
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { root.deleteLastPathComponent() }
        let source = root.appendingPathComponent("Docs/USER_CHANGELOG.md")

        guard FileManager.default.fileExists(atPath: source.path) else {
            throw XCTSkip("Docs/USER_CHANGELOG.md not reachable from \(source.path); skipping drift check.")
        }

        let bundledText = try String(contentsOf: bundled, encoding: .utf8)
        let sourceText = try String(contentsOf: source, encoding: .utf8)

        XCTAssertEqual(
            bundledText,
            sourceText,
            "OpenIntelligence/Resources/VersionHistory.md has drifted from Docs/USER_CHANGELOG.md. Copy the latter over the former."
        )
    }

    /// Every release heading in the changelog has to survive parsing.
    ///
    /// Catches the failure that matters: a heading style the parser does not recognise
    /// silently drops a whole release from the in-app history.
    func testEveryReleaseHeadingIsParsed() throws {
        let bundled = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "VersionHistory", withExtension: "md")
                ?? Bundle.main.url(forResource: "VersionHistory", withExtension: "md")
        )
        let text = try String(contentsOf: bundled, encoding: .utf8)

        let headingCount = text
            .components(separatedBy: .newlines)
            .filter { $0.hasPrefix("## ") }
            .count

        let releases = VersionHistoryLoader.parse(text)

        XCTAssertEqual(
            releases.count,
            headingCount,
            "Parsed \(releases.count) releases from \(headingCount) '## ' headings. A heading shape the parser does not handle drops that release from the history screen."
        )
        XCTAssertFalse(releases.isEmpty, "No releases parsed at all.")
    }

    /// Pins the two bullet shapes the changelog actually uses.
    func testBulletParsingSplitsLeadFromDetail() {
        let markdown = """
        ## v9.9 - January 1, 2030
        A summary line.

        ### A Section

        *   **Bold lead.** The remainder of the sentence.
        *   A plain bullet with no bold lead.
        """

        let releases = VersionHistoryLoader.parse(markdown)
        let release = try? XCTUnwrap(releases.first)

        XCTAssertEqual(release?.version, "9.9")
        XCTAssertEqual(release?.date, "January 1, 2030")
        XCTAssertEqual(release?.summary, "A summary line.")
        XCTAssertEqual(release?.sections.first?.heading, "A Section")

        let items = release?.sections.first?.items ?? []
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(items.first?.title, "Bold lead.")
        XCTAssertEqual(items.first?.detail, "The remainder of the sentence.")
        XCTAssertEqual(items.last?.title, "A plain bullet with no bold lead.")
        XCTAssertNil(items.last?.detail)
    }
}
