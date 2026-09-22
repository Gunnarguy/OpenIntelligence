import XCTest

@testable import OpenIntelligence

/// Pins the one payload shape the plans screen reads, and the count below which it says nothing.
final class AppStoreRatingSnapshotTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testParsesAppleLookupPayload() throws {
        let json =
            #"{"resultCount":1,"results":[{"averageUserRating":4.75,"userRatingCount":5,"trackName":"OpenIntelligence"}]}"#
        let snapshot = try XCTUnwrap(AppStoreRatingService.parse(Data(json.utf8), now: now))
        XCTAssertEqual(snapshot.average, 4.75)
        XCTAssertEqual(snapshot.count, 5)
        XCTAssertEqual(snapshot.fetchedAt, now)
    }

    func testEmptyOrForeignPayload_isNil() {
        XCTAssertNil(AppStoreRatingService.parse(Data(#"{"resultCount":0,"results":[]}"#.utf8), now: now))
        XCTAssertNil(AppStoreRatingService.parse(Data("not json".utf8), now: now))
    }

    func testFiveRatings_isNotWorthShowing() {
        // Five ratings tells a buyer the app is new. The line waits for a count that means something.
        XCTAssertFalse(AppStoreRatingSnapshot(average: 4.75, count: 5, fetchedAt: now).isWorthShowing)
        XCTAssertFalse(
            AppStoreRatingSnapshot(average: 4.9, count: AppStoreRatingSnapshot.minimumRatingCount - 1, fetchedAt: now)
                .isWorthShowing)
        XCTAssertTrue(
            AppStoreRatingSnapshot(average: 4.6, count: AppStoreRatingSnapshot.minimumRatingCount, fetchedAt: now)
                .isWorthShowing)
    }

    func testLineShowsOneDecimalLikeTheStore() {
        XCTAssertEqual(
            AppStoreRatingSnapshot(average: 4.75, count: 143, fetchedAt: now).line, "4.8 on the App Store, 143 ratings")
    }
}
