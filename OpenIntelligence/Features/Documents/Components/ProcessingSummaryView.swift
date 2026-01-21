//
//  ProcessingSummaryView.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/9/25.
//

import SwiftUI

struct ProcessingSummaryView: View {
    let summary: ProcessingSummary
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Success header
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("Document Processed!")
                            .font(.title2)
                            .fontWeight(.bold)

                        Text(summary.filename)
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)

                    // File Info Section
                    InfoSection(title: "File Information", icon: "doc.fill", color: .blue) {
                        DetailInfoRow(label: "File Size", value: summary.fileSize)
                        DetailInfoRow(label: "Type", value: summary.documentType.rawValue.capitalized)
                        if let pageCount = summary.pageCount {
                            DetailInfoRow(label: "Pages", value: "\(pageCount)")
                        }
                        if let ocrPages = summary.ocrPagesUsed {
                            DetailInfoRow(label: "OCR Used", value: "\(ocrPages) pages")
                        }
                    }

                    // Content Statistics Section
                    InfoSection(title: "Content Statistics", icon: "text.alignleft", color: .green) {
                        DetailInfoRow(label: "Characters", value: String(format: "%,d", summary.totalChars))
                        DetailInfoRow(label: "Words", value: String(format: "%,d", summary.totalWords))
                        DetailInfoRow(label: "Chunks Created", value: "\(summary.chunksCreated)")
                        DetailInfoRow(label: "Avg Chunk Size", value: "\(summary.chunkStats.avgChars) chars")
                        DetailInfoRow(label: "Size Range", value: "\(summary.chunkStats.minChars) - \(summary.chunkStats.maxChars) chars")
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.caption)
                                .foregroundColor(.cyan)
                            Text("Semantic boundary detection")
                                .font(.caption)
                                .foregroundColor(.cyan)
                        }
                    }

                    // Embedding Model Section
                    InfoSection(title: "Embedding Model", icon: summary.isHighAccuracyProvider ? "sparkles" : "brain.head.profile", color: summary.isHighAccuracyProvider ? .purple : .indigo) {
                        DetailInfoRow(label: "Provider", value: summary.embeddingProviderDisplayName)
                        if summary.isHighAccuracyProvider {
                            HStack {
                                Text("Quality")
                                    .foregroundColor(.secondary)
                                Spacer()
                                Label("High Accuracy", systemImage: "star.fill")
                                    .font(.caption)
                                    .foregroundColor(.purple)
                            }
                        }
                        DetailInfoRow(label: "Dimensions", value: "512")
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.caption)
                                .foregroundColor(.cyan)
                            Text("Neural Engine accelerated")
                                .font(.caption)
                                .foregroundColor(.cyan)
                        }
                    }

                    // Performance Section
                    InfoSection(title: "Performance Metrics", icon: "speedometer", color: .orange) {
                        DetailInfoRow(label: "Extraction Time", value: String(format: "%.2f s", summary.extractionTime))
                        DetailInfoRow(label: "Chunking Time", value: String(format: "%.3f s", summary.chunkingTime))
                        DetailInfoRow(label: "Embedding Time", value: String(format: "%.2f s", summary.embeddingTime))
                        DetailInfoRow(label: "Avg per Chunk", value: String(format: "%.0f ms", (summary.embeddingTime / Double(summary.chunksCreated)) * 1000))
                        Divider()
                        DetailInfoRow(label: "Total Time", value: String(format: "%.2f s", summary.totalTime), highlight: true)
                        HStack(spacing: 4) {
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.caption)
                                .foregroundColor(.cyan)
                            Text("Accelerate vDSP • Device-optimized batches")
                                .font(.caption)
                                .foregroundColor(.cyan)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Processing Complete")
            .iOSNavigationBarInline()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

extension View {
    @ViewBuilder func iOSNavigationBarInline() -> some View {
        #if os(iOS)
            navigationBarTitleDisplayMode(.inline)
        #else
            self
        #endif
    }
}

struct InfoSection<Content: View>: View {
    let title: String
    let icon: String
    let color: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(.headline)
            }

            VStack(spacing: 8) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(DSColors.surface)
        .cornerRadius(12)
    }
}

// MARK: - Simple Info Row for Document Details

struct DetailInfoRow: View {
    let label: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(highlight ? .bold : .regular)
                .foregroundColor(highlight ? .primary : .primary)
        }
        .font(highlight ? .body : .subheadline)
    }
}
