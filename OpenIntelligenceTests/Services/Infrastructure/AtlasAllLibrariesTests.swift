//
//  AtlasAllLibrariesTests.swift
//  OpenIntelligenceTests
//
//  The Knowledge Atlas's All Libraries view (5.7) draws every library whose vectors share one
//  embedding space in one projection. These pin which libraries can share it, which space is drawn,
//  how many passages each gives (never more than the 6,000 the main thread can analyse), which
//  passages a map reads, when the Atlas loads, and the axis names the 3D chart's key shows.
//

import SwiftUI
import XCTest

@testable import OpenIntelligence

@MainActor
final class AtlasAllLibrariesTests: XCTestCase {
    private typealias Service = OpenIntelligence.RAGService

    func testTheTwoCopiesOfTheBundledModelShareOneSpace() {
        let coreML = Service.atlasEmbeddingSpace(providerId: EmbeddingProviderDefaults.coreML, dimension: 384)
        let coreAI = Service.atlasEmbeddingSpace(providerId: EmbeddingProviderDefaults.coreAI, dimension: 384)
        XCTAssertEqual(coreML, coreAI)
        XCTAssertNotEqual(coreML, Service.atlasEmbeddingSpace(providerId: EmbeddingProviderDefaults.coreML, dimension: 512))
        XCTAssertNotEqual(coreML, Service.atlasEmbeddingSpace(providerId: "nl_embedding", dimension: 384))
    }

    func testTheSpaceWithTheMostPassagesIsDrawnAndEmptyLibrariesAreNotNamed() {
        let main = UUID(), notes = UUID(), emptyA = UUID(), emptyB = UUID(), other = UUID()
        let libraries: [(id: UUID, space: String, passages: Int)] = [
            (main, "bundled-384", 10_000), (notes, "bundled-384", 31),
            (emptyA, "nl-512", 0), (emptyB, "nl-512", 0), (other, "nl-512", 500),
        ]
        let choice = Service.atlasGroupChoice(libraries: libraries, activeId: other)
        XCTAssertEqual(choice.included, [main, notes], "two empty libraries in another space do not outvote 10,031 passages")
        XCTAssertEqual(choice.excluded, [other], "an empty library is neither drawn nor named")
        XCTAssertEqual(Service.atlasGroupChoice(libraries: [(emptyA, "a", 0)], activeId: emptyA).included, [])
    }

    func testATieGoesToTheOpenLibraryThenToTheSpaceName() {
        let a = UUID(), b = UUID(), c = UUID()
        let tied: [(id: UUID, space: String, passages: Int)] = [(a, "space-b", 100), (b, "space-a", 100), (c, "space-c", 100)]
        XCTAssertEqual(Service.atlasGroupChoice(libraries: tied, activeId: c).included, [c], "the open library's space")
        XCTAssertEqual(Service.atlasGroupChoice(libraries: tied, activeId: nil).included, [b], "then the first by name")
        XCTAssertEqual(Service.atlasGroupChoice(libraries: tied, activeId: UUID()).included, [b], "the same on every launch")
    }

    func testPassagesWithAMissingOrWrongSizedVectorAreLeftOut() {
        let document = UUID()
        func passage(_ width: Int) -> OpenIntelligence.DocumentChunk {
            OpenIntelligence.DocumentChunk(
                documentId: document, content: "a passage", embedding: Array(repeating: 0.1, count: width),
                metadata: OpenIntelligence.ChunkMetadata(chunkIndex: 0, wordCount: 2))
        }
        let kept = Service.passagesWithVectors([passage(384), passage(0), passage(512), passage(384)], dimension: 384)
        XCTAssertEqual(kept.map(\.embedding.count), [384, 384])
    }

    func testLibrariesThatFitAreDrawnWhole() {
        XCTAssertEqual(Service.atlasShares(passages: []), [])
        XCTAssertEqual(Service.atlasShares(passages: [10, 0, 2_000]), [10, 0, 2_000])
        XCTAssertEqual(Service.atlasShares(passages: [6_000]), [6_000])
        XCTAssertEqual(Service.atlasShares(passages: [-5, 7]), [0, 7])
    }

    func testLargeLibrariesShareTheLimitAndASmallOneStillShows() {
        let passages = [144_000, 63_000, 120, 0]
        let shares = Service.atlasShares(passages: passages)
        XCTAssertEqual(shares.count, passages.count)
        XCTAssertLessThanOrEqual(shares.reduce(0, +), Service.visualizationPassageLimit)
        XCTAssertGreaterThan(shares.reduce(0, +), Service.visualizationPassageLimit - passages.count)
        XCTAssertEqual(shares[2], 120, "a library under 300 passages is drawn whole")
        XCTAssertEqual(shares[3], 0)
        XCTAssertGreaterThan(shares[0], shares[1], "the larger library gives more")
        for (share, count) in zip(shares, passages) { XCTAssertLessThanOrEqual(share, count) }
    }

