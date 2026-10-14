//
//  VoiceDictation.swift
//  OpenIntelligence
//

import AVFoundation
import Combine
import Foundation
import Speech

/// Speaking a question into the chat field, with Apple's on-device dictation transcriber (5.7).
///
/// Settings described the app's speech feature as "Audio transcription & voice input", and the
/// microphone permission text said "Record voice queries or dictate text", but through 5.6 the app
/// had no microphone code (backlog row a60d2bf8ab4f428194d7d373c7c8b347). The field's microphone
/// button starts this; the words appear as they are recognised and a second tap stops it. Nothing
/// is sent until the person sends it, and the audio and the text stay on the device:
/// `DictationTranscriber` runs on the device, and the model it needs is one of Apple's system
/// assets (`AssetInventory`), downloaded by the system the first time.
@MainActor
final class VoiceDictation: ObservableObject {
    enum Phase: Equatable {
        case idle
        /// Asking for the microphone, or for the system to install the dictation model.
        case preparing
        case listening
    }

    enum Problem: Error, Equatable {
        case microphoneDenied
        case languageUnsupported
        case unavailable(String)

        var message: String {
            switch self {
            case .microphoneDenied:
                #if os(iOS)
                    return
                        "OpenIntelligence doesn't have access to the microphone. Turn it on in Settings > Privacy & Security > Microphone."
                #else
                    return
                        "OpenIntelligence doesn't have access to the microphone. Turn it on in System Settings > Privacy & Security > Microphone."
                #endif
            case .languageUnsupported:
                return "Dictation isn't available in your device's language."
            case .unavailable(let reason):
                return "Dictation couldn't start. \(reason)"
            }
        }
    }

    @Published private(set) var phase: Phase = .idle
    @Published var problem: Problem?

    /// Called with everything recognised so far, each time it changes.
    var onText: ((String) -> Void)?

    private var finished = ""
    private var inProgress = ""
    private let engine = AVAudioEngine()
    private var analyzer: SpeechAnalyzer?
    private var input: AsyncStream<AnalyzerInput>.Continuation?
    private var results: Task<Void, Never>?
    /// A stop that came while dictation was still preparing; `start` honours it before listening.
    private var stopRequested = false

    func start() async {
        guard phase == .idle else { return }
        problem = nil
        finished = ""
        inProgress = ""
        stopRequested = false
        phase = .preparing
        do {
            guard await AVAudioApplication.requestRecordPermission() else { throw Problem.microphoneDenied }
            guard let locale = await DictationTranscriber.supportedLocale(equivalentTo: Locale.current) else {
                throw Problem.languageUnsupported
            }
            let transcriber = DictationTranscriber(locale: locale, preset: .progressiveShortDictation)
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await installation.downloadAndInstall()
            }
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber]) else {
                throw Problem.unavailable("The microphone's audio can't be read.")
            }
            let analyzer = SpeechAnalyzer(modules: [transcriber])
            try await analyzer.prepareToAnalyze(in: format)
            let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
            // Kept before anything can fail or be stopped, so the stream is always finished.
            self.analyzer = analyzer
            self.input = continuation
            results = Task { [weak self] in
                do {
                    for try await result in transcriber.results {
                        self?.take(String(result.text.characters), isFinal: result.isFinal)
                    }
                } catch {
                    Log.warning("[Dictation] Results ended: \(error.localizedDescription)", category: .ui)
                }
            }
            guard !stopRequested else { throw CancellationError() }
            try startAudio(convertingTo: format, into: continuation)
            try await analyzer.start(inputSequence: stream)
            guard !stopRequested else { throw CancellationError() }
            phase = .listening
            Log.info("[Dictation] Listening (\(locale.identifier))", category: .ui)
        } catch {
            stopAudio()
            input?.finish()
            input = nil
            if let analyzer {
                await analyzer.cancelAndFinishNow()
            }
            analyzer = nil
            results?.cancel()
            results = nil
            if !(error is CancellationError) {
                problem = (error as? Problem) ?? .unavailable(error.localizedDescription)
            }
            phase = .idle
            Log.warning("[Dictation] Could not start: \(error.localizedDescription)", category: .ui)
        }
    }

    /// Stops listening, waits for the last words to be recognised, and leaves the text in the field.
    func stop() async {
        guard phase != .idle else { return }
        // Still preparing: `start` stops itself at its next step and cleans up.
        guard phase == .listening else {
            stopRequested = true
            return
        }
        stopAudio()
        input?.finish()
        input = nil
        // The last words normally arrive at once. If they do not within `finishingLimit`, the
        // analysis is cancelled, so the button does not stay on "Stop dictation".
        let analyzer = self.analyzer
        let results = self.results
        let deadline = Task {
            try? await Task.sleep(for: Self.finishingLimit)
            guard !Task.isCancelled else { return }
            Log.warning("[Dictation] The last words did not arrive in time; stopped", category: .ui)
            results?.cancel()
            await analyzer?.cancelAndFinishNow()
        }
        if let analyzer {
            do {
                try await analyzer.finalizeAndFinishThroughEndOfInput()
            } catch {
                await analyzer.cancelAndFinishNow()
            }
        }
        await results?.value
        deadline.cancel()
        self.results = nil
        self.analyzer = nil
        phase = .idle
    }

    static let finishingLimit: Duration = .seconds(3)

    private func take(_ text: String, isFinal: Bool) {
        if isFinal {
            finished = Self.joined(finished, text)
            inProgress = ""
        } else {
            inProgress = text
        }
        onText?(Self.joined(finished, inProgress))
    }

    /// Two pieces of text with one space between them, either of which may be empty.
    nonisolated static func joined(_ first: String, _ second: String) -> String {
        let a = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = second.trimmingCharacters(in: .whitespacesAndNewlines)
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return a + " " + b
    }

    // MARK: - Audio

    private func startAudio(
        convertingTo format: AVAudioFormat, into continuation: AsyncStream<AnalyzerInput>.Continuation
    ) throws {
        #if os(iOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
        let node = engine.inputNode
        let inputFormat = node.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, let converter = AVAudioConverter(from: inputFormat, to: format) else {
            throw Problem.unavailable("The microphone's audio can't be read.")
        }
        node.installTap(
            onBus: 0, bufferSize: 4096, format: inputFormat,
            block: Self.tapBlock(converter: converter, target: format, continuation: continuation))
        engine.prepare()
        try engine.start()
    }

    private func stopAudio() {
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        #if os(iOS)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }

    /// The tap runs on the audio thread, so it is built here, outside the main actor: it converts
    /// each buffer to the transcriber's format and hands it on.
    nonisolated private static func tapBlock(
        converter: AVAudioConverter, target: AVAudioFormat, continuation: AsyncStream<AnalyzerInput>.Continuation
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            let ratio = target.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var handedOver = false
            var failure: NSError?
            _ = converter.convert(to: converted, error: &failure) { _, status in
                if handedOver {
                    status.pointee = .noDataNow
                    return nil
                }
                handedOver = true
                status.pointee = .haveData
                return buffer
            }
            guard failure == nil, converted.frameLength > 0 else { return }
            continuation.yield(AnalyzerInput(buffer: converted))
        }
    }
}
