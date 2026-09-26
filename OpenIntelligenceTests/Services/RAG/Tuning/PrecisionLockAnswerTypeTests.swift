import XCTest
@testable import OpenIntelligenceEngine

/// Pins what the extractive lookup may put in place of a generated answer.
///
/// `SpecificationExtractor.extract` feeds `RAGService.highPrecisionLookupOverrideAnswer`, and a
/// result at or above `EvidenceScoringPolicyService.precisionLockThreshold` becomes the answer.
/// Deep Think and Maximum return it before the orchestrator runs; Standard swaps it in after
/// generation. Either way the source-only check declines it as "source-locked".
///
/// Device evidence 2026-09-25, macOS Debug build of 5.4, Deep Think: "How much notice do I have to
/// give before I move out?" over a library holding a lease (60 days' written notice, section 16) and
/// an air fryer manual with a cooking chart. The answer was "1 lb." cited to the manual and marked
/// Verified, and the model never ran. Two rules stacked to put "1 lb" at 0.85 against the 0.82 lock:
/// "much" appended liters, quarts, gallons, capacity and volume to the question, which made it a
/// measurement query worth +0.12 to every measurement, and the liquid-unit test found " l" inside
/// "1 lb", worth +0.22.
///
/// The documents are fictional stand-ins for the owner's sample library.
@MainActor
final class PrecisionLockAnswerTypeTests: XCTestCase {

    private let lockThreshold = EvidenceScoringPolicyService.precisionLockThreshold(forceExtractiveAttempt: false)

    private let noticeQuestion = "How much notice do I have to give before I move out?"

    private let leaseSection16 = """
        16. NOTICE TO VACATE. Tenant must give Landlord written notice at least sixty (60) days \
        before the end of the Term if Tenant intends to move out. If Tenant does not give timely \
        notice, this Lease continues month to month and either party may end it with 60 days' \
        written notice. Notice must be delivered to Landlord at the address in Section 2.
        """

    private let airFryerCookingChart = """
        Kestrel AF-620 Air Fryer - Cooking Chart
        Food | Amount | Temp | Time
        Frozen fries | 1 lb | 400°F | 15-18 min
        Chicken wings | 1 lb | 380°F | 22-25 min
        Brussels sprouts | 1 lb | 375°F | 12-15 min
        Salmon fillets | 2 fillets | 390°F | 8-10 min
        Pull the basket out and shake it halfway through. Remove food with tongs; do not overfill the basket.
        """

    private let airFryerSpecifications = """
        SPECIFICATIONS
        Basket capacity: 5.8 qt
        Power: 1700 W
        Voltage: 120 V
        Before first use, remove all packaging and wash the basket. Never pull the basket out while \
        the fryer is running.
        """

    private let truckSpecifications = """
        SPECIFICATIONS. Curb weight: 3,200 lb. Payload capacity: 1,500 lb. Tank size is on the fuel door.
        """

    private func chunk(_ content: String, document: String, page: Int) -> RetrievedChunk {
        let metadata = ChunkMetadata(
            chunkIndex: 0,
            startPosition: 0,
            endPosition: content.count,
            pageNumber: page,
            sectionTitle: nil,
            keywords: [],
            semanticDensity: nil,
            hasNumericData: true,
            hasListStructure: false,
            wordCount: content.split(separator: " ").count,
            characterCount: content.count,
            createdAt: Date()
        )
        return RetrievedChunk(
            chunk: DocumentChunk(
                id: UUID(),
                documentId: UUID(),
                content: content,
                parentContent: nil,
                contextualPrefix: nil,
                embedding: [],
                metadata: metadata
            ),
            similarityScore: 0.70,
            rank: 0,
            sourceDocument: document,
            pageNumber: page
        )
    }

    /// The span `highPrecisionLookupOverrideAnswer` would lock for these chunks, or nil when the
    /// question goes to the model.
    private func lockedSpan(_ question: String, _ chunks: [RetrievedChunk]) async -> String? {
        let result = await SpecificationExtractor().extract(query: question, chunks: chunks, answerIntent: .lookup)
        guard case .success(let extraction) = result, extraction.confidence >= lockThreshold else { return nil }
        return extraction.answerSpan
    }

    /// The reported case: a notice question, a lease clause, and a chart of weights.
    func testNoticeQuestionDoesNotLockAWeightFromACookingChart() async {
        let span = await lockedSpan(noticeQuestion, [
            chunk(leaseSection16, document: "Maple Court Lease.pdf", page: 4),
            chunk(airFryerCookingChart, document: "Kestrel AF-620 Air Fryer Manual.pdf", page: 1),
        ])
        XCTAssertNil(span, "A notice question locked '\(span ?? "")'; it must go to the model")
    }

    /// The same question against a genuine liquid capacity. Fixing the unit test alone leaves this
    /// locking "5.8 qt": only the expansion rule decides whether a notice question is about volume.
    func testNoticeQuestionDoesNotLockALiquidCapacity() async {
        let span = await lockedSpan(noticeQuestion, [
            chunk(leaseSection16, document: "Maple Court Lease.pdf", page: 4),
            chunk(airFryerSpecifications, document: "Kestrel AF-620 Air Fryer Manual.pdf", page: 2),
        ])
        XCTAssertNil(span, "A notice question locked '\(span ?? "")'; it must go to the model")
    }

    /// A pound is not a liquid unit, whatever the question. "Fuel" keeps the question a volume
    /// question, so this is the unit test's own case, independent of the expansion rule.
    func testFuelQuestionDoesNotLockAWeight() async {
        let span = await lockedSpan("How much fuel does the tank hold?", [
            chunk(truckSpecifications, document: "Truck Manual.pdf", page: 9),
        ])
        XCTAssertNil(span, "A fuel question locked the weight '\(span ?? "")'")
    }

    /// The case the extractor exists for must keep working.
    func testCapacityQuestionStillLocksItsLiquidValue() async {
        let span = await lockedSpan("How much food does the basket hold?", [
            chunk(airFryerSpecifications, document: "Kestrel AF-620 Air Fryer Manual.pdf", page: 2),
        ])
        XCTAssertEqual(span, "5.8 qt")
    }
}
