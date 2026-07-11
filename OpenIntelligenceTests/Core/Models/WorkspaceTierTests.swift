import XCTest
@testable import OpenIntelligenceEngine

final class WorkspaceTierTests: XCTestCase {

    func testRank() {
        XCTAssertEqual(WorkspaceTier.free.rank, 0)
        XCTAssertEqual(WorkspaceTier.pro.rank, 1)
        XCTAssertEqual(WorkspaceTier.lifetime.rank, 2)
    }

    func testIsAtLeast() {
        // Free tier checks
        XCTAssertTrue(WorkspaceTier.free.isAtLeast(.free))
        XCTAssertFalse(WorkspaceTier.free.isAtLeast(.pro))
        XCTAssertFalse(WorkspaceTier.free.isAtLeast(.lifetime))

        // Pro tier checks
        XCTAssertTrue(WorkspaceTier.pro.isAtLeast(.free))
        XCTAssertTrue(WorkspaceTier.pro.isAtLeast(.pro))
        XCTAssertFalse(WorkspaceTier.pro.isAtLeast(.lifetime))

        // Lifetime tier checks
        XCTAssertTrue(WorkspaceTier.lifetime.isAtLeast(.free))
        XCTAssertTrue(WorkspaceTier.lifetime.isAtLeast(.pro))
        XCTAssertTrue(WorkspaceTier.lifetime.isAtLeast(.lifetime))
    }
}
