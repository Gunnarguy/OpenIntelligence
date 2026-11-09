//
//  FigureRegionDetectorTests.swift
//  OpenIntelligenceTests
//
//  Synthetic page layouts for the figure detector ported from pdffigures2 (5.8). Boxes are Vision's normalized page
//  coordinates (origin bottom left); a word's box is about 0.008 wide per character and 0.012 tall, the size of body
//  text on a Letter page. Measured 2026-11-08 on eight research papers, none of their figures reached the index as a
//  figure; these layouts are the shapes those pages had.
//

import CoreGraphics
import XCTest

@testable import OpenIntelligence

final class FigureRegionDetectorTests: XCTestCase {
    private typealias Paragraph = (text: String, box: CGRect)

    private let prose =
        "The results of the trial were consistent across every prespecified subgroup and the sensitivity analyses "
        + "agreed with the primary estimate of effect in both arms"

    private func word(_ text: String, _ x: CGFloat, _ y: CGFloat, width: CGFloat? = nil) -> TextLayerWord {
        TextLayerWord(text: text, box: CGRect(x: x, y: y, width: width ?? CGFloat(text.count) * 0.008, height: 0.012))
    }

    /// The words of `text` laid out inside `box` on `lines` lines, the way a text layer reports a paragraph.
    private func fill(_ box: CGRect, with text: String, lines: Int = 3) -> [TextLayerWord] {
        let tokens = text.split(separator: " ").map(String.init)
        let perLine = max(1, Int((Double(tokens.count) / Double(lines)).rounded(.up)))
        return tokens.enumerated().map { index, token in
            let line = index / perLine
            let column = index % perLine
            let y = box.maxY - 0.015 - CGFloat(line) * (box.height / CGFloat(lines))
            let x = box.minX + CGFloat(column) * (box.width / CGFloat(perLine))
            return word(token, x, y)
        }
    }

    // MARK: - Single column

    func testSingleColumnFigureAboveItsCaption() {
        let top = CGRect(x: 0.1, y: 0.85, width: 0.8, height: 0.1)
        let caption = CGRect(x: 0.1, y: 0.40, width: 0.8, height: 0.04)
        let bottom = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.25)
        // Vision read the chart's axis and legend as paragraphs of their own.
        let axis = CGRect(x: 0.11, y: 0.46, width: 0.04, height: 0.36)
        let legend = CGRect(x: 0.6, y: 0.78, width: 0.2, height: 0.03)
        let captionText = "Figure 1. Survival by treatment arm over 24 months of follow-up."
        let paragraphs: [Paragraph] = [
            (prose, top), ("0 25 50 75 100", axis), ("Placebo Treatment", legend), (captionText, caption),
            (prose, bottom),
        ]
        var words = fill(top, with: prose) + fill(bottom, with: prose) + fill(caption, with: captionText, lines: 1)
        for (index, tick) in ["100", "75", "50", "25", "0"].enumerated() {
            words.append(word(tick, 0.11, 0.80 - CGFloat(index) * 0.08))
        }
        words += [word("Placebo", 0.6, 0.79), word("Treatment", 0.68, 0.79), word("Months", 0.5, 0.48)]

