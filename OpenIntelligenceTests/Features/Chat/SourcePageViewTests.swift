//
//  SourcePageViewTests.swift
//  OpenIntelligenceTests
//
//  The page a cited passage is on (5.7): finding the passage in a page's text, and going to it in a PDF.
//

import PDFKit
import SwiftUI
import XCTest

@testable import OpenIntelligence

final class PassageLocatorTests: XCTestCase {
    /// A PDF's text layer breaks lines and doubles spaces where the passage does not.
    func testFindsAPassageAcrossLineBreaksSpacesAndCase() throws {
        let page = "CLEANING\nSoak the handpiece for 15\nminutes in an enzymatic  solution.\nRinse it under running water for one minute.\nDry it."
        let passage = "Soak the handpiece for 15 minutes in an enzymatic solution. Rinse it under running water for one minute."

        let range = try XCTUnwrap(PassageLocator.range(of: passage, in: page))
        let found = (page as NSString).substring(with: range)

        XCTAssertTrue(found.hasPrefix("Soak the handpiece for 15\nminutes"))
        XCTAssertTrue(found.hasSuffix("for one minute."))
        XCTAssertFalse(found.contains("Dry it"))
    }

    /// A passage that runs over from the page before is highlighted where this page holds it.
    func testFindsThePartOfAPassageThatIsOnThePage() throws {
        let page = "Rinse it under running water for one minute. Dry it with a lint-free cloth before you store it."
        let passage = "Soak the handpiece for 15 minutes in an enzymatic solution. Rinse it under running water for one minute."

        let range = try XCTUnwrap(PassageLocator.range(of: passage, in: page))

        XCTAssertEqual((page as NSString).substring(with: range), "Rinse it under running water for one minute.")
    }

    func testFindsNothingOnAPageThatDoesNotHoldThePassage() {
        let page = "Sterilize the handpiece in a steam autoclave at 132 degrees for four minutes."
        let passage = "Soak the handpiece for 15 minutes in an enzymatic solution."

        XCTAssertNil(PassageLocator.range(of: passage, in: page))
    }

    /// Long sentences are matched by their first 12 words, and words carry their punctuation, which is matched as text.
    func testPiecesAreSentencesOfFourWordsOrMoreCutToTwelve() {
        let passage = "Warning. Do not immerse the battery pack (part 4100-110) in any liquid, solvent or cleaning solution at any time."

        let pieces = PassageLocator.pieces(of: passage)

        XCTAssertEqual(pieces.count, 1)
        XCTAssertEqual(pieces.first?.count, 12)
        XCTAssertEqual(pieces.first?.first, "Do")
        XCTAssertNotNil(
            PassageLocator.range(of: passage, in: "Do not immerse the battery pack (part 4100-110) in any liquid, solvent or water."))
    }

    func testAShortPassageIsOnePiece() {
        XCTAssertEqual(PassageLocator.pieces(of: "15 minutes"), [["15", "minutes"]])
        XCTAssertEqual(PassageLocator.pieces(of: "Minutes"), [])
    }

    /// The last sentence is matched whole when the page holds it, so a long one is highlighted to its end and not only
    /// through its first 12 words.
    func testALongLastSentenceIsHighlightedToItsEnd() throws {
        let last = "Rinse the handpiece under warm running tap water for at least one full minute while you flush every channel."
        let page = "CLEANING\nSoak the handpiece for 15 minutes in an enzymatic solution.\n\(last)\nDry it."
        let passage = "Soak the handpiece for 15 minutes in an enzymatic solution. \(last)"

        let range = try XCTUnwrap(PassageLocator.range(of: passage, in: page))

        XCTAssertTrue((page as NSString).substring(with: range).hasSuffix("flush every channel."))
    }

    /// A saved conversation keeps a passage cut short with "..." after it, sometimes inside a word; the highlight runs
    /// to the cut.
    func testACutOffPassageIsHighlightedToWhereItWasCut() throws {
        let page = "Soak the handpiece for 15 minutes in an enzymatic solution. Rinse it under running water for one minute."

        let cut = try XCTUnwrap(
            PassageLocator.range(
                of: "Soak the handpiece for 15 minutes in an enzymatic solution. Rinse it under running wa...", in: page))
        let ellipsis = try XCTUnwrap(
            PassageLocator.range(of: "Soak the handpiece for 15 minutes in an enzymatic solution. Rinse it under running\u{2026}", in: page))

        XCTAssertTrue((page as NSString).substring(with: cut).hasSuffix("Rinse it under running wa"))
        XCTAssertTrue((page as NSString).substring(with: ellipsis).hasSuffix("Rinse it under running"))
    }
}

