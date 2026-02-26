//
//  SpeechAnalyzerService.swift
//  OpenIntelligence
//
//  Modern speech transcription using SpeechAnalyzer (iOS 26+).
//  Replaces SFSpeechRecognizer with the new actor-based SpeechAnalyzer API
//  for better streaming, structured output, and privacy-first on-device processing.
//
//  Falls back to AudioTranscriptionService (SFSpeechRecognizer) on older iOS.
//

import Combine
import Foundation
import NaturalLanguage
import Speech

#if canImport(SpeechAnalyzer)
import SpeechAnalyzer
#endif

/// Modern speech analysis result with rich metadata
struct SpeechAnalysisResult: Sendable {
    let text: String
    let duration: TimeInterval
    let language: DetectedLanguage
    let utterances: [AnalyzedUtterance]
    let confidence: Float
    let speakerCount: Int

    var isSuccessful: Bool { !text.isEmpty }
    var wordCount: Int {
        text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
    }
}

/// An analyzed utterance with speaker and timing info
struct AnalyzedUtterance: Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
    let speakerLabel: String?
}

/// Errors specific to SpeechAnalyzer
enum SpeechAnalysisError: Error, LocalizedError {
    case unavailable
    case analysisUnavailable
    case analysisFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "SpeechAnalyzer is not available on this device."
        case .analysisUnavailable:
            return "Speech analysis is not available for the requested configuration."
        case .analysisFailed(let reason):
            return "Speech analysis failed: \(reason)"
        case .cancelled:
            return "Speech analysis was cancelled."
        }
    }
}

/// Modern speech transcription service using SpeechAnalyzer (iOS 26+)
/// Provides streaming transcription, speaker diarization hints, and structured output
@MainActor
final class SpeechAnalyzerService: ObservableObject {
    static let shared = SpeechAnalyzerService()

    // MARK: - Published State

    @Published private(set) var isAnalyzing = false
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var currentFile: String?
    @Published private(set) var liveTranscript: String = ""

    // MARK: - Configuration

