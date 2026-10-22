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
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    // Header with icon
                    HStack(spacing: DSSpacing.sm) {
                        Image(systemName: iconForTitle)
                            .font(.title2.weight(.medium))
                            .foregroundStyle(colorForTitle)
                            .frame(width: 40, height: 40)
                            .background(colorForTitle.opacity(0.12))
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                            Text(title)
                                .font(.headline)
                                .foregroundStyle(DSColors.primaryText)
                            Text("via Apple Intelligence")
                                .font(.caption)
                                .foregroundStyle(DSColors.secondaryText)
                        }
                    }
                    .padding(.bottom, DSSpacing.xs)

                    Divider()

                    // Result content — rendered with full block-level markdown
                    MarkdownText(result)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Divider()

                    // Feedback row — rate this AI transform
                    HStack {
                        Text("Helpful?")
                            .font(.subheadline)
                            .foregroundStyle(DSColors.secondaryText)
                        Spacer()
                        Button {
                            onFeedback?(true)
                        } label: {
                            Image(systemName: "hand.thumbsup")
                                .font(.body)
                                .foregroundStyle(.green)
                                .padding(DSSpacing.sm)
                                .background(Color.green.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        Button {
                            onFeedback?(false)
                        } label: {
                            Image(systemName: "hand.thumbsdown")
                                .font(.body)
                                .foregroundStyle(DSColors.secondaryText)
                                .padding(DSSpacing.sm)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    Divider()

                    // Action buttons
                    HStack(spacing: DSSpacing.sm) {
                        Button {
                            onCopy()
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                                .font(.footnote.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DSSpacing.sm)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        ShareLink(item: result) {
                            Label("Share", systemImage: "square.and.arrow.up")
                                .font(.footnote.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DSSpacing.sm)
                                .background(.ultraThinMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
                        }
                        .buttonStyle(.plain)

                        Button {
                            onInsertAsReply()
                        } label: {
                            Label("Insert", systemImage: "text.insert")
                                .font(.footnote.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DSSpacing.sm)
                                .foregroundStyle(.white)
                                .background(colorForTitle)
                                .clipShape(RoundedRectangle(cornerRadius: DSCorners.chip, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(DSSpacing.lg)
            }
            .background(DSColors.background)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
                #else
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                #endif
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
