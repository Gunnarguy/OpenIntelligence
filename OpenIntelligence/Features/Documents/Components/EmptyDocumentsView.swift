//
//  EmptyDocumentsView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI

struct EmptyDocumentsView: View {
    let isImportingSamples: Bool
    let hasImportedSamples: Bool
    let isAtDocumentLimit: Bool
    let documentLimit: Int
    let statusMessage: String?
    let onImportSamples: () -> Void
    let onPickFiles: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Hero icon with gradient
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.accentColor.opacity(0.1),
                                Color.accentColor.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 50))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.accentColor, Color.accentColor.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("No Documents Yet")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Start with files that keep their structure")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            if isAtDocumentLimit {
                Text("You've reached the free workspace limit of \(documentLimit) documents. Remove a document or upgrade to keep importing content.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            VStack(spacing: 12) {
                Button(action: onPickFiles) {
                    Label("Add Your Documents", systemImage: "tray.and.arrow.down")
                }
                .buttonStyle(.borderedProminent)

                Button(action: onImportSamples) {
                    HStack {
                        if isImportingSamples {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(hasImportedSamples ? "Re-import Sample Workspace" : "Import Sample Workspace")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isImportingSamples)

                if let statusMessage, !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else if isAtDocumentLimit {
                    Text("Upgrade to unlock more slots or clear a few documents to try the curated workspace.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                } else {
                    Text("PDFs, DOCX/XLSX/PPTX, TXT/MD, CSV, images, and transcriptable media import cleanly. Legacy Office, iWork, XML, code-heavy exports, and dense scientific tables often need cleanup or conversion first.")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            }

            // Features
            VStack(alignment: .leading, spacing: 12) {
                DocumentFeatureRow(
                    icon: "doc.fill",
                    title: "Multiple Formats",
                    description: "PDF, Office XML, text, images, and transcripts"
                )

                DocumentFeatureRow(
                    icon: "bolt.fill",
                    title: "Fast Processing",
                    description: "Adaptive OCR, chunking, and local indexing"
                )

                DocumentFeatureRow(
                    icon: "exclamationmark.triangle.fill",
                    title: "Format Caveats",
                    description: "Legacy formats and unusual exports often need cleanup first"
                )
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct DocumentFeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

#Preview {
    EmptyDocumentsView(
        isImportingSamples: false,
        hasImportedSamples: false,
        isAtDocumentLimit: false,
        documentLimit: 25,
        statusMessage: nil,
        onImportSamples: {},
        onPickFiles: {}
    )
}
