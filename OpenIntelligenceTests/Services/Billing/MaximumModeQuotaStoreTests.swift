import XCTest

@testable import OpenIntelligence

/// Pins the daily Maximum-mode allowance that the paywall sells.
///
/// The store existed since 2026-05-12 and nothing called `consumeIfAllowed`, so the "3 left
/// today" label never moved and every free user had unlimited Maximum mode for four months.
/// `ChatScreen.sendMessage` consumes a run now; this pins what consuming means.
final class MaximumModeQuotaStoreTests: XCTestCase {

    private var defaults: UserDefaults!
    private var store: MaximumModeQuotaStore!
    private let limit = 3
    private let noon = Date(timeIntervalSince1970: 1_790_000_000)  // a fixed instant

    override func setUp() {
        super.setUp()
        let suite = "MaximumModeQuotaStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        store = MaximumModeQuotaStore(defaults: defaults, calendar: .init(identifier: .gregorian))
    }

    func testThreeRunsThenBlocked() {
        for expectedRemaining in [2, 1, 0] {
            guard case .allowedMetered(let remaining, let dailyLimit) = store.consumeIfAllowed(limit: limit, now: noon)
            else {
                return XCTFail("run should be allowed")
            }
            XCTAssertEqual(remaining, expectedRemaining)
            XCTAssertEqual(dailyLimit, limit)
        }
        guard
            case .blocked(let remaining, let dailyLimit, let resetsAt) = store.consumeIfAllowed(limit: limit, now: noon)
        else {
            return XCTFail("fourth run should be blocked")
        }
        XCTAssertEqual(remaining, 0)
        XCTAssertEqual(dailyLimit, limit)
        XCTAssertGreaterThan(resetsAt, noon)
    }

    func testBlockedRunDoesNotConsume() {
        for _ in 0..<3 { _ = store.consumeIfAllowed(limit: limit, now: noon) }
        _ = store.consumeIfAllowed(limit: limit, now: noon)
        XCTAssertEqual(store.currentState(limit: limit, now: noon).usedCount, limit)
    }

    func testAllowanceResetsTheNextDay() {
        for _ in 0..<3 { _ = store.consumeIfAllowed(limit: limit, now: noon) }
        let tomorrow = noon.addingTimeInterval(24 * 60 * 60)
        XCTAssertEqual(store.currentState(limit: limit, now: tomorrow).remainingUses, limit)
        guard case .allowedMetered = store.consumeIfAllowed(limit: limit, now: tomorrow) else {
            return XCTFail("a new day should allow a run")
        }
    }
}
