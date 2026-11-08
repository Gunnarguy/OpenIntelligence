//
//  SourcePageView.swift
//  OpenIntelligence
//
//  The page a cited passage is on, with the passage highlighted (5.7).
//

import PDFKit
import SwiftUI

/// Shows the page of a PDF that a cited passage came from, scrolled to the passage and with it highlighted (5.7).
///
/// Through 5.6 a citation opened the document's details, and their Quick Look preview opens a PDF at its first page, so
/// checking an answer against its page meant finding the page by hand. PDFKit can go to a page and highlight a range of
/// its text. A page with no text layer (a scan that was read with OCR at import) still opens at the page, without a
/// highlight. The document's details stay one tap away.
struct SourcePageView: View {
    let document: Document
    /// The page, counted from 1 as the import records it.
    let pageNumber: Int
    /// The cited passage, for its id and the details' highlighted card.
    let chunk: RetrievedChunk?
    /// The library, which holds the passage's whole text.
    let lookup: LibraryDocumentLookup?

    /// The passage's text as the answer holds it, and then the library's whole copy: a saved conversation keeps each
    /// passage cut to 600 characters (`ChatMessage`), so after a relaunch the saved copy would highlight only its start.
    @State private var passage: String
    /// Whether the passage is in the document's text, and whether this page can show it (5.8).
    @State private var match: SourceMatch?
    @State private var pageIsScan = false
    @Environment(\.dismiss) private var dismiss

    init(document: Document, pageNumber: Int, passage: String, chunk: RetrievedChunk?, lookup: LibraryDocumentLookup? = nil) {
        self.document = document
        self.pageNumber = pageNumber
        self.chunk = chunk
        self.lookup = lookup
        _passage = State(initialValue: passage)
    }

    var body: some View {
        NavigationStack {
            PassagePDFView(url: document.fileURL, pageIndex: pageNumber - 1, passage: passage)
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let match {
                        SourceMatchBanner(
                            match: match,
                            detail: pageIsScan ? "This page is a scan, so the passage can't be highlighted on it." : nil)
                        .tour(.matchBanner, in: Tour.source, arrow: .top)
                    }
                }
                .navigationTitle("Page \(pageNumber)")
                .navigationSubtitle(Text(verbatim: document.filename))
                #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            DocumentDetailsView(document: document, embeddingProviderId: nil, highlightedChunk: chunk)
                        } label: {
                            Label("Document Details", systemImage: "info.circle")
                        }
                    }
                }
                .task {
                    if let id = chunk?.chunk.id, let whole = await lookup?.passageText(id, in: document), !whole.isEmpty {
                        passage = whole
                    }
                    pageIsScan = await SourceLookup.pageHasNoText(url: document.fileURL, pageIndex: pageNumber - 1)
                    match = await SourceLookup.find(
                        passage, in: document.id, isOverview: chunk?.chunk.metadata.abstractionLevel.isSummary ?? false
                    ).match
                    // A cited page opened (5.8 journal): the file's type and how its passage was found.
                    VerificationJournal.record(
                        "citation.open",
                        ["view": "page", "type": document.fileURL.pathExtension.lowercased(),
                            "match": match.map { "\($0)" } ?? "none", "scan": "\(pageIsScan)"])
                }
        }
        #if os(macOS)
            // A Mac sheet takes its size from its content, and a PDF view has none of its own: hosted with no frame it
            // measured 0 by 0 (2026-10-16). `PrivacyPolicyView` and `ContainerSettingsSheet` have the same note.
            .frame(minWidth: 560, idealWidth: 720, maxWidth: 1000, minHeight: 560, idealHeight: 760, maxHeight: .infinity)
        #endif
    }
}

/// A cited passage's PDF and page, for a sheet that shows it (5.7).
struct SourcePageTarget: Identifiable {
    let document: Document
    let page: Int
    var id: String { "\(document.id.uuidString)-\(page)" }
}

extension CitationSourceDocument {
    /// Whether a cited passage can be shown on its page: a PDF whose file is on this device, and a page number from
    /// the import (5.7). Anything else opens the document's details, as before.
    static func page(of chunk: RetrievedChunk, in document: Document) -> Int? {
        guard let page = chunk.pageNumber ?? chunk.chunk.metadata.pageNumber, page > 0 else { return nil }
        guard document.contentType == .pdf || document.fileURL.pathExtension.lowercased() == "pdf" else { return nil }
        return hasFile(document) ? page : nil
    }
}

