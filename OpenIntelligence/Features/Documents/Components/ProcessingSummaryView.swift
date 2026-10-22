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
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.xl) {
                    // Success header
                    VStack(spacing: DSSpacing.md) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.green)

                        Text("Document Processed!")
                            .font(.title2.weight(.bold))

                        Text(summary.filename)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, DSSpacing.lg)

                    // File Info Section
                    InfoSection(title: "File Information", icon: "doc.fill", color: .accentColor) {
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
                    InfoSection(title: "Content Statistics", icon: "text.alignleft", color: .accentColor) {
                        DetailInfoRow(label: "Characters", value: String(format: "%,d", summary.totalChars))
                        DetailInfoRow(label: "Words", value: String(format: "%,d", summary.totalWords))
                        DetailInfoRow(label: "Chunks Created", value: "\(summary.chunksCreated)")
                        DetailInfoRow(label: "Avg Chunk Size", value: "\(summary.chunkStats.avgChars) chars")
                        DetailInfoRow(label: "Size Range", value: "\(summary.chunkStats.minChars) - \(summary.chunkStats.maxChars) chars")
                        HStack(spacing: DSSpacing.xs) {
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Semantic boundary detection")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Embedding Model Section
                    InfoSection(title: "Embedding Model", icon: summary.isHighAccuracyProvider ? "sparkles" : "brain.head.profile", color: .accentColor) {
                        DetailInfoRow(label: "Provider", value: summary.embeddingProviderDisplayName)
                        if summary.isHighAccuracyProvider {
                            HStack {
                                Text("Quality")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Label("High Accuracy", systemImage: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        if let dimensions = summary.embeddingDimensions {
                            DetailInfoRow(label: "Dimensions", value: "\(dimensions)")
                        }
                        HStack(spacing: DSSpacing.xs) {
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(summary.embeddingRunsOn)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    // Performance Section
                    InfoSection(title: "Performance Metrics", icon: "speedometer", color: .accentColor) {
                        DetailInfoRow(label: "Extraction Time", value: String(format: "%.2f s", summary.extractionTime))
                        DetailInfoRow(label: "Chunking Time", value: String(format: "%.3f s", summary.chunkingTime))
                        DetailInfoRow(label: "Embedding Time", value: String(format: "%.2f s", summary.embeddingTime))
                        DetailInfoRow(label: "Avg per Chunk", value: String(format: "%.0f ms", (summary.embeddingTime / Double(summary.chunksCreated)) * 1000))
                        Divider()
                        DetailInfoRow(label: "Total Time", value: String(format: "%.2f s", summary.totalTime), highlight: true)
                        HStack(spacing: DSSpacing.xs) {
                            Image(systemName: "bolt.horizontal.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("Accelerate vDSP • Device-optimized batches")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(DSSpacing.lg)
            }
            .background(DSColors.background.ignoresSafeArea())
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
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.headline)
            }

            VStack(spacing: DSSpacing.sm) {
                content
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DSSpacing.lg)
        .background(DSColors.surface, in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
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
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(highlight ? .bold : .regular)
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .font(highlight ? .body : .subheadline)
    }
}

#Preview {
    ProcessingSummaryView(summary: ProcessingSummary(
        filename: "Report.pdf",
        fileSize: "2.4 MB",
        documentType: .pdf,
        pageCount: 15,
        ocrPagesUsed: 3,
        totalChars: 45000,
        totalWords: 8500,
        chunksCreated: 42,
        extractionTime: 1.2,
        chunkingTime: 0.3,
        embeddingTime: 0.8,
        totalTime: 2.3,
        chunkStats: ProcessingSummary.ChunkStatistics(avgChars: 1800, minChars: 500, maxChars: 3100),
        embeddingProviderId: "coreml_sentence_embedding"
    ))
}
