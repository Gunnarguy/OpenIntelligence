//
//  VisualDocumentSearch.swift
//  OpenIntelligence
//

#if canImport(VisualIntelligence)
    import AppIntents
    import CoreImage
    import Foundation
    import Vision
    import VisualIntelligence

    /// Visual Intelligence lists matching documents from the person's libraries (5.7): point the
    /// camera at a device's label or a printed page, or take a screenshot, and the documents that
    /// mention what is in the picture come back as OpenIntelligence items, which open on tap
    /// (`OpenDocumentIntent`). An app may have one such query (Apple's "Integrating your app with
    /// visual intelligence", read 2026-10-14).
    ///
    /// The text in the picture is read on the device (Vision) and searched, with the labels the
    /// system gives the picture, in the passages' keyword index across every library. A document
    /// whose name holds one of the words comes first. At most 100, as Apple's guide asks.
    @available(iOS 26.0, macOS 27.0, *)
    struct VisualDocumentSearchQuery: IntentValueQuery {
        func values(for input: SemanticContentDescriptor) async throws -> [OIDocumentEntity] {
            let terms = await VisualDocumentSearch.terms(for: input)
            guard !terms.isEmpty else { return [] }
            return await VisualDocumentSearch.documents(matching: terms)
        }
    }

    /// "More results": the app's own search, run for the words the picture gave. The schema's one
    /// parameter is `semanticContent`, and the intent opens the app (Xcode 27's
    /// AppIntentSchemas.sqlite, `ShowVisualSearchResultsInAppIntent`, read 2026-10-14).
    @available(iOS 26.0, macOS 27.0, *)
    @AppIntent(schema: .visualIntelligence.semanticContentSearch)
    struct VisualDocumentSearchResultsIntent {
        var semanticContent: SemanticContentDescriptor

        func perform() async throws -> some IntentResult {
            let terms = await VisualDocumentSearch.terms(for: semanticContent)
            await MainActor.run { AppNavigationRequest.post(.searchFor(terms.joined(separator: " "))) }
            return .result()
        }
    }

    @available(iOS 26.0, macOS 27.0, *)
    enum VisualDocumentSearch {
        static let maximumResults = 100

        /// The words to search for: the picture's text read on the device, then the system's labels.
        static func terms(for input: SemanticContentDescriptor) async -> [String] {
            let text = await recognizedText(in: input)
            let terms = VisualSearchTerms.from(text: text, labels: input.labels)
            Log.info(
                "[VisualSearch] \(terms.count) term(s) from \(text.count) characters of text and \(input.labels.count) label(s)",
                category: .retrieval)
            return terms
        }

        /// The text Vision reads in the picture, or nothing when there is no picture.
        @concurrent nonisolated static func recognizedText(in input: SemanticContentDescriptor) async -> String {
            guard let buffer = input.pixelBuffer else { return "" }
            // The buffer is lent for the closure only, so the picture is drawn into an image the
            // request can keep (Apple's guide does the same).
            let image: CGImage? = buffer.withUnsafeBuffer { pixelBuffer in
                let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
                return CIContext().createCGImage(ciImage, from: ciImage.extent)
            }
            guard let image else { return "" }
            do {
                let observations = try await RecognizeTextRequest().perform(on: image)
                return observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            } catch {
                Log.warning("[VisualSearch] Text could not be read: \(error.localizedDescription)", category: .retrieval)
                return ""
            }
        }

        /// Documents whose name holds a term, then documents whose passages match, best first.
        static func documents(matching terms: [String]) async -> [OIDocumentEntity] {
            let all = OIDocumentEntityQuery.loadAllDocuments()
            let byId = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var ordered: [UUID] = []
            var seen = Set<UUID>()
            for document in all where VisualSearchTerms.nameMatches(document.filename, terms: terms) {
                if seen.insert(document.id).inserted { ordered.append(document.id) }
            }
            // Every word first, then any word (`searchChunks` falls back by itself).
            let hits = await SQLiteFullTextService.shared.searchChunks(
                query: terms.joined(separator: " "), containerId: nil, limit: 400)
            for hit in hits where seen.insert(hit.documentId).inserted {
                ordered.append(hit.documentId)
            }
            return ordered.compactMap { byId[$0] }.prefix(maximumResults).map { $0 }
        }
    }
#endif

/// The words a picture's search uses: model numbers and other words with digits first, then the
/// longest other words, then the system's labels; no common words, at most 12. Outside the Visual
/// Intelligence guard because the iOS Simulator's SDK has no Visual Intelligence framework (Xcode 27,
/// measured 2026-10-14), so this is the part the test suite can run.
nonisolated enum VisualSearchTerms {
    static func from(text: String, labels: [String]) -> [String] {
        let common: Set<String> = [
            "the", "and", "for", "with", "that", "this", "from", "are", "was", "not", "you", "your",
            "all", "any", "can", "may", "use", "only", "made", "into", "per", "www", "com",
        ]
        var seen = Set<String>()
        func cleaned(_ words: [Substring]) -> [String] {
            words.map { String($0).lowercased() }
                .filter { $0.count >= 3 && !common.contains($0) && seen.insert($0).inserted }
        }
        let words = cleaned(text.split { !$0.isLetter && !$0.isNumber && $0 != "-" })
        let withDigits = words.filter { $0.contains(where: \.isNumber) && $0.contains(where: \.isLetter) }
        let others = words.filter { !withDigits.contains($0) }.sorted { $0.count > $1.count }
        let labelWords = cleaned(labels.flatMap { $0.split { !$0.isLetter && !$0.isNumber } })
        return Array((withDigits + others + labelWords).prefix(12))
    }

    /// Whether a document's name holds one of the words as a whole word, its extension left out.
    /// "pdf" from a screenshot's "Download PDF" matches no "Lease.pdf", while "mx450" matches
    /// "MX450-service-manual.pdf" and "sn-77a1" matches "Notes on SN-77A1.txt".
    static func nameMatches(_ filename: String, terms: [String]) -> Bool {
        var stem = filename.lowercased()
        if let dot = stem.lastIndex(of: "."), stem.distance(from: dot, to: stem.endIndex) <= 6 {
            stem = String(stem[..<dot])
        }
        let hyphenated = stem.split { !$0.isLetter && !$0.isNumber && $0 != "-" }.map(String.init)
        let parts = stem.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let words = Set(hyphenated + parts)
        return terms.contains { words.contains($0) }
    }
}
