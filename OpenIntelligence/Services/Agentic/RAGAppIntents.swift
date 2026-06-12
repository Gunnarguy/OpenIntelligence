//
//  RAGAppIntents.swift
//  OpenIntelligence
//
//  App Intents for Siri and Shortcuts integration
//  Enables voice-based RAG queries and document management
//
//  Created by GitHub Copilot on 10/15/25.
//

import AppIntents
import Foundation
import SwiftUI

private struct DocumentImportStatusSnapshot: Sendable {
    let activeCount: Int
    let currentFilename: String
    let currentStage: String
    let queuedFilenames: [String]
    let spokenResponse: String
}

// MARK: - Query Documents Intent (Siri Integration)

/// Allows users to query their document library via Siri
/// Usage: "Hey Siri, ask my documents about quarterly revenue"
@available(iOS 16.0, *)
struct QueryDocumentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Query Documents"
    static var description: IntentDescription = .init(
        "Ask a question about your documents using RAG",
        categoryName: "Documents",
        searchKeywords: ["search", "query", "ask", "document", "rag"]
    )

    static var openAppWhenRun: Bool = false // Can run in background

    @Parameter(title: "Question", description: "What would you like to know?")
    var question: String

    @Parameter(
        title: "Number of chunks",
        description: "How many document chunks to retrieve",
        default: 3
    )
    var topK: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Query documents with \(\.$question)") {
            \.$topK
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Avoid logging user content; keep logs metadata-only.
        Log.info("[Siri] Query Documents intent invoked (questionChars=\(question.count), topK=\(topK))", category: .pipeline)

        // Create RAG service instance on main actor
        let ragService = await MainActor.run {
            RAGService()
        }

        // Check if documents are available
        let documentCount = await MainActor.run {
            ragService.documents.count
        }

        guard documentCount > 0 else {
            Log.warning("[Siri] Query blocked: no documents loaded", category: .pipeline)
            return .result(
                dialog: IntentDialog(stringLiteral: "You don't have any documents loaded yet. Add some documents first."),
                view: ErrorSnippetView(message: "No documents available")
            )
        }

        do {
            // Execute RAG query
            let config = InferenceConfig(
                maxTokens: 300, // Shorter for Siri responses
                temperature: 0.7
            )

            let response = try await ragService.query(question, topK: topK, config: config)

            Log.info("[Siri] Query complete (answerChars=\(response.generatedResponse.count), chunks=\(response.retrievedChunks.count))", category: .pipeline)

            // Format response for Siri
            let spokenResponse = formatForSiri(response.generatedResponse)

            // Get final document count for view
            let finalDocCount = await MainActor.run {
                ragService.documents.count
            }

            return .result(
                dialog: IntentDialog(stringLiteral: spokenResponse),
                view: RAGResponseSnippetView(
                    question: question,
                    answer: response.generatedResponse,
                    chunkCount: response.retrievedChunks.count,
                    documentCount: finalDocCount
                )
            )

        } catch {
            Log.error("[Siri] Query failed: \(error.localizedDescription)", category: .pipeline)
            return .result(
                dialog: IntentDialog(stringLiteral: "Sorry, I couldn't answer that question. \(error.localizedDescription)"),
                view: ErrorSnippetView(message: error.localizedDescription)
            )
        }
    }

    /// Format response for Siri speech (remove markdown, shorten if needed)
    private func formatForSiri(_ text: String) -> String {
        var formatted = text

        // Remove markdown
        formatted = formatted.replacingOccurrences(of: "**", with: "")
        formatted = formatted.replacingOccurrences(of: "*", with: "")
        formatted = formatted.replacingOccurrences(of: "#", with: "")

        // Limit length for speech (Siri works best with shorter responses)
        if formatted.count > 500 {
            let truncated = String(formatted.prefix(500))
            formatted = truncated + "... I've shown you the full answer on screen."
        }

        return formatted
    }
}

// MARK: - Add Document Intent

