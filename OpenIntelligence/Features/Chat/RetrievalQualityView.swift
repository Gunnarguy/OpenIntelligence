//
//  RetrievalQualityView.swift
//  OpenIntelligence
//
//  Visual representations of retrieval quality - similarity scores,
//  confidence bars, and source quality indicators.
//

import SwiftUI

/// Horizontal bar chart showing similarity scores for retrieved chunks
struct RetrievalQualityBar: View {
    let chunks: [RetrievedChunk]
    let maxBars: Int
    
    init(chunks: [RetrievedChunk], maxBars: Int = 5) {
        self.chunks = chunks
        self.maxBars = maxBars
    }
    
    private var displayChunks: [RetrievedChunk] {
        Array(chunks.prefix(maxBars))
    }
    
    private var maxScore: Float {
        chunks.map(\.similarityScore).max() ?? 1.0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Header
            HStack {
                Text("Retrieval Quality")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                
                Spacer()
                
                Text("\(chunks.count) chunks")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary.opacity(0.7))
            }
            
            // Bars
            VStack(spacing: 3) {
                ForEach(Array(displayChunks.enumerated()), id: \.offset) { index, chunk in
                    SimilarityBar(
                        rank: index + 1,
                        score: chunk.similarityScore,
                        maxScore: maxScore,
                        docName: chunk.sourceDocument.isEmpty ? "Source \(index + 1)" : chunk.sourceDocument
                    )
                }
            }
            
            // Average score
            if !chunks.isEmpty {
                HStack {
                    Spacer()
                    Text("avg: \(String(format: "%.0f%%", averageScore * 100))")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(scoreColor(averageScore))
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemBackground))
        )
    }
    
    private var averageScore: Float {
        guard !chunks.isEmpty else { return 0 }
        return chunks.map(\.similarityScore).reduce(0, +) / Float(chunks.count)
    }
    
    private func scoreColor(_ score: Float) -> Color {
        if score > 0.8 { return .green }
        if score > 0.6 { return .blue }
        if score > 0.4 { return .orange }
        return .red
    }
}

/// Individual similarity bar
private struct SimilarityBar: View {
    let rank: Int
    let score: Float
    let maxScore: Float
    let docName: String
    
    private var normalizedWidth: CGFloat {
        guard maxScore > 0 else { return 0 }
        return CGFloat(score / maxScore)
    }
    
    private var barColor: Color {
        if score > 0.8 { return .green }
        if score > 0.6 { return .blue }
        if score > 0.4 { return .orange }
        return .red
    }
    
    var body: some View {
        HStack(spacing: 6) {
            // Rank badge
            Text("\(rank)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(barColor))
            
            // Bar with doc name
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // Background
                    Capsule()
                        .fill(barColor.opacity(0.15))
                    
                    // Filled portion
                    Capsule()
                        .fill(barColor.opacity(0.6))
                        .frame(width: geo.size.width * normalizedWidth)
                    
                    // Text overlay
                    HStack(spacing: 4) {
                        Text(docName)
                            .font(.system(size: 9, weight: .medium))
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Text(String(format: "%.0f%%", score * 100))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    }
                    .padding(.horizontal, 6)
                    .foregroundStyle(DSColors.primaryText)
                }
            }
            .frame(height: 18)
        }
    }
}

/// Compact inline quality indicator (single pill)
struct CompactQualityIndicator: View {
    let chunks: [RetrievedChunk]
    
    private var avgScore: Float {
        guard !chunks.isEmpty else { return 0 }
        return chunks.map(\.similarityScore).reduce(0, +) / Float(chunks.count)
    }
    
    private var qualityInfo: (label: String, color: Color, icon: String) {
        if avgScore > 0.8 { return ("Excellent", .green, "checkmark.seal.fill") }
        if avgScore > 0.6 { return ("Good", .blue, "hand.thumbsup.fill") }
        if avgScore > 0.4 { return ("Fair", .orange, "exclamationmark.triangle.fill") }
        return ("Low", .red, "xmark.circle.fill")
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: qualityInfo.icon)
                .font(.system(size: 9, weight: .semibold))
            
