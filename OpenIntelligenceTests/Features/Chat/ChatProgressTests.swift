//
//  ChatProgressTests.swift
//  OpenIntelligenceTests
//
//  What the plain chat says it is doing while an answer is on its way (5.7).
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class ChatProgressTests: XCTestCase {
    func testThePlainChatSaysWhatItIsDoingInWords() {
        XCTAssertEqual(ChatProgress.phrase(for: nil, thinksInSteps: false), "Reading your question…")
        XCTAssertEqual(ChatProgress.phrase(for: .queryRewrite, thinksInSteps: false), "Reading your question…")
        XCTAssertEqual(ChatProgress.phrase(for: .rrf, thinksInSteps: false), "Searching your documents…")
        XCTAssertEqual(ChatProgress.phrase(for: .bm25, thinksInSteps: false), "Searching your documents…")
        XCTAssertEqual(ChatProgress.phrase(for: .generation, thinksInSteps: false), "Writing the answer…")
        XCTAssertEqual(ChatProgress.phrase(for: .verification, thinksInSteps: false), "Checking against your documents…")
        // The confidence gate runs before the answer is written, and a tool call looks something up (review, 2026-10-17).
        XCTAssertEqual(ChatProgress.phrase(for: .gating, thinksInSteps: false), "Checking what it found…")
        XCTAssertEqual(ChatProgress.phrase(for: .toolCall, thinksInSteps: true), "Looking through your documents…")
        XCTAssertEqual(ChatProgress.phrase(for: .reasoning, thinksInSteps: true), "Thinking it through…")
        XCTAssertEqual(ChatProgress.phrase(for: .reasoning, thinksInSteps: false), "Working on it…")
    }

    /// No step's technical name reaches the plain chat: every kind of step has words of its own.
    func testNoTechnicalNameReachesThePlainChat() {
        for kind in ThinkingEvent.Kind.allCases {
            let phrase = ChatProgress.phrase(for: kind, thinksInSteps: true)
            for jargon in ["RRF", "BM25", "vector", "rerank", "MMR", "HyDE", "embedding", "fusion"] {
                XCTAssertFalse(phrase.localizedCaseInsensitiveContains(jargon), "\(kind): \(phrase)")
            }
        }
    }
}