/// Allows users to add documents via Siri
/// Usage: "Hey Siri, add a document to my RAG library"
@available(iOS 16.0, *)
struct AddDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Document"
    static var description: IntentDescription = .init(
        "Add a document to your RAG knowledge base",
        categoryName: "Documents"
    )

    static var openAppWhenRun: Bool = true // Need UI for file picker

    func perform() async throws -> some IntentResult & ProvidesDialog {
        // This would open the app to the document picker
        // The actual adding happens in the UI

        return .result(
            dialog: IntentDialog(stringLiteral: "Opening RAG app to add a document...")
        )
    }
}

// MARK: - List Documents Intent

/// Lists all documents in the RAG library
/// Usage: "Hey Siri, what documents do I have in RAG?"
@available(iOS 16.0, *)
struct ListDocumentsIntent: AppIntent {
    static var title: LocalizedStringResource = "List Documents"
    static var description: IntentDescription = .init(
        "Show all documents in your RAG library",
        categoryName: "Documents"
    )

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        Log.info("[Siri] List Documents intent invoked", category: .pipeline)

        let ragService = await MainActor.run {
            RAGService()
        }

        let documents = await MainActor.run {
            ragService.documents
        }

        guard !documents.isEmpty else {
            return .result(
                dialog: IntentDialog(stringLiteral: "You don't have any documents loaded yet."),
                view: ErrorSnippetView(message: "No documents")
            )
        }

        // Format document list for Siri
        let documentNames = documents.map { $0.filename }.joined(separator: ", ")
        let spokenResponse = "You have \(documents.count) document\(documents.count == 1 ? "" : "s"): \(documentNames)"

        return .result(
            dialog: IntentDialog(stringLiteral: spokenResponse),
            view: DocumentListSnippetView(documents: documents)
        )
    }
}

// MARK: - Document Import Status Intent

/// Reports the status of any pending or active document imports.
@available(iOS 16.0, *)
struct DocumentImportStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Document Import Status"
    static var description: IntentDescription = .init(
        "See whether document imports are queued or running",
        categoryName: "Documents",
        searchKeywords: ["import", "ingestion", "status", "queue", "processing"]
    )

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        Log.info("[Siri] Document Import Status intent invoked", category: .ingestion)

        let ragService = await MainActor.run {
            RAGService()
        }
        await ragService.restoreIngestionQueueIfNeeded()

        let snapshot = await MainActor.run { () -> DocumentImportStatusSnapshot? in
            let pendingItems = ragService.ingestionItems.filter { !$0.stage.isTerminal }
            guard !pendingItems.isEmpty else { return nil }

            let activeItem = pendingItems.first(where: { $0.stage != .queued }) ?? pendingItems[0]
            let spokenResponse: String
            if pendingItems.count == 1 {
                spokenResponse = "One document import is \(activeItem.stage.displayName.lowercased()): \(activeItem.filename)."
            } else {
                spokenResponse = "\(pendingItems.count) document imports are pending. Current stage: \(activeItem.stage.displayName.lowercased()) for \(activeItem.filename)."
            }

            return DocumentImportStatusSnapshot(
                activeCount: pendingItems.count,
                currentFilename: activeItem.filename,
                currentStage: activeItem.stage.displayName,
                queuedFilenames: pendingItems.map(\.filename),
                spokenResponse: spokenResponse
            )
        }

        guard let snapshot else {
            return .result(
                dialog: IntentDialog(stringLiteral: "No document imports are pending right now."),
                view: ErrorSnippetView(message: "No pending imports")
            )
        }

        return .result(
            dialog: IntentDialog(stringLiteral: snapshot.spokenResponse),
            view: DocumentImportStatusSnippetView(
                activeCount: snapshot.activeCount,
                currentFilename: snapshot.currentFilename,
                currentStage: snapshot.currentStage,
                queuedFilenames: snapshot.queuedFilenames
            )
        )
    }
}

// MARK: - App Shortcuts Provider

