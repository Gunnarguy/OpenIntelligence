import XCTest

@testable import OpenIntelligenceEngine

/// Graph packing gathers what the device's window can hold (5.7). It gathered 6,000 tokens everywhere, and on a
/// 4,096-token iPhone about half of that was then cut by document position rather than relevance.
final class GraphPackingBudgetTests: XCTestCase {
    func testAFourThousandTokenWindowGetsThreeQuartersOfIt() {
        XCTAssertEqual(RAGService.graphPackingTokenBudget(windowTokens: 4096), 3072)
    }

    /// 3,072 tokens at the packer's 0.71 tokens a character is about 4,330 characters, under the 4,470 the
    /// Standard path had left for passages on a 4,096 iPhone.
    func testTheFourKBudgetFitsWhatTheStandardPathLeavesForPassages() {
        let chars = Double(RAGService.graphPackingTokenBudget(windowTokens: 4096)) / FoundationModelTokenBudget.tokensPerChar
        XCTAssertLessThan(chars, 4470)
    }

    func testLargerWindowsKeepTheOldBudget() {
        XCTAssertEqual(RAGService.graphPackingTokenBudget(windowTokens: 8192), 6000)
        XCTAssertEqual(RAGService.graphPackingTokenBudget(windowTokens: 32768), 6000)
    }

    func testADeviceThatReportsNoWindowCountsAsFourThousand() {
        XCTAssertEqual(RAGService.graphPackingTokenBudget(windowTokens: 0), 3072)
    }
}
