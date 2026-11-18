import SwiftUI
import XCTest

@testable import OpenIntelligence

/// 5.8: a list item in an answer that is only a bold label (`- **What stays on the device:**`) draws as the
/// answer's `###` heading, and the bullets after it stay bullets under it. Everything else in the renderer
/// is pinned to parse exactly as it did before, and with the switch off (a question the user typed) the
/// same text parses as before.
final class MarkdownLabelBulletTests: XCTestCase {

    private func blocks(_ text: String, on: Bool = true) -> [String] {
        MarkdownParserTesting.blockSummary(text, promotesLabelBullets: on)
    }

    /// The answer the owner saw on his iPhone (Standard, OpenIntelligence Guide library), its middle lines
    /// filled in where his screenshot was cut.
    static let ownerAnswer = """
        - **What stays on the device:**
        - Document parsing and text recognition via Vision [S1] [S2].
        - Chunking and indexing [S1].
        - Embedding and retrieval of passages [S2].
        - Ranking and the on-device answer [S3].
        - **What can leave the device:**
        - Private Cloud Compute handles inference requests for the final answer, only after you consent [S3] [S4].
        - Importing a file that is not on the device, such as one from iCloud Drive [S4].
        """

    // MARK: - The owner's answer

    func testTheOwnersAnswerGetsTwoHeadingsWithTheirBullets() {
        XCTAssertEqual(
            blocks(Self.ownerAnswer),
            [
                "h3: What stays on the device",
                "ul: Document parsing and text recognition via Vision [S1] [S2]. | Chunking and indexing [S1]. | "
                    + "Embedding and retrieval of passages [S2]. | Ranking and the on-device answer [S3].",
                "h3: What can leave the device",
                "ul: Private Cloud Compute handles inference requests for the final answer, only after you consent "
                    + "[S3] [S4]. | Importing a file that is not on the device, such as one from iCloud Drive [S4].",
            ])
    }

    func testWithTheSwitchOffTheAnswerIsOneListAsBefore() {
        let off = blocks(Self.ownerAnswer, on: false)
        XCTAssertEqual(off.count, 1)
        XCTAssertTrue(off[0].hasPrefix("ul: **What stays on the device:** | Document parsing"), off[0])
    }

    // MARK: - Label shapes

    func testLabelShapes() {
        XCTAssertEqual(
            MarkdownParserTesting.labelHeadingText("**What stays on the device:**"), "What stays on the device")
        XCTAssertEqual(MarkdownParserTesting.labelHeadingText("**Risks**:"), "Risks")
        XCTAssertEqual(MarkdownParserTesting.labelHeadingText("**Risks** :"), "Risks")
        XCTAssertEqual(MarkdownParserTesting.labelHeadingText("**Risks**"), "Risks")
        XCTAssertEqual(
            MarkdownParserTesting.labelHeadingText("**Deep Think vs. Maximum: Candidates per Step**"),
            "Deep Think vs. Maximum: Candidates per Step")
    }

    func testNotLabels() {
        for item in [
            "**Standard.** One retrieval pass, then the answer.",  // bold lead-in followed by text
            "**Standard:** one retrieval pass",
            "Uses **Vision** to read scans.",  // bold inside a sentence
            "**Vision** and **Core ML**",  // two bold spans
            "**What st",  // still streaming
            "**What stays on the device:*",
            "**What stays on the device:** [S1]",  // a citation after the bold is a claim, not a label
            "** spaced **",
            "***Bold italic***",
            "**Never share your key.**",  // a bold sentence with no colon
            "**" + String(repeating: "word ", count: 30) + "end:**",  // over 120 characters
            "**:**",
            "",
        ] {
            XCTAssertNil(MarkdownParserTesting.labelHeadingText(item), item)
        }
    }

    // MARK: - Cases

    func testABoldLeadInBulletStaysABullet() {
        let text = """
            - **Standard.** One retrieval pass, then the answer.
            - **Deep Think.** Several passes.
            """
        XCTAssertEqual(
            blocks(text), ["ul: **Standard.** One retrieval pass, then the answer. | **Deep Think.** Several passes."])
    }

    func testALabelFollowedByTextOnTheNextLineIsALeadIn() {
        // The next line joins the item (as it always has), so the item is a lead-in followed by text.
        let text = """
            - **What stays on the device:**
              Parsing, chunking and indexing.
            """
        XCTAssertEqual(blocks(text), ["ul: **What stays on the device:** Parsing, chunking and indexing."])
    }

    func testBoldInsideASentenceIsUnchanged() {
        let text = "The app uses **Vision** to read scans [S1].\n\n- It runs **on device** [S2]."
        XCTAssertEqual(
            blocks(text), ["p: The app uses **Vision** to read scans [S1].", "ul: It runs **on device** [S2]."])
    }

    func testLabelAsFirstAndLastLine() {
        let text = """
            - **On device:**
            - Parsing [S1].
            - **Off device:**
            """
        XCTAssertEqual(blocks(text), ["h3: On device", "ul: Parsing [S1].", "h3: Off device"])
    }

