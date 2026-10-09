//
//  OpenIntelligenceLinksTests.swift
//  OpenIntelligenceTests
//
//  The link the app hands to other people carries a campaign tag, so App Store Connect can count
//  the downloads that came from a share. The plain link stays for opening the store from About.
//

import XCTest

@testable import OpenIntelligence

@MainActor
final class OpenIntelligenceLinksTests: XCTestCase {
    func testSharedLinkCarriesTheProviderTokenAndTheCampaignTag() throws {
        let components = try XCTUnwrap(
            URLComponents(url: OpenIntelligenceLinks.sharedAppStoreURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "apps.apple.com")
        XCTAssertEqual(components.path, "/app/apple-store/id\(OpenIntelligenceLinks.appStoreID)")

        let query = Dictionary(
            uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["pt"], "127101782")
        XCTAssertEqual(query["ct"], OpenIntelligenceLinks.shareCampaignTag)
        XCTAssertEqual(query["mt"], "8")
    }

    func testCampaignTagFitsAppleLimits() {
        // "You can use up to 30 alphanumeric characters and spaces", and a space cannot be first or
        // last: developer.apple.com/help/app-store-connect-analytics/acquisition/campaign-links/,
        // read 2026-10-09. Letters, digits and "_" only, so the tag needs no escaping in a link.
        let tag = OpenIntelligenceLinks.shareCampaignTag
        XCTAssertFalse(tag.isEmpty)
        XCTAssertLessThanOrEqual(tag.count, 30)
        XCTAssertTrue(tag.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }, tag)
    }

    func testPlainStoreLinkIsUntagged() {
        XCTAssertNil(URLComponents(url: OpenIntelligenceLinks.appStoreURL, resolvingAgainstBaseURL: false)?.query)
    }
}