        let figures = FigureRegionDetector.detect(paragraphs: paragraphs, bodyBoxes: [top, bottom], words: words)
        XCTAssertEqual(figures.count, 1)
        guard let figure = figures.first else { return }
        XCTAssertEqual(figure.number, "1")
        XCTAssertEqual(figure.caption, captionText)
        XCTAssertEqual(figure.captionParagraphIndex, 3)
        // From the caption's top edge to the body paragraph above, the page's content width.
        XCTAssertEqual(figure.region.minY, 0.44, accuracy: 0.001)
        XCTAssertEqual(figure.region.maxY, 0.85, accuracy: 0.001)
        XCTAssertLessThanOrEqual(figure.region.minX, 0.1)
        XCTAssertGreaterThanOrEqual(figure.region.maxX, 0.9)
        // The axis and legend paragraphs are the figure's, the prose and the caption are not.
        XCTAssertEqual(figure.paragraphIndices, [1, 2])
        // Lines top to bottom, each left to right: "100" sits above the legend, "0" and "Months" share a line.
        XCTAssertEqual(figure.labels, ["100", "Placebo Treatment", "75", "50", "25", "0 Months"])
        XCTAssertEqual(figure.passageText, captionText + "\nLABELS: 100 | Placebo Treatment | 75 | 50 | 25 | 0 Months")
    }

    func testCaptionAboveItsFigureTakesTheRegionBelow() {
        let top = CGRect(x: 0.1, y: 0.75, width: 0.8, height: 0.2)
        let caption = CGRect(x: 0.1, y: 0.70, width: 0.8, height: 0.03)
        let bottom = CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.2)
        let paragraphs: [Paragraph] = [(prose, top), ("Figure 2. Flow of participants.", caption), (prose, bottom)]
        let words =
            fill(top, with: prose) + fill(bottom, with: prose) + [
                word("Screened", 0.3, 0.6), word("Analysed", 0.3, 0.4),
            ]

        let figures = FigureRegionDetector.detect(paragraphs: paragraphs, bodyBoxes: [top, bottom], words: words)
        XCTAssertEqual(figures.count, 1)
        guard let figure = figures.first else { return }
        XCTAssertEqual(figure.region.maxY, 0.70, accuracy: 0.001)
        XCTAssertEqual(figure.region.minY, 0.30, accuracy: 0.001)
        XCTAssertEqual(figure.labels, ["Screened", "Analysed"])
    }

    // MARK: - Two columns

    func testTwoColumnFigureInTheLeftColumnStopsAtTheRightColumn() {
        let right = CGRect(x: 0.52, y: 0.1, width: 0.4, height: 0.8)
        let top = CGRect(x: 0.08, y: 0.8, width: 0.4, height: 0.12)
        let caption = CGRect(x: 0.08, y: 0.35, width: 0.4, height: 0.05)
        let bottom = CGRect(x: 0.08, y: 0.08, width: 0.4, height: 0.22)
        let peaks = CGRect(x: 0.12, y: 0.6, width: 0.3, height: 0.03)
        let rightText = prose + " " + prose
        let paragraphs: [Paragraph] = [
            (prose, top), ("Fig. 2. Chromatogram of the PAH standard mixture.", caption), (prose, bottom),
            (rightText, right),
            ("Naphthalene Fluorene Pyrene", peaks),
        ]
        var words = fill(top, with: prose) + fill(bottom, with: prose) + fill(right, with: rightText, lines: 20)
        words += [
            word("Naphthalene", 0.12, 0.61), word("Fluorene", 0.25, 0.61), word("Pyrene", 0.38, 0.61),
            word("Retention", 0.2, 0.43), word("time", 0.28, 0.43),
        ]

        let figures = FigureRegionDetector.detect(
            paragraphs: paragraphs, bodyBoxes: [top, bottom, right], words: words)
        XCTAssertEqual(figures.count, 1)
        guard let figure = figures.first else { return }
        XCTAssertEqual(figure.number, "2")
        XCTAssertLessThanOrEqual(figure.region.maxX, 0.52 + 0.001, "the right column's text bounds the region")
        XCTAssertEqual(figure.region.minY, 0.40, accuracy: 0.001)
        XCTAssertEqual(figure.region.maxY, 0.80, accuracy: 0.001)
        XCTAssertEqual(figure.labels, ["Naphthalene Fluorene Pyrene", "Retention time"], "no word of the right column")
        XCTAssertEqual(figure.paragraphIndices, [4])
    }

    func testTwoColumnRegionIsCutAtTheCentreWhenTheOtherColumnIsEmptyThere() {
        let top = CGRect(x: 0.08, y: 0.8, width: 0.4, height: 0.12)
        let rightTop = CGRect(x: 0.52, y: 0.82, width: 0.4, height: 0.1)
        let caption = CGRect(x: 0.08, y: 0.35, width: 0.4, height: 0.05)
        let bottom = CGRect(x: 0.08, y: 0.08, width: 0.4, height: 0.22)
        let rightBottom = CGRect(x: 0.52, y: 0.08, width: 0.4, height: 0.2)
        let paragraphs: [Paragraph] = [
            (prose, top), (prose, rightTop), ("Fig. 2. Chromatogram.", caption), (prose, bottom), (prose, rightBottom),
        ]
        let words =
            fill(top, with: prose) + fill(bottom, with: prose) + fill(rightTop, with: prose)
            + fill(rightBottom, with: prose)
            + [word("Naphthalene", 0.12, 0.61), word("Pyrene", 0.38, 0.61)]

        let figures = FigureRegionDetector.detect(
            paragraphs: paragraphs, bodyBoxes: [top, rightTop, bottom, rightBottom], words: words)
        XCTAssertEqual(figures.count, 1)
        guard let figure = figures.first else { return }
        XCTAssertEqual(figure.region.maxX, 0.5, accuracy: 0.001, "pdffigures2's cropToCenter")
        XCTAssertEqual(figure.labels, ["Naphthalene Pyrene"])
    }

    func testFullWidthFigureWithAWideCaptionSpansBothColumns() {
        let left = CGRect(x: 0.08, y: 0.08, width: 0.4, height: 0.3)
        let right = CGRect(x: 0.52, y: 0.08, width: 0.4, height: 0.3)
        let caption = CGRect(x: 0.08, y: 0.42, width: 0.84, height: 0.04)
        let paragraphs: [Paragraph] = [
            ("Figure 3: Study flow from screening to analysis.", caption), (prose, left), (prose, right),
        ]
        var words = fill(left, with: prose) + fill(right, with: prose)
        words += [
            word("Screened", 0.1, 0.85), word("Randomised", 0.45, 0.7, width: 0.1), word("Excluded", 0.8, 0.85),
            word("Analysed", 0.1, 0.5), word("Lost", 0.8, 0.5),
        ]

        let figures = FigureRegionDetector.detect(paragraphs: paragraphs, bodyBoxes: [left, right], words: words)
        XCTAssertEqual(figures.count, 1)
        guard let figure = figures.first else { return }
        XCTAssertLessThanOrEqual(figure.region.minX, 0.1)
        XCTAssertGreaterThanOrEqual(figure.region.maxX, 0.88)
        XCTAssertEqual(figure.labels, ["Screened Excluded", "Randomised", "Analysed Lost"])
    }

    // MARK: - Captions

    func testABodySentenceIsNotTheCaptionWhenARealOneHasTheSameNumber() {
        let paragraphs: [Paragraph] = [
            (
                "Figure 3 shows that the effect was larger in the older cohort than in the younger one.",
                CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.05)
            ),
            ("Figure 3. Effect by age cohort.", CGRect(x: 0.1, y: 0.3, width: 0.8, height: 0.03)),
        ]
        let captions = FigureRegionDetector.captions(paragraphs: paragraphs)
        XCTAssertEqual(captions.count, 1)
        XCTAssertEqual(
            captions.first?.paragraphIndex, 1, "pdffigures2's Period Only filter keeps the one with a period")
        XCTAssertEqual(captions.first?.number, "3")
        XCTAssertEqual(captions.first?.kind, .figure)
    }

    func testALoneBodySentenceIsACandidateButHasNoRegion() {
        // pdffigures2 keeps a lone candidate and relies on no plausible region being near it.
        let top = CGRect(x: 0.1, y: 0.76, width: 0.8, height: 0.2)
        let sentence: Paragraph = (
            "Figure 3 shows that the effect was larger in the older cohort than in the younger one.",
            CGRect(x: 0.1, y: 0.7, width: 0.8, height: 0.05)
        )
        let bottom = CGRect(x: 0.1, y: 0.45, width: 0.8, height: 0.24)
        let words =
            fill(top, with: prose) + fill(bottom, with: prose) + fill(sentence.box, with: sentence.text, lines: 2)
        XCTAssertEqual(FigureRegionDetector.captions(paragraphs: [sentence]).count, 1)
        let figures = FigureRegionDetector.detect(
            paragraphs: [(prose, top), sentence, (prose, bottom)], bodyBoxes: [top, bottom], words: words)
        XCTAssertTrue(figures.isEmpty, "body text a line above and below leaves no region 4% of the page tall")
    }

    func testATableCaptionYieldsNoRegion() {
        let caption = CGRect(x: 0.1, y: 0.5, width: 0.8, height: 0.03)
        let paragraphs: [Paragraph] = [("Table 1. Baseline characteristics.", caption)]
        let words = [word("Age", 0.1, 0.6), word("Sex", 0.3, 0.6), word("62.1", 0.1, 0.57)]
        let captions = FigureRegionDetector.captions(paragraphs: paragraphs)
        XCTAssertEqual(captions.count, 1)
        XCTAssertEqual(captions.first?.kind, .table)
        XCTAssertEqual(captions.first?.number, "1")
        XCTAssertNil(FigureRegionDetector.figureRegion(for: captions[0], body: [], words: words))
        XCTAssertTrue(FigureRegionDetector.detect(paragraphs: paragraphs, bodyBoxes: [], words: words).isEmpty)
    }

    func testAPageWithoutCaptionsHasNoFigures() {
        let box = CGRect(x: 0.1, y: 0.6, width: 0.8, height: 0.3)
        XCTAssertTrue(FigureRegionDetector.captions(paragraphs: [(prose, box)]).isEmpty)
        XCTAssertTrue(
            FigureRegionDetector.detect(paragraphs: [(prose, box)], bodyBoxes: [box], words: fill(box, with: prose))
                .isEmpty)
    }

    func testCaptionHeadersAndNumbers() {
        let box = CGRect(x: 0, y: 0, width: 0.1, height: 0.01)
        func caption(_ text: String) -> FigureRegionDetector.Caption? {
            FigureRegionDetector.captions(paragraphs: [(text, box)]).first
        }
        XCTAssertEqual(caption("FIG. 4 Overview")?.number, "4")
        XCTAssertEqual(caption("FIG. 4 Overview")?.header, "FIG.")
        XCTAssertEqual(caption("FIG. 4 Overview")?.isAllCapsFigure, true)
        XCTAssertEqual(caption("Figure IV: Map")?.number, "IV")
        XCTAssertEqual(caption("Figure IV: Map")?.separator, ":")
        XCTAssertEqual(caption("Fig 2. Something")?.header, "Fig")
        XCTAssertEqual(caption("Fig 2. Something")?.hasPeriod, true)
        XCTAssertEqual(
            caption("Fig . 2. Something")?.header, "Fig.", "a lone period joins the header, as in pdffigures2")
        XCTAssertEqual(caption("Table A.1 Items")?.kind, .table)
        XCTAssertEqual(caption("Table A.1 Items")?.number, "A.1")
        XCTAssertEqual(caption("TABLE II. Items")?.isAllCapsTable, true)
        XCTAssertEqual(caption("Figure 2.3 shows")?.number, "2.3")
        XCTAssertEqual(caption("Figure 3a. Panel")?.number, "3")
        XCTAssertEqual(caption("Figure 10")?.number, "10")
        XCTAssertEqual(caption("Figure 10")?.lineEnd, true)
        XCTAssertEqual(caption("Figure 10\nCaption on the next line")?.lineEnd, true)
        XCTAssertEqual(caption("Figure 10. Caption")?.lineEnd, false)
        XCTAssertEqual(caption("Figure 10\nCaption on the next line")?.text, "Figure 10 Caption on the next line")
        XCTAssertNil(caption("Figure Ivory"), "a Roman numeral must end the word")
        XCTAssertNil(caption("Table Validation"))
        XCTAssertNil(caption("Figures 2 and 3 show"))
        XCTAssertNil(caption("figure 2"))
        XCTAssertNil(caption("Figure 0"))
        XCTAssertNil(caption("See Figure 2 for the layout"), "only the paragraph's first word is tested")
    }

    func testDuplicateCaptionNumbersAreResolvedByTheirFormatting() {
        let box = CGRect(x: 0, y: 0, width: 0.1, height: 0.01)
        let colon = FigureRegionDetector.captions(paragraphs: [("Figure 1: Colon", box), ("Figure 1. Period", box)])
        XCTAssertEqual(colon.map(\.text), ["Figure 1: Colon"], "Colon Only is pdffigures2's first filter")

        let three = FigureRegionDetector.captions(paragraphs: [
            ("Figure 1. A", box), ("Figure 1. B", box), ("Figure 1. C", box),
        ])
        XCTAssertTrue(three.isEmpty, "more than two alike on one page are dropped")

        let two = FigureRegionDetector.captions(paragraphs: [("Figure 1. A", box), ("Figure 1. B", box)])
        XCTAssertEqual(two.count, 2, "two alike are both kept, as pdffigures2 does")

        let mixed = FigureRegionDetector.captions(paragraphs: [("Figure 1. A", box), ("Table 1. B", box)])
        XCTAssertEqual(mixed.count, 2, "a figure and a table share a number")

        let following = FigureRegionDetector.captions(paragraphs: [("Figure 2", box), ("Figure 2 is shown below", box)])
        XCTAssertEqual(
            following.map(\.text), ["Figure 2 is shown below"], "Figure Following Text comes before Line End Only")

        let allCaps = FigureRegionDetector.captions(paragraphs: [("FIG. 5. A", box), ("Fig. 5. B", box)])
        XCTAssertEqual(allCaps.map(\.text), ["FIG. 5. A"], "All Caps Figures Only comes before Abbreviated Fig Only")
    }

    // MARK: - Several figures

    func testStackedFiguresTakeDisjointRegions() {
        let caption1 = CGRect(x: 0.1, y: 0.55, width: 0.8, height: 0.03)
        let caption2 = CGRect(x: 0.1, y: 0.12, width: 0.8, height: 0.03)
        let paragraphs: [Paragraph] = [("Figure 1. First.", caption1), ("Figure 2. Second.", caption2)]
        let words = [word("a", 0.3, 0.9), word("b", 0.3, 0.7), word("c", 0.3, 0.45), word("d", 0.3, 0.25)]

        let figures = FigureRegionDetector.detect(paragraphs: paragraphs, bodyBoxes: [], words: words)
        XCTAssertEqual(figures.count, 2)
        guard figures.count == 2 else { return }
        XCTAssertFalse(figures[0].region.intersects(figures[1].region))
        XCTAssertEqual(figures[0].number, "1", "top of the page first")
        XCTAssertEqual(figures[0].labels, ["a", "b"])
        XCTAssertEqual(figures[1].labels, ["c", "d"], "Figure 2's region stops at Figure 1's caption")
    }

    func testFigureTextReadsLinesTopToBottomLeftToRight() {
        let region = CGRect(x: 0, y: 0, width: 1, height: 1)
        let words = [word("right", 0.6, 0.5), word("left", 0.1, 0.5), word("lower", 0.1, 0.2), word("upper", 0.1, 0.8)]
        XCTAssertEqual(FigureRegionDetector.figureText(region: region, words: words), ["upper", "left right", "lower"])
        XCTAssertEqual(
            FigureRegionDetector.figureText(region: CGRect(x: 0, y: 0, width: 0.05, height: 0.05), words: words), [])
    }

    func testProseClassification() {
        XCTAssertTrue(FigureRegionDetector.isProse(prose))
        XCTAssertTrue(FigureRegionDetector.isProse("The results are summarised in Table 2 and Figure 3 below."))
        XCTAssertFalse(
            FigureRegionDetector.isProse("UnSg4.73, P<.001 Isted HR. 4.11 HR 2.1 3.3 4.5 5.6"), "a chart's numbers")
        XCTAssertFalse(FigureRegionDetector.isProse("Naphthalene Acenaphthylene Fluorene Phenanthrene"), "peak labels")
        XCTAssertFalse(FigureRegionDetector.isProse("0 25 50 75 100"))
    }

    func testNoTextLayerMeansNoFigures() {
        let caption = CGRect(x: 0.1, y: 0.40, width: 0.8, height: 0.04)
        let figures = FigureRegionDetector.detect(
            paragraphs: [("Figure 1. A photo.", caption)], bodyBoxes: [], words: [])
        XCTAssertTrue(figures.isEmpty, "a region must hold a label; a scanned page has no words to hold")
    }
}
