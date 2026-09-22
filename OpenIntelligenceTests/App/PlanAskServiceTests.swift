import XCTest

@testable import OpenIntelligence

/// Pins the two unprompted plans asks: once at the end of the setup checklist, and once after the
/// fourth verified answer; both free tier only, both never under test. Each of those is a property that, if it drifted, would
/// turn a single well-timed ask into a nag, and none of them can be seen in a simulator because
/// the sheet needs a verified answer, which needs Foundation Models.
final class PlanAskServiceTests: XCTestCase {

    func testAsksOnTheFourthVerifiedAnswer_forFreeTier_once() {
        XCTAssertTrue(
            PlanAskService.shouldAsk(verifiedAnswers: 4, isFreeTier: true, alreadyShown: false, isTesting: false))
        XCTAssertTrue(
            PlanAskService.shouldAsk(verifiedAnswers: 9, isFreeTier: true, alreadyShown: false, isTesting: false))
    }

    func testWaitsForRealUse_notTheFirstAnswer() {
        // ReviewPromptService asks on the first verified answer and the onboarding screen has just
        // shown; a third ask minutes later would be a nag. Four is after real use.
        XCTAssertGreaterThan(PlanAskService.minimumVerifiedAnswers, ReviewPromptService.minimumVerifiedAnswers)
        XCTAssertEqual(PlanAskService.minimumVerifiedAnswers, 4)
        XCTAssertFalse(
            PlanAskService.shouldAsk(verifiedAnswers: 3, isFreeTier: true, alreadyShown: false, isTesting: false))
        XCTAssertFalse(
            PlanAskService.shouldAsk(verifiedAnswers: 0, isFreeTier: true, alreadyShown: false, isTesting: false))
    }

    func testNeverForAPayingUser() {
        XCTAssertFalse(
            PlanAskService.shouldAsk(verifiedAnswers: 10, isFreeTier: false, alreadyShown: false, isTesting: false))
    }

    func testNeverTwice() {
        XCTAssertFalse(
            PlanAskService.shouldAsk(verifiedAnswers: 10, isFreeTier: true, alreadyShown: true, isTesting: false))
    }

    func testNeverUnderTest() {
        XCTAssertFalse(
            PlanAskService.shouldAsk(verifiedAnswers: 10, isFreeTier: true, alreadyShown: false, isTesting: true))
    }

    func testOnboardingAsk_onceFreeOnly_neverUnderTest() {
        XCTAssertTrue(PlanAskService.shouldAskAfterOnboarding(isFreeTier: true, alreadyShown: false, isTesting: false))
        XCTAssertFalse(PlanAskService.shouldAskAfterOnboarding(isFreeTier: true, alreadyShown: true, isTesting: false))
        XCTAssertFalse(PlanAskService.shouldAskAfterOnboarding(isFreeTier: false, alreadyShown: false, isTesting: false))
        XCTAssertFalse(PlanAskService.shouldAskAfterOnboarding(isFreeTier: true, alreadyShown: false, isTesting: true))
    }

    func testNewEntryPoints_haveCopy() {
        for entry in [PlanUpgradeEntryPoint.launchSale, .momentOfValue, .onboarding] {
            XCTAssertFalse(entry.headline.isEmpty, "\(entry) headline")
            XCTAssertFalse(entry.subheadline.isEmpty, "\(entry) subheadline")
            XCTAssertFalse(entry.subheadline.contains("—"), "\(entry) subheadline carries an em dash")
        }
        XCTAssertTrue(PlanUpgradeEntryPoint.momentOfValue.subheadline.contains("You will not be asked again"))
    }
}
