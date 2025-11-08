//
//  SourceChipsView.swift
//  OpenIntelligence
//
//  Compact chips that summarize retrieved sources with similarity percent
//  Created by Cline on 10/28/25.
//

import SwiftUI

struct SourceChipsView: View {
    let chunks: [RetrievedChunk]
    let onTap: () -> Void
    
    private var topChips: [ChipData] {
        let top = chunks.prefix(5) // show up to 5 chips
        return top.enumerated().map { (i, c) in
            let pct = max(0, min(1, Double(c.similarityScore)))
            return ChipData(
                index: i + 1,
                percent: pct,
                tint: similarityColor(pct)
            )
        }
    }
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DSSpacing.xs) {
                ForEach(topChips) { chip in
                    Button(action: onTap) {
                        HStack(spacing: DSSpacing.xxs) {
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.caption2)
                            Text("Source \(chip.index) • \(String(format: "%.0f", chip.percent * 100))%")
                                .font(DSTypography.meta)
                        }
                        .padding(.horizontal, DSSpacing.xs)
                        .padding(.vertical, 6)
                        .background(DSColors.chipBackground(for: chip.tint))
                        .foregroundColor(chip.tint)
                        .cornerRadius(DSCorners.chip)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, DSSpacing.xs)
        }
        .accessibilityLabel("Retrieved sources")
    }
    
    private func similarityColor(_ score: Double) -> Color {
        if score >= 0.8 {
            return .green
        } else if score >= 0.6 {
            return .orange
        } else {
            return .red
        }
    }
    
    private struct ChipData: Identifiable {
        let id = UUID()
        let index: Int
        let percent: Double
        let tint: Color
    }
}

// MARK: - Preview

#Preview {
    let dummyChunks: [RetrievedChunk] = (0..<5).map { i in
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: UUID(),
                content: "Lorem ipsum \(i)",
                embedding: [],
                metadata: ChunkMetadata(chunkIndex: i, startPosition: 0, endPosition: 10)
            ),
            similarityScore: Float(0.5 + Double(i) * 0.1),
            rank: i,
            sourceDocument: "Doc \(i)",
            pageNumber: i + 1
        )
    }
    return SourceChipsView(chunks: dummyChunks) {}
        .padding()
}
