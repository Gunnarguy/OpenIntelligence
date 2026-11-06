//
//  ChatScreen+Content.swift
//  OpenIntelligence
//
//  Part of ChatScreen, moved from ChatScreen.swift on 2026-11-05 (5.8 split); only access keywords changed.
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

extension ChatScreen {
    // MARK: - Main Content Area

    @ViewBuilder var mainContentArea: some View {
        mainContentStack
            // How much machinery the chat shows (5.7): the step console, the badges under an answer and Fact Check's
            // numbers read it.
            .environment(\.showsTechnicalDetails, settings.showTechnicalDetails)
    }

    @ViewBuilder private var mainContentStack: some View {
        VStack(spacing: 0) {
            CompactChatHeader(
                containerService: ragService.containerService,
                docCount: activeDocCount,
                chunkCount: activeChunkCount,
                ragService: ragService,
                messageContainerOverride: $messageContainerOverride,
                onMaximumModeBlocked: presentMaximumModePaywall
            )

            // The stats bar is part of the technical view (5.7); the plain chat says what it is doing in the answer's
            // own bubble instead.
            if !settings.showTechnicalDetails {
                EmptyView()
            } else if let metricsData = consolidatedMetricsData {
                primaryMetricsBar(metricsData: metricsData)
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.bottom, DSSpacing.xs)
                    .transition(.opacity)
                    .animation(.easeInOut(duration: 0.15), value: metricsData.tokens)
            } else if isProcessing || currentRetrievedChunks.count > 0 {
                minimalMetricsBar()
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.bottom, DSSpacing.xs)
                    .transition(.opacity)
            }

            chatContentArea
            followUpSuggestionsBar
            unansweredQuestionBar

            Divider().opacity(0.5)

