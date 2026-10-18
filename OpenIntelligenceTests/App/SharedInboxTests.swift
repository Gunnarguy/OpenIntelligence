//
//  SharedInboxTests.swift
//  OpenIntelligenceTests
//
//  What the Share Sheet extension hands to the app (5.7).
//

import XCTest

@testable import OpenIntelligence

final class SharedInboxTests: XCTestCase {
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SharedInboxTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func item(_ kind: SharedInbox.Item.Kind, _ value: String, at seconds: TimeInterval) -> SharedInbox.Item {
        SharedInbox.Item(kind: kind, value: value, sharedAt: Date(timeIntervalSince1970: seconds))
    }

    /// What the extension saves the app claims oldest first, and an item leaves only once it is finished. A run that
    /// ended before it stored anything gives its items back as they were.
    func testItemsAreClaimedOldestFirstAndLeaveOnlyWhenFinished() throws {
        let earlier = item(.link, "https://example.com/lease", at: 1_000)
        let later = item(.text, "Rent is due on the first.", at: 2_000)
        try SharedInbox.save([later], in: folder)
        try SharedInbox.save([earlier], in: folder)

        XCTAssertEqual(SharedInbox.claimAll(from: folder).items.map(\.item), [earlier, later])
        XCTAssertTrue(SharedInbox.hasItems(in: folder), "claimed, not yet finished")
        let again = SharedInbox.claimAll(from: folder)
        XCTAssertEqual(again.items.map(\.item), [earlier, later], "a run that ended gives them back, no try counted")
        XCTAssertEqual(again.letGo, [])

        again.items.forEach(SharedInbox.finish)
        XCTAssertFalse(SharedInbox.hasItems(in: folder))
        XCTAssertEqual(SharedInbox.claimAll(from: folder).items.count, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [], "nothing left behind")
    }

    /// An item that couldn't be stored goes back with its try counted, and leaves after the last try.
    func testAnItemThatFailsIsTriedAgainThenLetGo() throws {
        try SharedInbox.save([item(.link, "https://example.com/offline", at: 1_000)], in: folder)
        for attempt in 1..<SharedInbox.maxAttempts {
            let claimed = try XCTUnwrap(SharedInbox.claimAll(from: folder).items.first)
            XCTAssertEqual(claimed.item.attempts ?? 0, attempt - 1)
            XCTAssertTrue(SharedInbox.putBack(SharedInbox.beginTrying(claimed), into: folder), "try \(attempt) is kept")
        }
        let last = try XCTUnwrap(SharedInbox.claimAll(from: folder).items.first)
        XCTAssertFalse(SharedInbox.putBack(SharedInbox.beginTrying(last), into: folder), "the last try lets it go")
        XCTAssertFalse(SharedInbox.hasItems(in: folder))
    }

    /// A run the app died in counts a try for the item it was storing and not for those waiting behind it, and an item
    /// that ends the app every time is let go after the last try, for the app to say so.
    func testARunTheAppDiedInCountsATryForTheItemInFlight() throws {
        let huge = item(.link, "https://example.com/huge", at: 1_000)
        let waiting = item(.text, "Waiting its turn", at: 2_000)
        try SharedInbox.save([huge, waiting], in: folder)

        for attempt in 0..<SharedInbox.maxAttempts {
            let claim = SharedInbox.claimAll(from: folder)
            XCTAssertEqual(claim.items.map(\.item.value), [huge.value, waiting.value], "run \(attempt + 1)")
            XCTAssertEqual(claim.items.first?.item.attempts ?? 0, attempt)
            XCTAssertEqual(claim.items.last?.item.attempts ?? 0, 0, "the one behind it isn't counted")
            // The app ends while it stores the first.
            _ = claim.items.first.map(SharedInbox.beginTrying)
        }
        let last = SharedInbox.claimAll(from: folder)
        XCTAssertEqual(last.letGo.map(\.value), [huge.value])
        XCTAssertEqual(last.items.map(\.item.value), [waiting.value])
    }

    /// An item the plan had no room for goes back as it was: no try counted, and it is taken again next time (5.7).
    func testAnItemReleasedGoesBackAsItWas() throws {
        let page = item(.link, "https://example.com/manual", at: 1_000)
        try SharedInbox.save([page], in: folder)
        let claimed = try XCTUnwrap(SharedInbox.claimAll(from: folder).items.first)
        XCTAssertEqual(SharedInbox.waitingCount(in: folder), 0, "taken")

        SharedInbox.release(claimed, into: folder)
        XCTAssertEqual(SharedInbox.waitingCount(in: folder), 1)
        let again = try XCTUnwrap(SharedInbox.claimAll(from: folder).items.first)
        XCTAssertEqual(again.item, page, "no try counted")
        SharedInbox.finish(again)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), [], "nothing left behind")
    }

    /// A file that can't be read is removed, so it doesn't wait forever.
    func testAnUnreadableFileIsRemoved() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: folder.appendingPathComponent("1-broken.json"))
        let kept = item(.text, "Kept", at: 3_000)
        try SharedInbox.save([kept], in: folder)

        let claim = SharedInbox.claimAll(from: folder)
        XCTAssertEqual(claim.items.map(\.item), [kept])
        claim.items.forEach(SharedInbox.finish)
        XCTAssertFalse(SharedInbox.hasItems(in: folder))
    }

    /// An empty or missing inbox gives nothing and makes nothing.
    func testAMissingInboxGivesNothing() {
        XCTAssertFalse(SharedInbox.hasItems(in: folder))
        XCTAssertEqual(SharedInbox.claimAll(from: folder).items.count, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    /// Shared items become what the Paste button reads: an address is a link, text that is one address is a link too,
    /// any other text is text, and an address that isn't http or https is nothing.
    func testSharedItemsReadAsPasteDoes() throws {
        let manual = try XCTUnwrap(URL(string: "https://example.com/manual"))
        XCTAssertEqual(SharedInboxImport.pastedItem(item(.link, "https://example.com/manual", at: 0)), .link(manual))
        XCTAssertEqual(
            SharedInboxImport.pastedItem(item(.text, "  https://example.com/manual  ", at: 0)), .link(manual))
        XCTAssertEqual(
            SharedInboxImport.pastedItem(item(.text, "Check the filter every 90 days.", at: 0)),
            .text("Check the filter every 90 days."))
        XCTAssertNil(SharedInboxImport.pastedItem(item(.link, "ftp://example.com/file", at: 0)))
        XCTAssertNotNil(SharedInboxImport.provider(for: .link(manual)))
        XCTAssertEqual(SharedInboxImport.label(for: item(.link, "https://example.com/manual", at: 0)), "example.com")
    }
}
