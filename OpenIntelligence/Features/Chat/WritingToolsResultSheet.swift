//
//  WritingToolsResultSheet.swift
//  OpenIntelligence
//
//  Sheet displaying results from Apple WritingTools (proofread, rewrite, summarize)
//

import SwiftUI

/// Displays the result of a WritingTools operation with copy and insert actions
struct WritingToolsResultSheet: View {
    let title: String
    let result: String
    let onCopy: () -> Void
    let onInsertAsReply: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header with icon
                    HStack(spacing: 10) {
                        Image(systemName: iconForTitle)
                            .font(.system(size: 24, weight: .medium))
                            .foregroundStyle(colorForTitle)
                            .frame(width: 40, height: 40)
                            .background(colorForTitle.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(title)
                                .font(.headline)
                            Text("via Apple Intelligence")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.bottom, 4)

                    Divider()

                    // Result content
                    Text(result)
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    // Action buttons
                    HStack(spacing: 12) {
                        Button {
                            onCopy()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)

                        Button {
                            onInsertAsReply()
                        } label: {
                            Label("Insert in Chat", systemImage: "text.insert")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .foregroundStyle(.white)
                                .background(colorForTitle)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var iconForTitle: String {
        switch title {
        case "Key Facts": return "list.bullet.rectangle"
        case "Step-by-Step": return "checklist"
        case "Cross-Reference": return "arrow.triangle.branch"
        case "Deep Dive": return "magnifyingglass.circle"
        case "Flash Cards": return "rectangle.on.rectangle.angled"
        // Legacy fallbacks
        case "Proofread": return "text.magnifyingglass"
        case "Rewrite": return "arrow.triangle.2.circlepath"
        case "Summary": return "text.redaction"
        default: return "apple.intelligence"
        }
    }

    private var colorForTitle: Color {
        switch title {
        case "Key Facts": return .blue
        case "Step-by-Step": return .green
        case "Cross-Reference": return .purple
        case "Deep Dive": return .orange
        case "Flash Cards": return .cyan
        // Legacy fallbacks
        case "Proofread": return .indigo
        case "Rewrite": return .teal
        case "Summary": return .orange
        default: return DSColors.accent
        }
    }
}

#Preview {
    WritingToolsResultSheet(
        title: "Summary",
        result: "This document covers machine learning fundamentals including neural networks, gradient descent optimization, and backpropagation algorithms for training deep learning models.",
        onCopy: {},
        onInsertAsReply: {}
    )
}
