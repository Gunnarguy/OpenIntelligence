//
//  WebPageFetchServiceTests.swift
//  OpenIntelligenceTests
//
//  "Ingest Webpage" queued the web address as if it were a file and downloaded nothing. These pin
//  the part that can be tested without a network: what a response becomes, and what is read out of
//  a page's HTML.
//

import XCTest

@testable import OpenIntelligenceEngine

final class WebPageFetchServiceTests: XCTestCase {
    private let address = URL(string: "https://example.com/manuals/air-fryer.html")!
    private let saved = Date(timeIntervalSince1970: 1_791_522_000)

    private func response(status: Int = 200, mime: String?, url: URL? = nil) -> URLResponse {
        var headers: [String: String] = [:]
        if let mime { headers["Content-Type"] = mime }
        return HTTPURLResponse(url: url ?? address, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private let page = """
        <!doctype html>
        <html>
          <head>
            <title>Air Fryer &amp; Oven Manual</title>
            <style>body { color: red; }</style>
            <script>var hidden = "do not import this";</script>
          </head>
          <body>
            <nav><a href="/">Home</a> <a href="/shop">Shop</a></nav>
            <h1>Air Fryer &amp; Oven Manual</h1>
            <p>Preheat to 350&#176;F for
               five minutes.</p>
            <!-- an editor's note that is not page text -->
            <h2>Cleaning</h2>
            <ul>
              <li>Hand wash the basket.</li>
              <li>The drip tray is dishwasher safe.</li>
            </ul>
            <table>
              <tr><th>Code</th><th>Meaning</th></tr>
              <tr><td>E1</td><td>Temperature sensor open circuit</td></tr>
            </table>
            <footer>Copyright 2026 Example Appliances</footer>
          </body>
        </html>
        """

    // MARK: - Reading a page

    func testAPageBecomesItsTextWithHeadingsListsAndRows() {
        let read = WebPageFetchService.readableText(fromHTML: page)
        XCTAssertEqual(read.title, "Air Fryer & Oven Manual")
        XCTAssertEqual(
            read.text,
            """
            # Air Fryer & Oven Manual

            Preheat to 350°F for five minutes.

            ## Cleaning

            - Hand wash the basket.
            - The drip tray is dishwasher safe.

            Code | Meaning
            E1 | Temperature sensor open circuit
            """
        )
    }

    func testScriptsStylesNavigationAndFootersAreLeftOut() {
        let text = WebPageFetchService.readableText(fromHTML: page).text
        for absent in ["do not import this", "color: red", "Shop", "Copyright", "editor's note"] {
            XCTAssertFalse(text.contains(absent), "\(absent) should not be in the page text")
        }
    }

    func testEntitiesAreDecodedAndUnknownOnesAreLeftAsWritten() {
        XCTAssertEqual(
            WebPageFetchService.decodeEntities("Tom &amp; Jerry &lt;3 &#8217;quoted&#x2019; &unknownthing; &"),
            "Tom & Jerry <3 \u{2019}quoted\u{2019} &unknownthing; &")
    }

    func testALessThanSignInTextIsNotTakenForATag() {
        let read = WebPageFetchService.readableText(
            fromHTML: "<body><p>Significant at p < 0.05 and x > 3, &plusmn;2 &micro;m, caf&eacute;.</p><p>The next paragraph.</p></body>")
        XCTAssertEqual(read.text, "Significant at p < 0.05 and x > 3, ±2 µm, café.\n\nThe next paragraph.")
    }

    func testASelfClosedScriptOrPictureDoesNotSwallowWhatFollows() {
        let read = WebPageFetchService.readableText(
            fromHTML: "<body><svg width=\"1\"/><p>Before.</p><script src=\"x.js\"/><p>After the script tag.</p><script>hidden()</script></body>")
        XCTAssertEqual(read.text, "Before.\n\nAfter the script tag.")
    }

    func testATitleWrittenOverTwoLinesIsOneLine() {
        XCTAssertEqual(
            WebPageFetchService.readableText(fromHTML: "<title>Air Fryer\n   Manual</title><body><p>x</p></body>").title,
            "Air Fryer Manual")
    }

    func testAPageThatNamesItsCharacterSetOnlyInAMetaTagIsReadWithIt() {
        // "café" in Windows-1252: the last byte, 0xE9, is not valid UTF-8 on its own.
        var bytes = Array("<meta charset=\"windows-1252\"><p>caf".utf8)
        bytes.append(0xE9)
        let data = Data(bytes)
        XCTAssertEqual(WebPageFetchService.declaredCharset(in: data), "windows-1252")
        XCTAssertTrue(WebPageFetchService.decode(data, encodingName: nil).hasSuffix("café"))
    }

    // MARK: - A response becomes a file

    func testAWebPageIsStoredAsMarkdownNamedByItsTitle() throws {
        let fetched = try WebPageFetchService.fetched(
            from: Data(page.utf8), response: response(mime: "text/html; charset=utf-8"), requestedURL: address,
            now: saved)
        XCTAssertEqual(fetched.fileName, "Air Fryer & Oven Manual.md")
        XCTAssertEqual(fetched.title, "Air Fryer & Oven Manual")

        let text = try XCTUnwrap(String(data: fetched.data, encoding: .utf8))
        XCTAssertTrue(text.hasPrefix("# Air Fryer & Oven Manual\n\nSource: https://example.com/manuals/air-fryer.html\nSaved: 2026-10-0"), text)
        XCTAssertEqual(text.components(separatedBy: "# Air Fryer & Oven Manual").count, 2, "the title is written once")
        XCTAssertTrue(text.contains("E1 | Temperature sensor open circuit"), text)
    }

    func testALinkToAPDFIsStoredAsThePDF() throws {
        let pdf = URL(string: "https://example.com/files/Lease%20Agreement.pdf")!
        let bytes = Data("%PDF-1.7 not a real file".utf8)
        let fetched = try WebPageFetchService.fetched(
            from: bytes, response: response(mime: "application/pdf", url: pdf), requestedURL: pdf)
        XCTAssertEqual(fetched.fileName, "Lease Agreement.pdf")
        XCTAssertEqual(fetched.data, bytes)
        XCTAssertNil(fetched.title)
    }

    func testAnErrorStatusIsReported() {
        XCTAssertThrowsError(
            try WebPageFetchService.fetched(
                from: Data(page.utf8), response: response(status: 404, mime: "text/html"), requestedURL: address)
        ) { error in
            XCTAssertEqual(error as? WebPageFetchService.FetchError, .httpStatus(404))
        }
    }

    func testAPageWithNoTextOfItsOwnIsReported() {
        let shell = "<html><head><title>App</title></head><body><div id=\"root\"></div><script>render()</script></body></html>"
        XCTAssertThrowsError(
            try WebPageFetchService.fetched(
                from: Data(shell.utf8), response: response(mime: "text/html"), requestedURL: address)
        ) { error in
            XCTAssertEqual(error as? WebPageFetchService.FetchError, .noReadableText)
        }
    }

    func testABodyOverTheLimitIsRefused() {
        let big = Data(count: WebPageFetchService.maxBytes + 1)
        XCTAssertThrowsError(
            try WebPageFetchService.fetched(from: big, response: response(mime: "application/pdf"), requestedURL: address)
        ) { error in
            XCTAssertEqual(error as? WebPageFetchService.FetchError, .tooLarge(bytes: WebPageFetchService.maxBytes + 1))
        }
    }

    func testAnUnsupportedTypeIsReportedByName() {
        XCTAssertThrowsError(
            try WebPageFetchService.fetched(
                from: Data([0, 1, 2]), response: response(mime: "application/zip"), requestedURL: address)
        ) { error in
            XCTAssertEqual(error as? WebPageFetchService.FetchError, .unsupportedContent("application/zip"))
        }
    }

    func testAPlainHTTPAddressIsAskedForOverHTTPS() {
        XCTAssertEqual(
            WebPageFetchService.requestURL(for: URL(string: "http://example.com/a?b=1")!)?.absoluteString,
            "https://example.com/a?b=1")
        XCTAssertEqual(
            WebPageFetchService.requestURL(for: URL(string: "https://example.com/a")!)?.absoluteString,
            "https://example.com/a")
        XCTAssertNil(WebPageFetchService.requestURL(for: URL(string: "ftp://example.com/a")!))
    }

    func testAWebPageOverItsOwnLimitIsRefused() {
        let big = Data(count: WebPageFetchService.maxHTMLBytes + 1)
        XCTAssertThrowsError(
            try WebPageFetchService.fetched(from: big, response: response(mime: "text/html"), requestedURL: address)
        ) { error in
            XCTAssertEqual(error as? WebPageFetchService.FetchError, .tooLarge(bytes: WebPageFetchService.maxHTMLBytes + 1))
        }
    }

    func testOnlyWebAddressesAreFetched() async {
        do {
            _ = try await WebPageFetchService.fetch(URL(fileURLWithPath: "/etc/hosts"))
            XCTFail("a file address must not be fetched")
        } catch {
            XCTAssertEqual(error as? WebPageFetchService.FetchError, .unsupportedAddress)
        }
    }
}
