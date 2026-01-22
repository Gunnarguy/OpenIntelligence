Expert Role

On-device Retrieval-Augmented Generation (RAG) architect for Apple platforms (Core ML, Vision, Foundation Models framework), with an IR (information retrieval) research background.

Objective

Confirm whether the “universal PDF understanding via RAG” approach is aligned with current RAG research and Apple’s latest on-device APIs, and give you a concrete, iOS-ready blueprint that stays primarily in Core ML + TinyBERT, with an optional “10×” upgrade path using Apple’s Foundation Models framework (still on-device).

Reasoning
	1.	“Universal understanding” is not a binary property.
For any PDF or document, your system’s real goal is to maximize grounded task success under resource constraints:
	•	Retrieval success (did we fetch the right evidence?)
	•	Extraction correctness (did we parse structure like tables, headers, lists?)
	•	Response faithfulness (are claims supported by evidence?)
	•	Latency + memory ceilings (on-device reality)
	2.	Latest RAG research (2025–2026) still converges on a stable spine:
	•	A RAG system is fundamentally retriever + generator, with the retriever often combining sparse (BM25-like) and dense (embeddings) retrieval, and the pipeline often improved via query transformations, reranking, and end-to-end evaluation loops.  ￼
Translation: your “hybrid retrieval + rerank + evidence-gated answering” plan is not outdated – it’s the mainstream backbone.
	3.	Apple’s newest on-device stack (iOS 26 era) cleanly matches that spine:
	•	Vision now has RecognizeDocumentsRequest for structured document understanding (tables, lists, paragraphs, QR codes, key strings like emails/URLs) and supports 26 languages.  ￼
	•	Core ML explicitly highlights improved weight compression, stateful/multi-function models, and a new MLTensor API to run advanced transformer workloads more efficiently on-device.  ￼
	•	Foundation Models framework (separate from Core ML) provides Swift-native access to Apple’s on-device LLM, with guided generation, tool calling, and stateful sessions, running on-device, offline, and without increasing app size.  ￼
Also: Apple explicitly frames the on-device model (3B params, 2-bit) as strong at summarization/extraction/classification but not “world knowledge or advanced reasoning.”  ￼
That’s actually good engineering guidance: your “RAG brain” should be retrieval-first and evidence-driven, not “LLM vibes.”
	4.	“10× new-age” in 2026 is basically: agentic tool-calling RAG + evaluation loops.
Example evidence: Ragas’ public guide shows a naive RAG pass rate of 65.2% improving to 87.9% with an agentic approach (+22.7 points) on their dataset.  ￼
You don’t need their stack specifically – the principle is the point: multi-step retrieval + structured tool calls + measured iteration drives reliability.

Answer

1) Direct answer to your question (no fluff)

Yes – the universal RAG approach I’ve been describing maps to:
	•	Current RAG research direction: hybrid retrieval, reranking, query transformation, pipeline-level evaluation/robustness.  ￼
	•	Apple’s current on-device “official” primitives:
	•	Vision RecognizeDocumentsRequest for structure-aware ingestion.  ￼
	•	Core ML for your TinyBERT embedder/reranker, with modern compression + transformer support.  ￼
	•	Optional “10× mode”: Foundation Models framework as the orchestrator/generator using tool calling + guided generation while keeping your retrieval in Core ML + TinyBERT.  ￼

2) The two viable architectures (staying honest about constraints)

Path	What runs where	“Understands any PDF” capability	Expected groundedness risk
A. Strict Core ML + TinyBERT only	Embed + retrieve + rerank + extractive answering on-device	High for fact lookup and extraction, medium for synthesis	Lower hallucination risk (≈1%–5% if you force quotes), higher “can’t answer” rate (≈10%–25%)
B. Core ML + TinyBERT retrieval + Foundation Models tool-calling	TinyBERT does retrieval/rerank, Apple model synthesizes with tools	Higher on synthesis, multi-hop Q&A, schema outputs	Hallucination risk manageable (≈2%–8%) if you hard-gate on citations

