//
//  SampleDocumentDescriptorTests.swift
//  OpenIntelligenceTests
//
//  Guards the matching rule that decides which library documents count as copies of a
//  built-in sample. Getting this wrong is not theoretical: matching only the canonical
//  filename let managed storage's "-2"/"-3" renames survive every refresh, and a capture
//  on 2026-08-27 found a General library holding five documents for three samples.
//

@testable import OpenIntelligence
import XCTest

final class SampleDocumentDescriptorTests: XCTestCase {
    private let sample = SampleDocumentDescriptor(
        filename: "OpenIntelligence Product Guide",
        extension: "md",
        body: "irrelevant to matching"
    )

    /// Spaces become hyphens on disk; the rest of the suite depends on this.
    func testStorageFilenameHyphenatesSpaces() {
        XCTAssertEqual(sample.storageFilename, "OpenIntelligence-Product-Guide.md")
    }

    func testMatchesCanonicalName() {
        XCTAssertTrue(sample.matchesStoredCopy("OpenIntelligence-Product-Guide.md"))
    }

    /// The regression this rule exists for: managed storage appends "-<n>" from 2 upward.
    func testMatchesNumberedCopies() {
        for n in 2...12 {
            XCTAssertTrue(
                sample.matchesStoredCopy("OpenIntelligence-Product-Guide-\(n).md"),
                "-\(n) copy should be recognised as the same sample"
            )
        }
    }

    /// A document the user named themselves must never be swept up by a sample refresh.
    func testDoesNotMatchUserAuthoredSuffixes() {
        for name in [
            "OpenIntelligence-Product-Guide-notes.md",
            "OpenIntelligence-Product-Guide-2b.md",
            "OpenIntelligence-Product-Guide-.md",
            "OpenIntelligence-Product-Guide-2-mine.md"
        ] {
            XCTAssertFalse(sample.matchesStoredCopy(name), "\(name) is not a generated copy")
        }
    }

    func testDoesNotMatchDifferentExtension() {
        XCTAssertFalse(sample.matchesStoredCopy("OpenIntelligence-Product-Guide.txt"))
        XCTAssertFalse(sample.matchesStoredCopy("OpenIntelligence-Product-Guide-2.txt"))
    }

    func testDoesNotMatchDifferentDocument() {
        XCTAssertFalse(sample.matchesStoredCopy("RAG-Technical-Architecture.md"))
        XCTAssertFalse(sample.matchesStoredCopy("RAG-Technical-Architecture-2.md"))
    }

    /// A longer stem that merely starts with this one is a different document.
    func testDoesNotMatchPrefixCollision() {
        XCTAssertFalse(sample.matchesStoredCopy("OpenIntelligence-Product-Guide-Extra-2.md"))
    }
}
