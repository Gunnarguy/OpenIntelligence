//
//  OpenIntelligenceLinksTests.swift
//  OpenIntelligenceTests
//
//  The link the app hands to other people carries a campaign tag, so App Store Connect can count
//  the downloads that came from a share. The plain link stays for opening the store from About.
//

import XCTest

#if canImport(UIKit)
    import LinkPresentation
    import UIKit
#endif

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

    // MARK: - The share sheet's header (5.7)

    func testShareSheetHeaderHasTheAppIcon() {
        // Read from the bundle's primary icon. The test host is the app, so this is the app's own.
        XCTAssertNotNil(ShareSheetPreview.appIcon)
    }

    func testShareTheAppNamesTheAppAndItsTaggedLink() {
        XCTAssertEqual(ShareSheetPreview.app.title, "OpenIntelligence")
        XCTAssertEqual(ShareSheetPreview.app.url, OpenIntelligenceLinks.sharedAppStoreURL)
        XCTAssertEqual(ShareSheetPreview.answer.title, AnswerShareFormatter.attribution)
    }

    #if canImport(UIKit)
        func testFirstItemCarriesTheHeaderAndEveryItemIsSharedUnchanged() throws {
            let text = "An answer"
            let url = OpenIntelligenceLinks.sharedAppStoreURL
            let items = PreviewedShareItem.items([text, url], preview: .app)
            XCTAssertEqual(items.count, 2)
            let first = try XCTUnwrap(items.first as? PreviewedShareItem)
            XCTAssertEqual(first.item as? String, text)
            XCTAssertEqual(items.last as? URL, url)

            let controller = UIActivityViewController(activityItems: [], applicationActivities: nil)
            XCTAssertEqual(first.activityViewController(controller, itemForActivityType: .message) as? String, text)
            let metadata = try XCTUnwrap(first.activityViewControllerLinkMetadata(controller))
            XCTAssertEqual(metadata.title, "OpenIntelligence")
            XCTAssertEqual(metadata.originalURL, url)
            XCTAssertNotNil(metadata.iconProvider)

            // Nothing to describe leaves the items as they were.
            XCTAssertEqual((PreviewedShareItem.items([text], preview: nil).first as? String), text)
        }
    #endif
}
