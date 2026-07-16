import XCTest
@testable import OpenIntelligenceEngine

final class PCCConsentPreferenceMigrationTests: XCTestCase {
    func testCanonicalAllowedWinsOverStaleLegacyAsk() {
        let result = PCCConsentPreferenceMigration.resolve(
            canonicalRaw: CloudConsentState.allowed.rawValue,
            legacyRaw: PCCSettings.ask.rawValue
        )

        XCTAssertEqual(result.consent, .allowed)
        XCTAssertEqual(result.setting, .allow)
    }

    func testCanonicalDeniedWinsOverStaleLegacyAllow() {
        let result = PCCConsentPreferenceMigration.resolve(
            canonicalRaw: CloudConsentState.denied.rawValue,
            legacyRaw: PCCSettings.allow.rawValue
        )

        XCTAssertEqual(result.consent, .denied)
        XCTAssertEqual(result.setting, .never)
    }

    func testLegacyRememberedChoiceMigratesWhenCanonicalKeyIsMissing() {
        let result = PCCConsentPreferenceMigration.resolve(
            canonicalRaw: nil,
            legacyRaw: PCCSettings.allow.rawValue
        )

        XCTAssertEqual(result.consent, .allowed)
        XCTAssertEqual(result.setting, .allow)
    }

    func testNoRememberedChoiceRemainsAskWhenNeeded() {
        let result = PCCConsentPreferenceMigration.resolve(canonicalRaw: nil, legacyRaw: nil)

        XCTAssertEqual(result.consent, .notDetermined)
        XCTAssertEqual(result.setting, .ask)
    }
}
