//
//  RetrievalSourcesTray.swift
//  OpenIntelligence
//
//  A compact tray that appears under the message list during Searching/Generating.
//  Shows live retrieved sources summary and expands to reveal source chips.
//  Created by Cline on 10/29/25.
//

import SwiftUI

struct RetrievalSourcesTray: View {
    let stage: ChatProcessingStage
    let chunks: [RetrievedChunk]
    let onTap: () -> Void
    
    private var isActive: Bool {
        stage == .searching || stage == .generating
    }
    
    private var headerText: String {
        if stage == .searching && chunks.isEmpty {
            return "Searching…"
        } else {
            let count = chunks.count
            return count == 1 ? "1 source" : "\(count) sources"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.caption2)
                    .foregroundColor(.green)
                Text(headerText)
                    .font(DSTypography.meta)
                    .foregroundColor(DSColors.secondaryText)
                Spacer()
                if !chunks.isEmpty {
                    Button(action: onTap) {
                        HStack(spacing: 4) {
                            Text("Details")
                                .font(DSTypography.meta)
                            Image(systemName: "chevron.up")
                                .font(.caption2)
                        }
                        .padding(.horizontal, DSSpacing.xs)
                        .padding(.vertical, 6)
                        .background(DSColors.chipBackground(for: DSColors.accent))
                        .foregroundColor(DSColors.accent)
                        .cornerRadius(DSCorners.chip)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            if isActive {
                if chunks.isEmpty {
                    ShimmerBar()
                        .frame(height: 6)
                        .clipShape(Capsule())
                        .transition(.opacity.combined(with: .move(edge: .top)))
                } else {
                    SourceChipsView(chunks: chunks) {
                        onTap()
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, DSSpacing.sm)
        .background(DSColors.surfaceElevated)
        .overlay(
            Rectangle()
                .fill(DSColors.surface.opacity(0.6))
                .frame(height: 0.5),
            alignment: .top
        )
        .animation(DSAnimations.fastEase, value: chunks.count)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Retrieval sources tray")
    }
}

// MARK: - Shimmer placeholder when searching

private struct ShimmerBar: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DSColors.surface)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .white.opacity(0.0),
                                .white.opacity(0.35),
                                .white.opacity(0.0)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * 0.35)
                    .offset(x: (geo.size.width + geo.size.width * 0.35) * phase - geo.size.width * 0.35)
                    .blur(radius: 6)
            }
            .onAppear {
                phase = 0
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        RetrievalSourcesTray(stage: .searching, chunks: []) { }
        RetrievalSourcesTray(stage: .generating, chunks: (0..<3).map { i in
            RetrievedChunk(
                chunk: DocumentChunk(
                    documentId: UUID(),
                    content: "Lorem ipsum \(i)",
                    embedding: [],
                    metadata: ChunkMetadata(chunkIndex: i, startPosition: 0, endPosition: 10)
                ),
                similarityScore: Float(0.7 + Double(i) * 0.05),
                rank: i,
                sourceDocument: "Doc \(i)",
                pageNumber: i + 1
            )
        }) { }
    }
    .background(DSColors.background)
}
