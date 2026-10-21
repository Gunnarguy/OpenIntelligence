//
//  RetrievalStyleTests.swift
//  OpenIntelligenceTests
//
//  Library Settings' Search section (5.7). Through 5.6 its styles were not shown, its controls sat
//  behind a developer switch that was always off, tuning after an import could replace values a
//  person set, and Passages Needed acted only for a library whose values equalled the High Accuracy
//  preset, where the acceptance override, set for nearly any library of ten passages, skipped it.
//  These pin what each choice does.
//

import XCTest

@testable import OpenIntelligenceEngine

@MainActor
final class RetrievalStyleTests: XCTestCase {
    private func passage(_ score: Float) -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: UUID(), content: "passage \(score)", embedding: [], metadata: ChunkMetadata(chunkIndex: 0)),
            similarityScore: score,
            rank: 1,
            sourceDocument: "Lease.pdf",
            pageNumber: nil
        )
    }

    // MARK: - Styles

    func testAChosenStyleSetsItsPresetAndIsKeptAsThePersons() throws {
        for style in RetrievalStyle.allCases where style != .automatic {
            let config = RetrievalConfig.chosen(style, documentTypes: [.pdf])
            let preset = try XCTUnwrap(style.preset)
            XCTAssertEqual(config.minSimilarity, preset.minSimilarity, "\(style)")
            XCTAssertEqual(config.vectorWeight, preset.vectorWeight, "\(style)")
            XCTAssertEqual(config.lexicalWeight, preset.lexicalWeight, "\(style)")
            XCTAssertEqual(config.mmrLambda, preset.mmrLambda, "\(style)")
            XCTAssertEqual(config.minConfidentChunks, preset.minConfidentChunks, "\(style)")
            XCTAssertTrue(config.isChosenByPerson, "\(style)")
            XCTAssertEqual(config.style, style, "a chosen preset reads back as itself")
        }
    }

    func testAutomaticFollowsTheLibrarysDocumentsAndIsLeftToTheApp() {
        let prose = RetrievalConfig.chosen(.automatic, documentTypes: [.pdf, .markdown, .text])
        XCTAssertFalse(prose.isChosenByPerson)
        XCTAssertEqual(prose.style, .automatic)
        XCTAssertEqual(prose.summary, "Balanced")

        let code = RetrievalConfig.chosen(.automatic, documentTypes: [.swift, .python, .pdf])
        XCTAssertFalse(code.isChosenByPerson)
        XCTAssertEqual(code.summary, "Technical Manual", "most of the library is code")
    }

    func testAStrictLibraryNobodyChoseForIsNotCalledAutomatic() {
        var strict = RetrievalConfig.default
        strict.minSimilarity = 0.52  // what an older library's strict mode became
        XCTAssertFalse(strict.isChosenByPerson)
        XCTAssertNil(RetrievalConfig.autoTuned(current: strict, recommended: .technicalManual), "tuning leaves it")
        XCTAssertNil(strict.style, "so it reads as Custom, not Automatic")
    }

    func testAPresetMovedOffItsValuesReadsAsCustom() {
        var precise = RetrievalConfig.chosen(.precise, documentTypes: [])
        precise.mmrLambda = 0.75
        XCTAssertNil(precise.style, "0.75 is not High Precision's 0.80")
        precise.mmrLambda = 0.30 + 10 * 0.05  // the slider's arithmetic back to 0.80
        XCTAssertEqual(precise.style, .precise)
    }

    func testValuesSetByHandAreCustom() {
        var config = RetrievalConfig.chosen(.balanced, documentTypes: [])
        config.minSimilarity = 0.60
        XCTAssertNil(config.style, "no preset has a 0.60 bar")

        var needed = RetrievalConfig.chosen(.balanced, documentTypes: [])
        needed.minConfidentChunks = 3
        XCTAssertNil(needed.style, "Balanced needs one passage; three is the person's own")
    }

    func testALibraryNoOneHasChosenForReadsAsAutomatic() {
        XCTAssertEqual(RetrievalConfig.default.style, .automatic)
        XCTAssertEqual(RetrievalConfig.technicalManual.style, .automatic)
        // The High Accuracy preset has always carried the flag, and was never something tuning picks.
        XCTAssertEqual(RetrievalConfig.highAccuracy.style, .precise)
    }

    // MARK: - Tuning after an import

    func testTuningLeavesThePersonsValuesAlone() {
        let chosen = RetrievalConfig.chosen(.exploratory, documentTypes: [])
        XCTAssertNil(RetrievalConfig.autoTuned(current: chosen, recommended: .technicalManual))
    }

    func testTuningChangesAnAutomaticLibraryWhenItsDocumentsCallForIt() {
        let tuned = RetrievalConfig.autoTuned(current: .default, recommended: .technicalManual)
        XCTAssertEqual(tuned?.summary, "Technical Manual")
        XCTAssertEqual(tuned?.isChosenByPerson, false, "still the app's to change")
        XCTAssertNil(RetrievalConfig.autoTuned(current: .default, recommended: .default), "nothing to change")
    }

    func testTuningLeavesAHighBarAlone() {
        var strict = RetrievalConfig.default
        strict.minSimilarity = 0.55
        XCTAssertNil(RetrievalConfig.autoTuned(current: strict, recommended: .technicalManual))
    }

    // MARK: - Passages Needed

    func testOnePassageNeededNeverHoldsAnAnswerBack() {
        var config = RetrievalConfig.chosen(.balanced, documentTypes: [])
        config.minSimilarity = 0.90
        XCTAssertNil(RetrievalPolicyService.strongPassageShortfall([passage(0.1)], config: config))
    }

    func testTooFewPassagesOverTheBarAreReported() {
        var config = RetrievalConfig.chosen(.balanced, documentTypes: [])
        config.minSimilarity = 0.40
        config.minConfidentChunks = 3

        let short = RetrievalPolicyService.strongPassageShortfall(
            [passage(0.62), passage(0.41), passage(0.39), passage(0.20)], config: config)
        XCTAssertEqual(short?.found, 2)
        XCTAssertEqual(short?.needed, 3)

        let enough = RetrievalPolicyService.strongPassageShortfall(
            [passage(0.62), passage(0.41), passage(0.40)], config: config)
        XCTAssertNil(enough, "a passage exactly on the bar clears it")
    }

    func testAPassageIsCountedAtTheScoreTheRerankerGaveIt() {
        let precise = RetrievalConfig.chosen(.precise, documentTypes: [])
        let best = passage(0.88)
        let rescued = passage(0.86)  // a table passage lifted to just under the best so it reaches the answer
        let reranked: [UUID: Float] = [best.chunk.id: 0.88, rescued.chunk.id: 0.21]
        let short = RetrievalPolicyService.strongPassageShortfall(
            [best, rescued], config: precise, score: { reranked[$0.chunk.id] ?? $0.similarityScore })
        XCTAssertEqual(short?.found, 1, "the rescued passage is not a close match")
        XCTAssertNil(RetrievalPolicyService.strongPassageShortfall([best, rescued], config: precise))
    }

    func testHighPrecisionNeedsTwoPassagesOverHalf() {
        let precise = RetrievalConfig.chosen(.precise, documentTypes: [])
        XCTAssertEqual(
            RetrievalPolicyService.strongPassageShortfall([passage(0.71), passage(0.49)], config: precise)?.found, 1)
        XCTAssertNil(RetrievalPolicyService.strongPassageShortfall([passage(0.71), passage(0.52)], config: precise))
    }

    // MARK: - The closeness bar

    func testAChosenBarIsUsedAsGivenInsteadOfTheLowerOfItAndTheModes() async {
        let profile = await QueryProfileService.shared.buildProfile(
            for: "What does the lease say about subletting the unit?")
        let strong = RetrievalMetrics(
            topSimilarity: 0.80, secondSimilarity: 0.70, averageTopFive: 0.70, candidateCount: 20)

        var chosen = RetrievalConfig.chosen(.balanced, documentTypes: [])
        chosen.minSimilarity = 0.40
        let held = RetrievalPolicyService.filteringDecision(
            for: profile, qualityMode: .standard, retrievalConfig: chosen, lenient: false, metrics: strong)
        XCTAssertEqual(held.baseMinSimilarity, 0.40, accuracy: 0.0001)

        var automatic = chosen
        automatic.isChosenByPerson = false
        let lowered = RetrievalPolicyService.filteringDecision(
            for: profile, qualityMode: .standard, retrievalConfig: automatic, lenient: false, metrics: strong)
        XCTAssertEqual(
            lowered.baseMinSimilarity, RAGQualityMode.standard.minSimilarity, accuracy: 0.0001,
            "left to the app, the bar is the lower of the library's and the mode's")
    }

    // MARK: - Saved form

    func testThePersonsChoiceSurvivesTheLibrarysSavedForm() throws {
        let chosen = RetrievalConfig.chosen(.technical, documentTypes: [])
        let decoded = try JSONDecoder().decode(RetrievalConfig.self, from: JSONEncoder().encode(chosen))
        XCTAssertTrue(decoded.isChosenByPerson)
        XCTAssertEqual(decoded.style, .technical)
    }
}
