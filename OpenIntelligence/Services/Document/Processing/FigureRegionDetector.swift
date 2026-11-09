//
//  FigureRegionDetector.swift
//  OpenIntelligence
//
//  Figures of a PDF page found from their captions (5.8). Measured 2026-11-08 on eight research papers, none of their
//  about 29 numbered figures reached the index as a figure: a vector chart's axis labels and numbers ended up inside
//  paragraphs ("UnSg4.73, P<.001 Isted HR. 4.11"), and so did a chromatogram's peak labels. This type ports the
//  published method of pdffigures2 (Allen Institute for AI, Apache-2.0, https://github.com/allenai/pdffigures2,
//  commit 3d7ad46753d4a315cccd1c2bcab398380e88c534 of 2023-11-27): a caption is a paragraph whose first word is
//  "Figure", "Fig." or "Table" followed by a number (CaptionDetector.scala), duplicates of one number are resolved by
//  the formatting the other candidates share (CaptionDetector.scala, `selectCaptionCandidates`), and the figure is the
//  region next to the caption that body text does not reach (FigureDetector.scala, `buildProposals`). What pdffigures2
//  reads from PDFBox's fonts and graphics is not available here; each departure is noted where it is made.
//
//  Every box is in Vision's normalized page coordinates: origin bottom left, 0 to 1 on each axis. "Above" is the larger
//  y. pdffigures2 measures in PDF points with y growing downward, so its constants are quoted in points and converted
//  for a US Letter page (612 by 792 points) where they are used.
//

import CoreGraphics
import Foundation

