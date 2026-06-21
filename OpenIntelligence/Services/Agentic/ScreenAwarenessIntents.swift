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
    static var title: LocalizedStringResource = "Ingest Document"
    static var description: IntentDescription = .init(
        "Adds a document or file directly to OpenIntelligence via Siri Screen Awareness.",
        categoryName: "Ingestion"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "File")
    var file: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("Add \(\.$file) to OpenIntelligence")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let fileURL = file.fileURL else {
            return .result(
                dialog: IntentDialog(stringLiteral: "I couldn't find a valid file payload."),
                view: ScreenAwarenessSnippetView(
                    title: "Failed",
                    message: "No valid file URL was provided.",
                    isSuccess: false
                )
            )
        }

        // Queue via BackgroundTaskService to handle large files gracefully
        let service = await MainActor.run { BackgroundTaskService.shared }
        await service.beginUserInitiatedBackgroundIngestion(url: fileURL)

        return .result(
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
    static var title: LocalizedStringResource = "Ingest Webpage"
    static var description: IntentDescription = .init(
        "Extracts and saves a webpage into OpenIntelligence.",
        categoryName: "Ingestion"
    )

    static var openAppWhenRun: Bool = false

    @Parameter(title: "URL")
    var url: URL

    static var parameterSummary: some ParameterSummary {
        Summary("Save \(\.$url) to OpenIntelligence")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        // Route URL background ingestion
        let service = await MainActor.run { BackgroundTaskService.shared }
        await service.beginUserInitiatedBackgroundIngestion(url: url)

        return .result(
            dialog: IntentDialog(stringLiteral: "I've started processing the webpage."),
            view: ScreenAwarenessSnippetView(
                title: "Ingestion Started",
                message: "Extracting webpage in the background.",
                isSuccess: true
            )
        )
    }
}
