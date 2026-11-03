//
//  SourceTextView.swift
//  OpenIntelligence
//
//  A cited passage in its document's text, highlighted, for every kind of document (5.8).
//

import PDFKit
import SwiftUI

/// Whether a cited passage is literally in its document.
nonisolated enum SourceMatch: Hashable, Sendable {
    /// Every word of the passage is in the document's text, in order.
    case exact
    /// Part of it is, and the rest differs.
    case partial
    /// None of it could be placed.
    case notFound
    /// The document's text isn't on this device.
    case noText
    /// Not the document's words at all: the overview the app wrote of it at import, which an answer can draw on.
    case overview

    var title: String {
        switch self {
        case .exact: "Found word for word in this document."
        case .partial: "Found in part. The rest doesn't match the document's text exactly."
        case .notFound: "Couldn't find this exact passage in the document's text."
        case .noText: "This document's text isn't available on this device."
        case .overview: "This is the app's own overview of the document, not text from it."
        }
    }

    var isConfirmed: Bool { self == .exact }
}

/// The text around a passage: a whole document can be millions of characters, which a text view can't lay out.
nonisolated struct SourceExcerpt: Equatable, Sendable {
    var before: String
    var passage: String
    var after: String
    var hasMoreBefore: Bool
    var hasMoreAfter: Bool

    /// `radius` characters either side of `range`, each cut back to a word's edge.
    static func around(_ range: NSRange, in text: String, radius: Int) -> SourceExcerpt {
        let string = text as NSString
        let start = max(0, range.location - radius)
        let end = min(string.length, range.location + range.length + radius)
        var before = string.substring(with: NSRange(location: start, length: range.location - start))
        var after = string.substring(
            with: NSRange(location: range.location + range.length, length: end - range.location - range.length))
        if start > 0, let space = before.firstIndex(where: \.isWhitespace) {
            before = String(before[space...])
        }
        if end < string.length, let space = after.lastIndex(where: \.isWhitespace) {
            after = String(after[..<space])
        }
        return SourceExcerpt(
            before: before, passage: string.substring(with: range), after: after,
            hasMoreBefore: start > 0, hasMoreAfter: end < string.length)
    }
}

