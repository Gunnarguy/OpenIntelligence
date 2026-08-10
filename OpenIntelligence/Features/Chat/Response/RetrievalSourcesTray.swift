//
//  RetrievalSourcesTray.swift
//  OpenIntelligence
//
//  A compact expandable tray that appears during RAG retrieval.
//  Shows live retrieved sources summary with shimmer loading state.
//  Polished with glass morphism, smooth animations, and haptics.
//  Created by Cline on 10/29/25.
//

import SwiftUI

struct RetrievalSourcesTray: View {
    let stage: ChatProcessingStage
    let chunks: [RetrievedChunk]
    let onTap: () -> Void
    
    @State private var isExpanded: Bool = false
    @State private var isVisible: Bool = false
    
    private var isActive: Bool {
        stage == .searching || stage == .generating
    }
    
    private var headerText: String {
        if stage == .searching && chunks.isEmpty {
            return "Searching knowledge base…"
        } else if chunks.isEmpty {
            return "No sources found"
        } else {
            return chunks.count == 1 ? "1 source retrieved" : "\(chunks.count) sources retrieved"
        }
    }
    
    private var averageScore: Double {
        guard !chunks.isEmpty else { return 0 }
        let sum = chunks.reduce(0.0) { $0 + Double($1.similarityScore) }
        return sum / Double(chunks.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row
            Button {
                DSHaptics.light()
                withAnimation(DSAnimations.snappySpring) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: DSSpacing.xs) {
                    // Status indicator
                    ZStack {
                        if stage == .searching && chunks.isEmpty {
                            // Searching spinner
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 16, height: 16)
                        } else {
                            // Quality indicator dot
                            Circle()
                                .fill(qualityColor)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .frame(width: 20)
                    
                    // Header text
                    Text(headerText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(DSColors.primaryText)
                    
                    Spacer()
                    
                    // Average score badge
                    if !chunks.isEmpty {
                        HStack(spacing: 3) {
                            Text("avg")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(DSColors.secondaryText)
                            Text("\(Int(averageScore * 100))%")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundColor(qualityColor)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(DSColors.chipBackground(for: qualityColor))
                        )
                    }
                    
                    // Expand chevron
                    if !chunks.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(DSColors.secondaryText)
                            .rotationEffect(.degrees(isExpanded ? 0 : 0))
                    }
                }
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.sm)
            }
            .buttonStyle(.plain)
            .disabled(chunks.isEmpty)
            
            // Expanded content
            if isExpanded && !chunks.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Divider()
                        .padding(.horizontal, DSSpacing.md)
                    
                    SourceChipsView(chunks: chunks, onTap: onTap)
                        .padding(.horizontal, DSSpacing.md)
                        .padding(.bottom, DSSpacing.sm)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
            
            // Shimmer loading bar when searching
            if stage == .searching && chunks.isEmpty {
                ShimmerBar()
                    .frame(height: 4)
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.bottom, DSSpacing.sm)
                    .transition(.opacity)
            }
        }
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .strokeBorder(DSColors.border.opacity(0.5), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal, DSSpacing.md)
        .opacity(isVisible ? 1.0 : 0.0)
        .offset(y: isVisible ? 0 : 10)
        .animation(DSAnimations.snappySpring, value: chunks.count)
        .animation(DSAnimations.snappySpring, value: isExpanded)
        .onAppear {
            withAnimation(DSAnimations.snappySpring.delay(0.1)) {
                isVisible = true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Retrieval sources, \(headerText)")
    }
    
    private var qualityColor: Color {
        if averageScore >= 0.75 { return .green }
        if averageScore >= 0.5 { return .orange }
        return .red
    }
}

// MARK: - Shimmer Loading Bar

private struct ShimmerBar: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Base track
                Capsule()
                    .fill(DSColors.surface)
                
                // Shimmer highlight
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                .white.opacity(0.4),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * 0.4)
                    .offset(x: (geo.size.width * 1.4) * phase - geo.size.width * 0.4)
                    .blur(radius: 3)
            }
            .clipShape(Capsule())
            .onAppear {
                withAnimation(.linear(duration: 1.5).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Retrieval Sources Tray") {
    VStack(spacing: DSSpacing.lg) {
        // Searching state
        RetrievalSourcesTray(stage: .searching, chunks: []) { }
        
        // With results
        RetrievalSourcesTray(
            stage: .generating,
            chunks: (0..<4).map { i in
                RetrievedChunk(
                    chunk: DocumentChunk(
                        documentId: UUID(),
                        content: "Sample content \(i)",
                        embedding: [],
                        metadata: ChunkMetadata(chunkIndex: i, startPosition: 0, endPosition: 100)
                    ),
                    similarityScore: Float(0.6 + Double(i) * 0.08),
                    rank: i,
                    sourceDocument: "Document \(i + 1).pdf",
                    pageNumber: i + 1
                )
            }
        ) { }
    }
    .padding()
    .background(DSColors.background)
}
