//
//  LayoutMarginStripTests.swift
//  OpenIntelligenceTests
//
//  Text set sideways along a page's edge is left out of the page's text (5.7,
//  `LayoutAwareExtractor.isMarginStrip`). The boxes are the ones Vision returned on 2026-10-14 for a
//  journal article's pages on the Mac, at the app's render scale. Not covered: the article itself,
//  which is not in the repository, and an import on a device.
//

import CoreGraphics
import XCTest

@testable import OpenIntelligence

final class LayoutMarginStripTests: XCTestCase {
    private func box(_ minX: CGFloat, _ maxX: CGFloat, _ minY: CGFloat, _ maxY: CGFloat) -> CGRect {
        CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    func testADownloadNoticeDownTheEdgeIsLeftOut() {
        XCTAssertTrue(LayoutAwareExtractor.isMarginStrip(box(0.970, 0.981, 0.019, 0.978)), "pages 3 to 8")
        XCTAssertTrue(LayoutAwareExtractor.isMarginStrip(box(0.968, 0.981, 0.020, 0.978)), "page 2")
        XCTAssertTrue(LayoutAwareExtractor.isMarginStrip(box(0.020, 0.034, 0.200, 0.800)), "the same down the left edge")
    }

    func testFigureLabelsHeadersAndBodyLinesStay() {
        XCTAssertFalse(LayoutAwareExtractor.isMarginStrip(box(0.065, 0.080, 0.128, 0.170)), "a rotated axis label")
        XCTAssertFalse(LayoutAwareExtractor.isMarginStrip(box(0.382, 0.395, 0.102, 0.196)), "a rotated label mid-page")
        XCTAssertFalse(LayoutAwareExtractor.isMarginStrip(box(0.080, 0.489, 0.703, 0.715)), "a body line")
        XCTAssertFalse(LayoutAwareExtractor.isMarginStrip(box(0.063, 0.329, 0.939, 0.971)), "the journal's logo")
        XCTAssertFalse(LayoutAwareExtractor.isMarginStrip(box(0.875, 0.996, 0.984, 0.997)), "a link at the corner")
    }
}