/// What a look for a passage found.
nonisolated struct SourceLookup: Equatable, Sendable {
    var match: SourceMatch
    /// The document's text, nil when there is none.
    var text: String?
    /// Where the passage is in it.
    var range: NSRange?

    /// What can stand between a table's cells: spaces, commas, tabs, and a Markdown table's pipes.
    private static let cellSeparators = #"[\s,;|:"]+"#

    /// Decides whether `passage` is in `text`. Exact first, since a passage found whole needs no second look. A table's
    /// passage carries labels the import added (`[Part 2]`, `HEADERS:`, `ROW 3:`, `|`), which aren't in the file, so
    /// without them its cells are looked for in order, whatever separates them there.
    static func find(_ passage: String, inText text: String?) -> SourceLookup {
        guard let text, !text.isEmpty else { return SourceLookup(match: .noText) }
        if let range = PassageLocator.exactRange(of: passage, in: text) {
            return SourceLookup(match: .exact, text: text, range: range)
        }
        let unlabeled = PassageLocator.withoutImportLabels(passage)
        if let unlabeled, let range = PassageLocator.exactRange(of: unlabeled, in: text, separators: cellSeparators) {
            return SourceLookup(match: .exact, text: text, range: range)
        }
        if text.contains("| --- |") {
            let values = PassageLocator.cellValues(of: unlabeled ?? passage) ?? unlabeled ?? passage
            if let range = PassageLocator.exactRange(of: values, in: text, separators: cellSeparators) {
                return SourceLookup(match: .exact, text: text, range: range)
            }
            // A passage that runs from a table's rows into its `name: value` form doesn't read in order as a whole.
            // Its opening cells still show where it is.
            let words = values.split(whereSeparator: \.isWhitespace)
            let opening = words.prefix(min(12, max(2, words.count / 2))).joined(separator: " ")
            if let range = PassageLocator.exactRange(of: opening, in: text, separators: cellSeparators) {
                return SourceLookup(match: .partial, text: text, range: range)
            }
        }
        if let range = PassageLocator.range(of: unlabeled ?? passage, in: text) {
            return SourceLookup(match: .partial, text: text, range: range)
        }
        return SourceLookup(match: .notFound, text: text)
    }

    /// Reads the document's text and looks. Off the main actor: a large document's text is megabytes, and the search
    /// runs over all of it.
    @concurrent static func find(_ passage: String, in documentId: UUID, isOverview: Bool = false) async -> SourceLookup {
        // Looking for an overview in the document would only ever say it wasn't found, which reads as a fault.
        if isOverview { return SourceLookup(match: .overview) }
        var text = SQLiteFullTextService.readContentDirectly(documentId: documentId)
        if text?.isEmpty != false {
            text = await FullTextStorageService.shared.retrieve(for: documentId)
        }
        return find(passage, inText: text)
    }

    /// Whether a PDF's page has no text layer, as a scan read with OCR doesn't, so nothing can be highlighted on it.
    @concurrent static func pageHasNoText(url: URL, pageIndex: Int) async -> Bool {
        guard let page = PDFDocument(url: url)?.page(at: pageIndex) else { return false }
        return page.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}

/// Says whether the passage on screen is literally in the document.
struct SourceMatchBanner: View {
    let match: SourceMatch
    var detail: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DSSpacing.sm) {
            Image(systemName: match.isConfirmed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(DSColors.readable(match.isConfirmed ? .green : DSColors.warning))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(match.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColors.primaryText)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(DSColors.secondaryText)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}

/// Shows a cited passage in its document's text, highlighted, and says whether it was found there (5.8).
///
/// `SourcePageView` does this on the page itself for a PDF. Anything else has no page PDFKit can mark, and Quick Look
/// can't be told to highlight a range, so this shows the text the app read from the file: the document itself for text
/// and Markdown, and the extracted text for Word, Excel, PowerPoint and the like, a recording's transcript, and the text
/// read from an image. What it proves is that the passage is literally there. Whether the answer read it correctly is
/// what the person checks by reading it.
struct SourceTextView: View {
    let document: Document
    /// The passage as the answer holds it. A saved conversation keeps it cut to 600 characters, so the library's whole
    /// copy replaces it, as on `SourcePageView`.
    let passage: String
    let chunk: RetrievedChunk?
    let lookup: LibraryDocumentLookup?

    private static let firstRadius = 3_000
    private static let moreRadius = 12_000

    @State private var result: SourceLookup?
    @State private var shownPassage: String?
    @State private var radius = Self.firstRadius
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(Text(verbatim: document.filename))
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
                    var whole = passage
                    if let id = chunk?.chunk.id, let stored = await lookup?.passageText(id, in: document),
                        !stored.isEmpty
                    {
                        whole = stored
                    }
                    shownPassage = whole
                    result = await SourceLookup.find(
                        whole, in: document.id, isOverview: chunk?.chunk.metadata.abstractionLevel.isSummary ?? false)
                }
        }
        #if os(macOS)
            .frame(
                minWidth: 560, idealWidth: 720, maxWidth: 1000, minHeight: 560, idealHeight: 760, maxHeight: .infinity)
        #endif
    }

    @ViewBuilder
    private var content: some View {
        if let result {
            ScrollViewReader { reader in
                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        if let text = result.text, let range = result.range {
                            excerpt(.around(range, in: text, radius: radius))
                        } else {
                            Text("The passage the answer used:")
                                .font(.subheadline.weight(.semibold))
                            Text(verbatim: shownPassage ?? passage)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(DSSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    SourceMatchBanner(match: result.match)
                }
                .onAppear { reader.scrollTo(Self.passageAnchor, anchor: .center) }
            }
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private static let passageAnchor = "passage"

    @ViewBuilder
    private func excerpt(_ part: SourceExcerpt) -> some View {
        if part.hasMoreBefore {
            Button("Show Earlier Text") { radius += Self.moreRadius }
                .font(.footnote)
        }
        Text(verbatim: part.before)
            .foregroundStyle(DSColors.secondaryText)
            .textSelection(.enabled)
        Text(verbatim: part.passage)
            .foregroundStyle(DSColors.primaryText)
            .padding(DSSpacing.xs)
            .background(
                RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                    .fill(Color.yellow.opacity(0.32))
            )
            .textSelection(.enabled)
            .id(Self.passageAnchor)
            .accessibilityLabel(Text("Highlighted passage: \(part.passage)"))
        Text(verbatim: part.after)
            .foregroundStyle(DSColors.secondaryText)
            .textSelection(.enabled)
        if part.hasMoreAfter {
            Button("Show Later Text") { radius += Self.moreRadius }
                .font(.footnote)
        }
    }
}
