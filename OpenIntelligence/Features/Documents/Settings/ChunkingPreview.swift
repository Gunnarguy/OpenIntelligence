//
//  ChunkingPreview.swift
//  OpenIntelligence
//
//  Moved from ContainerSettingsSheet+Sections.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import NaturalLanguage
import SwiftUI

// MARK: - Chunking Preview Visualization

struct ChunkingPreview: View {
    let targetWords: Int
    let overlap: Int

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text("Chunk Layout Preview")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                // Semantic chunking indicator
                HStack(spacing: DSSpacing.xs) {
                    Image(systemName: "brain")
                        .font(.caption2)
                    Text("Semantic")
                        .font(.caption2.weight(.medium))
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Capsule())
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let chunkWidth = min(width * 0.35, CGFloat(targetWords) / 600.0 * width * 0.7)
                let overlapWidth = min(chunkWidth * 0.4, CGFloat(overlap) / CGFloat(targetWords) * chunkWidth)

                HStack(spacing: -overlapWidth) {
                    ForEach(0 ..< 3, id: \.self) { index in
                        VStack(spacing: DSSpacing.xxs) {
                            RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous)
                                .fill(chunkColor(for: index))
                                .frame(width: chunkWidth, height: 20)
                                .overlay(
                                    Text("Chunk \(index + 1)")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                )
                            // Section snap indicator
                            if index == 0 {
                                HStack(spacing: DSSpacing.xxs) {
                                    Image(systemName: "arrow.turn.right.down")
                                        .scaledFont(size: 6)
                                    Text("Section")
                                        .scaledFont(size: 7)
                                }
                                .foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                }
            }
            .frame(height: 36)

            // Stats row
            HStack(spacing: DSSpacing.md) {
                Label("\(targetWords)w target", systemImage: "text.alignleft")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if overlap > 0 {
                    Label("\(overlap)w overlap", systemImage: "arrow.left.arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Overlap percentage
                let overlapPct = targetWords > 0 ? Int(Double(overlap) / Double(targetWords) * 100) : 0
                Text("\(overlapPct)% context")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Color.accentColor)
            }

            // Estimated chunks with semantic features
            let estimatedChunks = max(1, 2000 / max(1, targetWords - overlap))

            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text("A 2,000-word document → ~\(estimatedChunks) semantic chunks")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                HStack(spacing: DSSpacing.sm) {
                    featureTag(icon: "text.line.first.and.arrowtriangle.forward", label: "Topic boundaries")
                    featureTag(icon: "list.bullet.indent", label: "Section snapping")
                }
            }
        }
        .padding(DSSpacing.md)
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
    }

    @ViewBuilder
    private func featureTag(icon: String, label: String) -> some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: icon)
                .scaledFont(size: 8)
            Text(label)
                .scaledFont(size: 9)
        }
        .foregroundStyle(.secondary)
    }

    private func chunkColor(for index: Int) -> Color {
        Color.accentColor.opacity(index == 1 ? 0.65 : 0.85)
    }
}
