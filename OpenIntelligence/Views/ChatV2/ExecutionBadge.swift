//
//  ExecutionBadge.swift
//  OpenIntelligence
//
//  Displays where inference executed (on-device, PCC, cloud, etc.)
//  Uses TTFT heuristics and model metadata to classify execution location.
//

import SwiftUI

struct InferenceLocationBadge: View {
    let modelName: String
    let ttft: TimeInterval?
    let metadata: ResponseMetadata?
    
    private var executionInfo: (icon: String, label: String, color: Color) {
        // Check if we have explicit execution metadata
        if let meta = metadata {
            // If strict mode was enabled, show that first
            if meta.strictModeEnabled {
                return ("shield.checkered", "Strict", .orange)
            }
        }
        
        // Determine execution location based on model and TTFT
        if modelName.contains("GGUF") {
            return ("doc.badge.gearshape", "On-Device", .blue)
        } else if modelName.contains("Core ML") {
            return ("cpu", "Neural Engine", .purple)
        } else if modelName.contains("Apple Intelligence") || modelName.contains("Foundation") {
            // Use TTFT heuristic for Apple Intelligence
            if let ttft = ttft {
                if ttft < 0.3 {
                    return ("iphone", "On-Device", .blue)
                } else {
                    return ("cloud", "PCC", .green)
                }
            } else {
                return ("sparkles", "Apple AI", .indigo)
            }
        } else if modelName.contains("ChatGPT") {
            return ("bubble.left.and.bubble.right", "ChatGPT", .green)
        } else if modelName.contains("OpenAI") || modelName.contains("GPT") {
            return ("key.fill", "OpenAI", .orange)
        } else if modelName.contains("MLX") {
            return ("server.rack", "MLX Local", .cyan)
        } else if modelName.contains("On-Device Analysis") {
            return ("doc.text.magnifyingglass", "Extractive", .gray)
        }
        
        return ("questionmark.circle", "Unknown", .secondary)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: executionInfo.icon)
                .font(.caption2)
            
            Text(executionInfo.label)
                .font(.caption2)
                .fontWeight(.medium)
        }
        .foregroundColor(executionInfo.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(executionInfo.color.opacity(0.15))
        )
    }
}

// MARK: - Preview

struct InferenceLocationBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            InferenceLocationBadge(
                modelName: "Apple Intelligence",
                ttft: 0.2,
                metadata: nil
            )
            
            InferenceLocationBadge(
                modelName: "Apple Intelligence",
                ttft: 0.8,
                metadata: nil
            )
            
            InferenceLocationBadge(
                modelName: "GGUF • Qwen2.5-7B",
                ttft: 0.5,
                metadata: nil
            )
            
            InferenceLocationBadge(
                modelName: "Core ML • Phi-3",
                ttft: nil,
                metadata: nil
            )
            
            InferenceLocationBadge(
                modelName: "OpenAI GPT-4",
                ttft: 1.2,
                metadata: nil
            )
            
            InferenceLocationBadge(
                modelName: "On-Device Analysis",
                ttft: nil,
                metadata: nil
            )
        }
        .padding()
    }
}