/// Provides suggested shortcuts for the Shortcuts app
@available(iOS 16.0, *)
struct RAGAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QueryDocumentsIntent(),
            phrases: [
                "Query my documents in \(.applicationName)",
                "Ask \(.applicationName) about my documents",
                "Search my documents with \(.applicationName)",
            ],
            shortTitle: "Query Documents",
            systemImageName: "doc.text.magnifyingglass"
        )

        AppShortcut(
            intent: ListDocumentsIntent(),
            phrases: [
                "List my documents in \(.applicationName)",
                "Show my documents in \(.applicationName)",
                "What documents do I have in \(.applicationName)",
            ],
            shortTitle: "List Documents",
            systemImageName: "list.bullet.rectangle"
        )

        AppShortcut(
            intent: DocumentImportStatusIntent(),
            phrases: [
                "Check document import status in \(.applicationName)",
                "Show import queue in \(.applicationName)",
                "Is \(.applicationName) still importing documents"
            ],
            shortTitle: "Import Status",
            systemImageName: "arrow.down.doc.fill"
        )

        AppShortcut(
            intent: AskDocumentIntent(),
            phrases: [
                "Ask \(.applicationName) about \(\.$document)",
                "Query \(\.$document) in \(.applicationName)"
            ],
            shortTitle: "Ask About Document",
            systemImageName: "doc.text.fill"
        )

        AppShortcut(
            intent: SummarizeDocumentIntent(),
            phrases: [
                "Summarize \(\.$document) in \(.applicationName)",
                "Show summary of \(\.$document) in \(.applicationName)"
            ],
            shortTitle: "Summarize Document",
            systemImageName: "text.justify.left"
        )

        AppShortcut(
            intent: CompareDocumentsIntent(),
            phrases: [
                "Compare documents in \(.applicationName)",
                "Show comparison of documents in \(.applicationName)"
            ],
            shortTitle: "Compare Documents",
            systemImageName: "arrow.2.squarepath"
        )

        AppShortcut(
            intent: SearchLibraryIntent(),
            phrases: [
                "Search \(\.$library) in \(.applicationName)",
                "Query \(\.$library) in \(.applicationName)"
            ],
            shortTitle: "Search Library",
            systemImageName: "magnifyingglass.circle.fill"
        )

        if #available(iOS 26.0, *) {
            AppShortcut(
                intent: AnalyzeImageIntent(),
                phrases: [
                    "Analyze this image with \(.applicationName)",
                    "Read text from photo in \(.applicationName)",
                    "Extract text with \(.applicationName)"
                ],
                shortTitle: "Analyze Image",
                systemImageName: "eye.fill"
            )

            AppShortcut(
                intent: IngestFromCameraIntent(),
                phrases: [
                    "Scan a document with \(.applicationName)",
                    "Capture document for \(.applicationName)"
                ],
                shortTitle: "Scan Document",
                systemImageName: "camera.fill"
            )

            AppShortcut(
                intent: VisualSearchIntent(),
                phrases: [
                    "Search documents with this photo in \(.applicationName)",
                    "Visual search in \(.applicationName)"
                ],
                shortTitle: "Visual Search",
                systemImageName: "magnifyingglass"
            )
        }
    }
}

// MARK: - Get Embedding Provider Intent

/// Tells user which embedding provider is active
/// Usage: "Hey Siri, what embedding model is RAG using?"
@available(iOS 16.0, *)
struct GetEmbeddingProviderIntent: AppIntent {
    static var title: LocalizedStringResource = "Check Embedding Provider"
    static var description: IntentDescription = .init(
        "See which embedding model is powering your searches",
        categoryName: "Settings",
        searchKeywords: ["embedding", "provider", "accuracy", "contextual", "model"]
    )

    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        Log.info("[Siri] Get Embedding Provider intent invoked", category: .embedding)

        // Read from container settings
        let containerService = await MainActor.run { ContainerService() }
        let activeContainer = await MainActor.run { containerService.activeContainer }
        let providerId = activeContainer?.embeddingProviderId ?? "coreml_sentence_embedding"

        let (name, description, isHighAccuracy) = describeProvider(providerId)

        let spokenResponse = isHighAccuracy
            ? "You're using \(name), which provides up to 25% better accuracy for complex documents."
            : "You're using \(name), which is fast and efficient for most documents."

