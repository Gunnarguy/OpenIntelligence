//
//  AudioTranscriptionService.swift
//  OpenIntelligence
//
//  Transcribe audio and video files for RAG indexing using Speech.framework.
//  Supports: Voice memos, meeting recordings, podcasts, video narration.
//

import AVFoundation
import Combine
import Foundation
import NaturalLanguage
import Speech

/// Result of audio transcription
struct TranscriptionResult: Sendable {
    let text: String
    let duration: TimeInterval
    let language: DetectedLanguage
    let segments: [TranscriptionSegment]
    let confidence: Float

    /// Whether transcription was successful
    var isSuccessful: Bool { !text.isEmpty }

    /// Word count for chunk estimation
    var wordCount: Int {
        text.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
    }
}

/// A time-stamped segment of transcription
struct TranscriptionSegment: Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let confidence: Float
}

/// Errors during transcription
enum TranscriptionError: Error, LocalizedError {
    case authorizationDenied
    case recognizerUnavailable
    case unsupportedFormat
    case fileTooLarge(maxSeconds: Int)
    case transcriptionFailed(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            return "Speech recognition permission denied. Enable in Settings → Privacy → Speech Recognition."
        case .recognizerUnavailable:
            return "Speech recognizer not available for this language."
        case .unsupportedFormat:
            return "Unsupported audio format. Supported: M4A, MP3, WAV, CAF, MP4, MOV."
        case let .fileTooLarge(max):
            return "Audio file too long. Maximum duration: \(max / 60) minutes."
        case let .transcriptionFailed(reason):
            return "Transcription failed: \(reason)"
        case .cancelled:
            return "Transcription was cancelled."
        }
    }
}

/// Service for transcribing audio/video files to text
@MainActor
final class AudioTranscriptionService: ObservableObject {
    static let shared = AudioTranscriptionService()

    // MARK: - Published State

    @Published private(set) var isTranscribing = false
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var currentFile: String?

    // MARK: - Configuration

    /// Maximum audio duration (10 minutes default)
    let maxDurationSeconds: Int = 600

    /// Supported file extensions
    let supportedExtensions: Set<String> = ["m4a", "mp3", "wav", "caf", "aiff", "mp4", "mov", "m4v"]

    // MARK: - State

    private var currentTask: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    private init() {
        // Default to English recognizer
        recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    // MARK: - Authorization

    /// Check if speech recognition is authorized
    func checkAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    /// Request authorization if not already granted
    func requestAuthorization() async throws {
        let status = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        switch status {
        case .authorized:
            return
        case .denied, .restricted:
            throw TranscriptionError.authorizationDenied
        case .notDetermined:
            throw TranscriptionError.authorizationDenied
        @unknown default:
            throw TranscriptionError.authorizationDenied
        }
    }

    // MARK: - Public API

    /// Check if a file can be transcribed
    func canTranscribe(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    /// Transcribe an audio or video file
    func transcribe(url: URL, language: NLLanguage = .english) async throws -> TranscriptionResult {
        // Validate authorization
        try await requestAuthorization()

        // Validate file type
        guard canTranscribe(url: url) else {
            throw TranscriptionError.unsupportedFormat
        }

        // Get audio duration
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds

        guard duration <= Double(maxDurationSeconds) else {
            throw TranscriptionError.fileTooLarge(maxSeconds: maxDurationSeconds)
        }

        // Set up recognizer for the target language
        let locale = Locale(identifier: language.rawValue)
        if let speechRecognizer = SFSpeechRecognizer(locale: locale),
           speechRecognizer.isAvailable
        {
            recognizer = speechRecognizer
        } else {
            // Fall back to English if target language unavailable
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            guard recognizer?.isAvailable == true else {
                throw TranscriptionError.recognizerUnavailable
            }
            Log.warning("[AudioTranscription] Language \(language.rawValue) unavailable, falling back to English", category: .retrieval)
        }

        // Update UI state
        isTranscribing = true
        progress = 0.0
        currentFile = url.lastPathComponent

        defer {
            isTranscribing = false
            progress = 1.0
            currentFile = nil
        }

        Log.info("[AudioTranscription] Starting transcription: \(url.lastPathComponent) (\(Int(duration))s)", category: .retrieval)

        // Perform transcription
        let result = try await performTranscription(url: url, duration: duration, language: language)

        Log.info("[AudioTranscription] Complete: \(result.wordCount) words, \(Int(result.confidence * 100))% confidence", category: .retrieval)

        return result
    }

    /// Cancel current transcription
    func cancel() {
        currentTask?.cancel()
        currentTask = nil
        isTranscribing = false
    }

    // MARK: - Private Implementation

    private func performTranscription(
        url: URL,
        duration: TimeInterval,
        language: NLLanguage
    ) async throws -> TranscriptionResult {
        guard let recognizer = recognizer else {
            throw TranscriptionError.recognizerUnavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true // Privacy: always on-device

        // Add context hints if available
        request.taskHint = .dictation

        return try await withCheckedThrowingContinuation { continuation in
            var segments: [TranscriptionSegment] = []
            var totalConfidence: Float = 0
            var segmentCount = 0

            currentTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                if let error = error {
                    let nsError = error as NSError
                    if nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1 {
                        // User cancelled
                        continuation.resume(throwing: TranscriptionError.cancelled)
                    } else {
                        continuation.resume(throwing: TranscriptionError.transcriptionFailed(error.localizedDescription))
                    }
                    return
                }

                guard let result = result else { return }

                // Update progress based on transcribed segments
                if result.isFinal {
                    // Extract segments with timestamps
                    for segment in result.bestTranscription.segments {
                        segments.append(TranscriptionSegment(
                            text: segment.substring,
                            startTime: segment.timestamp,
                            endTime: segment.timestamp + segment.duration,
                            confidence: segment.confidence
                        ))
                        totalConfidence += segment.confidence
                        segmentCount += 1
                    }

                    let avgConfidence = segmentCount > 0 ? totalConfidence / Float(segmentCount) : 0.5

                    let transcriptionResult = TranscriptionResult(
                        text: result.bestTranscription.formattedString,
                        duration: duration,
                        language: DetectedLanguage(
                            code: language,
                            confidence: Double(avgConfidence),
                            displayName: Locale.current.localizedString(forLanguageCode: language.rawValue) ?? language.rawValue
                        ),
                        segments: segments,
                        confidence: avgConfidence
                    )

                    continuation.resume(returning: transcriptionResult)
                } else {
                    // Update progress
                    Task { @MainActor in
                        self?.progress = Double(result.bestTranscription.segments.count) / max(1, duration / 2)
                    }
                }
            }
        }
    }
}

// MARK: - DocumentProcessor Extension

extension AudioTranscriptionService {
    /// Convert transcription to a format suitable for chunking
    func transcriptionToDocument(_ result: TranscriptionResult, sourceFile: String) -> String {
        var output = """
        [Audio Transcription]
        Source: \(sourceFile)
        Duration: \(formatDuration(result.duration))
        Language: \(result.language.displayName)
        Confidence: \(Int(result.confidence * 100))%

        ---

        """

        output += result.text

        return output
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}