            Text(qualityInfo.label)
                .font(.system(size: 10, weight: .medium))
            
            Text("•")
                .font(.system(size: 8))
                .opacity(0.5)
            
            Text(String(format: "%.0f%%", avgScore * 100))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .foregroundStyle(qualityInfo.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(qualityInfo.color.opacity(0.12))
        )
    }
}

/// Vertical quality gauge (thermometer style)
struct QualityGauge: View {
    let score: Float
    let label: String
    
    private var gaugeColor: Color {
        if score > 0.8 { return .green }
        if score > 0.6 { return .blue }
        if score > 0.4 { return .orange }
        return .red
    }
    
    var body: some View {
        VStack(spacing: 4) {
            // Gauge
            GeometryReader { geo in
                ZStack(alignment: .bottom) {
                    // Background
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(gaugeColor.opacity(0.15))
                    
                    // Fill
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(gaugeColor)
                        .frame(height: geo.size.height * CGFloat(score))
                }
            }
            .frame(width: 12)
            
            // Label
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.secondary)
        }
    }
}

/// Multi-dimension quality radar (retrieval, relevance, confidence)
struct QualityRadar: View {
    let retrievalScore: Float
    let relevanceScore: Float
    let confidenceScore: Float
    
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 12) {
                QualityGauge(score: retrievalScore, label: "Ret")
                QualityGauge(score: relevanceScore, label: "Rel")
                QualityGauge(score: confidenceScore, label: "Conf")
            }
            .frame(height: 40)
            
            // Overall score
            let overall = (retrievalScore + relevanceScore + confidenceScore) / 3
            HStack(spacing: 4) {
                Text("Quality:")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.secondary)
                Text(String(format: "%.0f%%", overall * 100))
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(gaugeColor(overall))
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(uiColor: .tertiarySystemBackground))
        )
    }
    
    private func gaugeColor(_ score: Float) -> Color {
        if score > 0.8 { return .green }
        if score > 0.6 { return .blue }
        if score > 0.4 { return .orange }
        return .red
    }
}

// MARK: - Preview Helpers

private extension RetrievedChunk {
    /// Create a mock chunk for previews
    static func mock(
        text: String = "Sample text",
        sourceName: String = "document.md",
        similarity: Float = 0.8,
        pageNumber: Int? = nil
    ) -> RetrievedChunk {
        let chunk = DocumentChunk(
            documentId: UUID(),
            content: text,
            embedding: [],
            metadata: ChunkMetadata(chunkIndex: 0, pageNumber: pageNumber)
        )
        return RetrievedChunk(
            chunk: chunk,
            similarityScore: similarity,
            rank: 1,
            sourceDocument: sourceName,
            pageNumber: pageNumber
        )
    }
}

#Preview("Retrieval Quality Bar") {
    let chunks = [
        RetrievedChunk.mock(sourceName: "architecture.md", similarity: 0.92, pageNumber: 1),
        RetrievedChunk.mock(sourceName: "pricing.pdf", similarity: 0.78, pageNumber: 2),
        RetrievedChunk.mock(sourceName: "readme.txt", similarity: 0.65),
        RetrievedChunk.mock(sourceName: "notes.md", similarity: 0.52, pageNumber: 1),
    ]
    
    VStack(spacing: 20) {
        RetrievalQualityBar(chunks: chunks)
        
        HStack(spacing: 16) {
            CompactQualityIndicator(chunks: chunks)
            CompactQualityIndicator(chunks: [chunks[0]])
            CompactQualityIndicator(chunks: [chunks[3]])
        }
        
        QualityRadar(retrievalScore: 0.85, relevanceScore: 0.72, confidenceScore: 0.68)
    }
    .padding()
    .background(DSColors.background)
}