        return .result(
            dialog: IntentDialog(stringLiteral: spokenResponse),
            view: EmbeddingProviderSnippetView(
                providerName: name,
                description: description,
                isHighAccuracy: isHighAccuracy
            )
        )
    }

    private func describeProvider(_ id: String) -> (name: String, description: String, isHighAccuracy: Bool) {
        switch id {
        case "nl_contextual_embedding":
            return ("Contextual Embedding", "BERT-style model with 15-25% accuracy boost", true)
        case "nl_embedding":
            return ("Standard NL Embedding", "Fast and efficient word2vec-style model", false)
        case "coreml_sentence_embedding":
            return ("CoreML Sentence", "Sentence-level semantic embedding", false)
        case "apple_fm_embed":
            return ("Apple Foundation Model", "Apple Intelligence powered embedding", true)
        default:
            return ("Unknown", id, false)
        }
    }
}

// MARK: - Embedding Provider Snippet View

@available(iOS 16.0, *)
struct EmbeddingProviderSnippetView: View {
    let providerName: String
    let description: String
    let isHighAccuracy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: isHighAccuracy ? "sparkles" : "bolt.badge.a")
                    .font(.system(size: 32))
                    .foregroundStyle(isHighAccuracy ? .purple : .blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Embedding Model")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(providerName)
                        .font(.headline)
                }
            }

            Text(description)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if isHighAccuracy {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("High accuracy mode active")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }
        }
        .padding()
    }
}

// MARK: - Snippet Views (for Siri and Shortcuts UI)

@available(iOS 16.0, *)
struct RAGResponseSnippetView: View {
    let question: String
    let answer: String
    let chunkCount: Int
    let documentCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Question
            VStack(alignment: .leading, spacing: 4) {
                Text("Question")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(question)
                    .font(.headline)
            }

            Divider()

            // Answer
            VStack(alignment: .leading, spacing: 4) {
                Text("Answer")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(answer)
                    .font(.body)
            }

            Divider()

            // Metadata
            HStack {
                Label("\(chunkCount) chunks", systemImage: "doc.text")
                Spacer()
                Label("\(documentCount) docs", systemImage: "folder")
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
    }
}

@available(iOS 16.0, *)
struct DocumentListSnippetView: View {
    let documents: [Document]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your Documents")
                .font(.headline)

            ForEach(documents.prefix(10)) { document in
                HStack {
                    Image(systemName: "doc.fill")
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.filename)
                            .font(.body)
                        Text("\(document.totalChunks) chunks")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if documents.count > 10 {
                Text("... and \(documents.count - 10) more")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
}

@available(iOS 16.0, *)
struct DocumentImportStatusSnippetView: View {
    let activeCount: Int
    let currentFilename: String
    let currentStage: String
    let queuedFilenames: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Document Import")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(activeCount) pending")
                        .font(.headline)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(currentFilename)
                    .font(.body)
                Text(currentStage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if queuedFilenames.count > 1 {
                Text(queuedFilenames.dropFirst().prefix(2).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }
}

@available(iOS 16.0, *)
struct ErrorSnippetView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 40))
                .foregroundColor(.orange)

            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// MARK: - Entity-Native App Intents

@available(iOS 16.0, *)
struct AskDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask About a Document"
    static var description: IntentDescription = .init(
        "Ask a question about a specific document",
        categoryName: "Documents"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Document")
    var document: OIDocumentEntity

    @Parameter(title: "Question")
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask \(\.$document) about \(\.$question)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let ragService = await MainActor.run { RAGService() }
        do {
            let config = InferenceConfig(maxTokens: 300, temperature: 0.7)
            let prompt = "Using ONLY the document '\(document.filename)', answer: \(question)"
            let response = try await ragService.query(prompt, config: config)
            let spokenResponse = response.generatedResponse
            
            return .result(
                dialog: IntentDialog(stringLiteral: spokenResponse),
                view: RAGResponseSnippetView(
                    question: question,
                    answer: response.generatedResponse,
                    chunkCount: response.retrievedChunks.count,
                    documentCount: 1
                )
            )
        } catch {
            return .result(
                dialog: IntentDialog(stringLiteral: "Failed to query the document: \(error.localizedDescription)"),
                view: ErrorSnippetView(message: error.localizedDescription)
            )
        }
    }
}

