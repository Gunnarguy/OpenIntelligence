import NaturalLanguage
import XCTest
@testable import OpenIntelligenceEngine

final class SemanticChunkerTests: XCTestCase {

    var chunker: SemanticChunker!

    override func setUp() {
        super.setUp()
        chunker = SemanticChunker()
    }

    override func tearDown() {
        chunker = nil
        super.tearDown()
    }

    // MARK: - testChunkText Basic Functionality

    func testChunkText_basicSingleChunk() {
        let text = "This is a short test document. It should be parsed into a single chunk since it is small."
        let documentId = UUID()

        let chunks = chunker.chunkText(text, documentId: documentId)

        XCTAssertEqual(chunks.count, 1)
        XCTAssertEqual(chunks[0].metadata.documentId, documentId)
        XCTAssertEqual(chunks[0].content, text)
        XCTAssertEqual(chunks[0].metadata.chunkIndex, 0)
        XCTAssertEqual(chunks[0].metadata.totalChunks, 1)
    }

    func testChunkText_longTextChunking() {
        // Generate a text that exceeds the target/max size of a chunk
        var longText = ""
        for i in 1...100 {
            longText += "Sentence number \(i) is here to add some length to the text. "
        }

        let documentId = UUID()
        var config = SemanticChunker.ChunkingConfig()
        config.targetSize = 100 // Set a small target to ensure multiple chunks are created
        config.minSize = 50
        config.maxSize = 150
        config.overlap = 20
        config.useTopicDetection = false // Disable topic detection to simplify chunking logic for this test

        let chunks = chunker.chunkText(longText, documentId: documentId, config: config)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertEqual(chunk.metadata.documentId, documentId)
        }
    }

    /// Text with few spaces overlaps by the setting, counted in the tokenizer's words as a passage's size is (5.7). Each
    /// run between spaces here is three words ("r12a:r12b:r12c"), and through 5.6 an overlap of 20 took 20 runs, which
    /// is 60 words.
    func testOverlapInTextWithFewSpacesIsTheSetting() {
        let text = (1...400).map { "r\($0)a:r\($0)b:r\($0)c" }.joined(separator: " ")
        var config = SemanticChunker.ChunkingConfig()
        config.targetSize = 100
        config.minSize = 50
        config.maxSize = 150
        config.overlap = 20
        config.useTopicDetection = false

        let chunks = chunker.chunkText(text, documentId: UUID(), config: config)
        XCTAssertGreaterThan(chunks.count, 3)

        let tokenizer = NLTokenizer(unit: .word)
        for (current, next) in zip(chunks, chunks.dropFirst()) {
            tokenizer.string = next.content
            guard let first = tokenizer.tokens(for: next.content.startIndex..<next.content.endIndex).first,
                let shared = current.content.range(of: String(next.content[first]), options: .backwards)
            else { continue }
            let overlap = String(current.content[shared.lowerBound...])
            tokenizer.string = overlap
            let words = tokenizer.tokens(for: overlap.startIndex..<overlap.endIndex).count
            // No sentence ends in this text, so the overlap starts at the point itself. Through 5.6 it was 60 or more, and
            // with the snap of the time 25 or 26 (review of 2026-10-17).
            XCTAssertLessThanOrEqual(words, config.overlap + 1, "overlap of \(words) words")
        }
    }

    /// The last passage isn't the overlap again (5.7, measured 2026-10-17). A passage that reached the end of the text
    /// still stepped back for the overlap, and the loop cut one more passage of the overlap alone, wholly inside the one
    /// before it, at the end of nearly every document.
    func testTheLastPassageIsNotTheOverlapAgain() {
        let sentence = "The sterilizer cycle must be checked before each use by the operator."
        for ending in ["", "\n\n", " ."] {
            let text = Array(repeating: sentence, count: 60).joined(separator: " ") + ending
            var config = SemanticChunker.ChunkingConfig()
            config.targetSize = 100
            config.minSize = 50
            config.maxSize = 150
            config.overlap = 20
            config.useTopicDetection = false

            let chunks = chunker.chunkText(text, documentId: UUID(), config: config)
            XCTAssertGreaterThan(chunks.count, 2, "ending \(ending.debugDescription)")
            guard let last = chunks.last else { continue }
            let previous = chunks[chunks.count - 2]
            XCTAssertGreaterThan(
                last.metadata.endOffset, previous.metadata.endOffset,
                "ending \(ending.debugDescription): the last passage lies inside the one before it")
            let lastWords = last.content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            XCTAssertTrue(lastWords.hasSuffix("by the operator"), "ending \(ending.debugDescription): the text's last words")
        }
    }

    /// No passage ends inside a word, in text with no sentence end to stop at: a run-on line of words, and records of
    /// JSON (5.7). Through 5.6 the end of the search window counted as a sentence's end wherever it fell.
    func testNoPassageEndsInsideAWord() {
        let runOn = (1...600).map { "word\($0)" }.joined(separator: " ")
        let records = (1...300).map { #"{"id":\#($0),"name":"part-\#($0)","qty":\#($0 % 7)}"# }.joined(separator: " ")
        for text in [runOn, records] {
            var config = SemanticChunker.ChunkingConfig()
            config.targetSize = 100
            config.minSize = 50
            config.maxSize = 150
            config.overlap = 20
            config.useTopicDetection = false
            let chunks = chunker.chunkText(text, documentId: UUID(), config: config)
            XCTAssertGreaterThan(chunks.count, 2)
            for chunk in chunks.dropLast() {
                let end = text.index(text.startIndex, offsetBy: chunk.metadata.endOffset)
                let cutsAWord = end < text.endIndex && end > text.startIndex
                    && !text[end].isWhitespace && !text[text.index(before: end)].isWhitespace
                XCTAssertFalse(cutsAWord, "a passage ends inside a word: …\(chunk.content.suffix(24))")
            }
        }
    }

    /// A sentence ends at the end of the text, at a line break, or after a sentence's end with a space or the text's end
    /// after it; not inside a number, an address or a word (5.7).
    func testWhereASentenceCanEnd() {
        let text = "Check the seal. Replace it yearly!\nPi is 3.14 at example.com today"
        func at(_ offset: Int) -> String.Index { text.index(text.startIndex, offsetBy: offset) }
        XCTAssertTrue(SemanticChunker.canEndSentence(at: at(15), in: text), "after a period, before a space")
        XCTAssertTrue(SemanticChunker.canEndSentence(at: at(16), in: text), "after a period and its space")
        XCTAssertTrue(SemanticChunker.canEndSentence(at: at(34), in: text), "at a line break")
        XCTAssertTrue(SemanticChunker.canEndSentence(at: text.endIndex, in: text))
        XCTAssertFalse(SemanticChunker.canEndSentence(at: at(8), in: text), "inside a word")
        XCTAssertFalse(SemanticChunker.canEndSentence(at: at(43), in: text), "inside 3.14")
        XCTAssertFalse(SemanticChunker.canEndSentence(at: at(57), in: text), "inside example.com")
        XCTAssertFalse(SemanticChunker.canEndSentence(at: at(24), in: text), "after a word and a space")
    }

    func testSnappingToAWordBoundary() {
        let text = "alpha bravo charlie"
        func at(_ offset: Int) -> String.Index { text.index(text.startIndex, offsetBy: offset) }
        XCTAssertEqual(SemanticChunker.snappedToWordBoundary(at(8), in: text, within: 10), at(6), "back to bravo's start")
        XCTAssertEqual(SemanticChunker.snappedToWordBoundary(at(5), in: text, within: 10), at(5), "already at a space")
        XCTAssertEqual(SemanticChunker.snappedToWordBoundary(at(15), in: text, within: 10), at(12), "back to charlie's start")
        let token = String(repeating: "x", count: 50)
        let middle = token.index(token.startIndex, offsetBy: 25)
        XCTAssertEqual(SemanticChunker.snappedToWordBoundary(middle, in: token, within: 10), middle, "a token longer than the reach")
    }

    /// A sentence starts at the start of the text, after a line break, or after a sentence's end, quotes allowed; not in
    /// the middle of a sentence (5.7).
    func testWhereASentenceCanStart() {
        let text = "Check the seal. \"Replace it\" yearly!\nThen torque the bolts to spec"
        func at(_ offset: Int) -> String.Index { text.index(text.startIndex, offsetBy: offset) }
        XCTAssertTrue(SemanticChunker.canStartSentence(at: text.startIndex, in: text))
        XCTAssertTrue(SemanticChunker.canStartSentence(at: at(16), in: text), "after a period and a space")
        XCTAssertTrue(SemanticChunker.canStartSentence(at: at(37), in: text), "after a line break")
        XCTAssertFalse(SemanticChunker.canStartSentence(at: at(6), in: text), "inside a sentence")
        XCTAssertFalse(SemanticChunker.canStartSentence(at: at(42), in: text), "after a word and a space")

        // A dot with no space after it is a number or an address, not a sentence's end; a CJK full stop needs no space.
        let numbers = "Pi is 3.14159 and the site is example.com today"
        func index(in string: String, _ offset: Int) -> String.Index { string.index(string.startIndex, offsetBy: offset) }
        XCTAssertFalse(SemanticChunker.canStartSentence(at: index(in: numbers, 8), in: numbers), "after 3.")
        XCTAssertFalse(SemanticChunker.canStartSentence(at: index(in: numbers, 38), in: numbers), "after example.")
        let japanese = "これは本です。次の文です"
        XCTAssertTrue(SemanticChunker.canStartSentence(at: index(in: japanese, 7), in: japanese), "after 。")
        let quoted = "「止まれ。」次の文"
        XCTAssertTrue(SemanticChunker.canStartSentence(at: index(in: quoted, 6), in: quoted), "after 。 and 」")
        let hindi = "यह पहला वाक्य है। यह दूसरा"
        let afterDanda = hindi.index(after: hindi.firstIndex(of: "\u{0964}")!)
        XCTAssertTrue(SemanticChunker.canStartSentence(at: hindi.index(after: afterDanda), in: hindi), "after । and a space")
    }

    /// Merging a small passage into the one before keeps both lists' order and leaves out repeats (5.7).
    func testMergedKeywordsKeepTheirOrder() {
        XCTAssertEqual(
            SemanticChunker.orderedUnion(["valve", "seal", "torque"], ["seal", "gasket", "valve", "bolt"]),
            ["valve", "seal", "torque", "gasket", "bolt"])
    }

    /// Keywords with the same count come out in alphabetical order, after those with higher counts (5.7). Through 5.6
    /// ties kept a dictionary's order, which changes with every launch.
    func testKeywordsWithTheSameCountAreInAlphabeticalOrder() {
        let counts = ["zebra": 1, "apple": 1, "mango": 2, "kiwi": 1, "fig": 3]
        XCTAssertEqual(SemanticChunker.topKeywords(counts, limit: 4), ["fig", "mango", "apple", "kiwi"])
        XCTAssertEqual(SemanticChunker.topKeywords(counts, limit: 10), ["fig", "mango", "apple", "kiwi", "zebra"])
    }

    func testChunkText_WithEmptyString_ReturnsEmptyArray() {
        let text = ""
        let documentId = UUID()
        let config = SemanticChunker.ChunkingConfig(
            targetSize: 200,
            minSize: 50,
            maxSize: 400,
            overlap: 20,
            useTopicDetection: true,
        )

        let chunks = chunker.chunkText(
            text,
            documentId: documentId,
            config: config
        )

        XCTAssertTrue(chunks.isEmpty || (chunks.count == 1 && chunks.first?.content.isEmpty == true), "Chunking an empty string should return an empty array or a single empty chunk.")
    }

    func testChunkTextAsync_WithEmptyString_ReturnsEmptyArray() async {
        let text = ""
        let documentId = UUID()
        let config = SemanticChunker.ChunkingConfig(
            targetSize: 200,
            minSize: 50,
            maxSize: 400,
            overlap: 20,
            useTopicDetection: true,
        )

        let chunks = await chunker.chunkTextAsync(
            text,
            documentId: documentId,
            config: config
        )

        XCTAssertTrue(chunks.isEmpty || (chunks.count == 1 && chunks.first?.content.isEmpty == true), "Async chunking an empty string should return an empty array or a single empty chunk.")
    }

    /// The preset values, as literals.
    ///
    /// `narrative.targetSize` was asserted here as 280 and is now 260. The preset genuinely
    /// declared 280, and `DocumentProcessor` has always built its config as
    /// `min(activeWindow, maxTargetSize)`, so Word, Excel, PowerPoint, audio and video were
    /// already being chunked at 260. This assertion passed the whole time while pinning a number
    /// that never reached ingestion, which is the limit of comparing a constant to a literal: it
    /// catches a typo, not a value the pipeline refuses.
    ///
    /// `ChunkingLimitsTests.testEveryPresetSurvivesTheClampUnchanged` is the check that would
    /// have caught it, because it asserts every preset against the enforced ceiling rather than
    /// against a number written next to it. Keep both: this one pins the intended shape of each
    /// preset, that one pins that the shape is achievable.
    func testChunkingConfig_presets() {
        let techConfig = SemanticChunker.ChunkingConfig.technicalReference
        XCTAssertEqual(techConfig.targetSize, 240)
        XCTAssertEqual(techConfig.maxSize, 310)

        let narrativeConfig = SemanticChunker.ChunkingConfig.narrative
        XCTAssertEqual(narrativeConfig.targetSize, 260)
        XCTAssertEqual(narrativeConfig.maxSize, 310)

        let codeConfig = SemanticChunker.ChunkingConfig.code
        XCTAssertEqual(codeConfig.targetSize, 180)
        XCTAssertEqual(codeConfig.maxSize, 280)
    }

    // MARK: - Extract Entities

    func testExtractEntitiesNamedEntities() {
        let text = "Tim Cook works at Apple in Cupertino."
        let entities = chunker.extractEntities(text)

        XCTAssertTrue(entities.contains("Tim Cook"), "Should extract Tim Cook as a personal name")
        XCTAssertTrue(entities.contains("Apple"), "Should extract Apple as an organization name")
        XCTAssertTrue(entities.contains("Cupertino"), "Should extract Cupertino as a place name")
    }

    func testExtractEntitiesTechnicalTerms() {
        let text = "We use the SemanticChunker class with Foundation framework."
        let entities = chunker.extractEntities(text)

        XCTAssertTrue(entities.contains("SemanticChunker"), "Should extract SemanticChunker as a technical term (PascalCase)")
    }

    func testExtractEntitiesCapitalizedNouns() {
        let text = "The Model Architecture ensures robust performance."
        let entities = chunker.extractEntities(text)

        XCTAssertTrue(entities.contains("Model") || entities.contains("Architecture") || entities.contains("Model Architecture"), "Should extract Model Architecture as capitalized domain term")
    }

    /// Words that open sentences are not names (5.7, roadmap row "Sentence-opening words like However
    /// become entities"), and the same chunk gives the same entities each time it is read.
    func testWordsThatOpenSentencesAreNotEntitiesAndRepeatedReadsAgree() {
        let text =
            "However, the deposit is due before moving in. Should the tenant leave early, Acme Property keeps it. Generally the office in Cupertino replies within a week."
        let first = chunker.extractEntities(text)
        for word in ["However", "Should", "Generally"] {
            XCTAssertFalse(first.contains(word), "\(word) opens a sentence and is not a name: \(first)")
        }
        XCTAssertTrue(first.contains("Acme Property"), "a name is still found: \(first)")
        XCTAssertTrue(first.contains("Cupertino"), "a name is still found: \(first)")
        for _ in 0..<5 {
            XCTAssertEqual(Set(chunker.extractEntities(text)), Set(first))
        }
    }

    func testExtractEntitiesDeduplication() {
        let text = "Apple makes the iPhone. Apple is a large company."
        let entities = chunker.extractEntities(text)

        let appleCount = entities.filter { $0.lowercased() == "apple" }.count
        XCTAssertEqual(appleCount, 1, "Should deduplicate entities")
    }
}