    func testManyLibrariesNeverPassTheLimit() {
        // Thirty libraries at 300 each would be 9,000, past what the main thread can analyse.
        let passages = Array(repeating: 1_000, count: 30)
        let shares = Service.atlasShares(passages: passages)
        XCTAssertLessThanOrEqual(shares.reduce(0, +), Service.visualizationPassageLimit)
        XCTAssertTrue(shares.allSatisfy { $0 >= 200 }, "every library still shows: \(shares)")
    }

    func testTheAtlasLoadsWhenAnImportEndsNotWhenItStarts() {
        let library = UUID()
        let settled = AtlasContentKey(containerId: library, documentCount: 3, importing: false)
        let importing = AtlasContentKey(containerId: library, documentCount: 3, importing: true)
        let after = AtlasContentKey(containerId: library, documentCount: 13, importing: true)
        let ended = AtlasContentKey(containerId: library, documentCount: 13, importing: false)

        XCTAssertFalse(settled.onlyStartsAnImport(after: nil), "the first appearance loads")
        XCTAssertTrue(importing.onlyStartsAnImport(after: settled), "nothing new is in the library yet")
        XCTAssertEqual(importing, after, "the key holds still while the import adds documents")
        XCTAssertNotEqual(ended, after, "the end of the import changes the key")
        XCTAssertFalse(ended.onlyStartsAnImport(after: importing))
        XCTAssertFalse(importing.onlyStartsAnImport(after: importing), "appearing again mid-import loads, as before")

        let other = AtlasContentKey(containerId: UUID(), documentCount: 3, importing: true)
        XCTAssertFalse(other.onlyStartsAnImport(after: settled), "another library loads even mid-import")
        let tsne = AtlasContentKey(containerId: library, documentCount: 3, importing: true, variant: "tsne")
        XCTAssertFalse(tsne.onlyStartsAnImport(after: settled), "another projection loads even mid-import")
    }

    func testAChangeOfCountAloneWaitsAndAChangeOfLibraryOrViewDoesNot() {
        let library = UUID()
        let loaded = AtlasContentKey(containerId: library, documentCount: 10, importing: false)
        // A re-embed re-adds its documents one at a time and each clears the import flag as it ends.
        XCTAssertTrue(AtlasContentKey(containerId: library, documentCount: 11, importing: false).settlesFirst(after: loaded))
        XCTAssertTrue(AtlasContentKey(containerId: library, documentCount: 9, importing: false).settlesFirst(after: loaded))
        XCTAssertFalse(AtlasContentKey(containerId: UUID(), documentCount: 10, importing: false).settlesFirst(after: loaded))
        XCTAssertFalse(
            AtlasContentKey(containerId: library, documentCount: 10, importing: false, variant: "tsne").settlesFirst(after: loaded))
        XCTAssertFalse(AtlasContentKey(containerId: library, documentCount: 10, importing: true).settlesFirst(after: loaded))
        XCTAssertFalse(loaded.settlesFirst(after: nil), "the first appearance loads at once")
    }

    func testEveryLibraryGetsAColourOfItsOwnWhenTheyAllStartTheSame() {
        let palette: [PlatformColor] = [
            PlatformColor(Color.blue), PlatformColor(Color.purple), PlatformColor(Color.green),
            PlatformColor(Color.orange), PlatformColor(Color.pink), PlatformColor(Color.teal),
        ]
        let colors = Fullscreen3DAtlasView.distinctLibraryColors(Array(repeating: "#4F46E5", count: 10), palette: palette)
        XCTAssertEqual(colors.count, 10)
        let rgb = colors.map { Fullscreen3DAtlasView.rgb(of: $0) }
        XCTAssertEqual(rgb[0].x, 0x4F / 255.0, accuracy: 0.01, "the first library keeps its own colour")
        for i in rgb.indices {
            for j in rgb.indices where j > i {
                let distance = abs(rgb[i].x - rgb[j].x) + abs(rgb[i].y - rgb[j].y) + abs(rgb[i].z - rgb[j].z)
                XCTAssertGreaterThanOrEqual(distance, 0.15, "libraries \(i) and \(j) look alike")
            }
        }
    }

    func testAxisTitlesNameBothEnds() {
        XCTAssertEqual(AtlasChart3D.axisTitle(negative: "lease", positive: "recipes", fallback: "X"), "lease ↔ recipes")
        XCTAssertEqual(AtlasChart3D.axisTitle(negative: "", positive: "recipes", fallback: "X"), "recipes")
        XCTAssertEqual(AtlasChart3D.axisTitle(negative: "lease", positive: "", fallback: "X"), "lease")
        XCTAssertEqual(AtlasChart3D.axisTitle(negative: "", positive: "", fallback: "Y"), "Y")
        XCTAssertEqual(
            AtlasChart3D.axisTitle(negative: "Component 3", positive: "Component 3", fallback: "Z"), "Component 3",
            "an axis whose ends do not differ is named once")
    }
}
