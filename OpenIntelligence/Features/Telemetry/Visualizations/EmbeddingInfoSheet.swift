//
//  EmbeddingInfoSheet.swift
//  OpenIntelligence
//
//  Moved from VisualizationsView.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import Charts
import Foundation
import SwiftUI
#if canImport(UIKit)
    import UIKit
#endif

// MARK: - Info Sheet

struct EmbeddingInfoSheet: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject private var settings: SettingsStore

    /// Human-readable name for the active embedding method
    private var embeddingMethodName: String {
        switch settings.defaultEmbeddingProvider {
        case "coreml_sentence_embedding":
            return "Neural Engine Embeddings"
        case "coreai_sentence_embedding":
            return "Core AI Embeddings"
        case "nl_contextual_embedding":
            return "NLContextualEmbedding"
        case "nl_embedding":
            return "NLEmbedding (Legacy)"
        case "apple_fm_embed":
            return "Apple Foundation Model"
        default:
            return "Neural Engine Embeddings"
        }
    }

    /// Description of the current embedding method
    private var embeddingMethodDescription: String {
        switch settings.defaultEmbeddingProvider {
        case "coreml_sentence_embedding":
            return "all-MiniLM-L6-v2 sentence-transformer via Core ML. Mean-pooled 384D vectors with Neural Engine acceleration for semantic similarity."
        case "coreai_sentence_embedding":
            return "all-MiniLM-L6-v2 sentence-transformer via Core AI. Mean-pooled 384D vectors computed on the GPU for semantic similarity."
        case "nl_contextual_embedding":
            return "NLContextualEmbedding (BERT-based) produces 512D context-aware vectors. 'Bank' near 'river' ≠ 'bank' near 'money'."
        case "nl_embedding":
            return "NLEmbedding word vectors (512D) averaged per chunk. Fast but loses word order and context nuance."
        case "apple_fm_embed":
            return "Apple Foundation Model embeddings (1024D) for state-of-the-art semantic understanding via Private Cloud Compute."
        default:
            return "all-MiniLM-L6-v2 sentence-transformer via Core ML. Mean-pooled 384D vectors with Neural Engine acceleration for semantic similarity."
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    VisualizationInfoSection(title: "What are Embeddings?") {
                        HStack(spacing: DSSpacing.sm) {
                            Image(systemName: "brain.head.profile")
                                .foregroundStyle(DSColors.accent)
                            Text("Think of them as GPS pins for sentences—chunks that mean the same thing land near each other even if they use different words.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VisualizationInfoSection(title: "Current Method: \(embeddingMethodName)") {
                        HStack(spacing: DSSpacing.sm) {
                            Image(systemName: "cpu.fill")
                                .foregroundStyle(.orange)
                            Text(embeddingMethodDescription)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VisualizationInfoSection(title: "Projection Methods") {
                        HStack(spacing: DSSpacing.sm) {
                            Image(systemName: "chart.xyaxis.line")
                                .foregroundStyle(.green)
                            Text("PCA, t-SNE, and UMAP flatten the embedding fingerprint into a 3D view so you can literally see topic islands and overlaps.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VisualizationInfoSection(title: "Future: Embedding Atlas") {
                        HStack(spacing: DSSpacing.sm) {
                            Image(systemName: "sparkles")
                                .foregroundStyle(.orange)
                            Text("Apple's Embedding Atlas will add pinch-to-explore controls and shareable scenes.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(DSSpacing.lg)
            }
            .navigationTitle("Embedding Space")
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

struct VisualizationInfoSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DSColors.accent)

            content()
        }
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.accent.opacity(0.1))
        )
    }
}