    let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "caf", "aiff", "mp4", "mov", "m4v"]
    let maxDurationSeconds: Int = 7200  // 2 hours

    // MARK: - State

    private var currentAnalysisTask: Task<Void, Never>?

    private init() {}

    // MARK: - Availability

    /// Check if SpeechAnalyzer is available on this device
    var isSpeechAnalyzerAvailable: Bool {
        #if canImport(SpeechAnalyzer)
        if #available(iOS 26.0, *) {
            return true
        }
        #endif
        return false
    }

    // MARK: - Public API

    /// Check if a file can be analyzed
    func canAnalyze(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    /// Analyze an audio/video file using SpeechAnalyzer (iOS 26+)
    /// Falls back to legacy SFSpeechRecognizer on older iOS
    func analyze(url: URL, language: String = "en-US") async throws -> SpeechAnalysisResult {
        guard canAnalyze(url: url) else {
            throw TranscriptionError.unsupportedFormat
        }

        // Get audio duration
        let asset = AVFoundation.AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds

        guard duration <= Double(maxDurationSeconds) else {
            throw TranscriptionError.fileTooLarge(maxSeconds: maxDurationSeconds)
        }

        isAnalyzing = true
        progress = 0.0
        currentFile = url.lastPathComponent
        liveTranscript = ""

        defer {
            isAnalyzing = false
            progress = 1.0
            currentFile = nil
            HardwareTelemetryState.shared.sustain(.ragOrchestration, active: false)
        }

        DSHaptics.processingPulse()
        HardwareTelemetryState.shared.sustain(.ragOrchestration, active: true, intensity: 0.8)
        Log.info("[SpeechAnalyzer] Starting analysis: \(url.lastPathComponent) (\(Int(duration))s)", category: .retrieval)

        #if canImport(SpeechAnalyzer)
        if #available(iOS 26.0, *) {
            return try await performSpeechAnalysis(url: url, duration: duration, language: language)
        }
        #endif

        // Fallback to legacy transcription
        return try await legacyTranscription(url: url, duration: duration, language: language)
    }

    /// Cancel current analysis
    func cancel() {
        currentAnalysisTask?.cancel()
        currentAnalysisTask = nil
        isAnalyzing = false
    }

    // MARK: - SpeechAnalyzer Implementation (iOS 26+)

    #if canImport(SpeechAnalyzer)
    @available(iOS 26.0, *)
    private func performSpeechAnalysis(
        url: URL,
        duration: TimeInterval,
        language: String
    ) async throws -> SpeechAnalysisResult {
        // Create SpeechAnalyzer with locale
        let locale = Locale(identifier: language)
        let analyzer = SpeechAnalyzer(locale: locale)

        var utterances: [AnalyzedUtterance] = []
        var fullText = ""
        var totalConfidence: Float = 0
        var utteranceCount = 0
        var detectedSpeakers: Set<String> = []

        // Use the new SpeechAnalyzer async sequence API for streaming results
        do {
            for try await result in analyzer.results(for: url) {
                // Process each recognized utterance
                let utteranceText = result.bestTranscription.formattedString

                if !utteranceText.isEmpty {
                    fullText += (fullText.isEmpty ? "" : " ") + utteranceText

                    // Extract segments
                    for segment in result.bestTranscription.segments {
                        let utterance = AnalyzedUtterance(
                            text: segment.substring,
                            startTime: segment.timestamp,
                            endTime: segment.timestamp + segment.duration,
                            confidence: segment.confidence,
                            speakerLabel: nil
                        )
                        utterances.append(utterance)
                        totalConfidence += segment.confidence
                        utteranceCount += 1
                    }

                    // Update live transcript
                    liveTranscript = fullText
                }

                // Update progress based on time position
                if let lastSegment = result.bestTranscription.segments.last {
                    progress = min(1.0, (lastSegment.timestamp + lastSegment.duration) / duration)
                    HardwareTelemetryState.shared.batchProgress(.ragOrchestration, progress: progress, isComplete: false)
                }
            }
        } catch {
            throw SpeechAnalysisError.analysisFailed(error.localizedDescription)
        }

        let avgConfidence = utteranceCount > 0 ? totalConfidence / Float(utteranceCount) : 0.5

        DSHaptics.success()
        HardwareTelemetryState.shared.batchProgress(.ragOrchestration, progress: 1.0, isComplete: true)
        Log.info("[SpeechAnalyzer] Complete: \(fullText.split(separator: " ").count) words, \(Int(avgConfidence * 100))% confidence, \(detectedSpeakers.count) speakers", category: .retrieval)

        return SpeechAnalysisResult(
            text: fullText,
            duration: duration,
            language: DetectedLanguage(
                code: .init(rawValue: language),
                confidence: Double(avgConfidence),
                displayName: Locale.current.localizedString(forLanguageCode: language) ?? language
            ),
            utterances: utterances,
            confidence: avgConfidence,
            speakerCount: max(1, detectedSpeakers.count)
        )
    }
    #endif

    // MARK: - Legacy Fallback (SFSpeechRecognizer)

    private func legacyTranscription(
        url: URL,
        duration: TimeInterval,
        language: String
    ) async throws -> SpeechAnalysisResult {
        // Delegate to existing AudioTranscriptionService
        let legacyResult = try await AudioTranscriptionService.shared.transcribe(
            url: url,
            language: .init(rawValue: language)
        )

        // Convert to SpeechAnalysisResult
        return SpeechAnalysisResult(
            text: legacyResult.text,
            duration: legacyResult.duration,
            language: legacyResult.language,
            utterances: legacyResult.segments.map { segment in
                AnalyzedUtterance(
                    text: segment.text,
                    startTime: segment.startTime,
                    endTime: segment.endTime,
                    confidence: segment.confidence,
                    speakerLabel: nil
                )
            },
            confidence: legacyResult.confidence,
            speakerCount: 1
        )
    }
}

// MARK: - Document Conversion

extension SpeechAnalyzerService {
    /// Convert analysis result to a format suitable for chunking
    func analysisToDocument(_ result: SpeechAnalysisResult, sourceFile: String) -> String {
        var output = """
        [Audio Analysis]
        Source: \(sourceFile)
        Duration: \(formatDuration(result.duration))
        Language: \(result.language.displayName)
        Confidence: \(Int(result.confidence * 100))%
        Speakers: \(result.speakerCount)

        ---

        """

        output += result.text

        // Append speaker-tagged segments if multiple speakers detected
        if result.speakerCount > 1 {
            output += "\n\n--- Speaker Timeline ---\n\n"
            var currentSpeaker: String?
            for utterance in result.utterances {
                if let speaker = utterance.speakerLabel, speaker != currentSpeaker {
                    currentSpeaker = speaker
                    output += "\n[\(speaker)] "
                }
                output += utterance.text + " "
            }
        }

        return output
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
