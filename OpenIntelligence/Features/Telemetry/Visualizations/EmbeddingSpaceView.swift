//
//  EmbeddingSpaceView.swift
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

// MARK: - Embedding Space View

struct EmbeddingSpaceView: View {
    let chunkCount: Int
    let documentCount: Int
    let embeddingDimension: Int // Actual dimension from container

    @State private var projectionMethod: ProjectionMethod = .pca
    @State private var showingInfo = false

    enum ProjectionMethod: String, CaseIterable, Identifiable {
        case pca = "PCA"
        case tsne = "t-SNE"
        case umap = "UMAP"

        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            header
            projectionPicker
            EmbeddingSpaceRenderer(
                projectionMethod: projectionMethod,
                chunkCount: chunkCount,
                documentCount: documentCount
            )
            statsRow
        }
        .sheet(isPresented: $showingInfo) {
            EmbeddingInfoSheet()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("Embedding Space")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("\(chunkCount) chunks translated into a map—dots that sit close together discuss similar ideas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                showingInfo = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundStyle(DSColors.accent)
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    // Uses `embeddingDimension`, the value this view is already handed, rather than a
    // literal. The copy said "512-number vectors" unconditionally, and five providers ship
    // with four different dimensions: `AppleFMEmbeddingProvider` 1024, `NLEmbeddingProvider`
    // and `NLContextualEmbeddingProvider` 512, `CoreMLSentenceEmbeddingProvider` and
    // `CoreAISentenceEmbeddingProvider` 384. So it was right for a library embedded by
    // either NL provider and wrong for every MiniLM one. It was never a false claim, only a
    // hardcoded one, which is why this reads the real value rather than being "corrected"
    // to 384. `VisualizationsView.embeddingSection` has always passed the container's
    // `embeddingDim` in through this view's own initialiser.
    private var projectionPicker: some View {
        HStack {
            Picker("Projection", selection: $projectionMethod) {
                ForEach(ProjectionMethod.allCases) { method in
                    Text(method.rawValue).tag(method)
                }
            }
            .pickerStyle(.segmented)

            InfoButtonView(
                title: "Projection Method",
                explanation: "We flatten \(embeddingDimension)-number vectors into something you can see.\n\n• PCA: super fast overview of the biggest themes.\n• t-SNE: highlights tiny topic bubbles.\n• UMAP: balanced layout when your library mixes formats."
            )
        }
        .padding(.horizontal, DSSpacing.lg)
    }

    private var statsRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            EmbeddingLegendCard()

            HStack(spacing: DSSpacing.md) {
                StatCard(
                    icon: "cube.box",
                    label: "Chunks",
                    value: "\(chunkCount)",
                    color: DSColors.accent
                )

                StatCard(
                    icon: "doc.text",
                    label: "Documents",
                    value: "\(documentCount)",
                    color: .green
                )

                StatCard(
                    icon: "ruler",
                    label: "Dimensions",
                    value: "\(embeddingDimension)",
                    color: DSColors.accent
                )
            }
        }
        .padding(.horizontal, DSSpacing.lg)
    }
}

struct EmbeddingLegendCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(DSColors.accent)
                Text("How to read this map")
                    .font(.headline)
            }

            Text("Each dot is a document chunk. Neighbors share meaning, tone, or phrasing—spread apart points are unrelated topics.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                AxisRow(title: "X axis", detail: "Left ↔ Right shows the biggest difference our model detected (often topic vs. reference material).", color: .blue)
                AxisRow(title: "Y axis", detail: "Up ↕ Down captures the second strongest pattern, like narrative vs. tables.", color: .green)
                AxisRow(title: "Z axis", detail: "Depth adds nuance—tilt the scene with two fingers to reveal stacked subtopics.", color: .purple)
            }
        }
        .padding(DSSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.background)
        )
    }

    private struct AxisRow: View {
        let title: String
        let detail: String
        let color: Color

        var body: some View {
            HStack(alignment: .top, spacing: DSSpacing.sm) {
                Circle()
                    .fill(color.opacity(0.9))
                    .frame(width: 8, height: 8)
                    .padding(.top, DSSpacing.xs)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