nonisolated enum FigureRegionDetector {
    // MARK: - Types

    enum Kind: String, Sendable, Equatable {
        case figure
        case table
    }

    /// A paragraph that starts with a caption header and number.
    struct Caption: Sendable, Equatable {
        let kind: Kind
        /// The number as printed: "3", "IV", "A.1", "2.3".
        let number: String
        /// The whole paragraph, its line breaks replaced by spaces.
        let text: String
        /// The paragraph's box.
        let box: CGRect
        /// The index of the paragraph in the array passed to `captions(paragraphs:)`.
        let paragraphIndex: Int
        /// The header as printed ("Figure", "FIG.", "Table"); pdffigures2's `CaptionStart.header`.
        let header: String
        /// ":" or "." when one follows the number, else ""; pdffigures2's `numberSyntax`.
        let separator: String
        /// The header and number are the paragraph's whole first line; pdffigures2's `lineEnd`.
        let lineEnd: Bool

        var hasColon: Bool { separator == ":" }
        var hasPeriod: Bool { separator == "." }
        var isAllCapsFigure: Bool { header.hasPrefix("FIG") }
        var isAllCapsTable: Bool { header == "TABLE" }
        var isAbbreviatedFigure: Bool { header == "Fig." }
        /// pdffigures2 groups candidates by `(figType, name)`.
        var groupKey: String { "\(kind.rawValue)|\(number)" }
    }

    /// A figure located on the page.
    struct Figure: Sendable, Equatable {
        let number: String
        /// The caption paragraph's text ("Figure 3. Kaplan-Meier ...").
        let caption: String
        /// The figure's region, from the caption's edge to the nearest body text in that direction.
        let region: CGRect
        /// The text-layer words inside the region, as lines top to bottom, each left to right: the figure's labels.
        let labels: [String]
        /// The paragraphs (indices into the array passed to `detect`) whose box centre lies inside the region. They are
        /// the figure's labels that Vision read as paragraphs and belong to the figure, not the page's prose.
        let paragraphIndices: [Int]
        let captionParagraphIndex: Int

        /// The text a `.figure` element stores: the caption, then the labels one line per figure line.
        var passageText: String {
            labels.isEmpty ? caption : "\(caption)\nLABELS: \(labels.joined(separator: " | "))"
        }
    }

    // MARK: - Constants

    /// pdffigures2 drops a caption number with more than three candidates in the document (`MaxDuplicateCaptionNames`)
    /// or more than two on one page (`MaxSamePageDuplicateCaptionNames`), CaptionDetector.scala lines 30 and 31.
    static let maxDuplicateCaptionNames = 3
    static let maxSamePageDuplicateCaptionNames = 2

    /// The shortest region taken as a figure, as a fraction of the page height. pdffigures2's `MinProposalHeight` is 15
    /// points (0.019 of a Letter page, FigureDetector.scala line 5); this port asks for 0.04, about three lines of body
    /// text, because Vision's paragraph boxes leave a gap of one or two lines between paragraphs that is not a figure.
    static let minRegionHeight: CGFloat = 0.04
    /// pdffigures2's `MinProposalWidth`, 20 points (FigureDetector.scala line 6), as a fraction of a Letter page's width.
    static let minRegionWidth: CGFloat = 20.0 / 612.0
    /// pdffigures2 snaps a column edge to the text centre when it is within 10 points (FigureDetector.scala,
    /// `findCenterColumn`), as a fraction of a Letter page's width.
    static let columnSnapDistance: CGFloat = 10.0 / 612.0
    /// Half a line of body text: Vision's boxes overlap their neighbours by about that much.
    static let edgeTolerance: CGFloat = 0.005

    /// pdffigures2's caption header, `captionStartRegex` (CaptionDetector.scala line 107):
    /// `^(Figure.|Figure|FIGURE|Table|TABLE||Fig.|Fig|FIG.|FIG)$` on the line's first word, with a lone "." as the next
    /// word merged into the header. Its number, `captionNumberRegex` (line 110):
    /// `^([1-9][0-9]*.[1-9][0-9]*|[1-9][0-9]*|[IVX]+|[1-9I][0-9I]*|[A-D].[1-9][0-9]*)($|:|.)?` on the next word.
    /// Here both apply to the start of a paragraph's text, so the two words are joined by optional whitespace, the
    /// unescaped dots are literal periods, and the number must end the word (an optional sub-panel letter allowed, "3a"),
    /// which pdffigures2 did not require because it matched a word that was already split off; without it "Table
    /// Validation" would be Table V. The `[1-9I][0-9I]*` form (an OCR "I" for "1") is left out: these paragraphs come
    /// from Vision or the text layer, and "Figure I" is already a Roman numeral.
    static let captionPattern =
        #"^(Figure|FIGURE|Fig\.?|FIG\.?|Table|TABLE)\s*(?:\.\s*)?([1-9][0-9]*\.[1-9][0-9]*|[1-9][0-9]*|[IVX]+|[A-D]\.[1-9][0-9]*)(?:[A-Za-z](?![A-Za-z]))?\s*([:.])?(?![A-Za-z0-9])"#

    // MARK: - 1. Captions

    /// The paragraphs that are captions, after pdffigures2's duplicate resolution. A paragraph is a candidate when its
    /// first word is a caption header followed by a number (`findCaptionCandidates`); when one number has several
    /// candidates, the first filter that removes a candidate from some group without emptying any group is applied,
    /// until no group has duplicates or no filter helps (`selectCaptionCandidates`); a group that still has more than
    /// `maxSamePageDuplicateCaptionNames` candidates is dropped.
    static func captions(paragraphs: [(text: String, box: CGRect)]) -> [Caption] {
        guard let regex = try? NSRegularExpression(pattern: captionPattern) else { return [] }
        var candidates: [Caption] = []
        for (index, paragraph) in paragraphs.enumerated() {
            let text = paragraph.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                let headerRange = Range(match.range(at: 1), in: text),
                let numberRange = Range(match.range(at: 2), in: text)
            else { continue }
            var header = String(text[headerRange])
            // pdffigures2 merges "Fig" and a following "." into "Fig." (CaptionDetector.scala, `findCaptionCandidates`).
            if header == "Fig" || header == "FIG" {
                let afterHeader = text[headerRange.upperBound...].drop(while: \.isWhitespace)
                if afterHeader.first == "." { header += "." }
            }
            let separatorRange = Range(match.range(at: 3), in: text)
            let separator = separatorRange.map { String(text[$0]) } ?? ""
            let firstLine =
                text.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init)
                ?? text
            let matched = Range(match.range, in: text).map { text[$0] } ?? Substring()
            let lineEnd = firstLine.trimmingCharacters(in: .whitespaces) == matched.trimmingCharacters(in: .whitespaces)
            candidates.append(
                Caption(
                    kind: header.hasPrefix("F") ? .figure : .table,
                    number: String(text[numberRange]),
                    text: text.replacingOccurrences(of: "\n", with: " "),
                    box: paragraph.box,
                    paragraphIndex: index,
                    header: header,
                    separator: separator,
                    lineEnd: lineEnd))
        }
        return selectCaptionCandidates(candidates)
    }

    /// pdffigures2's filters in its order (CaptionDetector.scala, `findCaptions`), without the three `NonStandardFont`
    /// filters (no font is known here) and the two `LeftAlignedOnly` filters (they compare the caption line's left edge
    /// with the next line's, and a Vision paragraph has one box).
    private static let candidateFilters: [(name: String, accept: @Sendable (Caption) -> Bool)] = [
        ("Colon Only", { $0.hasColon }),
        ("All Caps Figures Only", { $0.isAllCapsFigure || $0.kind == .table }),
        ("All Caps Table Only", { $0.isAllCapsTable || $0.kind == .figure }),
        ("Abbreviated Fig Only", { $0.isAbbreviatedFigure || $0.kind == .table }),
        ("Figure Following Text", { $0.kind == .table || !$0.lineEnd }),
        ("Period Only", { $0.hasPeriod }),
        ("Line End Only", { $0.lineEnd }),
    ]

    /// `selectCaptionCandidates` (CaptionDetector.scala): keep filtering while some number has duplicates and a filter
    /// removes a candidate without emptying a group. pdffigures2's last resort keeps the candidates that start a
    /// paragraph; every candidate here starts one (only a paragraph's first word is tested), so that step is a no-op and
    /// is left out. Candidates here are all on one page, so only the per-page limit applies.
    static func selectCaptionCandidates(_ candidates: [Caption]) -> [Caption] {
        var groups: [String: [Caption]] = Dictionary(grouping: candidates, by: \.groupKey)
        while groups.values.contains(where: { $0.count > 1 }) {
            let filter = candidateFilters.first { filter in
                let removesAny = groups.values.contains { group in group.contains { !filter.accept($0) } }
                let removesGroup = groups.values.contains { group in group.allSatisfy { !filter.accept($0) } }
                return removesAny && !removesGroup
            }
            guard let filter else { break }
            groups = groups.mapValues { $0.filter(filter.accept) }
        }
        let kept = groups.values.filter {
            $0.count <= maxSamePageDuplicateCaptionNames && $0.count <= maxDuplicateCaptionNames
        }
        return kept.flatMap { $0 }.sorted { $0.paragraphIndex < $1.paragraphIndex }
    }

    // MARK: - 2. The figure's region

    /// The region of `caption`'s figure, or nil: a table's caption (tables are read elsewhere), or no region next to the
    /// caption qualifies. Following pdffigures2's `buildProposals` (FigureDetector.scala): the caption's box is extended
    /// away from the caption until the nearest body block that overlaps it horizontally (the upward proposal first, then
    /// the downward one), then widened to the page's content bounds, stopping at body blocks beside it (`boxExpandLR`);
    /// on a two-column page a proposal that crosses the centre while the caption does not is cut at the centre, unless
    /// a label crosses the centre too (`cropToCenter`). The region must be at least `minRegionHeight` tall and
    /// `minRegionWidth` wide and hold at least one text-layer word that no body block holds: the figure's labels.
    /// pdffigures2 then scores every caption's proposals together; this port takes the upward region when it qualifies
    /// and `detect` keeps a downward region only where no upward one claims the same area.
    ///
    /// - Parameters:
    ///   - body: the boxes of the page's body text (prose paragraphs, tables, lists, other captions). The caption's own
    ///     box may be among them; it is ignored.
    ///   - words: the page's text-layer words.
    static func figureRegion(for caption: Caption, body: [CGRect], words: [TextLayerWord]) -> CGRect? {
        let proposals = proposals(for: caption, body: body, words: words)
        return proposals.above ?? proposals.below
    }

    /// Both of a caption's proposals, each nil when it does not qualify.
    static func proposals(
        for caption: Caption, body: [CGRect], words: [TextLayerWord]
    ) -> (above: CGRect?, below: CGRect?) {
        guard caption.kind == .figure else { return (nil, nil) }
        let blocks = body.filter { !isSameBlock($0, caption.box) }
        let labels = words.filter { word in
            let centre = centre(of: word.box)
            return !caption.box.contains(centre) && !blocks.contains { $0.contains(centre) }
        }
        guard !labels.isEmpty else { return (nil, nil) }
        let bounds = contentBounds(caption: caption.box, blocks: blocks, words: words)
        let columns = centreColumn(blocks: blocks, caption: caption.box)
        return (
            proposal(
                above: true, caption: caption.box, blocks: blocks, bounds: bounds, columns: columns, labels: labels),
            proposal(
                above: false, caption: caption.box, blocks: blocks, bounds: bounds, columns: columns, labels: labels)
        )
    }

    private static func proposal(
        above: Bool, caption: CGRect, blocks: [CGRect], bounds: CGRect, columns: (left: CGFloat, right: CGFloat)?,
        labels: [TextLayerWord]
    ) -> CGRect? {
        // The vertical reach: the nearest body block that overlaps the caption horizontally, in that direction
        // (`buildProposals`: `h == 0` with `v == 1` or `v == -1`).
        var limit = above ? bounds.maxY : bounds.minY
        for block in blocks where overlapsHorizontally(block, caption) {
            if above, block.minY >= caption.maxY - edgeTolerance {
                limit = min(limit, block.minY)
            } else if !above, block.maxY <= caption.minY + edgeTolerance {
                limit = max(limit, block.maxY)
            }
        }
        let minY = above ? caption.maxY : limit
        let maxY = above ? limit : caption.minY
        guard maxY - minY >= minRegionHeight else { return nil }
        var region = CGRect(x: caption.minX, y: minY, width: caption.width, height: maxY - minY)

        // Widened to the content bounds, stopping at body blocks beside it (`boxExpandLR`: `v == 0` with `h == 1` or
        // `h == -1`).
        var left = bounds.minX
        var right = bounds.maxX
        for block in blocks where overlapsVertically(block, region) {
            if block.maxX <= caption.minX + edgeTolerance {
                left = max(left, block.maxX)
            } else if block.minX >= caption.maxX - edgeTolerance {
                right = min(right, block.minX)
            }
        }
        region = CGRect(x: left, y: region.minY, width: right - left, height: region.height)

        // Two-column page: cut at the centre unless the caption crosses it, or the caption is wider than half the page
        // (a full-width figure), or a label inside the proposal crosses the column gap (`cropToCenter`).
        if let columns {
            let centre = (columns.left + columns.right) / 2
            let captionCrosses = (caption.minX <= centre && caption.maxX > centre) || caption.width > bounds.width / 2
            let regionCrosses = region.minX < centre && region.maxX > centre
            if regionCrosses, !captionCrosses {
                let labelCrosses = labels.contains { word in
                    word.box.minX < columns.left && word.box.maxX > columns.right
                        && region.contains(self.centre(of: word.box))
                }
                if !labelCrosses {
                    if caption.minX > centre {
                        region = CGRect(x: centre, y: region.minY, width: region.maxX - centre, height: region.height)
                    } else {
                        region = CGRect(
                            x: region.minX, y: region.minY, width: centre - region.minX, height: region.height)
                    }
                }
            }
        }

        guard region.width >= minRegionWidth else { return nil }
        guard labels.contains(where: { region.contains(centre(of: $0.box)) }) else { return nil }
        return region
    }

    /// pdffigures2's `findCenterColumn` on one page: the body blocks wholly left of the text's centre and those wholly
    /// right of it; the column gap is the left side's right edge to the right side's left edge, each snapped to the
    /// centre when within `columnSnapDistance` of it. Nil when either side is empty or the sides overlap (one column).
    /// pdffigures2 decides two columns once per document from its text layout; a page is decided here on its own.
    static func centreColumn(blocks: [CGRect], caption: CGRect) -> (left: CGFloat, right: CGFloat)? {
        let text = blocks.reduce(caption) { $0.union($1) }
        let textCentre = text.midX
        let leftSide = blocks.filter { $0.maxX < textCentre }
        let rightSide = blocks.filter { $0.minX > textCentre }
        guard let leftEdge = leftSide.map(\.maxX).max(), let rightEdge = rightSide.map(\.minX).min(),
            leftEdge < rightEdge
        else { return nil }
        let left = abs(leftEdge - textCentre) < columnSnapDistance ? leftEdge : textCentre
        let right = abs(rightEdge - textCentre) < columnSnapDistance ? rightEdge : textCentre
        return (min(left, right), max(left, right))
    }

    /// pdffigures2's `bounds = Box.container(allContent)`: the smallest box holding every block, the caption and every
    /// word.
    static func contentBounds(caption: CGRect, blocks: [CGRect], words: [TextLayerWord]) -> CGRect {
        var bounds = blocks.reduce(caption) { $0.union($1) }
        for word in words { bounds = bounds.union(word.box) }
        return bounds
    }

    // MARK: - 3. The figure's text

    /// The text-layer words whose centre lies in `region`, as lines top to bottom, each left to right. Words are grouped
    /// into lines the way `StructuredDocumentParser.textLayerText` does: a word joins the line whose first word's middle
    /// is within half the median word height of its own.
    static func figureText(region: CGRect, words: [TextLayerWord]) -> [String] {
        let inside = words.filter { region.contains(centre(of: $0.box)) }
        guard !inside.isEmpty else { return [] }
        let heights = inside.map(\.box.height).sorted()
        let lineTolerance = heights[heights.count / 2] * 0.5
        var lines: [[TextLayerWord]] = []
        for word in inside.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let first = lines.last?.first, abs(first.box.midY - word.box.midY) <= lineTolerance {
                lines[lines.count - 1].append(word)
            } else {
                lines.append([word])
            }
        }
        return lines.map { $0.sorted { $0.box.minX < $1.box.minX }.map(\.text).joined(separator: " ") }
    }

    // MARK: - 4. Detection

    /// The figures on a page. `bodyBoxes` are the boxes of the page's body text: prose paragraphs (`isProse`), tables and
    /// lists; a caption's box among them is ignored, and every caption bounds the other captions' regions (pdffigures2
    /// counts captions as non-figure content). Figures are returned top of page first. Where a figure's downward region
    /// overlaps another figure's upward region, the upward one wins (`figureRegion`).
    static func detect(
        paragraphs: [(text: String, box: CGRect)], bodyBoxes: [CGRect], words: [TextLayerWord]
    ) -> [Figure] {
        let found = captions(paragraphs: paragraphs)
        guard !found.isEmpty, !words.isEmpty else { return [] }
        let captionIndices = Set(found.map(\.paragraphIndex))
        let body = bodyBoxes.filter { box in !found.contains { isSameBlock($0.box, box) } }

        var placed: [(caption: Caption, region: CGRect)] = []
        var deferred: [(caption: Caption, region: CGRect)] = []
        for caption in found where caption.kind == .figure {
            let others = found.filter { $0.paragraphIndex != caption.paragraphIndex }.map(\.box)
            let proposals = proposals(for: caption, body: body + others, words: words)
            if let above = proposals.above {
                placed.append((caption, above))
            } else if let below = proposals.below {
                deferred.append((caption, below))
            }
        }
        for candidate in deferred where !placed.contains(where: { $0.region.intersects(candidate.region) }) {
            placed.append(candidate)
        }

        return placed.map { entry in
            let inside = paragraphs.indices.filter { index in
                !captionIndices.contains(index) && entry.region.contains(centre(of: paragraphs[index].box))
            }
            return Figure(
                number: entry.caption.number,
                caption: entry.caption.text,
                region: entry.region,
                labels: figureText(region: entry.region, words: words),
                paragraphIndices: inside,
                captionParagraphIndex: entry.caption.paragraphIndex)
        }.sorted { $0.region.maxY > $1.region.maxY }
    }

    /// Whether a paragraph's text is running prose, whose box bounds a figure's region, rather than a figure's labels
    /// read as a paragraph. pdffigures2 separates body text from other text by font and size (its `TextClassifier`),
    /// which Vision does not report; this is the port's own rule: eight or more words with fewer than a quarter of
    /// them holding a digit, or twenty or more words. A chart's axis ("0 25 50 75 100") and a chromatogram's peak names
    /// fail it; a one-line paragraph of prose passes.
    static func isProse(_ text: String) -> Bool {
        let tokens = text.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 8 else { return false }
        if tokens.count >= 20 { return true }
        let numeric = tokens.filter { $0.contains(where: \.isNumber) }.count
        return Double(numeric) < Double(tokens.count) * 0.25
    }

    // MARK: - Geometry

    static func centre(of box: CGRect) -> CGPoint {
        CGPoint(x: box.midX, y: box.midY)
    }

    /// Two boxes are the same block when their intersection covers over half of the smaller one.
    static func isSameBlock(_ a: CGRect, _ b: CGRect) -> Bool {
        let overlap = a.intersection(b)
        guard !overlap.isNull else { return false }
        let smaller = min(a.width * a.height, b.width * b.height)
        guard smaller > 0 else { return a == b }
        return overlap.width * overlap.height > smaller * 0.5
    }

    private static func overlapsHorizontally(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxX, b.maxX) - max(a.minX, b.minX) > edgeTolerance
    }

    private static func overlapsVertically(_ a: CGRect, _ b: CGRect) -> Bool {
        min(a.maxY, b.maxY) - max(a.minY, b.minY) > edgeTolerance
    }
}
