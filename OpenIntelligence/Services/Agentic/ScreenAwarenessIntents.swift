//
//  ScreenAwarenessIntents.swift
//  OpenIntelligence
//

import AppIntents
import Foundation
import SwiftUI

@available(iOS 26.0, macOS 26.0, *)
struct ScreenAwarenessSnippetView: View {
    let title: String
    let message: String
    let isSuccess: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundColor(isSuccess ? .green : .orange)
                Text(title)
                    .font(.headline)
            }
            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
    }
}

// MARK: - File Ingestion (Siri Screen Awareness)

@available(iOS 26.0, macOS 26.0, *)
struct IngestDocumentIntent: AppIntent {
    static var title: LocalizedStringResource = "Add a File"
    static var description: IntentDescription = .init(
        "Adds a file to your active library.",
        categoryName: "Ingestion"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "File")
    var file: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$file) to OpenIntelligence")
    }

    /// Returns the name the file was stored under. The file is copied into the imported-documents
    /// folder before it is queued: through 5.6 the queue was given the action's own copy, which the
    /// system can remove when the action ends.
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let stored: URL
        do {
            if let fileURL = file.fileURL {
                stored = try IntentSupport.copyIntoImports(fileURL, preferredFileName: file.filename)
            } else {
                stored = try IntentSupport.store(file.data, preferredFileName: file.filename)
            }
        } catch {
            throw OIIntentError("The file could not be added: \(error.localizedDescription)")
        }

        // Queue via RAGService to handle large files gracefully on the MainActor
        await MainActor.run {
            _ = IntentSupport.engine().enqueueDocuments([stored])
        }

        return .result(
            value: stored.lastPathComponent,
            dialog: IntentDialog(stringLiteral: "I've started ingesting your document into OpenIntelligence."),
            view: ScreenAwarenessSnippetView(
                title: "Ingestion Started",
                message: "Processing file in the background.",
                isSuccess: true
            )
        )
    }
}

// MARK: - URL Ingestion (Siri Screen Awareness)

@available(iOS 26.0, macOS 26.0, *)
struct IngestURLIntent: AppIntent {
    static var title: LocalizedStringResource = "Save a Web Page"
    static var description: IntentDescription = .init(
        "Downloads a web page and adds its text to your active library.",
        categoryName: "Ingestion"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "URL")
    var url: URL

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$url) to OpenIntelligence")
    }

    /// Downloads the page, stores its text as a Markdown file and queues that file. Returns the
    /// file's name. Through 5.6 this queued the web address itself as if it were a file on disk,
    /// and nothing was downloaded.
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        let stored: URL
        let title: String
        do {
            let fetched = try await WebPageFetchService.fetch(url)
            stored = try IntentSupport.store(fetched.data, preferredFileName: fetched.fileName)
            title = fetched.title ?? stored.lastPathComponent
        } catch {
            Log.warning("[Shortcuts] Ingest Webpage failed: \(error.localizedDescription)", category: .ingestion)
            throw OIIntentError("The page could not be saved. \(error.localizedDescription)")
        }

        await MainActor.run {
            _ = IntentSupport.engine().enqueueDocuments([stored])
        }

        return .result(
            value: stored.lastPathComponent,
            dialog: IntentDialog(stringLiteral: "I saved the page and started importing it."),
            view: ScreenAwarenessSnippetView(
                title: "Page Saved",
                message: "\(title) is being imported.",
                isSuccess: true
            )
        )
    }
}
