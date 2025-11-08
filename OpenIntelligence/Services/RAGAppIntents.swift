//
//  RAGAppIntents.swift
//  OpenIntelligence
//
//  App Intents for Siri and Shortcuts integration
//  Enables voice-based RAG queries and document management
//
//  Created by GitHub Copilot on 10/15/25.
//

import Foundation
import AppIntents
import SwiftUI

// MARK: - Query Documents Intent (Siri Integration)

/// Allows users to query their document library via Siri
/// Usage: "Hey Siri, ask my documents about quarterly revenue"
@available(iOS 16.0, *)
struct QueryDocumentsIntent: AppIntent {
    static var title: LocalizedStringResource = "Query Documents"
    static var description: IntentDescription = IntentDescription(
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
        print("\n🎙️ [Siri] Query Documents Intent invoked")
        print("   Question: \(question)")
        print("   Top K: \(topK)")
        
        // Create RAG service instance on main actor
        let ragService = await MainActor.run {
            RAGService()
        }
        
        // Check if documents are available
        let documentCount = await MainActor.run {
            ragService.documents.count
        }
        
        guard documentCount > 0 else {
            print("   ⚠️ No documents loaded")
            return .result(
                dialog: IntentDialog(stringLiteral: "You don't have any documents loaded yet. Add some documents first."),
                view: ErrorSnippetView(message: "No documents available")
            )
        }
        
        do {
            // Execute RAG query
            let config = InferenceConfig(
                maxTokens: 300,  // Shorter for Siri responses
                temperature: 0.7
            )
            
            let response = try await ragService.query(question, topK: topK, config: config)
            
            print("   ✅ Query complete")
            print("   Response length: \(response.generatedResponse.count) chars")
            print("   Chunks retrieved: \(response.retrievedChunks.count)")
            
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
            print("   ❌ Query failed: \(error.localizedDescription)")
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
    static var description: IntentDescription = IntentDescription(
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
    static var description: IntentDescription = IntentDescription(
        "Show all documents in your RAG library",
        categoryName: "Documents"
    )
    
    static var openAppWhenRun: Bool = false
    
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        print("\n🎙️ [Siri] List Documents Intent invoked")
        
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
                "Search my documents with \(.applicationName)"
            ],
            shortTitle: "Query Documents",
            systemImageName: "doc.text.magnifyingglass"
        )
        
        AppShortcut(
            intent: ListDocumentsIntent(),
            phrases: [
                "List my documents in \(.applicationName)",
                "Show my documents in \(.applicationName)",
                "What documents do I have in \(.applicationName)"
            ],
            shortTitle: "List Documents",
            systemImageName: "list.bullet.rectangle"
        )
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
