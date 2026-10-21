import AVFoundation
import CoreMedia
import Speech
import XCTest

@testable import OpenIntelligenceEngine

/// Transcription of real speech. `testSilentAudio_FailsLoudlyInsteadOfProducingAnEmptyDocument`
/// only proves that nothing-to-transcribe throws; until these tests no automated test showed that
/// speech comes back as words.
///
/// The fixture `Fixtures/spoken_fox_sentence.wav` was made on a Mac with the system voice:
/// `say -o fox.aiff "The quick brown fox jumps over the lazy dog. Please transcribe this sentence
/// about the apple orchard."` then `afconvert -f WAVE -d LEI16@16000 -c 1 fox.aiff
/// spoken_fox_sentence.wav` (5.7 s, 16 kHz mono). The assertion is word overlap, not an exact
/// match, because recogniser output varies with the OS version and the installed model.
///
/// Both tests skip, with the reason, when this machine cannot transcribe: no speech model for the
/// language yet (a new simulator downloads it first), or Speech Recognition not allowed to the
/// test host (the Simulator cannot be granted it).
@MainActor
final class SpeechTranscriptionTests: XCTestCase {

    private static let expectedWords: Set<String> = [
        "quick", "brown", "fox", "jumps", "lazy", "dog", "transcribe", "sentence", "apple", "orchard",
    ]
    private static let minimumMatches = 6

    private func fixtureURL() throws -> URL {
        let bundle = Bundle(for: Self.self)
        if let url = bundle.url(forResource: "spoken_fox_sentence", withExtension: "wav") {
            return url
        }
        if let url = bundle.url(
            forResource: "spoken_fox_sentence", withExtension: "wav", subdirectory: "Fixtures")
        {
            return url
        }
        throw XCTSkip("spoken_fox_sentence.wav is not in the test bundle.")
    }

    private func matchedWords(in text: String) -> Set<String> {
        let spoken = Set(
            text.lowercased().components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
        return Self.expectedWords.intersection(spoken)
    }

    private func assertSpeech(_ text: String, via path: String, file: StaticString = #filePath, line: UInt = #line) {
        let matched = matchedWords(in: text)
        XCTAssertGreaterThanOrEqual(
            matched.count, Self.minimumMatches,
            "\(path) returned \"\(text)\", which holds \(matched.count) of \(Self.expectedWords.count) "
                + "spoken words (\(matched.sorted())).",
            file: file, line: line)
    }

    /// Throws XCTSkip unless the on-device model for English is installed and usable.
    private func englishTranscriberOrSkip() async throws -> SpeechTranscriber {
        guard SpeechTranscriber.isAvailable else {
            throw XCTSkip("SpeechTranscriber is not available on this device.")
        }
        guard let locale = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US"))
        else {
            throw XCTSkip("SpeechTranscriber supports no English locale here.")
        }
        let transcriber = SpeechTranscriber(
            locale: locale, transcriptionOptions: [], reportingOptions: [], attributeOptions: [])
        // `AssetInventory.status` has read "supported" on a Mac whose model was installed and
        // working (measured 2026-10-09), so the installation request is the test, as in the app.
        let request: AssetInstallationRequest?
        do {
            request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber])
        } catch {
            throw XCTSkip("The speech model state could not be read: \(error.localizedDescription)")
        }
        if request != nil {
            throw XCTSkip("The English speech model is not installed on this machine yet.")
        }
        return transcriber
    }

    /// The transcriber the app uses, fed the fixture the way the app's fallback feeds it. Needs no
    /// Speech Recognition permission, so it runs in the Simulator whenever the model is there.
    func testSpokenSentence_TranscribesWithSpeechTranscriber() async throws {
        let url = try fixtureURL()
        let transcriber = try await englishTranscriberOrSkip()
        let audioFile = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let collecting = Task { () throws -> String in
            var pieces: [String] = []
            for try await result in transcriber.results where result.isFinal {
                pieces.append(String(result.text.characters))
            }
            return pieces.joined(separator: " ")
        }
        do {
            if let last = try await analyzer.analyzeSequence(from: audioFile) {
                try await analyzer.finalizeAndFinish(through: last)
            } else {
                await analyzer.cancelAndFinishNow()
            }
        } catch {
            await analyzer.cancelAndFinishNow()
            collecting.cancel()
            throw XCTSkip("SpeechTranscriber could not run here: \(error.localizedDescription)")
        }
        let text = try await collecting.value
        assertSpeech(text, via: "SpeechTranscriber")
    }

    /// The app's own `SpeechAnalyzerService`, end to end on the fixture.
    func testSpokenSentence_TranscribesThroughSpeechAnalyzerService() async throws {
        let url = try fixtureURL()
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw XCTSkip(
                "Speech Recognition is not authorized for the test host (the Simulator cannot be "
                    + "granted it); SpeechAnalyzerService uses the transcriber only when it is.")
        }
        _ = try await englishTranscriberOrSkip()

        let service = SpeechAnalyzerService.shared
        XCTAssertTrue(service.canAnalyze(url: url))
        let result = try await service.analyze(url: url, language: "en-US")
        XCTAssertTrue(result.isSuccessful, "The service returned an empty transcript for spoken audio.")
        XCTAssertFalse(result.utterances.isEmpty)
        assertSpeech(result.text, via: "SpeechAnalyzerService")
        XCTAssertEqual(result.duration, 5.7, accuracy: 0.5)
    }
}
