//
//  FirstQueryPromptView.swift
//  OpenIntelligence
//
//  Moved from ChatScreen.swift on 2026-11-05 (5.8 split); only access keywords changed.
//

import AppIntents
import Combine
import Foundation
import StoreKit
import SwiftUI
import TipKit
import Translation

#if os(iOS)
    import PDFKit
    import VisionKit
#endif

// MARK: - First-Query Guidance

struct FirstQueryPromptView: View {
    let hasDocuments: Bool
    var modelNotice: String? = nil
    let prompts: [String]
    let categories: [String: SuggestedQuestionsService.QuestionCategory]
    let questionDetails: [String: SuggestedQuestionsService.SuggestedQuestion]
    /// Every prompt shown is one of the questions written by hand for the sample documents.
    var writtenForSamples: Bool = false
    let libraryDocumentCount: Int
    let isRefreshing: Bool
    let onPromptSelected: (String) -> Void
    let onRefresh: () -> Void

    private var sourceDocumentCount: Int {
        Set(questionDetails.values.flatMap(\.relevantDocuments)).count
    }

    private var headerText: String {
        hasDocuments ? "What would you like to know?" : "Get started"
    }

    private var supportingText: String {
        guard hasDocuments else {
            return "Import documents from the Documents tab, then ask about them here."
        }

        guard !prompts.isEmpty else {
            return
                "No grounded suggestions are ready yet. Ask about a specific warning, requirement, step, setting, or value in this library."
        }

        if writtenForSamples {
            return "These questions were written for the sample documents."
        }

        guard !questionDetails.isEmpty else {
            return "Suggestions are generated from specific passages in this library."
        }

        if libraryDocumentCount > sourceDocumentCount && sourceDocumentCount > 0 {
            return
                "This batch is pulled from \(sourceDocumentCount) of \(libraryDocumentCount) docs in this library. Refresh for a different slice."
        }

        return "Suggestions are generated from specific passages in this library."
    }

    private func sourceLine(for prompt: String) -> String? {
        guard let detail = questionDetails[prompt],
            let primaryDoc = detail.relevantDocuments.first
        else {
            return nil
        }

        let extraDocCount = max(0, detail.relevantDocuments.count - 1)
        let section = detail.sourceSections.first?.trimmingCharacters(in: .whitespacesAndNewlines)

        var parts: [String] = [primaryDoc]
        if let section, !section.isEmpty {
            parts.append(section)
        }
        if extraDocCount > 0 {
            parts.append("+\(extraDocCount) more")
        }

        return parts.joined(separator: " • ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            HStack(alignment: .top, spacing: DSSpacing.md) {
                Image(systemName: "sparkles")
                    .scaledFont(size: 28, weight: .semibold)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [DSColors.accent, DSColors.accent.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: DSColors.accent.opacity(0.3), radius: 8)

                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(headerText)
                        .font(DSTypography.title)
                        .foregroundStyle(DSColors.primaryText)

                    Text(supportingText)
                        .font(DSTypography.body)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                if hasDocuments {
                    Button {
                        DSHaptics.selection()
                        onRefresh()
                    } label: {
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .scaledFont(size: 16, weight: .bold)
                            .foregroundStyle(DSColors.accent)
                            .padding(DSSpacing.sm)
                            .background(DSColors.accent.opacity(0.1))
                            .clipShape(Circle())
                            .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                            .animation(
                                isRefreshing
                                    ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                                    : .default,
                                value: isRefreshing
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(isRefreshing)
                    .accessibilityLabel("Refresh suggestions")
                }
            }

            if let modelNotice {
                HStack(alignment: .top, spacing: DSSpacing.sm) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(.orange)
                    Text(modelNotice)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(DSSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
                .accessibilityElement(children: .combine)
            }

            if !prompts.isEmpty {
                VStack(alignment: .leading, spacing: DSSpacing.md) {
                    ForEach(prompts, id: \.self) { prompt in
                        Button {
                            onPromptSelected(prompt)
                        } label: {
                            HStack(spacing: DSSpacing.md) {
                                if let category = categories[prompt] {
                                    Image(systemName: category.icon)
                                        .scaledFont(size: 14, weight: .semibold)
                                        .foregroundStyle(.white)
                                        .frame(width: 32, height: 32)
                                        .background(
                                            Circle()
                                                .fill(DSColors.accent.gradient)
                                        )
                                }

                                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                    Text(prompt)
                                        .font(DSTypography.body.weight(.medium))
                                        .foregroundStyle(DSColors.primaryText)
                                        .multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)

                                    if let source = sourceLine(for: prompt) {
                                        Text(source)
                                            .font(DSTypography.meta)
                                            .foregroundStyle(DSColors.secondaryText)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer(minLength: DSSpacing.sm)

                                Image(systemName: "arrow.up.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(DSColors.accent)
                                    .symbolRenderingMode(.hierarchical)
                            }
                            .padding(DSSpacing.md)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background {
                            if #available(iOS 26.0, *) {
                                Color.clear
                                    .glassEffect(
                                        .regular.interactive(),
                                        in: RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous))
                            } else {
                                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                                    .fill(DSColors.surface)
                                    .shadow(color: .black.opacity(0.03), radius: 4, y: 2)
                            }
                        }
                    }
                }
            }
        }
        .padding(DSSpacing.lg)
        .background {
            if #available(iOS 26.0, *) {
                Color.clear
                    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                    .fill(DSColors.surfaceElevated)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DSCorners.sheet, style: .continuous)
                .strokeBorder(DSColors.accent.opacity(0.1), lineWidth: 1)
        }
    }
}
