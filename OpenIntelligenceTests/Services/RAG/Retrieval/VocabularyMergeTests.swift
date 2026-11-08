//
//  VocabularyMergeTests.swift
//  OpenIntelligenceTests
//
//  A library's saved vocabulary loads in a task the service starts at launch, and an import can learn into the library
//  before it finishes. Until 5.8 the saved copy replaced what was learned meanwhile; it is now added in.
//

import XCTest

@testable import OpenIntelligence

final class VocabularyMergeTests: XCTestCase {
    private func vocabulary(_ id: UUID, terms: [String: Int], entities: Set<String>, chunks: Int, documents: Int)
        -> ContainerVocabulary
    {
        ContainerVocabulary(
            containerId: id, lastUpdated: Date(timeIntervalSince1970: 0), termFrequencies: terms,
            specificationCodes: [], namedEntities: entities, technicalPhrases: [], documentCount: documents,
            chunkCount: chunks)
    }

    func testWhatWasLearnedBeforeTheSavedCopyLoadedIsKept() {
        let id = UUID()
        let saved = vocabulary(id, terms: ["dha": 3, "zinc": 1], entities: ["Parkinson"], chunks: 100, documents: 2)
        let meanwhile = vocabulary(id, terms: ["dha": 2, "taurine": 4], entities: ["MDPI"], chunks: 595, documents: 1)
        let merged = ContainerVocabularyService.merged(saved: saved, learnedMeanwhile: meanwhile)
        XCTAssertEqual(merged.termFrequencies, ["dha": 5, "zinc": 1, "taurine": 4])
        XCTAssertEqual(merged.namedEntities, ["Parkinson", "MDPI"])
        XCTAssertEqual(merged.chunkCount, 695)
        XCTAssertEqual(merged.documentCount, 3)
    }
}
