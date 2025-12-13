//
//  ResponseDetailsView.swift
//  OpenIntelligence
//
//  Centralized chat response details view for ChatV2 with granular metrics
//

import SwiftUI

struct ChatResponseDetailsView: View {
    let metadata: ResponseMetadata
    let retrievedChunks: [RetrievedChunk]
    
    @State private var selectedTab: DetailTab = .overview
    @Environment(\.dismiss) private var dismiss
    
    enum DetailTab: String, CaseIterable {
        case overview = "Overview"
        case timing = "Timing"
        case sources = "Sources"
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    // Tab picker
                    Picker("Section", selection: $selectedTab) {
                        ForEach(DetailTab.allCases, id: \.self) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    
                    switch selectedTab {
                    case .overview:
                        overviewSection
                    case .timing:
                        timingSection
                    case .sources:
                        sourcesSection
                    }
                }
                .padding(.vertical)
            }
            .background(DSColors.background)
            .navigationTitle("Response Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    // MARK: - Overview Section
    
    private var overviewSection: some View {
        VStack(spacing: DSSpacing.md) {
            // Execution badges
            HStack(spacing: 8) {
                ModelExecutionBadge(
                    modelName: metadata.modelUsed,
                    ttft: metadata.timeToFirstToken,
                    strictMode: metadata.strictModeEnabled
                )
                
                if let toolCalls = metadata.toolCallsMade, toolCalls > 0 {
                    ToolCallBadge(count: toolCalls)
                }
            }
            
            if metadata.strictModeEnabled {
                strictModeBadge
            }
            
            if let decision = metadata.gatingDecision {
                gatingBadge(for: decision)
            }
            
            // Key metrics cards
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                MetricCard(
                    icon: "clock.arrow.circlepath",
                    title: "First Token",
                    value: metadata.timeToFirstToken != nil ? 
                        String(format: "%.0fms", metadata.timeToFirstToken! * 1000) : "—",
                    color: .blue
                )
                
                MetricCard(
                    icon: "timer",
                    title: "Total Time",
                    value: String(format: "%.2fs", metadata.totalGenerationTime),
                    color: .green
                )
                
                MetricCard(
                    icon: "number",
                    title: "Tokens",
                    value: "\(metadata.tokensGenerated)",
                    color: .purple
                )
                
                MetricCard(
                    icon: "speedometer",
                    title: "Speed",
                    value: metadata.tokensPerSecond != nil ?
                        String(format: "%.1f t/s", metadata.tokensPerSecond!) : "—",
                    color: speedColor
                )
            }
            .padding(.horizontal)
            
            // Quick source summary
            if !retrievedChunks.isEmpty {
                HStack {
                    CompactQualityIndicator(chunks: retrievedChunks)
                    Spacer()
                    Text("\(retrievedChunks.count) sources retrieved")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var speedColor: Color {
        guard let tps = metadata.tokensPerSecond else { return .gray }
        if tps > 40 { return .green }
        if tps > 20 { return .blue }
        if tps > 10 { return .orange }
        return .red
    }
    
    // MARK: - Timing Section
    
    private var timingSection: some View {
        VStack(spacing: DSSpacing.md) {
            // Timing waterfall
            TimingBreakdownView(
                embedding: metadata.retrievalTime * 0.3, // Approximate split
                searching: metadata.retrievalTime * 0.7,
                generating: metadata.totalGenerationTime,
                total: metadata.totalGenerationTime + metadata.retrievalTime
            )
            .padding(.horizontal)
            
            // Performance summary
            VStack(alignment: .leading, spacing: 8) {
                Text("Performance Analysis")
                    .font(.system(size: 15, weight: .semibold))
                
                performanceInsight
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal)
        }
    }
    
    private var performanceInsight: some View {
        let ttft = metadata.timeToFirstToken ?? 0
        let tps = metadata.tokensPerSecond ?? 0
        
        var insights: [(icon: String, text: String, color: Color)] = []
        
        if ttft < 0.3 {
            insights.append(("bolt.fill", "Ultra-fast first token response", .green))
        } else if ttft < 1.0 {
            insights.append(("checkmark.circle", "Good time to first token", .blue))
        } else {
            insights.append(("clock.badge.exclamationmark", "First token latency could be improved", .orange))
        }
        
        if tps > 40 {
            insights.append(("flame.fill", "Exceptional generation speed", .green))
        } else if tps > 20 {
            insights.append(("speedometer", "Solid generation throughput", .blue))
        } else if tps > 0 {
            insights.append(("tortoise.fill", "Generation was slower than typical", .orange))
        }
        
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(insights.indices, id: \.self) { index in
                let insight = insights[index]
                HStack(spacing: 8) {
                    Image(systemName: insight.icon)
                        .font(.system(size: 12))
                        .foregroundStyle(insight.color)
                    Text(insight.text)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    // MARK: - Sources Section
    
    private var sourcesSection: some View {
        VStack(spacing: DSSpacing.md) {
            if retrievedChunks.isEmpty {
                emptySourcesView
            } else {
                // Quality visualization
                RetrievalQualityBar(chunks: retrievedChunks)
                    .padding(.horizontal)
                
                // Detailed source list
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(retrievedChunks.enumerated()), id: \.offset) { index, chunk in
                        ExpandableChunkView(chunk: chunk, rank: index + 1)
                    }
                }
                .padding(.horizontal)
            }
        }
    }
    
    private var emptySourcesView: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("No sources retrieved")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            Text("This response was generated without RAG context")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - Badges
    
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
}

// MARK: - Metric Card

private struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let color: Color
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            
            Text(value)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .foregroundStyle(DSColors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Expandable Chunk View

private struct ExpandableChunkView: View {
    let chunk: RetrievedChunk
    let rank: Int
    
    @State private var isExpanded = false
    
    private var similarityScore: Double {
        Double(chunk.similarityScore)
    }
    
    private var similarityColor: Color {
        if similarityScore >= 0.8 { return .green }
        if similarityScore >= 0.6 { return .blue }
        if similarityScore >= 0.4 { return .orange }
        return .red
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with rank, similarity, and expand toggle
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    // Rank badge
                    Text("#\(rank)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(similarityColor)
                        .clipShape(Capsule())
                    
                    // Source name
                    Text(chunk.sourceDocument.isEmpty ? "Document" : chunk.sourceDocument)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DSColors.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Similarity percentage
                    Text(String(format: "%.0f%%", similarityScore * 100))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundStyle(similarityColor)
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            
            // Similarity bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.2))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(similarityColor)
                        .frame(width: geo.size.width * similarityScore)
                }
            }
            .frame(height: 4)
            
            // Expanded content
            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(chunk.chunk.content)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(nil)
                    
                    HStack(spacing: 12) {
                        Label("\(chunk.chunk.content.count) chars", systemImage: "text.alignleft")
                        Label("\(chunk.chunk.content.split(separator: " ").count) words", systemImage: "textformat")
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Metric Row (Legacy Support)

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

// MARK: - Model Execution Badge

/// Compact badge showing model and execution location
private struct ModelExecutionBadge: View {
    let modelName: String
    let ttft: TimeInterval?
    let strictMode: Bool
    
    private var executionInfo: (icon: String, label: String, color: Color) {
        // Strict mode takes priority
        if strictMode {
            return ("shield.checkered", "Strict Mode", .orange)
        }
        
        // Determine execution location based on model name and TTFT
        if modelName.contains("GGUF") {
            return ("doc.badge.gearshape", "On-Device GGUF", .blue)
        } else if modelName.contains("Core ML") {
            return ("cpu", "Neural Engine", .purple)
        } else if modelName.contains("Apple Intelligence") || modelName.contains("Foundation") {
            // Use TTFT heuristic for Apple Intelligence
            if let ttft = ttft {
                if ttft < 0.3 {
                    return ("iphone", "On-Device", .blue)
                } else {
                    return ("cloud", "Private Cloud", .green)
                }
            } else {
                return ("sparkles", "Apple AI", .indigo)
            }
        } else if modelName.contains("ChatGPT") {
            return ("bubble.left.and.bubble.right", "ChatGPT", .green)
        } else if modelName.contains("OpenAI") || modelName.contains("GPT") {
            return ("key.fill", "OpenAI API", .orange)
        } else if modelName.contains("MLX") {
            return ("server.rack", "MLX Local", .cyan)
        } else if modelName.contains("On-Device Analysis") {
            return ("doc.text.magnifyingglass", "Extractive", .gray)
        }
        
        return ("questionmark.circle", "Unknown", .secondary)
    }
    
    var body: some View {
        HStack(spacing: DSSpacing.xxs) {
            Image(systemName: executionInfo.icon)
                .font(.system(size: 10, weight: .semibold))
            
            Text(executionInfo.label)
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(executionInfo.color)
        .padding(.horizontal, DSSpacing.xs)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(DSColors.chipBackground(for: executionInfo.color))
        )
        .overlay(
            Capsule()
                .strokeBorder(executionInfo.color.opacity(0.2), lineWidth: 0.5)
        )
    }
}
