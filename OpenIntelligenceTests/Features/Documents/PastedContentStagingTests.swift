//
//  PastedContentStagingTests.swift
//  OpenIntelligenceTests
//
//  The Paste button on the Documents screen takes a copied file, a web address or text. These pin
//  how what was pasted is told apart, and that text is stored as a note the import queue can read.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class PastedContentStagingTests: XCTestCase {
    private typealias Staging = PastedContentStaging

    func testAStringThatIsOnlyAWebAddressIsALink() {
        XCTAssertEqual(
            Staging.item(for: "https://example.com/lease.html"), .link(URL(string: "https://example.com/lease.html")!))
        XCTAssertEqual(
            Staging.item(for: "  http://example.com/a?b=1\n"), .link(URL(string: "http://example.com/a?b=1")!))
    }

    func testAnythingElseWithContentIsText() {
        XCTAssertEqual(
            Staging.item(for: "See https://example.com for the lease."), .text("See https://example.com for the lease."))
        XCTAssertEqual(Staging.item(for: "Rent is due on the 1st."), .text("Rent is due on the 1st."))
        XCTAssertEqual(Staging.item(for: "example.com"), .text("example.com"))
        XCTAssertEqual(Staging.item(for: "mailto:someone@example.com"), .text("mailto:someone@example.com"))
        XCTAssertNil(Staging.item(for: "  \n "))
    }

    func testAnAddressIsAFileALinkOrNothing() {
        let file = URL(fileURLWithPath: "/tmp/Lease.pdf")
        XCTAssertEqual(Staging.item(for: file), .file(file))
        XCTAssertEqual(
            Staging.item(for: URL(string: "https://example.com")!), .link(URL(string: "https://example.com")!))
        XCTAssertNil(Staging.item(for: URL(string: "openintelligence://chat")!))
        XCTAssertNil(Staging.item(for: URL(string: "ftp://example.com/file")!))
    }

    /// A browser puts a copied link on the pasteboard twice, as an address and as its text.
    func testTheSameItemPastedTwiceIsKeptOnce() {
        let link = Staging.Item.link(URL(string: "https://example.com")!)
        XCTAssertEqual(Staging.deduplicated([link, .text("note"), link, .text("note")]), [link, .text("note")])
    }

    func testPastedTextIsStoredAsANoteNamedFromItsFirstWords() throws {
        let text = "Rent is due on the first of the month.\nA late charge applies after the fifth."
        let stored = try Staging.storeText(text)
        defer { try? FileManager.default.removeItem(at: stored) }

        XCTAssertEqual(stored.pathExtension, "txt")
        XCTAssertTrue(stored.lastPathComponent.hasPrefix("Rent is due on the first of the"), stored.lastPathComponent)
        XCTAssertEqual(try String(contentsOf: stored, encoding: .utf8), text)
    }

    /// A screenshot's suggested name ends in a time, which is not a file extension.
    func testAPastedPictureGetsItsExtensionUnlessItsNameAlreadyHasIt() {
        XCTAssertEqual(
            Staging.fileName(stem: "Screenshot 2026-10-09 at 10.31.22", extension: "png"),
            "Screenshot 2026-10-09 at 10.31.22.png")
        XCTAssertEqual(Staging.fileName(stem: "Lease", extension: "pdf"), "Lease.pdf")
        XCTAssertEqual(Staging.fileName(stem: "Lease.PDF", extension: "pdf"), "Lease.PDF")
        XCTAssertEqual(Staging.fileName(stem: "Pasted", extension: "png"), "Pasted.png")
    }

    func testAFailureIsNamedByWhatFailed() {
        XCTAssertEqual(Staging.label(for: .file(URL(fileURLWithPath: "/tmp/Lease.pdf"))), "Lease.pdf")
        XCTAssertEqual(Staging.label(for: .link(URL(string: "https://example.com/a/b")!)), "example.com")
        XCTAssertEqual(Staging.label(for: .text("anything")), "Text")
    }
}
