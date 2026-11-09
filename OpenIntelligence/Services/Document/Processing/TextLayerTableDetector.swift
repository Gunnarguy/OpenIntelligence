//
//  TextLayerTableDetector.swift
//  OpenIntelligence
//
//  Tables read from where a PDF's own words sit (5.8). Where a table is (its region) is found by a heuristic whose
//  thresholds were set on eight PDFs (BenchmarkRuns/2026-11-08-extraction-fidelity); its cells are read with the
//  heuristic's own grid. A port of pdfplumber's "text" strategy (`pdfplumberGrid`, MIT) is kept for comparison: measured
//  2026-11-08 it tied the heuristic grid on olmOCR-Bench's tables (128 checks each) and lost on the eight PDFs (413
//  against 433 of 515 checks, with its multi-line header join). Vision's document
//  reading finds a table from the rendered page and, measured 2026-11-08 on eight PDFs, missed whole tables or kept a
//  fragment: JAMA Psychiatry's full-page Table 1 came out as two mangled columns and its values as paragraph text (4 of 21
//  cell checks passed), the PAH paper's 48-row Table 1 was in no container at all. A page with a good text layer already
//  says where every word is, so rows are its lines, cells are runs of words with less than a word gap between them, and
//  columns are the vertical strips no cell crosses.
//

import CoreGraphics
import Foundation

