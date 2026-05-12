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
    /// Called when the user rates the AI transform quality.
    /// `true` = helpful, `false` = not helpful.
    /// Wire to `LanguageModelSession.logFeedbackAttachment` in the calling site
    /// once the session reference is threaded through.
    var onFeedback: ((Bool) -> Void)? = nil

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

                    // Result content — rendered with full block-level markdown
                    MarkdownText(result)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    // Feedback row — rate this AI transform
                    HStack {
                        Text("Helpful?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button {
                            onFeedback?(true)
                        } label: {
                            Image(systemName: "hand.thumbsup")
                                .font(.system(size: 18))
                                .foregroundStyle(.green)
                                .padding(8)
                                .background(Color.green.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            onFeedback?(false)
                        } label: {
                            Image(systemName: "hand.thumbsdown")
                                .font(.system(size: 18))
                                .foregroundStyle(.secondary)
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

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

                        ShareLink(item: result) {
                            Label("Share", systemImage: "square.and.arrow.up")
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
        case "Plain English": return "text.bubble"
        case "What's Missing?": return "questionmark.circle"
        default: return "apple.intelligence"
        }
    }

    private var colorForTitle: Color {
        switch title {
        case "Key Facts": return .blue
        case "Step-by-Step": return .green
        case "Plain English": return .mint
        case "What's Missing?": return .orange
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