            ChatComposerV2(
                isProcessing: isProcessing,
                onSend: sendMessage,
                onStop: stopGeneration,
                onAttach: nil,
                onSendWithAttachments: sendMessageWithAttachments,
                onVisionCapture: visionCaptureAction,
                isCheckingAnswer: isCheckingFinishedAnswer && questionAfterCheck == nil,
                draft: composerDraft
            )
        }
    }

    /// Set when Apple's model can't be used, so the first thing an empty chat says is why written
    /// answers won't come and what still works. nil on a device where the model is available.
    private var appleIntelligenceNotice: String? {
        let capabilities = RAGService.checkDeviceCapabilities()
        return AppleIntelligenceCopy.notice(
            for: capabilities.foundationModelUnavailability,
            isAvailable: capabilities.supportsFoundationModels
        )
    }

    @ViewBuilder private var chatContentArea: some View {
        if shouldShowFirstQueryHero {
            ScrollView {
                FirstQueryPromptView(
                    hasDocuments: activeDocCount > 0,
                    modelNotice: appleIntelligenceNotice,
                    prompts: starterPrompts,
                    categories: starterQuestionDetails.mapValues(\.category),
                    questionDetails: starterQuestionDetails,
                    // The chips shown, not the library: after a document is added or removed the
                    // previous chips stay until the new ones arrive.
                    writtenForSamples: !starterPrompts.isEmpty
                        && starterPrompts.allSatisfy(SuggestedQuestionsService.curatedQuestionTexts.contains),
                    libraryDocumentCount: activeDocCount,
                    isRefreshing: isRefreshingSuggestions,
                    onPromptSelected: sendSuggestedPrompt,
                    onRefresh: { refreshSuggestedQuestions(force: true) }
                )
                .padding(.horizontal, DSSpacing.md)
                .padding(.vertical, DSSpacing.md)
            }
            .scrollDismissesKeyboard(.interactively)
            .onTapGesture {
                #if canImport(UIKit)
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
            }
        } else {
            MessageListV2(
                messages: $messages,
                thinkingEvents: $thinkingEvents,
                streamingText: streamingText,
                isStreaming: isProcessing,
                isCheckingAnswer: isCheckingFinishedAnswer,
                qualityMode: effectiveQualityMode,
                generationStart: generationStart,
                onRegenerate: { message in regenerateResponse(for: message) },
                onGoDeeper: { goDeeper() },
                onThumbsUp: {
                    #if canImport(FoundationModels)
                        if #available(iOS 26.0, *) {
                            ragService.submitPositiveFeedback()
                        }
                    #endif
                    DSHaptics.success()
                    // No review ask here: Apple says not to request one from a tap, and App Review Guideline
                    // 5.6.1 disallows custom review prompts (5.8). `ReviewPromptService` asks after an answer.
                },
                onThumbsDown: {
                    #if canImport(FoundationModels)
                        if #available(iOS 26.0, *) {
                            ragService.submitNegativeFeedback()
                        }
                    #endif
                    DSHaptics.warning()
                    showFeedbackEmailPrompt = true
                },
                onTranslate: { text in
                    translationText = text
                    showTranslation = true
                },
                onIllustrate: ImagePlaygroundService.shared.isAvailable ? { text in illustrate(text) } : nil,
                // Supplied here because this is where RAGService actually lives: it arrives through
                // this screen's init as an @ObservedObject, never through the environment. Reaching
                // for it with @EnvironmentObject inside the bubble crashed the app on 2026-08-19.
                libraryStateProvider: { containerId in
                    await ragService.libraryStateTraceBlock(for: containerId)
                }
            )
        }
    }

    @ViewBuilder private var followUpSuggestionsBar: some View {
        if !followUpSuggestions.isEmpty && !isProcessing {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.sm) {
                    ForEach(followUpSuggestions) { suggestion in
                        Button {
                            DSHaptics.selection()
                            followUpSuggestions = []
                            sendMessage(suggestion.text)
                        } label: {
                            HStack(spacing: DSSpacing.xxs) {
                                Image(systemName: suggestion.category.iconName)
                                    .font(.caption2)
                                Text(suggestion.text)
                                    .font(.caption)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, DSSpacing.md)
                            .padding(.vertical, DSSpacing.sm)
                            .background(DSColors.surface)
                            .foregroundStyle(DSColors.accent)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, DSSpacing.md)
            }
            .padding(.vertical, DSSpacing.xxs)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.25), value: followUpSuggestions.isEmpty)
        }
    }

    /// The chat's last message when it is a question with no answer and nothing is working on one (5.7). On the
    /// owner's iPhone (2026-10-21) a Deep Think question ended with the app in the background, and the reopened chat
    /// showed the question and nothing under it, with no way to get the answer but typing it again.
    private var unansweredQuestion: ChatMessage? {
        guard !isProcessing, !isCheckingFinishedAnswer, questionAfterCheck == nil,
            let last = messages.last, last.role == .user
        else { return nil }
        return last
    }

    @ViewBuilder private var unansweredQuestionBar: some View {
        if let question = unansweredQuestion {
            HStack(spacing: DSSpacing.sm) {
                Text("This answer didn't finish.")
                    .font(.caption)
                    .foregroundStyle(DSColors.secondaryText)
                Spacer(minLength: 0)
                Button {
                    DSHaptics.selection()
                    messages.removeAll { $0.id == question.id }
                    sendMessage(question.content)
                } label: {
                    HStack(spacing: DSSpacing.xxs) {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                        Text("Ask again")
                            .font(.caption)
                    }
                    .padding(.horizontal, DSSpacing.md)
                    .padding(.vertical, DSSpacing.sm)
                    .background(DSColors.surface)
                    .foregroundStyle(DSColors.accent)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.accentColor.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.xxs)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder var writingToolsProgressOverlay: some View {
        if writingToolsProcessing {
            VStack(spacing: DSSpacing.md) {
                Spacer()
                HStack(spacing: DSSpacing.sm) {
                    ProgressView().tint(.white)
                    Text("\(writingToolsTitle)…")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.md)
                .background(.ultraThinMaterial.opacity(0.95))
                .background(DSColors.accent.opacity(0.6))
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                .padding(.bottom, 100)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .transition(.opacity.combined(with: .scale(scale: 0.9)))
            .animation(DSAnimations.snappySpring, value: writingToolsProcessing)
        }
    }

}
