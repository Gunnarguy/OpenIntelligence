//
//  LiveTelemetryStatsView.swift
//  OpenIntelligence
//
//  Real-time pipeline metrics overlay for chat queries
//

import SwiftUI

/// Live telemetry stats display that shows current pipeline stage and metrics
struct LiveTelemetryStatsView: View {
    @ObservedObject private var telemetry = TelemetryCenter.shared
    
    // Filter to recent events (last 10 seconds)
    private var recentEvents: [TelemetryEvent] {
        let cutoff = Date().addingTimeInterval(-10)
        return telemetry.events.filter { $0.timestamp > cutoff }
    }
    
    // Current stage based on most recent event
    private var currentStage: (category: TelemetryCategory, title: String, metadata: [String: String])? {
        guard let latest = recentEvents.last else { return nil }
        return (latest.category, latest.title, latest.metadata)
    }
    
    // Aggregate metrics from recent events
    private var metrics: PipelineMetrics {
        var m = PipelineMetrics()
        
        for event in recentEvents {
            switch event.category {
            case .retrieval:
                if event.title.contains("expanded") {
                    m.queryVariants = Int(event.metadata["variants"] ?? "0") ?? 0
                } else if event.title.contains("Hybrid retrieval") {
                    m.candidatesRetrieved = Int(event.metadata["candidates"] ?? "0") ?? 0
                    m.retrievalTime = event.duration
                } else if event.title.contains("Re-ranking") {
                    m.rerankedCount = Int(event.metadata["candidates"] ?? "0") ?? 0
                    m.rerankTime = event.duration
                } else if event.title.contains("MMR") {
                    m.diverseChunks = Int(event.metadata["selected"] ?? "0") ?? 0
                    m.mmrTime = event.duration
                } else if event.title.contains("Context assembled") {
                    m.finalChunks = Int(event.metadata["chunks"] ?? "0") ?? 0
                    m.contextChars = Int(event.metadata["chars"] ?? "0") ?? 0
                }
                
            case .embedding:
                if event.title.contains("Query embedding") {
                    m.embeddingDims = Int(event.metadata["dimensions"] ?? "0") ?? 0
                    m.embeddingTime = event.duration
                }
                
            case .generation:
                if event.title.contains("Response generated") {
                    m.tokensGenerated = Int(event.metadata["tokens"] ?? "0") ?? 0
                    m.modelName = event.metadata["model"] ?? "Unknown"
                    m.generationTime = event.duration
                }
                
            case .system:
                if event.title.contains("Query complete") {
                    m.totalTime = event.duration
                }
                
            default:
                break
            }
        }
        
        return m
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let stage = currentStage {
                // Current stage header
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(categoryColor(stage.category).opacity(0.15))
                            .frame(width: 44, height: 44)
                        
                        Image(systemName: stage.category.symbolName)
                            .font(.title3)
                            .foregroundColor(categoryColor(stage.category))
                    }
                    
                    VStack(alignment: .leading, spacing: 3) {
                        Text(stage.title)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(stage.category.rawValue.capitalized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Live indicator with pulse
                    HStack(spacing: 5) {
                        ZStack {
                            Circle()
                                .fill(Color.green.opacity(0.2))
                                .frame(width: 16, height: 16)
                                .scaleEffect(pulseScale)
                            
                            Circle()
                                .fill(Color.green)
                                .frame(width: 8, height: 8)
                        }
                        .animation(
                            Animation.easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: pulseScale
                        )
                        
                        Text("LIVE")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.green)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.green.opacity(0.1))
                    .cornerRadius(10)
                }
                
                Divider()
                    .padding(.vertical, 2)
                
                // Pipeline metrics grid
                metricsGrid
            } else {
                // Idle state
                HStack(spacing: 10) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.title3)
                        .foregroundColor(.secondary.opacity(0.5))
                    
