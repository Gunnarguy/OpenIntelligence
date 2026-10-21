//
//  SearchPassagesIntent.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// Finds the passages that match a query and returns them, without asking the model for an answer.
///
/// "Search Library" generates an answer and shows a card; nothing comes back to the shortcut. This
/// returns the passages themselves, so a following step, or another app's model, can read them.
/// The search runs in the active library.
@available(iOS 26.0, macOS 26.0, *)
struct SearchPassagesIntent: AppIntent {
    static var title: LocalizedStringResource = "Find Passages"
    static var description: IntentDescription = .init(
        "Finds the passages in your active library that match a search, and returns them without writing an answer.",
        categoryName: "Documents",
        searchKeywords: ["search", "find", "passages", "excerpts", "lookup"]
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Search", description: "Words or a question to match")
    var query: String

    @Parameter(title: "Limit", description: "The most passages to return, at most 20", default: 5, inclusiveRange: (1, 20))
    var limit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Find passages matching \(\.$query)") {
            \.$limit
        }
    }

    /// The most passages one run hands back. The parameter's range stops at it in the editor, but a
    /// shortcut can pass a number from another step, so the run clamps it as well.
    static let maxPassages = 20

    /// A requested limit held to 1...`maxPassages`.
    static func clampedLimit(_ requested: Int) -> Int {
        min(max(requested, 1), maxPassages)
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[OIPassageEntity]> & ProvidesDialog {
        let wanted = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !wanted.isEmpty else {
            throw $query.needsValueError("What should I search for?")
        }
        let cap = Self.clampedLimit(self.limit)
        Log.info("[Shortcuts] Find Passages invoked (queryChars=\(wanted.count), limit=\(cap))", category: .pipeline)

        let engine = await MainActor.run { IntentSupport.engine() }
        let documentCount = await MainActor.run { engine.documents.count }
        guard documentCount > 0 else {
            throw OIIntentError("There are no documents in the active library yet.")
        }

        let chunks: [RetrievedChunk]
        do {
            chunks = try await engine.searchDocumentsRaw(query: wanted, topK: cap)
        } catch {
            throw OIIntentError("The search did not finish: \(error.localizedDescription)")
        }

        let passages = OIPassageEntity.handedOut(Array(chunks.prefix(cap)))
        let dialog: IntentDialog =
            passages.isEmpty
            ? "No passages matched."
            : "Found \(passages.count) passage\(passages.count == 1 ? "" : "s")."
        return .result(value: Array(passages), dialog: dialog)
    }
}