/// Where a cited passage sits in a page's text (5.7).
///
/// A passage and the PDF's text layer differ in whitespace (line breaks, runs of spaces) and can differ in case, so
/// each sentence is matched as its words in order with any whitespace between them. Sentences of four words or more
/// are matched by their first 12 words, and the last one whole when the page holds it whole, so the range runs from
/// the first sentence found to the end of the last: the whole passage when its sentences are on the page, and the part
/// that is on it when the passage runs over from the page before or onto the next one. A passage cut short with "..."
/// (as a saved conversation keeps it) is matched up to the cut.
nonisolated enum PassageLocator {
    static func range(of passage: String, in pageText: String) -> NSRange? {
        let length = (pageText as NSString).length
        let sentences = Self.sentences(of: passage)
        var first: NSRange?
        var last: NSRange?
        for (index, words) in sentences.enumerated() {
            let start = last.map { $0.location + $0.length } ?? 0
            guard start < length else { break }
            let whole = index == sentences.count - 1 && words.count > 12
                ? match(words, in: pageText, from: start, length: length) : nil
            guard let found = whole ?? match(Array(words.prefix(12)), in: pageText, from: start, length: length)
            else { continue }
            if first == nil { first = found }
            last = found
        }
        guard let first, let last else { return nil }
        return NSRange(location: first.location, length: last.location + last.length - first.location)
    }

    /// Where the passage sits when every one of its words is there, in order, with only whitespace and case
    /// differing (5.8). `range(of:in:)` finds where a passage is and tolerates a sentence that isn't there, which is
    /// right for placing a highlight. This is what lets the app say "word for word".
    static func exactRange(of passage: String, in text: String, separators: String = #"\s+"#) -> NSRange? {
        var trimmed = passage.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("...") {
            trimmed.removeLast(3)
        } else if trimmed.hasSuffix("\u{2026}") {
            trimmed.removeLast()
        }
        let words = trimmed.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return nil }
        return match(words, in: text, from: 0, length: (text as NSString).length, separators: separators)
    }

    /// A passage without the labels the import adds around a table's cells and a split passage's parts, or nil when
    /// it has none. Those labels aren't in the file, so a passage carrying them can never be found in it word for word.
    static func withoutImportLabels(_ passage: String) -> String? {
        let wholeLines = ["HEADERS:", "TABLE:", "SOURCE:", "Section Path:", "[Specifications]"]
        // Anywhere in a line: a long table's parts are split again by words, which can run rows together.
        let inline = [#"\[Part \d+\]\s*"#, #"\bROW \d+:\s*"#, #"\s\|\s"#]
        // A row names its later cells by column from 5.8 ("DHA | Daily Dose: 1-2 g"); the names are the passage's own
        // HEADERS line, which the file prints once, so they come out too.
        let columnNames: [String] = passage.components(separatedBy: .newlines)
            .first(where: { $0.hasPrefix("HEADERS:") })
            .map { line in
                line.dropFirst("HEADERS:".count).components(separatedBy: " | ")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            } ?? []
        var changed = false
        var kept: [String] = []
        for line in passage.components(separatedBy: .newlines) {
            if wholeLines.contains(where: line.hasPrefix) {
                changed = true
                continue
            }
            var cleaned = line
            if cleaned.range(of: #"\bROW \d+:"#, options: .regularExpression) != nil {
                for name in columnNames {
                    cleaned = cleaned.replacingOccurrences(of: " | \(name): ", with: " | ")
                }
            }
            for label in inline {
                cleaned = cleaned.replacingOccurrences(of: label, with: " ", options: .regularExpression)
            }
            cleaned = cleaned.trimmingCharacters(in: .whitespaces)
            if cleaned != line { changed = true }
            if !cleaned.isEmpty { kept.append(cleaned) }
        }
        return changed ? kept.joined(separator: "\n") : nil
    }

    /// A table's passage written as `name: value` lines, as just its values, or nil when none has a name. The import
    /// indexes a table that way too, and the file holds the names once, in its header. For a table only: in prose, the
    /// words before a colon are the document's own.
    static func cellValues(of passage: String) -> String? {
        var changed = false
        var values: [String] = []
        for line in passage.components(separatedBy: .newlines) {
            for piece in line.components(separatedBy: ";") {
                var value = piece.trimmingCharacters(in: .whitespaces)
                let unnamed = value.replacingOccurrences(of: #"^[^:]{1,40}:\s+"#, with: "", options: .regularExpression)
                if unnamed != value { changed = true }
                value = unnamed
                if value.hasSuffix(".") { value.removeLast() }
                if !value.isEmpty { values.append(value) }
            }
        }
        return changed ? values.joined(separator: " ") : nil
    }

    /// The pieces matched first: each sentence's first 12 words.
    static func pieces(of passage: String) -> [[String]] {
        sentences(of: passage).map { Array($0.prefix(12)) }
    }

    /// The passage's sentences of four words or more, as their words; a passage with no such sentence is one sentence
    /// of its words, when it has two or more. A "..." or "…" that ends a cut-short passage is left out.
    static func sentences(of passage: String) -> [[String]] {
        var text = passage.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix("...") {
            text.removeLast(3)
        } else if text.hasSuffix("\u{2026}") {
            text.removeLast()
        }
        var sentences: [[String]] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .bySentences) { sentence, _, _, _ in
            guard let sentence else { return }
            let words = sentence.split(whereSeparator: \.isWhitespace).map(String.init)
            if words.count >= 4 { sentences.append(words) }
        }
        if !sentences.isEmpty { return sentences }
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        return words.count >= 2 ? [words] : []
    }

    private static func match(
        _ words: [String], in text: String, from start: Int, length: Int, separators: String = #"\s+"#
    ) -> NSRange? {
        let pattern = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: separators)
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        return expression.firstMatch(in: text, range: NSRange(location: start, length: length - start))?.range
    }
}