    func testTwoLabelsInARow() {
        let text = """
            - **Privacy:**
            - **What stays on the device:**
            - Parsing [S1].
            """
        XCTAssertEqual(blocks(text), ["h3: Privacy", "h3: What stays on the device", "ul: Parsing [S1]."])
    }

    func testACitationInsideTheBoldStaysInTheHeadingAsALink() {
        let link = "[[S1]](citation://chunk/6F9619FF-8B86-D011-B42D-00C04FC964FF)"
        let text = """
            - **What stays on the device \(link):**
            - Parsing.
            """
        XCTAssertEqual(blocks(text), ["h3: What stays on the device \(link)", "ul: Parsing."])
        XCTAssertEqual(blocks("- **On device [S1]:**\n- Parsing."), ["h3: On device [S1]", "ul: Parsing."])
    }

    func testAStarBulletLabelWithoutAColon() {
        let text = """
            * **Risks**
            * The model can be wrong.
            * **Benefits**
            * Nothing leaves the device.
            """
        XCTAssertEqual(
            blocks(text),
            ["h3: Risks", "ul: The model can be wrong.", "h3: Benefits", "ul: Nothing leaves the device."])
    }

    func testAListOfBoldNamesStaysAList() {
        let text = """
            - **Standard**
            - **Deep Think**
            - **Maximum**
            """
        XCTAssertEqual(blocks(text), ["ul: **Standard** | **Deep Think** | **Maximum**"])
        // And one alone at the end, with nothing under it, stays a bullet.
        XCTAssertEqual(blocks("- Parsing.\n- **Summary**"), ["ul: Parsing. | **Summary**"])
    }

    func testNestedLists() {
        // A top-level label over nested bullets: the label heads them.
        let topLevel = """
            - **What stays on the device:**
              - Parsing [S1].
              - Indexing [S2].
            """
        XCTAssertEqual(blocks(topLevel), ["h3: What stays on the device", "ul: Parsing [S1]. | Indexing [S2]."])

        // A label nested under another item stays a bullet in its list.
        let nested = """
            - Storage
              - **Details:**
              - Indexing [S2].
            """
        XCTAssertEqual(blocks(nested), ["ul: Storage | **Details:** | Indexing [S2]."])
        // A top-level label with no colon over nested items heads them.
        XCTAssertEqual(blocks("- **Risks**\n  - **Hallucination**"), ["h3: Risks", "ul: **Hallucination**"])
    }

    func testAPartlyWrittenLineStaysABulletUntilTheBoldCloses() {
        XCTAssertEqual(blocks("- **What st"), ["ul: **What st"])
        XCTAssertEqual(blocks("- **What stays on the device:*"), ["ul: **What stays on the device:*"])
        XCTAssertEqual(blocks("- **What stays on the device:**"), ["h3: What stays on the device"])
        XCTAssertEqual(blocks("- **What stays on the device:**\n- Pars"), ["h3: What stays on the device", "ul: Pars"])
    }

    func testABulletLabelBeforeANumberedList() {
        let text = """
            - **Steps:**
            1. **Open** the library.
            2. Ask.
            """
        XCTAssertEqual(blocks(text), ["h3: Steps", "ol: 1. **Open** the library. | 2. Ask."])
    }

    // MARK: - What must not change

    func testNumberedListsAreUnchanged() {
        let text = "1. **What stays on the device:**\n2. Parsing [S1]."
        XCTAssertEqual(blocks(text), blocks(text, on: false))
        XCTAssertEqual(blocks(text), ["ol: 1. **What stays on the device:** | 2. Parsing [S1]."])
    }

    func testTablesAndCodeAreUnchanged() {
        // Compact pipes: the inline normalizer splits `| a | b |` rows apart before any table is read, with
        // the switch on or off (the equality check below holds for that spelling too).
        let spaced = "| Stage | Where |\n|---|---|\n| **Parsing:** | Device |"
        XCTAssertEqual(blocks(spaced), blocks(spaced, on: false))
        let text = """
            |Stage|Where|
            |---|---|
            |**Parsing:**|Device|

            ```
            - **What stays on the device:**
            - Parsing
            ```
            """
        XCTAssertEqual(blocks(text), blocks(text, on: false))
        XCTAssertEqual(
            blocks(text),
            [
                "table: Stage | Where",
                "code: - **What stays on the device:**\n- Parsing",
            ])
    }

    func testHeadingsParagraphsAndRulesAreUnchanged() {
        let text = """
            ### Deep Think vs. Maximum: Candidates per Step

            Deep Think keeps **three** candidates [S1].

            ---

            - Plain bullet [S2].
            """
        XCTAssertEqual(blocks(text), blocks(text, on: false))
    }
}

// MARK: - Pictures

