import XCTest

@testable import OpenIntelligence

/// Fails the build when the newest shipped release has no What's New entry.
///
/// This exists because of a silent failure that has now happened three times. `WhatsNewStore`
/// looks its copy up by `CFBundleShortVersionString`, and `evaluateOnLaunch` treats an unknown
/// key as "nothing authored": it records the version as seen and returns. So a release that
/// ships without a key shows nothing to anyone who updates into it, no build fails, no log line
/// is written, and the only way to notice is to update a real device and see an empty launch.
/// 5.0.2 and 5.1 shipped that way, and so did 5.3 on 2026-09-18.
///
/// The check is anchored to the bundled `VersionHistory.md` rather than to `CHANGELOG.md`
/// because that file is already a build input, already byte-compared against
/// `Docs/USER_CHANGELOG.md` by `VersionHistoryTests`, and is the same file the in-app Version
/// History screen renders. A release that is real enough to have user-facing notes is real
/// enough to need a sheet.
@MainActor
final class WhatsNewCoverageTests: XCTestCase {

    /// `## v5.3 - September 18, 2026` becomes `5.3`. Returns nil for any other heading shape,
    /// which is deliberate: `testHeadingShapeIsStillRecognised` below turns that into a failure
    /// rather than letting an unparsed heading quietly pass this whole suite.
    private static func version(fromHeading line: String) -> String? {
        guard line.hasPrefix("## v") else { return nil }
        let afterMarker = line.dropFirst("## v".count)
        let token = afterMarker.prefix { $0.isNumber || $0 == "." }
        guard !token.isEmpty, token.last != "." else { return nil }
        return String(token)
    }

    private func newestDocumentedVersion() throws -> String {
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "VersionHistory", withExtension: "md")
                ?? Bundle.main.url(forResource: "VersionHistory", withExtension: "md"),
            "VersionHistory.md is not in the test bundle."
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        let versions = text
            .components(separatedBy: .newlines)
            .compactMap { Self.version(fromHeading: $0) }
        return try XCTUnwrap(versions.first, "No `## vX.Y` heading found in VersionHistory.md.")
    }

    // MARK: - The guard

    func testNewestReleaseHasAWhatsNewEntry() throws {
        let newest = try newestDocumentedVersion()
        XCTAssertNotNil(
            WhatsNewStore.releases[newest],
            """
            VersionHistory.md documents \(newest) as the newest release, but \
            WhatsNewStore.releases has no "\(newest)" key. Anyone updating into \(newest) would \
            be shown nothing, because evaluateOnLaunch records an unknown version as seen and \
            returns. Add a "\(newest)" entry worded from the Docs/USER_CHANGELOG.md section of \
            the same name.
            """
        )
    }

    /// The entry has to describe the version it is keyed to, which is the defect from 2026-08-22
    /// where the 5.0 sheet was frozen mid-cycle and 17 user-visible commits never reached it.
    func testNewestEntryIsKeyedToItself() throws {
        let newest = try newestDocumentedVersion()
        guard let release = WhatsNewStore.releases[newest] else { return }  // the test above owns this failure
        XCTAssertEqual(release.version, newest, "The \(newest) entry carries version \(release.version).")
        XCTAssertEqual(release.id, newest, "WhatsNewRelease.id is its version, and the sheet is identified by it.")
    }

    /// Every authored entry must be presentable. An empty headline or an entry with no items
    /// renders as a sheet with nothing in it, which is worse than the silent skip.
    func testEveryAuthoredEntryIsPresentable() {
        for (key, release) in WhatsNewStore.releases {
            XCTAssertFalse(release.headline.isEmpty, "\(key) has an empty headline")
            XCTAssertFalse(release.items.isEmpty, "\(key) has no items")
            XCTAssertEqual(release.version, key, "\(key) is keyed to a release that calls itself \(release.version)")
            for item in release.items {
                XCTAssertFalse(item.title.isEmpty, "\(key) has an item with no title")
                XCTAssertFalse(item.detail.isEmpty, "\(key) item \(item.title.prefix(40)) has no detail")
                XCTAssertFalse(item.symbol.isEmpty, "\(key) item \(item.title.prefix(40)) has no SF Symbol")
            }
        }
    }

    // MARK: - The parser this suite depends on

    func testHeadingShapeIsStillRecognised() {
        XCTAssertEqual(Self.version(fromHeading: "## v5.3 - September 18, 2026"), "5.3")
        XCTAssertEqual(Self.version(fromHeading: "## v5.0.2 - August 26, 2026"), "5.0.2")
        XCTAssertEqual(Self.version(fromHeading: "## v5.4 - unreleased"), "5.4")
        XCTAssertNil(Self.version(fromHeading: "## Unreleased"))
        XCTAssertNil(Self.version(fromHeading: "### v5.3 - September 18, 2026"))
        XCTAssertNil(Self.version(fromHeading: "Some prose mentioning v5.3 in passing."))
    }
}