Those %’s are realistic priors for “production-ish” systems, not guarantees – you measure and update them with evaluation (below). The key point: Path A cannot do truly general synthesis without becoming a template engine. Path B is the modern on-device way to get synthesis without shipping a giant model. Apple basically hands you the generator.  ￼

3) Quantifying feasibility (memory, speed) with real math

If you store embeddings for N chunks, embedding dimension d, bytes per element b:

\text{EmbeddingStoreBytes} = N \times d \times b

Example (common on-device choice): float16 so b=2.
If N=50{,}000 chunks and d=384:

50{,}000 \times 384 \times 2 = 38{,}400{,}000\ \text{bytes} \approx 36.6\ \text{MiB}

That’s totally sane on-device, especially if you also:
	•	keep lexical index compact (BM25 inverted index),
	•	aggressively chunk (don’t embed whole pages),
	•	compress weights (Core ML emphasizes composable weight compression).  ￼

4) “10× New Age” iOS-native ingestion: Vision structured parsing (real code)

This is the exact Apple-style API for structured extraction (tables, then cell-level detected data).  ￼

import Foundation
import Vision

enum AppError: Error {
    case noDocument
    case noTable
}

struct Contact: Hashable {
    let name: String
    let email: String
    let phoneNumber: String?
}

/// Process an image and return the first table detected.
func extractTable(from image: Data) async throws -> DocumentObservation.Container.Table {
    // The Vision request.
    let request = RecognizeDocumentsRequest()

    // Perform the request on the image data and return the results.
    let observations = try await request.perform(on: image)

    // Get the first observation from the array.
    guard let document = observations.first?.document else {
        throw AppError.noDocument
    }

    // Extract the first table detected.
    guard let table = document.tables.first else {
        throw AppError.noTable
    }

    return table
}

/// Extract name, email addresses, and phone number from a table into a list of contacts.
func parseTable(_ table: DocumentObservation.Container.Table) -> [Contact] {
    var contacts = [Contact]()

    // Iterate over each row in the table.
    for row in table.rows {
        // The contact name will be taken from the first column.
        guard let firstCell = row.first else { continue }

        // Extract the text content from the transcript.
        let name = firstCell.content.text.transcript

        // Look for emails and phone numbers in the remaining cells.
        var detectedPhone: String? = nil
        var detectedEmail: String? = nil

        for cell in row.dropFirst() {
            // Get all detected data in the cell, then match emails and phone numbers.
            let allDetectedData = cell.content.text.detectedData

            for data in allDetectedData {
                switch data.match.details {
                case .emailAddress(let email):
                    detectedEmail = email.emailAddress
                case .phoneNumber(let phoneNumber):
                    detectedPhone = phoneNumber.phoneNumber
                default:
                    break
                }
            }
        }

        // Create a contact if an email was detected.
        if let email = detectedEmail {
            contacts.append(Contact(name: name, email: email, phoneNumber: detectedPhone))
        }
    }

    return contacts
}

Why this matters for “universal PDF understanding”:
	•	You stop treating a document as a flat text blob.
	•	You preserve structure (tables, paragraphs, lists) which massively improves retrieval precision and downstream answering.  ￼

5) “10× New Age” answering: tool-calling RAG on-device (real Foundation Models code)

This is the Apple-native pattern: create tools, attach them to a session, and the model calls them autonomously.  ￼

Below is a minimal, working shape you can drop into your app. You’ll wire LocalDocIndex.search(...) to your Core ML + TinyBERT pipeline.

import Foundation
import FoundationModels

// Your own index result type (keep it simple and citation-friendly).
struct SearchHit: Codable, Hashable {
    let chunkId: String
    let title: String?
    let text: String
    let score: Double
}

// Your own local index (implement with Core ML + TinyBERT + BM25).
final class LocalDocIndex {
    func search(query: String, topK: Int) async -> [SearchHit] {
        // TODO: implement hybrid retrieval + rerank.
        // Return chunks with stable IDs so you can cite them.
        return []
    }
}

// Tool that lets the model fetch evidence.
final class LocalSearchTool: Tool {
    let name = "local_search"
    let description = """
    Search the on-device document index.
    Return the most relevant chunks as evidence, including chunkId for citations.
    """

    private let index: LocalDocIndex

