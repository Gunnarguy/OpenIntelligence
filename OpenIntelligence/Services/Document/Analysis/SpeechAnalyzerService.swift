//
//  SpeechAnalyzerService.swift
//  OpenIntelligence
//
//  Transcribes a recording with `SpeechAnalyzer` and `SpeechTranscriber`, Apple's long-form
//  on-device transcriber (iOS 26, macOS 26), and with `AudioTranscriptionService`
//  (`SFSpeechRecognizer`, also on device) when that one cannot take the file.
//
//  Through 5.6 the first path sat behind `#if canImport(SpeechAnalyzer)`. No module has that name:
//  the type is in `Speech`. So the condition was never true, the code under it was never compiled,
//  and every recording went to the older recognizer. What was under it also called methods the
//  framework does not have (`SpeechAnalyzer(locale:)`, `results(for:)`).
//

import AVFoundation
import Combine
import CoreMedia
import Foundation
import NaturalLanguage
import Speech

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

    /// Whether the long-form transcriber exists on this device. A language's model can still be
    /// missing; `analyze` finds that out per file.
    var isSpeechAnalyzerAvailable: Bool {
        SpeechTranscriber.isAvailable
    }

    // MARK: - Public API

    /// Check if a file can be analyzed
    func canAnalyze(url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return supportedExtensions.contains(ext)
    }

    /// Transcribes an audio or video file: with `SpeechTranscriber` when it can take the file, and
    /// with the older recognizer otherwise, or when the first attempt fails.
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

        do {
            if let result = try await performSpeechAnalysis(url: url, duration: duration, language: language) {
                return result
            }
            Log.info(
                "[SpeechAnalyzer] Not used for \(url.lastPathComponent): using the older recognizer",
                category: .retrieval)
        } catch is CancellationError {
            // Unchanged, so the import's own `catch is CancellationError` sees it.
            throw CancellationError()
        } catch {
            // A cancelled import does not start a second transcription.
            if Task.isCancelled { throw CancellationError() }
            // The import is not lost to a failure of the newer path.
            Log.warning(
                "[SpeechAnalyzer] Failed on \(url.lastPathComponent) (\(error.localizedDescription)): "
                    + "using the older recognizer",
                category: .retrieval)
        }

        return try await legacyTranscription(url: url, duration: duration, language: language)
    }

    /// Cancel current analysis
    func cancel() {
        currentAnalysisTask?.cancel()
        currentAnalysisTask = nil
        isAnalyzing = false
    }

    // MARK: - SpeechAnalyzer and SpeechTranscriber

    /// Returns nil when this path cannot take the file here: the transcriber is not on the device,
    /// the language is not one it supports, the language's model would have to be downloaded first,
    /// or the file does not open as audio. The caller then uses the older recognizer.
    ///
    /// A missing model is not downloaded from here. `AssetInventory.assetInstallationRequest`
    /// returns a request only when something has to be installed; `AssetInventory.status` read
    /// "supported" on a Mac whose English model was installed and transcribing (measured
    /// 2026-10-09), so the request is the test.
    private func performSpeechAnalysis(
        url: URL,
        duration: TimeInterval,
        language: String
    ) async throws -> SpeechAnalysisResult? {
        // The framework asks no permission to transcribe a file on the device. The app still keeps
        // to the answer the person gave it: only when Speech Recognition is allowed. Anything else
        // goes to the older path, which asks, or throws on a refusal, as it did through 5.6.
        guard SFSpeechRecognizer.authorizationStatus() == .authorized,
            SpeechTranscriber.isAvailable,
            let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: language))
        else { return nil }

        let transcriber = SpeechTranscriber(
            locale: locale,
            transcriptionOptions: [],
            reportingOptions: [],
            attributeOptions: [.transcriptionConfidence]
        )
        guard try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) == nil else { return nil }
        guard let audioFile = try? AVAudioFile(forReading: url) else { return nil }

        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let collecting = Task { () throws -> [AnalyzedUtterance] in
            var utterances: [AnalyzedUtterance] = []
            for try await result in transcriber.results where result.isFinal {
                let text = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let confidences = result.text.runs.compactMap { $0.transcriptionConfidence }
                let confidence = confidences.isEmpty ? 0 : confidences.reduce(0, +) / Double(confidences.count)
                let utterance = AnalyzedUtterance(
                    text: text,
                    startTime: result.range.start.seconds,
                    endTime: result.range.end.seconds,
                    confidence: Float(confidence),
                    speakerLabel: nil
                )
                utterances.append(utterance)
                self.noteTranscribed(utterance, duration: duration)
            }
            return utterances
        }

        do {
            if let lastSample = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: lastSample)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            // Ends the results sequence, so the collecting task cannot wait forever.
            await analyzer.cancelAndFinishNow()
            collecting.cancel()
            throw error
        }
        let utterances = try await collecting.value

        let fullText = utterances.map(\.text).joined(separator: " ")
        let avgConfidence =
            utterances.isEmpty ? 0 : utterances.map(\.confidence).reduce(0, +) / Float(utterances.count)

        HardwareTelemetryState.shared.batchProgress(.ragOrchestration, progress: 1.0, isComplete: true)
        if utterances.isEmpty {
            // Nothing was said in the recording. The importer turns an empty result into an error;
            // it is not announced as a success here.
            Log.info("[SpeechAnalyzer] No speech found in \(url.lastPathComponent)", category: .retrieval)
        } else {
            DSHaptics.success()
            Log.info(
                "[SpeechAnalyzer] Complete: \(fullText.split(separator: " ").count) words in "
                    + "\(utterances.count) utterance(s), \(Int(avgConfidence * 100))% confidence",
                category: .retrieval)
        }

        let languageCode = locale.language.languageCode?.identifier ?? language
        return SpeechAnalysisResult(
            text: fullText,
            duration: duration,
            language: DetectedLanguage(
                code: .init(rawValue: languageCode),
                confidence: Double(avgConfidence),
                displayName: Locale.current.localizedString(forLanguageCode: languageCode) ?? language
            ),
            utterances: utterances,
            confidence: avgConfidence,
            speakerCount: 1
        )
    }

    private func noteTranscribed(_ utterance: AnalyzedUtterance, duration: TimeInterval) {
        liveTranscript += (liveTranscript.isEmpty ? "" : " ") + utterance.text
        guard duration > 0 else { return }
        progress = min(1.0, utterance.endTime / duration)
        HardwareTelemetryState.shared.batchProgress(.ragOrchestration, progress: progress, isComplete: false)
    }

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
        var header = [
            "[Audio Analysis]",
            "Source: \(sourceFile)",
            "Duration: \(formatDuration(result.duration))",
            "Language: \(result.language.displayName)",
        ]
        // Zero means the transcriber reported no confidence. A figure nobody measured is not indexed.
        if result.confidence > 0 {
            header.append("Confidence: \(Int(result.confidence * 100))%")
        }
        header.append("Speakers: \(result.speakerCount)")
        var output = header.joined(separator: "\n") + "\n\n---\n"

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