@available(iOS 16.0, *)
struct SummarizeDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Summarize Document"
    static var description: IntentDescription = .init(
        "Generate a summary for a specific document",
        categoryName: "Documents"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Document")
    var document: OIDocumentEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize \(\.$document)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let ragService = await MainActor.run { RAGService() }
        do {
            let config = InferenceConfig(maxTokens: 400, temperature: 0.5)
            let prompt = "Provide a concise summary of the main points and key information in the document '\(document.filename)'."
            let response = try await ragService.query(prompt, config: config)
            let spokenResponse = "Here is a summary of \(document.filename): \(response.generatedResponse)"
            
            return .result(
                dialog: IntentDialog(stringLiteral: spokenResponse),
                view: RAGResponseSnippetView(
                    question: "Summarize \(document.filename)",
                    answer: response.generatedResponse,
                    chunkCount: response.retrievedChunks.count,
                    documentCount: 1
                )
            )
        } catch {
            return .result(
                dialog: IntentDialog(stringLiteral: "Failed to summarize the document: \(error.localizedDescription)"),
                view: ErrorSnippetView(message: error.localizedDescription)
            )
        }
    }
}

@available(iOS 16.0, *)
struct CompareDocumentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Compare Documents"
    static var description: IntentDescription = .init(
        "Compare two documents on a specific topic",
        categoryName: "Documents"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "First Document")
    var document1: OIDocumentEntity

    @Parameter(title: "Second Document")
    var document2: OIDocumentEntity

    @Parameter(title: "Topic")
    var topic: String

    static var parameterSummary: some ParameterSummary {
        Summary("Compare \(\.$document1) and \(\.$document2) on \(\.$topic)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let ragService = await MainActor.run { RAGService() }
        do {
            let config = InferenceConfig(maxTokens: 400, temperature: 0.6)
            let prompt = "Compare what is stated in '\(document1.filename)' versus what is stated in '\(document2.filename)' on the topic: \(topic)."
            let response = try await ragService.query(prompt, config: config)
            
            return .result(
                dialog: IntentDialog(stringLiteral: response.generatedResponse),
                view: RAGResponseSnippetView(
                    question: "Comparison of \(document1.filename) and \(document2.filename) on \(topic)",
                    answer: response.generatedResponse,
                    chunkCount: response.retrievedChunks.count,
                    documentCount: 2
                )
            )
        } catch {
            return .result(
                dialog: IntentDialog(stringLiteral: "Failed to compare the documents: \(error.localizedDescription)"),
                view: ErrorSnippetView(message: error.localizedDescription)
            )
        }
    }
}

@available(iOS 16.0, *)
struct SearchLibraryIntent: AppIntent {
    static var title: LocalizedStringResource = "Search Library"
    static var description: IntentDescription = .init(
        "Search within a specific document library",
        categoryName: "Documents"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "Library")
    var library: OILibraryEntity

    @Parameter(title: "Query")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Search \(\.$library) for \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let ragService = await MainActor.run { RAGService() }
        do {
            let config = InferenceConfig(maxTokens: 300, temperature: 0.7)
            let response = try await ragService.query(query, config: config, containerId: library.id)
            
            return .result(
                dialog: IntentDialog(stringLiteral: response.generatedResponse),
                view: RAGResponseSnippetView(
                    question: query,
                    answer: response.generatedResponse,
                    chunkCount: response.retrievedChunks.count,
                    documentCount: library.totalDocuments
                )
            )
        } catch {
            return .result(
                dialog: IntentDialog(stringLiteral: "Failed to search the library: \(error.localizedDescription)"),
                view: ErrorSnippetView(message: error.localizedDescription)
            )
        }
    }
}