    init(index: LocalDocIndex) {
        self.index = index
    }

    @Generable
    struct Arguments {
        let query: String
        let topK: Int
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        let hits = await index.search(query: arguments.query, topK: arguments.topK)

        // Return machine-readable JSON so the model can cite chunkIds.
        let data = try JSONEncoder().encode(hits)
        let json = String(decoding: data, as: UTF8.self)

        return ToolOutput(json)
    }
}

@MainActor
func answerWithOnDeviceModel(userQuestion: String, index: LocalDocIndex) async throws -> String {
    // Apple recommends checking availability (region/device gating).
    // See: SystemLanguageModel.availability in the WWDC session.
    // (You should gate your UI if unavailable.)
    //  [oai_citation:15‡Apple Developer](https://developer.apple.com/videos/play/wwdc2025/286/)

    let tools: [Tool] = [LocalSearchTool(index: index)]

    let session = LanguageModelSession(
        tools: tools,
        instructions: """
        You are a grounded document assistant.
        Always call local_search before answering.
        Only answer using returned evidence.
        If evidence is insufficient, say you cannot answer.
        """
    )

    // Prompt injection note: Apple explicitly distinguishes developer instructions vs user prompts.
    // Keep instructions static and don’t interpolate untrusted user input into them.
    //  [oai_citation:16‡Apple Developer](https://developer.apple.com/videos/play/wwdc2025/286/)

    let response = try await session.respond(to: userQuestion)
    return String(describing: response)
}

This gives you a clean division of labor:
	•	TinyBERT in Core ML does retrieval + rerank
	•	Apple’s model does controlled synthesis, plus it can call tools repeatedly in multi-turn sessions  ￼
	•	You get a path to the “agentic” performance jump pattern seen in evaluation guides (multi-step tool use).  ￼

6) Reliability: build a measurable confidence model (math + practice)

Define:
	•	s_r = reranker score (normalized 0–1)
	•	c = coverage ratio of answer spans supported by evidence (0–1)
	•	m = margin between top1 and top2 evidence scores

A simple confidence logit:

z = \alpha s_r + \beta c + \gamma m - \delta
\qquad
\Rightarrow
\qquad
P(\text{answer is correct}) = \sigma(z) = \frac{1}{1+e^{-z}}

Then you choose a refusal threshold, e.g. refuse if P < 0.8.
This converts “it feels right” into something you can tune against a test set.

Measurement with uncertainty (don’t skip this):
If you evaluate N questions and get \hat{p} correct:

\hat{p}=\frac{k}{N},
\quad
SE=\sqrt{\frac{\hat{p}(1-\hat{p})}{N}},
\quad
95\%\ CI \approx \hat{p}\pm 1.96\cdot SE

Example: N=400, \hat{p}=0.88:

SE=\sqrt{\frac{0.88\cdot 0.12}{400}}=\sqrt{0.000264}=0.01625
95\%CI \approx 0.88 \pm 0.0319 \Rightarrow [0.848,\ 0.912]

That CI is what you use to justify “this is production-ready” vs “we got lucky.”

Suggested visualizations (fast, high signal):
	•	Histogram of chunk lengths (tokens) to tune chunking
	•	Recall@k curve (k = 1..50) for hybrid retrieval
	•	Latency distribution (p50/p95) for end-to-end Q&A
	•	Calibration plot: predicted confidence vs empirical accuracy

7) Practical bottom line for your constraint set (Core ML + TinyBERT)

If you truly mean no on-device generator at all:
	•	You can still do strong universal lookup by:
	•	Vision structured extraction (tables/paragraphs)
	•	Hybrid retrieval + rerank
	•	Answer by quoting the best spans + lightweight templating
	•	You will cap out on:
	•	cross-section summaries
	•	multi-hop reasoning
	•	natural language synthesis

If you allow Apple’s Foundation Models framework as the generator (still on-device):
	•	You get the “10×” step-up:
	•	guided generation for schema output
	•	tool-calling loops
	•	stateful sessions
	•	And Apple explicitly frames this as on-device, offline, privacy-preserving, Swift-native, and available on iOS 26-class systems.  ￼
