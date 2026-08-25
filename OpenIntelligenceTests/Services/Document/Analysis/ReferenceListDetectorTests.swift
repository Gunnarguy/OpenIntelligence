import XCTest
@testable import OpenIntelligenceEngine

/// Pins `ReferenceListDetector`, which two subsystems depend on for opposite reasons:
/// `RAGEngine` demotes reference chunks during reranking, and `ContentTaggingService`
/// excludes them from the chunks it samples to generate a document's tags.
///
/// Most of these assert text is **not** a reference list. Over-triggering is the more
/// expensive failure: it would demote a real methods section and strip legitimate
/// chunks out of tag sampling.
final class ReferenceListDetectorTests: XCTestCase {

    // MARK: - Must be detected

    /// Close to the chunk that produced the tags `cho`, `merten`, `zeng` on device.
    func testDetectsANumberedBibliography() {
        let text = """
        58. Menegas W, Akiti K, Amo R, Uchida N, Watabe-Uchida M. Dopamine neurons projecting \
        to the posterior striatum. Nat. Neurosci. 2018; 21: 1421-1430.
        59. Cho JR, Treweek JB, Robinson JE, Xiao C, Bremner LR. Dorsal raphe dopamine neurons \
        modulate arousal. Neuron 2017; 94: 1205-1219.
        60. Zeng H, Merten A, Wang L, Chang C. Serotonergic modulation of behaviour. \
        Cell Rep. 2019; 27: 1900-1912.
        """
        XCTAssertTrue(ReferenceListDetector.analyse(text).looksLikeReferenceList)
    }

    func testDetectsAnAuthorHeavyCitationBlock() {
        let text = """
        Weissbourd B, Ren J, DeLoach KE, Guenthner CJ, Miyamichi K, Luo L. Presynaptic partners \
        of dorsal raphe serotonergic neurons. Neuron 2014; 83: 645-662. \
        Correia PA, Lottem E, Banerjee D, Machado AS, Carey MR, Mainen ZF. Transient inhibition \
        of dopamine neurons. eLife 2017; 6: e20975.
        """
        XCTAssertTrue(ReferenceListDetector.analyse(text).looksLikeReferenceList)
    }

    // MARK: - Must NOT be detected

    /// The main false-positive risk: prose that cites its sources is still prose.
    func testDoesNotDetectProseThatCitesAuthors() {
        let text = """
        Stimulation of dopamine axon terminals in the dorsal striatum induced the acceleration \
        of locomotion within 160 ms, a result consistent with earlier work. Serotonin receptors \
        are more diverse, consisting of Gi-coupled 5-HT1 and 5-HT5 receptors, and their roles in \
        locomotion, reinforcement learning and working memory remain under active investigation.
        """
        XCTAssertFalse(ReferenceListDetector.analyse(text).looksLikeReferenceList)
    }

    /// A methods section carries author names and year figures without being a bibliography.
    func testDoesNotDetectAMethodsSection() {
        let text = """
        Recordings followed the protocol described by Watabe-Uchida M, adapted for freely moving \
        animals. Animals were habituated for 3 days before testing began, and all procedures were \
        approved under protocol 2019; 14 of the institutional guidelines then in force.
        """
        XCTAssertFalse(ReferenceListDetector.analyse(text).looksLikeReferenceList)
    }

    /// A numbered procedure opens on digits without being a reference list.
    func testDoesNotDetectANumberedProcedure() {
        let text = """
        1. Remove the retaining bolt and set it aside where it will not roll away from the bench. \
        2. Lift the housing clear of the mount, taking care not to strain the loom beneath it. \
        3. Inspect the seal for cracking before reassembly, replacing it whenever in any doubt.
        """
        XCTAssertFalse(ReferenceListDetector.analyse(text).looksLikeReferenceList)
    }

    func testShortTextIsNeverDetected() {
        XCTAssertFalse(ReferenceListDetector.analyse("Menegas W, Uchida N. 2018; 21: 1421.").looksLikeReferenceList)
        XCTAssertFalse(ReferenceListDetector.analyse("").looksLikeReferenceList)
    }

    // MARK: - Density

    /// Density separates a citation-dense chunk from a long passage that mentions a few.
    func testDensityIsHigherForADenseBibliography() {
        let dense = """
        58. Menegas W, Akiti K, Amo R. Nat. Neurosci. 2018; 21: 1421-1430. \
        59. Cho JR, Treweek JB, Robinson JE. Neuron 2017; 94: 1205-1219. \
        60. Zeng H, Merten A, Wang L. Cell Rep. 2019; 27: 1900-1912.
        """
        let sparse = String(repeating: "The striatum integrates dopaminergic and serotonergic input over long timescales. ", count: 12)
            + "Menegas W, Akiti K. Nat. Neurosci. 2018; 21: 1421-1430."

        XCTAssertGreaterThan(
            ReferenceListDetector.analyse(dense).markerDensity,
            ReferenceListDetector.analyse(sparse).markerDensity
        )
    }
}
