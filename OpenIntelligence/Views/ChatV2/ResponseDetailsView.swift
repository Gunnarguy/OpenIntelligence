//
//  ResponseDetailsView.swift
//  OpenIntelligence
//
//  Centralized chat response details view for ChatV2
//

import SwiftUI

struct ChatResponseDetailsView: View {
    let metadata: ResponseMetadata
    let retrievedChunks: [RetrievedChunk]
    
    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            if metadata.strictModeEnabled {
                strictModeBadge
            }
            if let decision = metadata.gatingDecision {
                gatingBadge(for: decision)
            }
            performanceMetricsSection
            
            if !retrievedChunks.isEmpty {
                retrievedContextSection
            }
        }
    }
    
    // MARK: - Performance Metrics Section
    private var performanceMetricsSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                    .foregroundColor(.blue)
                Text("Performance Metrics")
                    .font(DSTypography.meta)
                    .fontWeight(.semibold)
            }
            
            VStack(spacing: 4) {
                ResponseDetailMetricRow(
                    icon: "cpu",
                    label: "Model",
                    value: metadata.modelUsed,
                    color: .purple
                )
                
                ResponseDetailMetricRow(
                    icon: "magnifyingglass",
                    label: "Retrieval Time",
                    value: String(format: "%.0f ms", metadata.retrievalTime * 1000),
                    color: .green
                )
                
                ResponseDetailMetricRow(
                    icon: "text.bubble",
                    label: "Generation Time",
                    value: String(format: "%.2f s", metadata.totalGenerationTime),
                    color: .orange
                )
                
                ResponseDetailMetricRow(
                    icon: "number",
                    label: "Tokens Generated",
                    value: "\(metadata.tokensGenerated)",
                    color: .cyan
                )
                
                if let tps = metadata.tokensPerSecond {
                    ResponseDetailMetricRow(
                        icon: "speedometer",
                        label: "Generation Speed",
                        value: String(format: "%.1f tok/s", tps),
                        color: .red
                    )
                }
            }
        }
        .padding(12)
        .background(DSColors.surface.opacity(0.6))
        .cornerRadius(12)
    }
    
    // MARK: - Strict Mode Badge
    private var strictModeBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.shield.fill")
                .foregroundColor(.red)
            Text("Strict Mode")
                .font(DSTypography.meta)
                .fontWeight(.semibold)
                .foregroundColor(DSColors.primaryText)
        }
        .padding(8)
        .background(Color.red.opacity(0.12))
        .cornerRadius(8)
    }
    
    // MARK: - Gating Decision Badge
    private func gatingBadge(for decision: String) -> some View {
        let icon: String
        let label: String
        let color: Color
        
        switch decision {
        case "acceptance_override":
            icon = "checkmark.seal.fill"
            label = "Acceptance Override"
            color = .green
        case "lenient":
            icon = "hand.thumbsup.fill"
            label = "Lenient Mode"
            color = .blue
        case "strict_blocked":
            icon = "exclamationmark.triangle.fill"
            label = "Strict Gate"
            color = .red
        case "fallback_ondevice_low_confidence":
            icon = "bolt.horizontal.circle.fill"
            label = "On‑Device Fallback"
            color = .orange
        default:
            icon = "questionmark.circle.fill"
            label = decision
            color = .gray
        }
        
        return HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(label)
                .font(DSTypography.meta)
                .fontWeight(.semibold)
                .foregroundColor(DSColors.primaryText)
        }
        .padding(8)
        .background(color.opacity(0.12))
        .cornerRadius(8)
    }
    
    // MARK: - Retrieved Context Section
    private var retrievedContextSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .foregroundColor(.green)
                Text("Retrieved Context")
                    .font(DSTypography.meta)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(retrievedChunks.count) chunks")
                    .font(DSTypography.meta)
                    .foregroundColor(DSColors.secondaryText)
            }
            
            ForEach(Array(retrievedChunks.enumerated()), id: \.offset) { index, chunk in
                chunkView(chunk: chunk, index: index)
            }
        }
        .padding(12)
        .background(DSColors.surface.opacity(0.6))
        .cornerRadius(12)
    }
    
    private func chunkView(chunk: RetrievedChunk, index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "sparkle")
                        .font(.caption2)
                        .foregroundColor(similarityColor(Double(chunk.similarityScore)))
                    Text("Chunk \(index + 1)")
                        .font(DSTypography.meta)
                        .fontWeight(.medium)
                }
                
                Spacer()
                
                similarityIndicator(score: Double(chunk.similarityScore))
            }
            
            let preview = chunk.chunk.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            let displayText = preview.count > 150 ? preview.prefix(150) + "..." : preview
            
            Text(displayText)
                .font(DSTypography.body)
                .foregroundColor(DSColors.secondaryText)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DSColors.surface)
                .cornerRadius(8)
            
            HStack(spacing: 12) {
                Label("\(chunk.chunk.content.count) chars", systemImage: "text.alignleft")
                Label("\(chunk.chunk.content.split(separator: " ").count) words", systemImage: "textformat")
            }
            .font(.caption2)
            .foregroundColor(DSColors.secondaryText)
        }
        .padding(10)
        .background(DSColors.surface.opacity(0.4))
        .cornerRadius(10)
    }
    
    private func similarityIndicator(score: Double) -> some View {
        HStack(spacing: 4) {
            Text(String(format: "%.1f%%", score * 100))
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(similarityColor(score))
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                    Rectangle()
                        .fill(similarityColor(score))
                        .frame(width: geo.size.width * CGFloat(score))
                }
            }
            .frame(width: 40, height: 4)
            .cornerRadius(2)
        }
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
}

// MARK: - Metric Row

struct ResponseDetailMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 16)
            
            Text(label)
                .font(.caption)
                .foregroundColor(DSColors.secondaryText)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(DSColors.primaryText)
        }
    }
}
