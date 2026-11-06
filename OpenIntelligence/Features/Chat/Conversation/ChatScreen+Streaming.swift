//
//  ChatScreen+Streaming.swift
//  OpenIntelligence
//
//  Part of ChatScreen, moved unchanged from ChatScreen.swift on 2026-11-05 (5.8 split).
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
    // MARK: - Streaming Cadence Helpers

    /// The answer's text has finished arriving and the pipeline is still checking it.
    ///
    /// The text stops before `RAGService.query` returns: the verification gates run after the
    /// last word, and so does the source-only check for an extractive question in Deep Think or
    /// Maximum, or in Standard when the gates flag the answer. Until 2026-09-23 Standard ran that
    /// check on every extractive answer, and four such questions measured on macOS that day sat
    /// 19 to 164 seconds past their last word behind a blinking cursor and a locked text field.
    /// While this is true the cursor goes, the bubble says it is checking sources, and the composer
    /// takes the next question.
    var isCheckingFinishedAnswer: Bool {
        isProcessing && isStreamFinished && streamingBuffer.isEmpty && streamingPumpTask == nil
            && !streamingText.isEmpty
    }

    /// Connects the 5 Hz tick that drives the elapsed-time readout.
    func startProcessingClock() {
        processingClockConnection?.cancel()
        processingClock = Timer.publish(every: 0.2, on: .main, in: .common)
        processingClockConnection = processingClock.connect()
        nowTick = Date()
    }

    /// Keeps what an answer had written when iOS ended the app's background time, and says why.
    ///
    /// The expiration handler cancels the query and, in the same main-actor turn, clears the session
    /// id, so the query's own error path finds a different id when it runs and saves nothing. An
    /// answer that stopped this way used to vanish without a word. The roadmap row "A long answer outlives its
    /// 30-second background grant" tracks keeping it running; this makes stopping visible.
    func keepAnswerStoppedByBackgroundExpiry() {
        guard isProcessing else { return }
        let containerId = currentQueryContainerId ?? ragService.containerService.activeContainerId
        let textWasComplete = isCheckingFinishedAnswer
        let reason = "iOS ended the app's background time before the answer finished. Ask again to finish it."
        flushStreamingBufferToVisibleText()
        let written = sanitizeFinalResponse(streamingText.trimmingCharacters(in: .whitespacesAndNewlines))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        // Always with the reason. `partialResponseMessageContent` drops the footer from a long
        // partial, which suits a Stop the person chose, not an answer iOS cut off. An answer whose
        // text was complete is not partial; what it lacks is the check and its sources.
        let content: String
        if written.isEmpty {
            content = reason
        } else if textWasComplete {
            content =
                written
                + "\n\n*(Saved without its sources: iOS ended the app's background time while they were being checked.)*"
        } else {
            content = written + "\n\n*(Partial answer. \(reason))*"
        }
        var notice = ChatMessage(role: .assistant, content: content)
        notice.containerId = containerId
        appendAndPersistMessage(notice, for: containerId)
        VerificationJournal.record(
            "answer.keptAfterExpiry",
            ["kept": written.isEmpty ? "empty" : textWasComplete ? "complete" : "partial",
                "chars": "\(written.count)", "inFront": "\(isAppeared)"])
        if !isAppeared {
            ChatAnswerNotice.shared.answerFinishedOffScreen()
        }
    }

    /// Clears any live streaming UI/buffer state (used before/after each query and on cancel).
    func resetStreamingState() {
        streamingPumpTask?.cancel()
        streamingPumpTask = nil
        streamingBuffer.removeAll(keepingCapacity: true)
        streamingText = ""
        hasReceivedStreamToken = false
        isStreamFinished = false
    }

    func cancelInFlightQueryWork(resetLLMSession: Bool = true) {
        continuedQueryCoordinator.cancelCurrentQuery()
        questionAfterCheck = nil
        currentQuerySessionId = nil
        currentQueryTask?.cancel()
        currentQueryTask = nil
        queryStart = nil
        ragService.cancelActiveGeneration(resetSession: resetLLMSession)
    }

    /// Queues incoming streamed text and starts the drip pump when idle.
    func enqueueStreamingText(_ incoming: String) {
        guard
            let sanitized = sanitizeStreamChunk(
                incoming,
                isFirstChunk: !hasReceivedStreamToken
            ), !sanitized.isEmpty
        else { return }
        streamingBuffer.append(sanitized)
        hasReceivedStreamToken = true
        if streamingPumpTask == nil {
            streamingPumpTask = Task { await pumpStreamingBuffer() }
        }
    }

    /// Forces any buffered characters to render immediately (typically when the stream closes).
    func flushStreamingBufferToVisibleText() {
        streamingPumpTask?.cancel()
        streamingPumpTask = nil
        guard !streamingBuffer.isEmpty else { return }
        streamingText.append(streamingBuffer)
        streamingBuffer.removeAll(keepingCapacity: true)
    }

    /// Drips buffered characters into the visible text at a steady cadence to avoid bursty dumps.
    @MainActor
    private func pumpStreamingBuffer(chunkSize: Int = 50, cadence: UInt64 = 80_000_000) async {
        defer { streamingPumpTask = nil }
        while !Task.isCancelled {
            guard !streamingBuffer.isEmpty else { return }
            let backlog = streamingBuffer.count
            let adaptiveChunkSize: Int
            let adaptiveCadence: UInt64

            if backlog > 1200 {
                adaptiveChunkSize = max(120, chunkSize)
                adaptiveCadence = 40_000_000
            } else if backlog > 400 {
                adaptiveChunkSize = max(80, chunkSize)
                adaptiveCadence = 60_000_000
            } else {
                adaptiveChunkSize = isStreamFinished ? max(100, chunkSize) : chunkSize
                adaptiveCadence = isStreamFinished ? 20_000_000 : cadence
            }

            let takeCount = min(adaptiveChunkSize, streamingBuffer.count)
            let nextChunk = String(streamingBuffer.prefix(takeCount))
            streamingBuffer.removeFirst(takeCount)

            // Force immediate UI update with explicit animation
            withAnimation(.linear(duration: 0.04)) {
                streamingText.append(nextChunk)
            }

            // Update speed history for the sparkline
            updateSpeedHistory()

            do {
                try await Task.sleep(nanoseconds: adaptiveCadence)
            } catch {
                return
            }
        }
    }

    /// Cleans streamed chunks before they reach the UI, stripping stray control characters and the recurring "null" artifact reported in the stream gutter.
    private func sanitizeStreamChunk(_ chunk: String, isFirstChunk: Bool) -> String? {
        guard !chunk.isEmpty else { return nil }

        // Remove null scalars and non-printable control characters while preserving whitespace/newlines for Markdown layout.
        var cleaned = chunk.replacingOccurrences(of: "\u{0000}", with: "")
        let disallowedControls = CharacterSet.controlCharacters.subtracting(.whitespacesAndNewlines)
        if cleaned.rangeOfCharacter(from: disallowedControls) != nil {
            cleaned = cleaned.components(separatedBy: disallowedControls).joined()
        }

        guard !cleaned.isEmpty else { return nil }

        // On the first chunk, strip common malformed prefixes that appear from certain LLM streams
        if isFirstChunk {
            // Pattern matches: "null", "(null)", "null -", "null:", "null\n", etc.
            if let range = cleaned.range(
                of: #"^\s*(?:\(null\)|null)[\s\-–—:]*"#,
                options: [.regularExpression, .caseInsensitive]
            ) {
                let removed = cleaned[range]
                cleaned = String(cleaned[range.upperBound...])
                let prefixSample = removed.trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefixSample.isEmpty {
                    Log.warning(
                        "Dropped malformed stream prefix: \(prefixSample)",
                        category: .streaming
                    )
                    TelemetryCenter.emit(
                        .system,
                        severity: .warning,
                        title: "Trimmed malformed stream prefix",
                        metadata: ["prefix": prefixSample]
                    )
                }
            }
        }

        // Also strip standalone "null" if the entire chunk is just "null"
        if cleaned.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "null" {
            Log.debug("Dropped standalone 'null' chunk", category: .streaming)
            return nil
        }

        return cleaned.isEmpty ? nil : cleaned
    }

    /// Sanitizes the final response text before displaying in message bubble.
    /// Strips leading "null" artifacts and other malformed prefixes.
    func sanitizeFinalResponse(_ text: String) -> String {
        var cleaned = text

        // Strip leading "null" or "(null)" with optional separator
        if let range = cleaned.range(
            of: #"^\s*(?:\(null\)|null)[\s\-–—:]*"#,
            options: [.regularExpression, .caseInsensitive]
        ) {
            let removed = cleaned[range]
            cleaned = String(cleaned[range.upperBound...])
            let prefixSample = removed.trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefixSample.isEmpty {
                Log.warning("Stripped malformed response prefix: \(prefixSample)", category: .llm)
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Returns the text to persist for an interrupted response.
    /// Strong partial answers are kept as-is; weak fragments stay visibly marked as partial.
    func partialResponseMessageContent(
        sanitizedPartial: String,
        failureMessage: String? = nil,
        userInitiatedStop: Bool = false
    ) -> String? {
        let cleaned = sanitizedPartial.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }

        if userInitiatedStop || shouldKeepPartialResponseAsAnswer(cleaned) {
            return cleaned
        }

        guard let failureMessage, !failureMessage.isEmpty else {
            return cleaned + "\n\n*(Partial answer)*"
        }

        return cleaned + "\n\n*(Partial answer. \(failureMessage))*"
    }

    /// Heuristic for deciding whether an interrupted response is already useful enough
    /// to keep without an inline failure footer.
    func shouldKeepPartialResponseAsAnswer(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 180 else { return false }

        let hasCitations = trimmed.range(of: #"\[S\d+\]"#, options: .regularExpression) != nil
        if hasCitations { return true }

        let sentenceCount =
            trimmed
            .components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 20 }
            .count

        if sentenceCount >= 4 { return true }
        if sentenceCount >= 3 && trimmed.count >= 240 { return true }

        let hasStructuredLayout =
            trimmed.contains("\n### ") || trimmed.contains("\n## ") || trimmed.contains("\n- ")
            || trimmed.contains("\n1. ")

        return hasStructuredLayout && sentenceCount >= 2 && trimmed.count >= 220
    }

    func userFacingErrorMessage(_ error: Error) -> String {
        if error is CancellationError {
            return "Generation canceled."
        }

        if let ragError = error as? RAGServiceError {
            switch ragError {
            case .emptyQuery:
                return "Type a question to get started."
            case .noDocumentsAvailable:
                return "No documents yet. Add files to enable grounded answers."
            case .noRelevantContext:
                return "I couldn't find relevant info in your library. Try rephrasing."
            case .retrievalFailed:
                return "Retrieval failed. Please try again."
            case .rebuildBlockedByQueue:
                // Names the reason rather than the failure, because this one is waitable: the
                // queue drains on its own and the rebuild then succeeds.
                return
                    "This library's search index needs rebuilding, but some documents are still importing. Try again once the import finishes."
            case .modelNotAvailable:
                return "The selected model isn't available right now."
            case .routingAbstained:
                // Deliberately does not blame the model. The planner declined to
                // route; the model is usually fine.
                return "I couldn't work out how to answer that from what your documents returned. Try rephrasing."
            case .maximumModeQuotaReached(let limit):
                return
                    "Maximum is capped at \(limit) uses per day on Free. Switch modes or upgrade for unlimited Maximum."
            case .cloudConsentDenied:
                return "Cloud processing was declined. Switch to on-device or try again."
            case .cloudConsentUnavailable:
                return "Cloud processing needs confirmation in the foreground. Open the app and try again."
            }
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet:
                return "You're offline. Reconnect and try again."
            case .timedOut:
                return "The request timed out. Please try again."
            default:
                return "Network error. Please try again."
            }
        }

        // Handle LLM-specific errors
        if let llmError = error as? LLMError {
            switch llmError {
            case .contextWindowExceeded:
                return "Deep Think ran too long. Try Standard mode or a shorter question."
            case .generationFailed(let message):
                if message.contains("decode") || message.contains("internal") {
                    return "AI processing limit reached. Try Standard mode instead."
                }
                return message
            case .modelUnavailable:
                // Says which of Apple's reasons applies. Until 5.6 every reason read "Enable it in
                // Settings.", including a device that cannot run Apple Intelligence at all.
                return AppleIntelligenceCopy.chatMessage(
                    for: RAGService.checkDeviceCapabilities().foundationModelUnavailability)
            case .notImplemented:
                return "This feature isn't available yet."
            case .rateLimited:
                return "AI is temporarily busy. Please wait a moment and try again."
            case .concurrentRequests:
                return "A request is already in progress. Please wait for it to finish."
            }
        }

        let message = error.localizedDescription.lowercased()
        if message.contains("exceededcontextwindowsize") {
            return "Deep Think ran too long. Try Standard mode or a shorter question."
        }
        if message.contains("decode") || message.contains("json") {
            return "AI processing limit reached. Try Standard mode instead."
        }

        return "Something went wrong. Please try again."
    }
}
