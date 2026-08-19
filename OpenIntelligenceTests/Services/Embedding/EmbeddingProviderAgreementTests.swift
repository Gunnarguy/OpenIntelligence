//
//  EmbeddingProviderAgreementTests.swift
//  OpenIntelligenceTests
//
//  Pins the invariant that both embedding providers compute the same thing.
//

@testable import OpenIntelligence
import XCTest

/// Core AI and Core ML run the same MiniLM weights. After the mean-pooling re-export they should
/// also pool the same way, so the same text must produce nearly the same vector from either.
///
/// This is the check that actually validates the re-export. Confirming the exported graph declares
/// an `attention_mask` input proves the graph shape; it does not prove the numbers. Two providers
/// agreeing from identical weights does.
///
/// Before the re-export this test would have failed loudly: Core AI read `last_hidden_state[:, 0, :]`,
/// the CLS token, while Core ML mean-pooled over the attention mask. Same weights, genuinely
/// different vectors — the difference measured at `vector r@1` 0.000 to 0.571.
///
/// **This skips in the simulator and that is not a timing problem.** `CoreAISentenceEmbeddingProvider`
/// resolves its model resource at line 78; when that lookup fails it sets `isModelLoadingFailed`
/// before attempting a load, and `isAvailable` is `!isModelLoadingFailed`. A device capture on
/// 2026-08-18 shows the other side of it: `Created .aimodel symlink`, `Loaded Core AI model
/// successfully`, `available: true`. So the tokenizer loads in both places and the model only loads
/// on hardware.
///
/// The consequence is that **the re-export is not validated by CI**, and cannot be. Run this on a
/// device before trusting the vectors:
///
///     xcodebuild test -scheme OpenIntelligence \
///       -destination 'platform=iOS,id=<device-udid>' \
///       -only-testing:OpenIntelligenceTests/EmbeddingProviderAgreementTests
///
/// A skip here means "unverified", never "fine".
final class EmbeddingProviderAgreementTests: XCTestCase {

    private static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return .nan }
        var dot: Float = 0, na: Float = 0, nb: Float = 0
        for i in a.indices {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        guard na > 0, nb > 0 else { return .nan }
        return dot / (sqrt(na) * sqrt(nb))
    }

    /// Texts chosen to exercise the padding path, which is what the attention mask exists for.
    /// A two-word input pads with ~510 `[PAD]` tokens; if the mask is ignored those dominate the
    /// average and short inputs collapse toward each other regardless of content.
    private let probes = [
        "dopamine",
        "Dopamine modulates social behavior.",
        "Transient and sustained effects of dopamine and serotonin signaling in the nucleus accumbens during social conditioning and learned helplessness in a rodent model.",
    ]

    func testCoreAIAndCoreMLAgreeOnTheSameText() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else {
            throw XCTSkip("Core AI requires iOS/macOS 27")
        }

        let coreML = CoreMLSentenceEmbeddingProvider()
        guard coreML.isAvailable else { throw XCTSkip("Core ML embedding model not present") }

        let coreAI = CoreAISentenceEmbeddingProvider()
        guard coreAI.isAvailable else { throw XCTSkip("Core AI embedding model not available here") }

        XCTAssertEqual(
            coreML.poolingRecipe, coreAI.poolingRecipe,
            "The two providers declare different pooling. They run the same weights, so this is the "
                + "CLS-versus-mean-pooling defect either unfixed or reintroduced."
        )

        for text in probes {
            let a = try await coreML.embed(text: text)
            let b = try await coreAI.embed(text: text)
            XCTAssertEqual(a.count, b.count, "dimension mismatch for \(text.prefix(30))")

            let sim = Self.cosine(a, b)
            XCTAssertGreaterThan(
                sim, 0.99,
                "Providers disagree on \"\(text.prefix(40))\" (cosine \(sim)). Same weights should "
                    + "give the same vector; a low value here means the pooling still differs."
            )
        }
    }

    /// The mask's own job, testable without a second provider.
    ///
    /// If padding is being averaged in, every short text drifts toward the same `[PAD]`-dominated
    /// point and distinct short inputs stop being distinguishable. This is the failure the mask
    /// prevents, and it is the one that is invisible in a dimension or norm check.
    func testShortTextsRemainDistinguishable() async throws {
        guard #available(iOS 27.0, macOS 27.0, *) else {
            throw XCTSkip("Core AI requires iOS/macOS 27")
        }
        let coreAI = CoreAISentenceEmbeddingProvider()
        guard coreAI.isAvailable else { throw XCTSkip("Core AI embedding model not available here") }

        let a = try await coreAI.embed(text: "dopamine")
        let b = try await coreAI.embed(text: "quarterly capital expenditure")
        let sim = Self.cosine(a, b)

        XCTAssertLessThan(
            sim, 0.95,
            "Two unrelated short texts embedded at cosine \(sim). That is the signature of padding "
                + "dominating the mean, i.e. the attention mask not reaching the graph."
        )
    }
}