nonisolated enum TextLayerTableDetector {
    struct Table: Equatable, Sendable {
        /// The table's region in Vision's normalized coordinates (origin bottom left).
        let box: CGRect
        /// The header row (several header lines joined per column), when the table has one.
        let header: [String]?
        /// Body rows, each with one entry per column ("" for an empty cell).
        let rows: [[String]]
    }

    private struct Segment {
        var text: String
        var box: CGRect
        var wordCount: Int
        /// Six or more words over a quarter of the page wide: running text, either a long cell or the other column of
        /// a two-column page beside the table.
        var isProse: Bool { wordCount >= 6 && box.width > 0.25 }
    }

    private struct Line {
        var segments: [Segment]
        /// The box of the line's cell-like segments (not its prose).
        var box: CGRect
        /// How many cell-like segments the line has.
        var cellCount: Int
    }

    private static func isNumeric(_ text: String) -> Bool {
        // A group size under a column name ("(n = 3026)", "N = 187 341") is part of the header, not a value.
        if text.range(of: #"^\(?\s*[nN]\s*="#, options: .regularExpression) != nil { return false }
        let digits = text.filter(\.isNumber).count
        let letters = text.filter(\.isLetter).count
        return digits > 0 && digits >= letters
    }

    /// The page's lines, top to bottom, each cut into segments where words are further apart than `gap` times the
    /// line's word height. A line with nothing but prose segments is left out: on a two-column page the other column's
    /// running text sits between a table's rows.
    private static func lines(of words: [TextLayerWord]) -> [Line] {
        guard !words.isEmpty else { return [] }
        let heights = words.map(\.box.height).sorted()
        let height = max(heights[heights.count / 2], 0.002)
        var grouped: [[TextLayerWord]] = []
        for word in words.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let first = grouped.last?.first, abs(first.box.midY - word.box.midY) <= height * 0.5 {
                grouped[grouped.count - 1].append(word)
            } else {
                grouped.append([word])
            }
        }
        return grouped.compactMap { group in
            var segments: [Segment] = []
            for word in group.sorted(by: { $0.box.minX < $1.box.minX }) {
                if var last = segments.last, word.box.minX - last.box.maxX <= height * 0.9 {
                    last.text += " " + word.text
                    last.box = last.box.union(word.box)
                    last.wordCount += 1
                    segments[segments.count - 1] = last
                } else {
                    segments.append(Segment(text: word.text, box: word.box, wordCount: 1))
                }
            }
            let cells = segments.filter { !$0.isProse }
            guard let first = cells.first else { return nil }
            return Line(
                segments: segments, box: cells.dropFirst().reduce(first.box) { $0.union($1.box) }, cellCount: cells.count)
        }
    }

    /// How many cells the words inside `box` make: runs of words with less than a word gap between them, line by line.
    /// A table Vision found holds its region well when it has nearly this many cells.
    static func segmentCount(in box: CGRect, words: [TextLayerWord]) -> Int {
        let inside = words.filter { box.contains(CGPoint(x: $0.box.midX, y: $0.box.midY)) }
        return lines(of: inside).reduce(0) { $0 + $1.cellCount }
    }

    /// Tables on a page from its text-layer words, largest first. A table needs at least 4 body rows of 3 or more cells
    /// and numbers in at least a quarter of its body cells, so running text, reference lists and two-column prose are
    /// not tables.
    static func tables(in words: [TextLayerWord]) -> [Table] {
        let pageLines = lines(of: words)
        guard pageLines.count >= 4 else { return [] }
        let heights = words.map(\.box.height).sorted()
        let height = max(heights[heights.count / 2], 0.002)

        // Regions: runs of lines in which lines of 3+ segments recur, joined while consecutive lines overlap
        // horizontally and sit within 3 line heights. A line of fewer segments (a wrapped label, a section label) stays
        // in the region when a tabular line follows within the same distance.
        var regions: [[Line]] = []
        var current: [Line] = []
        var pending: [Line] = []
        func close() {
            if current.filter({ $0.cellCount >= 3 }).count >= 4 { regions.append(current) }
            current = []
            pending = []
        }
        for line in pageLines {
            let tabular = line.cellCount >= 3
            if let last = (pending.last ?? current.last) {
                let gap = last.box.minY - line.box.maxY
                let overlaps = last.box.minX < line.box.maxX && line.box.minX < last.box.maxX
                if gap > height * 3 || !overlaps { close() }
            }
            if tabular {
                current.append(contentsOf: pending)
                pending = []
                current.append(line)
            } else if current.isEmpty {
                // Lines of two or more cells just above a table are header candidates ("No / ADHD" over "ADHD /
                // (n = 3026)"); a one-cell line there is a caption or running text.
                if line.cellCount >= 2 {
                    pending.append(line)
                    if pending.count > 3 { pending.removeFirst() }
                } else {
                    pending = []
                }
            } else {
                // Up to six short lines inside a table: section labels, wrapped labels and values a merged cell
                // centres between rows (JAMA's Table 1 split in two at its "0.52 | 0.17" lines).
                pending.append(line)
                if pending.count > 6 { close() }
            }
        }
        close()

        let found = regions.compactMap { table(from: $0, height: height) }
        // The region is found by the heuristic above; its cells are read with the heuristic's grid unless pdfplumber's
        // text strategy is selected (`gridMethod`).
        let gridded: [Table]
        if gridMethod == .pdfplumber {
            gridded = found.map { table in
                let inside = words.filter {
                    table.box.insetBy(dx: -0.002, dy: -0.002).contains(CGPoint(x: $0.box.midX, y: $0.box.midY))
                }
                guard let grid = pdfplumberGrid(words: inside), !grid.isEmpty else { return table }
                // pdfplumber makes every printed line a row, so a header printed on two lines ("Retention" over
                // "time (min)") named its column by half (measured 2026-11-08, after13: PAH table checks 53 to 35 of
                // 60). The rows above the first row with numbers in half its value cells are the header, joined per
                // column, as the position grid does.
                let split = headerRowCount(grid)
                let header = split == 0 ? grid[0] : (0..<grid[0].count).map { column in
                    grid[..<split].map { $0[column] }.filter { !$0.isEmpty }.joined(separator: " ")
                }
                let body = Array(grid[(split == 0 ? 1 : split)...])
                guard !body.isEmpty else { return table }
                return Table(box: table.box, header: header, rows: body)
            }
        } else {
            gridded = found
        }
        return gridded
            .sorted { $0.rows.count * ($0.rows.first?.count ?? 0) > $1.rows.count * ($1.rows.first?.count ?? 0) }
    }

    /// How many rows open a grid before its first body row: a row whose value cells (all but the first) hold at least
    /// two values, half or more of them numbers. Zero when the first row is already a body row.
    static func headerRowCount(_ rows: [[String]]) -> Int {
        rows.firstIndex { row in
            let values = row.dropFirst().filter { !$0.isEmpty }
            return values.count >= 2 && Double(values.filter(isNumeric).count) >= Double(values.count) * 0.5
        } ?? 0
    }

    private static func table(from lines: [Line], height: CGFloat) -> Table? {
        // Columns: the union of the x-extents of the segments on lines with nearly the most segments; a gap in that
        // union is a column boundary.
        let most = lines.map(\.cellCount).max() ?? 0
        let defining = lines.filter { Double($0.cellCount) >= Double(most) * 0.7 }
        // The table's extent from its cell-like segments; then its columns from every segment of those lines that
        // starts inside that extent, so a long text cell (an indication, a description) has a column of its own while
        // the page's other column, starting outside it, does not.
        let cellSpans = defining.flatMap { $0.segments.filter { !$0.isProse }.map(\.box) }
        guard let extentMinX = cellSpans.map(\.minX).min(), let extentMaxX = cellSpans.map(\.maxX).max() else {
            return nil
        }
        func belongs(_ segment: Segment) -> Bool {
            !segment.isProse || (segment.box.minX >= extentMinX - 0.01 && segment.box.minX < extentMaxX)
        }
        let spans = defining.flatMap { $0.segments.filter(belongs).map { ($0.box.minX, $0.box.maxX) } }
            .sorted { $0.0 < $1.0 }
        var columns: [(minX: CGFloat, maxX: CGFloat)] = []
        for span in spans {
            if let last = columns.last, span.0 <= last.maxX {
                columns[columns.count - 1].maxX = max(last.maxX, span.1)
            } else {
                columns.append((span.0, span.1))
            }
        }
        guard columns.count >= 3 else { return nil }

        func column(of segment: Segment) -> Int {
            var best = 0
            var bestOverlap: CGFloat = -1
            for (index, column) in columns.enumerated() {
                let overlap = min(column.maxX, segment.box.maxX) - max(column.minX, segment.box.minX)
                let distance = overlap > 0 ? overlap : -abs(segment.box.midX - (column.minX + column.maxX) / 2)
                if distance > bestOverlap {
                    bestOverlap = distance
                    best = index
                }
            }
            return best
        }

        // Rows: each line a row, except a line within 0.6 line heights of the row above that fills fewer than half the
        // columns and continues that row: a value wrapped under its cell (no label), or a label wrapped onto a second
        // line, which either starts in lower case or follows a label left unfinished ("Incident MCI or dementia," then
        // "No. (%)"). A label line after a finished label is a new row (a section label such as "Race, No. (%)").
        let joiningWords: Set<String> = ["or", "and", "of", "with", "the", "in", "for", "to", "a", "an", "by", "at", "on", "vs"]
        func unfinished(_ label: String) -> Bool {
            guard let last = label.split(separator: " ").last else { return false }
            if let character = last.last, ",-(/&".contains(character) { return true }
            return joiningWords.contains(last.lowercased())
        }
        var rows: [[String]] = []
        var rowBoxes: [CGRect] = []
        for line in lines {
            var cells = Array(repeating: "", count: columns.count)
            var lineBox: CGRect? = nil
            for segment in line.segments where belongs(segment) {
                let index = column(of: segment)
                cells[index] = cells[index].isEmpty ? segment.text : cells[index] + " " + segment.text
                lineBox = lineBox?.union(segment.box) ?? segment.box
            }
            guard let lineBox else { continue }
            let filled = cells.filter { !$0.isEmpty }.count
            let continues: Bool = {
                guard let lastBox = rowBoxes.last, lastBox.minY - lineBox.maxY < height * 0.6,
                    Double(filled) < Double(columns.count) * 0.5
                else { return false }
                if cells[0].isEmpty { return true }
                guard filled == 1 else { return false }
                return cells[0].first?.isLowercase == true || unfinished(rows[rows.count - 1][0])
            }()
            if continues, let lastBox = rowBoxes.last {
                for index in cells.indices where !cells[index].isEmpty {
                    let previous = rows[rows.count - 1][index]
                    rows[rows.count - 1][index] = previous.isEmpty ? cells[index] : previous + " " + cells[index]
                }
                rowBoxes[rowBoxes.count - 1] = lastBox.union(lineBox)
            } else {
                rows.append(cells)
                rowBoxes.append(lineBox)
            }
        }
        guard !rows.isEmpty else { return nil }

        // An edge column filled in under 15% of the rows (at least 2) is not the table's: a heading or line end of the
        // page's other column on the same line as a row. Its words stay out of the table for the coverage pass.
        var keep = Array(columns.indices)
        func filledCount(_ column: Int) -> Int { rows.filter { !$0[column].isEmpty }.count }
        let sparse = max(2, Int(Double(rows.count) * 0.15))
        while keep.count > 3, let last = keep.last, filledCount(last) < sparse { keep.removeLast() }
        while keep.count > 3, let first = keep.first, filledCount(first) < sparse { keep.removeFirst() }
        if keep.count < columns.count {
            let keptMinX = columns[keep[0]].minX
            let keptMaxX = columns[keep[keep.count - 1]].maxX
            rows = rows.map { row in keep.map { row[$0] } }
            rowBoxes = rowBoxes.map { box in
                let minX = max(box.minX, keptMinX)
                let maxX = min(box.maxX, keptMaxX)
                return CGRect(x: minX, y: box.minY, width: max(maxX - minX, 0), height: box.height)
            }
        }
        let columnCount = keep.count
        let nonEmpty = rows.indices.filter { rows[$0].contains { !$0.isEmpty } }
        rows = nonEmpty.map { rows[$0] }
        rowBoxes = nonEmpty.map { rowBoxes[$0] }
        guard !rows.isEmpty else { return nil }

        // Header: the rows before the first row with numbers in at least half of its non-label cells, joined per column.
        let firstBody =
            rows.firstIndex { row in
                let values = row.dropFirst().filter { !$0.isEmpty }
                return !values.isEmpty && Double(values.filter(isNumeric).count) >= Double(values.count) * 0.5
                    && values.count >= 2
            } ?? 0
        let headerRows = rows[..<firstBody]
        let body = Array(rows[firstBody...])
        let header: [String]? =
            headerRows.isEmpty
            ? nil
            : (0..<columnCount).map { index in
                headerRows.map { $0[index] }.filter { !$0.isEmpty }.joined(separator: " ")
            }

        let wideRows = body.filter { $0.filter { !$0.isEmpty }.count >= 3 }
        guard wideRows.count >= 4 else { return nil }
        let bodyCells = body.flatMap { $0 }.filter { !$0.isEmpty }
        guard !bodyCells.isEmpty, Double(bodyCells.filter(isNumeric).count) >= Double(bodyCells.count) * 0.25 else {
            return nil
        }
        let box = rowBoxes.dropFirst().reduce(rowBoxes[0]) { $0.union($1) }
        return Table(box: box, header: header, rows: body)
    }

    // MARK: - pdfplumber's "text" strategy, ported

    /// Which grid a found region's cells are read with. `positions` (the heuristic's own) is the default, chosen by
    /// measurement on 2026-11-08 (see the file header); `OI_TABLE_GRID=pdfplumber` in the environment selects the port
    /// below, to compare the two on one build.
    enum GridMethod { case pdfplumber, positions }
    static var gridMethod: GridMethod {
        ProcessInfo.processInfo.environment["OI_TABLE_GRID"] == "pdfplumber" ? .pdfplumber : .positions
    }

    private struct PlumberWord {
        let text: String
        let x0: Double, x1: Double, top: Double, bottom: Double
        var centerX: Double { (x0 + x1) / 2 }
        var centerY: Double { (top + bottom) / 2 }
    }

    /// pdfplumber's `cluster_list`: values sorted, a value within `tolerance` of the previous one joins its group.
    private static func clusterIndices(_ values: [Double], tolerance: Double) -> [[Int]] {
        let order = values.indices.sorted { values[$0] < values[$1] }
        var groups: [[Int]] = []
        var last = -Double.infinity
        for index in order {
            if let _ = groups.last, values[index] <= last + tolerance {
                groups[groups.count - 1].append(index)
            } else {
                groups.append([index])
            }
            last = values[index]
        }
        return groups
    }

    /// pdfplumber's `snap_objects` on one coordinate: each cluster (tolerance chained) moves to its mean.
    private static func snapped(_ values: [Double], tolerance: Double) -> [Double] {
        var out = values
        for group in clusterIndices(values, tolerance: tolerance) {
            let mean = group.reduce(0) { $0 + values[$1] } / Double(group.count)
            for index in group { out[index] = mean }
        }
        return out
    }

    /// The cells of a table region read with pdfplumber's "text" strategy and its defaults (pdfplumber `table.py` and
    /// `utils`, stable branch, read 2026-11-08): vertical edges where at least 3 words (`min_words_vertical`) share a left
    /// edge, right edge or centre within 1 point, largest clusters first, a cluster's box dropped when it overlaps a box
    /// already kept, an edge at each kept box's left side and one at the rightmost right side, spanning the kept boxes'
    /// height; horizontal edges at the top and bottom of every line (words whose tops are within 1 point,
    /// `min_words_horizontal` 1), spanning the lines' width; edges within 3 points snapped to their mean
    /// (`snap_tolerance`), and an edge meets another within 3 points (`intersection_tolerance`). A word belongs to the
    /// cell its centre is in. Rows and columns with no word are left out. Nil when the region has under two columns or rows.
    static func pdfplumberGrid(words: [TextLayerWord]) -> [[String]]? {
        guard let first = words.first else { return nil }
        let size = first.pageSize.width > 0 ? first.pageSize : CGSize(width: 612, height: 792)
        let items = words.map { word in
            PlumberWord(
                text: word.text, x0: Double(word.box.minX * size.width), x1: Double(word.box.maxX * size.width),
                top: Double((1 - word.box.maxY) * size.height), bottom: Double((1 - word.box.minY) * size.height))
        }

        // Vertical edges.
        let clusters =
            (clusterIndices(items.map(\.x0), tolerance: 1) + clusterIndices(items.map(\.x1), tolerance: 1)
            + clusterIndices(items.map(\.centerX), tolerance: 1))
            .enumerated().sorted { ($0.element.count, -$0.offset) > ($1.element.count, -$1.offset) }.map(\.element)
            .filter { $0.count >= 3 }
        typealias Box = (x0: Double, x1: Double, top: Double, bottom: Double)
        func box(_ group: [Int]) -> Box {
            (
                group.map { items[$0].x0 }.min()!, group.map { items[$0].x1 }.max()!,
                group.map { items[$0].top }.min()!, group.map { items[$0].bottom }.max()!
            )
        }
        func overlaps(_ a: Box, _ b: Box) -> Bool {
            let width = min(a.x1, b.x1) - max(a.x0, b.x0)
            let height = min(a.bottom, b.bottom) - max(a.top, b.top)
            return width >= 0 && height >= 0 && width + height > 0
        }
        var kept: [Box] = []
        for group in clusters {
            let candidate = box(group)
            if !kept.contains(where: { overlaps($0, candidate) }) { kept.append(candidate) }
        }
        guard !kept.isEmpty else { return nil }
        let vTop = kept.map(\.top).min()!, vBottom = kept.map(\.bottom).max()!
        let vertical = kept.map(\.x0).sorted() + [kept.map(\.x1).max()!]

        // Horizontal edges.
        let lineGroups = clusterIndices(items.map(\.top), tolerance: 1)
        let lineBoxes = lineGroups.map(box)
        let hX0 = lineBoxes.map(\.x0).min()!, hX1 = lineBoxes.map(\.x1).max()!
        let horizontal = lineBoxes.flatMap { [$0.top, $0.bottom] }

        // Snap, keep the edges that meet the other set, and read the grid between them.
        let tolerance = 3.0
        let xs = Array(Set(snapped(vertical, tolerance: tolerance).filter { $0 >= hX0 - tolerance && $0 <= hX1 + tolerance })).sorted()
        let ys = Array(Set(snapped(horizontal, tolerance: tolerance).filter { $0 >= vTop - tolerance && $0 <= vBottom + tolerance })).sorted()
        guard xs.count >= 3, ys.count >= 3 else { return nil }
        var grid = Array(repeating: Array(repeating: [PlumberWord](), count: xs.count - 1), count: ys.count - 1)
        for item in items {
            guard let column = (0..<(xs.count - 1)).first(where: { item.centerX >= xs[$0] && item.centerX < xs[$0 + 1] }),
                let row = (0..<(ys.count - 1)).first(where: { item.centerY >= ys[$0] && item.centerY < ys[$0 + 1] })
            else { continue }
            grid[row][column].append(item)
        }
        var rows: [[String]] = grid.map { row in
            row.map { cell in
                // A cell's words in reading order: lines by top, then left to right.
                cell.sorted { abs($0.top - $1.top) > 1 ? $0.top < $1.top : $0.x0 < $1.x0 }.map(\.text).joined(separator: " ")
            }
        }
        rows.removeAll { $0.allSatisfy(\.isEmpty) }
        guard !rows.isEmpty else { return nil }
        let filledColumns = (0..<rows[0].count).filter { column in rows.contains { !$0[column].isEmpty } }
        rows = rows.map { row in filledColumns.map { row[$0] } }
        guard filledColumns.count >= 2, rows.count >= 2 else { return nil }
        return rows
    }
}