                    Text("Awaiting query...")
                        .font(.headline)
                        .foregroundColor(.secondary.opacity(0.7))
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DSColors.background)
                .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    currentStage != nil 
                        ? categoryColor(currentStage!.category).opacity(0.4)
                        : Color.gray.opacity(0.15),
                    lineWidth: 1.5
                )
        )
        .onAppear {
            pulseScale = 1.3
        }
    }
    
    @State private var pulseScale: CGFloat = 1.0
    
    private var metricsGrid: some View {
        let m = metrics
        
        return VStack(spacing: 12) {
            // Row 1: Query processing
            if m.queryVariants > 0 {
                TelemetryMetricRow(
                    icon: "arrow.triangle.branch",
                    label: "Query Variants",
                    value: "\(m.queryVariants)",
                    color: .purple
                )
            }
            
            if m.embeddingDims > 0 {
                TelemetryMetricRow(
                    icon: "brain.head.profile",
                    label: "Embedding",
                    value: "\(m.embeddingDims)-dim" + (m.embeddingTime.map { " • \(formatTime($0))" } ?? ""),
                    color: .blue
                )
            }
            
            // Row 2: Retrieval pipeline
            if m.candidatesRetrieved > 0 {
                TelemetryMetricRow(
                    icon: "magnifyingglass.circle",
                    label: "Hybrid Search",
                    value: "\(m.candidatesRetrieved) candidates" + (m.retrievalTime.map { " • \(formatTime($0))" } ?? ""),
                    color: .green
                )
            }
            
            if m.rerankedCount > 0 {
                TelemetryMetricRow(
                    icon: "arrow.up.arrow.down.circle",
                    label: "Re-ranked",
                    value: "\(m.rerankedCount) chunks" + (m.rerankTime.map { " • \(formatTime($0))" } ?? ""),
                    color: .orange
                )
            }
            
            if m.diverseChunks > 0 {
                TelemetryMetricRow(
                    icon: "sparkles",
                    label: "MMR Diversity",
                    value: "\(m.diverseChunks) selected" + (m.mmrTime.map { " • \(formatTime($0))" } ?? ""),
                    color: .pink
                )
            }
            
            // Row 3: Context and generation
            if m.finalChunks > 0 {
                TelemetryMetricRow(
                    icon: "doc.text",
                    label: "Context",
                    value: "\(m.finalChunks) chunks • \(formatNumber(m.contextChars)) chars",
                    color: .cyan
                )
            }
            
            if m.tokensGenerated > 0 {
                let tps = m.generationTime != nil && m.generationTime! > 0 
                    ? Float(m.tokensGenerated) / Float(m.generationTime!)
                    : 0
                
                TelemetryMetricRow(
                    icon: "bolt.fill",
                    label: m.modelName,
                    value: "\(m.tokensGenerated) tokens" + (tps > 0 ? " • \(String(format: "%.1f", tps)) tok/s" : ""),
                    color: .red
                )
            }
            
            // Total time (if available)
            if let total = m.totalTime {
                Divider()
                    .padding(.vertical, 4)
                
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(Color.purple.opacity(0.15))
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: "clock.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.purple)
                    }
                    
                    Text("Total Pipeline")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text(formatTime(total))
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                        .monospacedDigit()
                }
                .padding(.vertical, 4)
            }
        }
    }
    
    private func categoryColor(_ category: TelemetryCategory) -> Color {
        switch category {
        case .ingestion: return .orange
        case .embedding: return .blue
        case .retrieval: return .green
        case .generation: return .red
        case .storage: return .purple
        case .system: return .cyan
        case .error: return .red
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        if seconds < 1.0 {
            return String(format: "%.0fms", seconds * 1000)
        } else {
            return String(format: "%.2fs", seconds)
        }
    }
    
    private func formatNumber(_ num: Int) -> String {
        if num >= 1000 {
            return String(format: "%.1fk", Double(num) / 1000.0)
        }
        return "\(num)"
    }
}

private struct TelemetryMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(color.opacity(0.12))
                    .frame(width: 32, height: 32)
                
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(color)
            }
            
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .monospacedDigit()
        }
        .padding(.vertical, 2)
    }
}

private struct PipelineMetrics {
    var queryVariants: Int = 0
    var embeddingDims: Int = 0
    var embeddingTime: TimeInterval? = nil
    var candidatesRetrieved: Int = 0
    var retrievalTime: TimeInterval? = nil
    var rerankedCount: Int = 0
    var rerankTime: TimeInterval? = nil
    var diverseChunks: Int = 0
    var mmrTime: TimeInterval? = nil
    var finalChunks: Int = 0
    var contextChars: Int = 0
    var tokensGenerated: Int = 0
    var modelName: String = ""
    var generationTime: TimeInterval? = nil
    var totalTime: TimeInterval? = nil
}

#Preview {
    LiveTelemetryStatsView()
        .padding()
}
