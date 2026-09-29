import XCTest
@testable import OpenIntelligenceEngine

/// Audit probe, not an app test: which questions lock a span, before and after the 2026-09-26
/// extractor fix. `run.sh` compiles it beside the extractor and prints one `MATRIX|` line per case.
/// The passages are fictional stand-ins for household manuals and a lease.
@MainActor
final class LockMatrixProbe: XCTestCase {

    private func chunk(_ content: String, _ document: String) -> RetrievedChunk {
        let metadata = ChunkMetadata(
            chunkIndex: 0,
            startPosition: 0,
            endPosition: content.count,
            pageNumber: 1,
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
            pageNumber: 1
        )
    }

    func testMatrix() async {
        let fryer = chunk(
            "SPECIFICATIONS\nBasket capacity: 5.8 qt\nPower: 1700 W\nVoltage: 120 V\nBefore first use, remove all packaging and wash the basket.",
            "Air Fryer.pdf")
        let chart = chunk(
            "Cooking Chart\nFood | Amount | Temp | Time\nFrozen fries | 1 lb | 400°F | 15-18 min\nChicken wings | 1 lb | 380°F | 22-25 min\nPull the basket out and shake it halfway through.",
            "Air Fryer.pdf")
        let car = chunk(
            "CAPACITIES\nEngine oil with filter: 4.5 L (4.8 US qt)\nFuel tank: 14.3 US gal (54 L)\nEngine coolant: 7.2 L\nRecommended oil: SAE 0W-20",
            "Car Manual.pdf")
        let mower = chunk("Engine oil capacity: 4.5L. Check the level before every use.", "Mower Manual.pdf")
        let coffee = chunk(
            "Water reservoir capacity: 1.2 L. The carafe holds 12 cups. Descale every 3 months.", "Coffee Maker.pdf")
        let mixer = chunk(
            "Product weight: 11.2 lb (5.1 kg). Dimensions: 14 x 12 x 13 in. Maximum load: 30 lb.", "Stand Mixer.pdf")
        let lease = chunk(
            "16. NOTICE TO VACATE. Tenant must give Landlord written notice at least sixty (60) days before the end of the Term if Tenant intends to move out.",
            "Lease.pdf")

        let cases: [(String, [RetrievedChunk])] = [
            ("How much notice do I have to give before I move out?", [lease, chart]),
            ("How much notice do I have to give before I move out?", [lease, fryer]),
            ("How many days notice do I need to give?", [lease, chart]),
            ("How much rent is due?", [lease, chart]),
            ("How much power does it use?", [fryer]),
            ("How much does the basket hold?", [fryer]),
            ("What is the basket capacity?", [fryer]),
            ("How much oil does the engine take?", [car]),
            ("How much oil does the engine take?", [mower]),
            ("How many quarts of oil does it need?", [car]),
            ("What oil does the car take?", [car]),
            ("How much fuel does the tank hold?", [car]),
            ("What is the fuel tank capacity?", [car]),
            ("How much coolant does it need?", [car]),
            ("How much water does the reservoir take?", [coffee]),
            ("How much water does it hold?", [coffee]),
            ("How much does it weigh?", [mixer]),
            ("What is the product weight?", [mixer]),
        ]

        let lock = EvidenceScoringPolicyService.precisionLockThreshold(forceExtractiveAttempt: false)
        for (question, chunks) in cases {
            let result = await SpecificationExtractor().extract(query: question, chunks: chunks, answerIntent: .lookup)
            let documents = chunks.map(\.sourceDocument).joined(separator: " + ")
            switch result {
            case .success(let extraction):
                let verdict = extraction.confidence >= lock ? "LOCKS" : "model"
                print("MATRIX|\(question)|\(documents)|\(verdict)|\(extraction.answerSpan)|\(String(format: "%.2f", extraction.confidence))")
            case .failure(let failure):
                print("MATRIX|\(question)|\(documents)|model|-|\(failure)")
            }
        }
    }
}
