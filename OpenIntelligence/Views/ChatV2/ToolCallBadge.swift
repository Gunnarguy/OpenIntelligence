//
//  ToolCallBadge.swift
//  OpenIntelligence
//
//  Displays the number of tool/function calls made during a response.
//  Shows when the LLM used agentic capabilities (e.g., Apple Foundation Models tools).
//

import SwiftUI

struct ToolCallBadge: View {
    let count: Int
    
    var body: some View {
        if count > 0 {
            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.caption2)
                
                Text("\(count) tool\(count == 1 ? "" : "s")")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .foregroundColor(.purple)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.purple.opacity(0.15))
            )
        }
    }
}

// MARK: - Preview

struct ToolCallBadge_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 12) {
            ToolCallBadge(count: 0)
            ToolCallBadge(count: 1)
            ToolCallBadge(count: 3)
            ToolCallBadge(count: 7)
        }
        .padding()
    }
}