#if canImport(UIKit)
    @MainActor
    final class PassageRevealTests: XCTestCase {
        /// A PDF with one line of text on each page, drawn the way a document's text layer is.
        private func pdf(_ pages: [String]) throws -> PDFDocument {
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
            let data = renderer.pdfData { context in
                for text in pages {
                    context.beginPage()
                    (text as NSString).draw(
                        in: CGRect(x: 72, y: 72, width: 468, height: 648),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
                }
            }
            return try XCTUnwrap(PDFDocument(data: data))
        }

        func testGoesToThePageAndSelectsThePassage() throws {
            let document = try pdf([
                "Setting up the console.",
                "Soak the handpiece for 15 minutes in an enzymatic solution.",
                "Sterilizing the handpiece.",
            ])

            let target = try XCTUnwrap(
                PassageReveal.target(
                    in: document, pageIndex: 1, passage: "Soak the handpiece for 15 minutes in an enzymatic solution."))

            XCTAssertEqual(document.index(for: target.page), 1)
            XCTAssertEqual(target.selection?.string?.contains("15 minutes"), true)
        }

        func testGoesToThePageWithoutASelectionWhenItsTextDoesNotHoldThePassage() throws {
            let document = try pdf(["Setting up the console.", "Sterilizing the handpiece."])

            let target = try XCTUnwrap(
                PassageReveal.target(in: document, pageIndex: 1, passage: "Soak the handpiece for 15 minutes in an enzymatic solution."))

            XCTAssertEqual(document.index(for: target.page), 1)
            XCTAssertNil(target.selection)
        }

        /// A page number past the end, from a file that changed since its import, opens the last page.
        func testAPagePastTheEndOpensTheLastPage() throws {
            let document = try pdf(["One.", "Two."])

            let target = try XCTUnwrap(PassageReveal.target(in: document, pageIndex: 9, passage: "Two."))

            XCTAssertEqual(document.index(for: target.page), 1)
        }

        /// The view itself, in a window: once it is laid out it shows the cited page with the passage highlighted.
        /// Before its first layout a PDF view has nothing to scroll, which is why it goes there afterwards.
        func testTheViewShowsThePageWithThePassageHighlightedOnceItIsLaidOut() throws {
            let passage = "Soak the handpiece for 15 minutes in an enzymatic solution."
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("SourcePage-\(UUID().uuidString).pdf")
            let pages = ["Setting up the console.", "Cleaning.", passage, "Sterilizing the handpiece."]
            try XCTUnwrap(try pdf(pages).dataRepresentation()).write(to: url)
            defer { try? FileManager.default.removeItem(at: url) }
            let document = Document(filename: "Handpiece IFU.pdf", fileURL: url, contentType: .pdf)
            let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
            let host = UIHostingController(
                rootView: SourcePageView(document: document, pageNumber: 3, passage: passage, chunk: nil))
            window.rootViewController = host
            window.isHidden = false
            defer { window.isHidden = true }

            var pdfView: RevealingPDFView?
            for _ in 0..<40 where pdfView?.highlightedSelections == nil {
                RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                pdfView = Self.firstPDFView(in: host.view)
            }

            let shown = try XCTUnwrap(pdfView)
            let current = try XCTUnwrap(shown.currentPage)
            XCTAssertEqual(shown.document?.index(for: current), 2)
            XCTAssertEqual(shown.highlightedSelections?.first?.string?.contains("15 minutes"), true)
        }

        /// A saved conversation's copy of a passage is cut short; when the library's whole copy arrives, the view
        /// highlights again, to the passage's end.
        func testAWholeCopyOfThePassageIsHighlightedAgain() throws {
            let whole = "Soak the handpiece for 15 minutes in an enzymatic solution. Rinse it under running water for one minute."
            let view = RevealingPDFView(frame: CGRect(x: 0, y: 0, width: 402, height: 800))
            view.document = try pdf(["Cleaning.", whole])
            func highlighted() -> String {
                (view.highlightedSelections?.first?.string ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }

            view.show("Soak the handpiece for 15 minutes in an enzymatic solution. Rinse it u...", pageIndex: 1)
            XCTAssertTrue(highlighted().hasSuffix("enzymatic solution."))

            view.show(whole, pageIndex: 1)
            XCTAssertTrue(highlighted().hasSuffix("for one minute."))
        }

        private static func firstPDFView(in view: UIView) -> RevealingPDFView? {
            if let found = view as? RevealingPDFView { return found }
            for subview in view.subviews {
                if let found = firstPDFView(in: subview) { return found }
            }
            return nil
        }
    }
#endif