#if canImport(UIKit)
/// Draws the owner's answer as the finished answer bubble lays it out (`MessageBubbleV2`: a leading VStack, 16 by 12
/// padding, the surface grey, an 18-point corner, a 24-point spacer, inside a 393-point-wide list) with the text
/// as a plain answer (14 points scaled) and as a grounded answer (`GroundedAnswerView`: `.body`). Three versions:
/// before (switch off), after (switch on), and the same answer written with `###` headings, to compare the label
/// headings with the headings answers already had. Light and dark, default and AX2 text. PNGs go to
/// `/private/tmp/oi-labelbullets/` for a person to look at; the test checks only that each was drawn.
@MainActor
final class MarkdownLabelBulletPictureTests: XCTestCase {

    private static func linked(_ text: String) -> String {
        var text = text
        for n in 1...4 {
            text = text.replacingOccurrences(
                of: "[S\(n)]", with: "[[S\(n)]](citation://chunk/00000000-0000-0000-0000-00000000000\(n))")
        }
        return text
    }

    private static let answer = linked(MarkdownLabelBulletTests.ownerAnswer)
    private static let hashHeadings = linked(
        MarkdownLabelBulletTests.ownerAnswer
            .replacingOccurrences(of: "- **What stays on the device:**", with: "### What stays on the device\n")
            .replacingOccurrences(of: "- **What can leave the device:**", with: "### What can leave the device\n"))

    private struct Bubble: View {
        let text: String
        let grounded: Bool
        let promotes: Bool

        var body: some View {
            HStack(alignment: .bottom, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    if grounded {
                        VStack(alignment: .leading, spacing: DSSpacing.md) {
                            MarkdownText(text, font: .body, foregroundColor: DSColors.primaryText)
                                .labelBulletsAsHeadings(promotes)
                        }
                    } else {
                        MarkdownText(text, scaledSize: 14, foregroundColor: DSColors.primaryText)
                            .labelBulletsAsHeadings(promotes)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(DSColors.surface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                Spacer(minLength: 24)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(width: 393)
            .background(DSColors.background)
        }
    }

    func testDrawBeforeAndAfter() throws {
        let folder = URL(fileURLWithPath: "/private/tmp/oi-labelbullets", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [String] = []
        let versions: [(name: String, text: String, promotes: Bool)] = [
            ("before", Self.answer, false), ("after", Self.answer, true), ("hash-headings", Self.hashHeadings, false),
        ]
        for grounded in [false, true] {
            for scheme in [ColorScheme.light, .dark] {
                for size in [DynamicTypeSize.large, .accessibility2] {
                    for version in versions {
                        let view = Bubble(text: version.text, grounded: grounded, promotes: version.promotes)
                            .environment(\.colorScheme, scheme)
                            .environment(\.dynamicTypeSize, size)
                        let renderer = ImageRenderer(content: view)
                        renderer.scale = 2
                        let image = try XCTUnwrap(renderer.uiImage, "nothing drawn")
                        let data = try XCTUnwrap(image.pngData())
                        let name =
                            [
                                grounded ? "grounded" : "bubble",
                                scheme == .dark ? "dark" : "light",
                                size == .large ? "default" : "ax2",
                                version.name,
                            ].joined(separator: "-") + ".png"
                        try data.write(to: folder.appendingPathComponent(name))
                        written.append(name)
                    }
                }
            }
        }
        XCTAssertEqual(written.count, 24)
        print("[MarkdownLabelBulletPictureTests] wrote \(written.count) PNGs to \(folder.path)")
    }

    /// The same bubbles laid out by UIKit in a window, inside a ScrollView and LazyVStack as the chat lays them
    /// out (`MessageListV2`), not by `ImageRenderer`: files named `hosted-...`.
    func testDrawHostedInAWindow() throws {
        let folder = URL(fileURLWithPath: "/private/tmp/oi-labelbullets", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first, "no window scene")
        var written = 0
        for grounded in [false, true] {
            for size in [DynamicTypeSize.large, .accessibility2] {
                for version in [("before", Self.answer, false), ("after", Self.answer, true),
                                ("hash-headings", Self.hashHeadings, false)] {
                    let root = ScrollView {
                        LazyVStack(spacing: 0) {
                            Bubble(text: version.1, grounded: grounded, promotes: version.2)
                        }
                    }
                    .environment(\.dynamicTypeSize, size)
                    let host = UIHostingController(rootView: root)
                    let window = UIWindow(windowScene: scene)
                    window.frame = CGRect(x: 0, y: 0, width: 393, height: size == .large ? 700 : 2400)
                    window.overrideUserInterfaceStyle = .light
                    window.rootViewController = host
                    window.isHidden = false
                    host.view.layoutIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.5))
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        _ = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    window.isHidden = true
                    let name = ["hosted", grounded ? "grounded" : "bubble", size == .large ? "default" : "ax2",
                                version.0].joined(separator: "-") + ".png"
                    try XCTUnwrap(image.pngData()).write(to: folder.appendingPathComponent(name))
                    written += 1
                }
            }
        }
        XCTAssertEqual(written, 12)
    }
}
#endif
