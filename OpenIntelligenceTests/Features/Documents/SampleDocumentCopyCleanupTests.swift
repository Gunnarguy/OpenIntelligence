import XCTest

@testable import OpenIntelligence

/// Pins which sample copies the refresh pass deletes.
///
/// Managed storage uniquifies a colliding filename by appending `-2`, `-3` and so on, and a
/// sample refresh could leave such a copy beside the canonical file. Until 2026-09-14 the cleanup
/// ran only for samples whose content was stale, so a copy left by an earlier refresh survived
/// once the content was current; the owner's General library sat at five documents for three
/// samples. The decision is a pure function now, and its one hard rule is that a lone numbered
/// copy is never deleted: it may be the only copy the user has.
final class SampleDocumentCopyCleanupTests: XCTestCase {

    private let samples = [
        SampleDocumentDescriptor(filename: "OpenIntelligence Product Guide", extension: "md", body: ""),
        SampleDocumentDescriptor(filename: "RAG Technical Architecture", extension: "md", body: ""),
        SampleDocumentDescriptor(filename: "Apple Intelligence & Private Cloud Compute", extension: "md", body: ""),
    ]

    func testNumberedCopyBesideItsCanonical_isRemoved() {
        let existing = [
            "OpenIntelligence-Product-Guide.md",
            "RAG-Technical-Architecture.md",
            "RAG-Technical-Architecture-2.md",
            "Apple-Intelligence-&-Private-Cloud-Compute.md",
        ]
        XCTAssertEqual(
            SampleDocumentManager.numberedCopiesToRemove(existingFilenames: existing, samples: samples),
            ["RAG-Technical-Architecture-2.md"]
        )
    }

    func testFiveDocumentsForThreeSamples_losesBothCopies() {
        let existing = [
            "OpenIntelligence-Product-Guide.md",
            "OpenIntelligence-Product-Guide-2.md",
            "RAG-Technical-Architecture.md",
            "RAG-Technical-Architecture-3.md",
            "Apple-Intelligence-&-Private-Cloud-Compute.md",
        ]
        let doomed = SampleDocumentManager.numberedCopiesToRemove(existingFilenames: existing, samples: samples)
        XCTAssertEqual(Set(doomed), ["OpenIntelligence-Product-Guide-2.md", "RAG-Technical-Architecture-3.md"])
    }

    func testLoneNumberedCopy_isKept() {
        // The canonical file is gone; the -2 is the user's only copy and must survive.
        let existing = [
            "OpenIntelligence-Product-Guide.md",
            "RAG-Technical-Architecture-2.md",
            "Apple-Intelligence-&-Private-Cloud-Compute.md",
        ]
        XCTAssertTrue(
            SampleDocumentManager.numberedCopiesToRemove(existingFilenames: existing, samples: samples).isEmpty)
    }

    func testUsersOwnFiles_areNeverTouched() {
        let existing = [
            "OpenIntelligence-Product-Guide.md",
            "OpenIntelligence-Product-Guide-notes.md",
            "RAG-Technical-Architecture.md",
            "RAG-Technical-Architecture-2.pdf",
            "Apple-Intelligence-&-Private-Cloud-Compute.md",
            "Quarterly-Report.pdf",
        ]
        XCTAssertTrue(
            SampleDocumentManager.numberedCopiesToRemove(existingFilenames: existing, samples: samples).isEmpty)
    }

    func testEmptyLibrary_removesNothing() {
        XCTAssertTrue(SampleDocumentManager.numberedCopiesToRemove(existingFilenames: [], samples: samples).isEmpty)
    }

    // MARK: Where refreshed samples go (2026-11-18)

    private let general = UUID()
    private let library4 = UUID()
    private let deleted = UUID()

    func testRefreshTarget_skipsALibraryThatNoLongerExists() {
        // The owner's Mac: two stale records from a deleted library came first, then three in General.
        XCTAssertEqual(
            SampleDocumentManager.refreshTarget(
                storedIn: [deleted, deleted, general, general, general], liveLibraries: [general, library4]),
            general)
    }

    func testRefreshTarget_keepsTheLibraryTheSamplesWereIn() {
        XCTAssertEqual(
            SampleDocumentManager.refreshTarget(storedIn: [library4, library4], liveLibraries: [general, library4]),
            library4)
    }

    func testRefreshTarget_fallsBackToTheDefaultLibrary() {
        XCTAssertEqual(
            SampleDocumentManager.refreshTarget(storedIn: [nil, deleted], liveLibraries: [general, library4]), general)
    }

    // MARK: - Where a replay of the guides goes (5.8, `importSamples`)

    func testExistingGuideLibrary_skipsAGuideRecordInADeletedLibrary() {
        // The owner's Mac on 2026-11-18: a guide record named deleted BDB0BCA5, and the import went to Library 4.
        XCTAssertEqual(
            SampleDocumentManager.existingGuideLibrary(storedIn: [deleted, general], liveLibraries: [general, library4]),
            general)
    }

    func testExistingGuideLibrary_isNilWhenEveryGuideSitsInADeletedLibrary() {
        // Nil sends the guides to the guide library, never to the deleted one or the one on screen.
        XCTAssertNil(
            SampleDocumentManager.existingGuideLibrary(storedIn: [deleted, deleted], liveLibraries: [general, library4]))
    }

    func testExistingGuideLibrary_aRecordWithNoLibraryIsTheDefaultOne() {
        XCTAssertEqual(
            SampleDocumentManager.existingGuideLibrary(storedIn: [deleted, nil], liveLibraries: [general, library4]),
            general)
        XCTAssertEqual(
            SampleDocumentManager.existingGuideLibrary(storedIn: [library4], liveLibraries: [general, library4]),
            library4)
    }
}