/// The page and, when its text layer holds the passage, the passage's selection on it (5.7).
enum PassageReveal {
    static func target(in document: PDFDocument, pageIndex: Int, passage: String) -> (page: PDFPage, selection: PDFSelection?)? {
        guard document.pageCount > 0 else { return nil }
        let index = min(max(pageIndex, 0), document.pageCount - 1)
        guard let page = document.page(at: index) else { return nil }
        guard let text = page.string, let range = PassageLocator.range(of: passage, in: text),
            let selection = page.selection(for: range)
        else { return (page, nil) }
        return (page, selection)
    }
}

/// A PDF view that goes to a passage's page and highlights the passage. Before its first layout it has nothing to
/// scroll, so it goes there once it has a size.
final class RevealingPDFView: PDFView {
    private var reveal: (() -> Void)?
    /// The passage it highlights, so the same text is not found twice and a longer copy of it is found again.
    private(set) var shownPassage: String?

    /// A view of the PDF at `url`, its pages one after another down the screen, scaled to fit.
    static func showing(_ url: URL) -> RevealingPDFView {
        let view = RevealingPDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = PDFDocument(url: url)
        return view
    }

    /// Goes to the passage's page and highlights the passage where the page's text holds it: now when the view has a
    /// size, and otherwise after its first layout. Shown again with a longer copy, the highlight grows to it; a copy
    /// the page does not hold leaves the highlight there is.
    func show(_ passage: String, pageIndex: Int) {
        guard passage != shownPassage, let document,
            let target = PassageReveal.target(in: document, pageIndex: pageIndex, passage: passage)
        else { return }
        shownPassage = passage
        reveal = { [weak self] in
            guard let self else { return }
            VerificationJournal.record("citation.highlight", ["found": "\(target.selection != nil)"])
            if let selection = target.selection {
                selection.color = .systemYellow
                self.highlightedSelections = [selection]
                self.go(to: selection)
            } else if self.highlightedSelections == nil {
                self.go(to: target.page)
            }
        }
        revealOnce()
    }

    #if canImport(UIKit)
        override func layoutSubviews() {
            super.layoutSubviews()
            revealOnce()
        }
    #else
        // Hosted in SwiftUI on the Mac, AppKit calls this once the view has its size (a probe on macOS 27,
        // 2026-10-16: one call, after which the cited page was current and the passage highlighted).
        override func layout() {
            super.layout()
            revealOnce()
        }
    #endif

    private func revealOnce() {
        guard bounds.width > 0, bounds.height > 0, let reveal else { return }
        self.reveal = nil
        reveal()
    }
}

#if canImport(UIKit)
    private struct PassagePDFView: UIViewRepresentable {
        let url: URL
        let pageIndex: Int
        let passage: String

        func makeUIView(context: Context) -> RevealingPDFView {
            let view = RevealingPDFView.showing(url)
            view.show(passage, pageIndex: pageIndex)
            return view
        }

        func updateUIView(_ view: RevealingPDFView, context: Context) {
            view.show(passage, pageIndex: pageIndex)
        }
    }
#else
    private struct PassagePDFView: NSViewRepresentable {
        let url: URL
        let pageIndex: Int
        let passage: String

        func makeNSView(context: Context) -> RevealingPDFView {
            let view = RevealingPDFView.showing(url)
            view.show(passage, pageIndex: pageIndex)
            return view
        }

        func updateNSView(_ view: RevealingPDFView, context: Context) {
            view.show(passage, pageIndex: pageIndex)
        }
    }
#endif
