import Foundation

/// Describes a built-in sample file packaged for onboarding.
struct SampleDocumentDescriptor {
    let filename: String
    let `extension`: String
    let body: String
}

/// Handles authoring and importing curated sample documents for a better first-run experience.
@MainActor
final class SampleDocumentManager {
    static let shared = SampleDocumentManager()

    private init() {}

    private let samples: [SampleDocumentDescriptor] = [
        SampleDocumentDescriptor(
            filename: "OpenIntelligence Pricing",
            extension: "md",
            body: #"""
# OpenIntelligence Pricing Guide

## What is OpenIntelligence?

OpenIntelligence is a privacy-first AI document assistant that runs entirely on your device. It uses Retrieval-Augmented Generation (RAG) to answer questions from your imported documents — no cloud uploads, no data collection, no account required.

Every query, every embedding, and every answer stays on your iPhone or iPad.

---

## Pricing Tiers

### Free Tier
- **5 documents** maximum
- 1 library / container
- Full privacy dashboard
- On-device AI processing (Apple Foundation Model)
- Hybrid search (semantic + keyword)
- No account required — works immediately

### Pro Subscription
- **Monthly**: $5.99/month
- **Annual**: $49.99/year (save 30%)
- Up to **1,000 documents**
- **5 libraries** for topic organization
- Priority ingestion queue
- AI Hub transforms (Key Facts, Step-by-Step, Plain English, What's Missing?, Illustrate)
- Advanced RAG features: iterative retrieval, contextual compression, RAPTOR-lite routing
- Entity extraction and domain classification

### Lifetime License
- **One-time**: $59.99
- Up to **1,000 documents** forever
- **10 libraries** maximum
- All Pro features included
- No recurring payments — pay once, own it

---

## Key Capabilities

### Privacy Architecture
1. **100% On-Device**: All AI processing uses Apple's Foundation Model (3B parameters on-device)
2. **Private Cloud Compute**: When needed, Apple's PCC provides server-side AI with zero data retention
3. **No Telemetry**: We collect zero usage data — not even crash reports unless you opt in
4. **Works Offline**: Query your documents without internet connection

### Document Intelligence
- **Multi-format support**: PDF, Word (.docx), Excel (.xlsx), Markdown, plain text, images (via OCR)
- **OCR Pipeline**: 360 DPI rendering with 5 adaptive preprocessing strategies for scanned documents
- **Semantic Chunking**: Content is split at natural boundaries (sections, paragraphs, topic shifts)
- **Entity Extraction**: Automatically identifies people, organizations, dates, and technical terms

### Search & Retrieval
- **Hybrid Search**: Combines 384-dimensional vector embeddings with BM25 keyword matching
- **Cross-Encoder Reranking**: Neural reranker scores each result for relevance
- **MMR Diversification**: Ensures variety in retrieved sources (no redundant chunks)
- **Lost-in-Middle Reordering**: Places strongest evidence at the start and end of context

### AI Hub Transforms
Transform any AI answer with one tap:
- **Key Facts**: Extract bullet-point facts from the response
- **Step-by-Step**: Convert into numbered procedural steps
- **Plain English**: Simplify jargon and technical language
- **What's Missing?**: Identify gaps in the response relative to your question
- **Illustrate**: Generate a visual concept description for the answer
"""#
        ),
        SampleDocumentDescriptor(
            filename: "RAG Technical Architecture",
            extension: "md",
            body: #"""
# RAG Technical Architecture

## What is RAG?

RAG (Retrieval-Augmented Generation) is an AI technique that grounds language model responses in your actual documents. Instead of relying on the model's training data (which can hallucinate), RAG retrieves relevant passages from your documents and provides them as context to the AI. This produces accurate, sourced answers with dramatically reduced hallucination.

---

## The OpenIntelligence Pipeline

### Ingestion (6 Steps)

**Step 1 — Parse**
Documents are parsed based on type: PDFKit for PDFs, ZIP extraction for Office XML (.docx, .xlsx), or plain text reading. Scanned PDFs trigger Vision OCR at 360 DPI with 5 adaptive preprocessing strategies (minimal, moderate, high contrast, deskew, maximum). A PHASE -1 Jaccard validation catches font-encoded PDFs (like Kia/Hyundai manuals) where characters look normal but are actually cipher-shifted.

**Step 2 — Semantic Chunking**
Content is split into chunks of up to 310 words at natural boundaries: section headers, paragraph breaks, and embedding-similarity topic shifts. Each chunk gets a contextual prefix (document title + section path) so it can stand alone when retrieved later. A BertTokenizer validates that no chunk exceeds the 510-token embedding limit.

**Step 3 — Entity Extraction**
NLTagger NER identifies people, organizations, locations, and dates. PascalCase technical terms are detected via regex. Entities are stored in an inverted index for cross-document search.

**Step 4 — Token Validation**
Every chunk is tokenized with BertTokenizer to verify it fits within the MiniLM-L6-v2 512-token window (510 usable after CLS/SEP tokens). Oversized chunks are re-split.

**Step 5 — Embedding**
Each chunk is converted to a 384-dimensional vector using CoreML MiniLM-L6-v2. These vectors capture semantic meaning — similar concepts produce similar vectors regardless of exact wording.

**Step 6 — Store**
Vectors are indexed in an HNSW graph (Hierarchical Navigable Small World) for fast approximate nearest-neighbor search. Full text is stored in SQLite FTS5 for keyword search. Entities go into a separate inverted index.

---

### Query Processing (10+ Steps)

**Step 1 — Query Understanding**
Pronouns are resolved using conversation history. Named entities are extracted. The query is classified by intent: lookup, procedure, comparison, or summarization.

**Step 2 — Query Expansion**
The original query is enriched with corpus-specific vocabulary and synonyms to improve recall. For example, "rent" might expand to include "monthly payment" and "lease amount".

**Step 3 — Hybrid Search**
Two parallel searches run:
- **Vector Search**: The query embedding is compared against all chunk embeddings using cosine similarity in the HNSW index
- **BM25 Keyword Search**: SQLite FTS5 scores chunks by term frequency and inverse document frequency

Results are fused using Reciprocal Rank Fusion (RRF), which combines rankings without needing score calibration.

**Step 4 — Cross-Encoder Reranking**
A TinyBERT cross-encoder model scores each (query, chunk) pair for relevance. This is more accurate than embedding similarity because it sees both texts together.

**Step 5 — MMR Diversification**
Maximal Marginal Relevance ensures retrieved chunks aren't redundant. Lambda = 0.6 balances relevance vs. diversity.

**Step 6 — Context Assembly**
Selected chunks are reordered using Lost-in-Middle placement: strongest evidence at the beginning and end of the context window (LLMs attend less to middle content). Total context is capped at 5,500 characters (~4,000 tokens) to fit the 4,096-token Apple Foundation Model limit.

**Step 7 — LLM Generation**
Apple's Foundation Model generates a response grounded in the retrieved context. The prompt instructs the model to cite sources and avoid speculation beyond what the documents contain.

**Step 8 — Verification Gates**
Seven gates (A-G) check the response:
- **Gate A**: Does the top retrieval score show confident evidence?
- **Gate B**: Is every claim supported by retrieved context?
- **Gate C**: Do numbers in the response match source documents?
- **Gate D**: Does the response contradict any source evidence?
- **Gate E**: Is the response semantically grounded in source chunks?
- **Gate F**: Are quoted terms faithful to their source definitions?
- **Gate G**: Is the text free from repetition loops and degeneration?

---

## Technical Specifications

| Component | Technology | Details |
|-----------|-----------|---------|
| Embeddings | MiniLM-L6-v2 (CoreML) | 384 dimensions, <100ms per chunk |
| Vector Index | HNSW graph | BNNS-accelerated on Apple Silicon |
| Keyword Search | SQLite FTS5 | BM25 scoring with porter stemming |
| Cross-Encoder | TinyBERT (CoreML) | Pairwise relevance scoring |
| LLM | Apple Foundation Model | 3B parameters on-device, 4096 token context |
| OCR | Apple Vision framework | 360 DPI, 5 preprocessing strategies |

## Performance Targets
- **Embedding**: <100ms per chunk on A17 Pro
- **Retrieval**: <500ms for 10,000 chunks (hybrid search + rerank)
- **Generation**: 15–25 tokens/second on-device
- **Total query latency**: <3 seconds end-to-end
"""#
        ),
        SampleDocumentDescriptor(
            filename: "Apple Intelligence & Private Cloud Compute",
            extension: "md",
            body: #"""
# Apple Intelligence & Private Cloud Compute

## What is Apple Intelligence?

Apple Intelligence is Apple's personal intelligence system, deeply integrated into iOS, iPadOS, and macOS. It combines on-device machine learning models with optional Private Cloud Compute (PCC) to deliver AI features while maintaining Apple's privacy standards.

OpenIntelligence is built 100% on Apple's native AI stack — no OpenAI, no third-party models, no data leaving your control.

---

## On-Device Foundation Model

### Architecture
Apple's on-device model is a ~3 billion parameter language model optimized for Apple Silicon. Key specifications:

| Spec | Value |
|------|-------|
| Parameters | ~3B |
| Context window | 4,096 tokens |
| Inference speed | 15–25 tokens/sec (A17 Pro) |
| Model format | CoreML optimized |
| Quantization | Mixed INT4/INT8 |
| Memory footprint | ~2.5 GB |

### FoundationModels Framework (iOS 26+)
The `FoundationModels` framework provides Swift-native access to Apple's on-device LLM:

```swift
import FoundationModels

let session = LanguageModelSession()
let response = try await session.respond(to: "Your prompt here")
```

Key features:
- **Guardrails API**: Built-in content safety filtering
- **Structured generation**: JSON schema-constrained output via `@Generable`
- **Tool calling**: `@Tool` protocol for function-calling patterns
- **Streaming**: Token-by-token response streaming
- **Session management**: Conversation context across multiple turns

### The 4,096 Token Limit
This is the single most important constraint for RAG applications:
- ~3,000 words of English text maximum in a single prompt
- The prompt must include: system instructions + retrieved context + user question + generation space
- OpenIntelligence budgets ~5,500 characters for context (~4,000 tokens with margin)
- RAG solves this by retrieving only the most relevant chunks instead of feeding entire documents

---

## Private Cloud Compute (PCC)

### What is PCC?
When on-device processing isn't sufficient for complex tasks, Apple's Private Cloud Compute provides server-side AI with privacy guarantees that no other cloud AI can match.

### How PCC Works

1. **Encryption**: Your device encrypts the request with a one-time key
2. **Routing**: Request is sent to a verified, attested PCC node
3. **Isolation**: The node processes the request in isolated, encrypted memory
4. **Response**: Result is encrypted and returned to your device
5. **Purge**: All data is immediately and cryptographically erased from the node

### Privacy Guarantees

PCC provides guarantees enforced by hardware and cryptography, not just policy:

- **No Persistence**: User data is never written to persistent storage on any server
- **No Logging**: Prompts and responses are never logged, even for debugging
- **No Access**: Apple engineers cannot view, read, or extract request content — even with physical access to servers
- **Verifiable Code**: Every PCC server image is cryptographically signed and published for independent security research verification
- **Stateless Processing**: Each request is processed in a fresh, isolated compute environment

### When Does OpenIntelligence Use PCC?

| Scenario | Processing Location |
|----------|-------------------|
| Simple factual queries | On-device (3B model) |
| Quick document lookups | On-device |
| Offline operation | On-device |
| Complex multi-step reasoning | PCC (when available) |
| Large context analysis | PCC (when available) |
| Resource-constrained device | PCC (when available) |

The app always prefers on-device processing. PCC is only used when the on-device model indicates lower confidence or when the task complexity exceeds local capabilities.

---

## Apple Native Frameworks Used

OpenIntelligence uses 23 Apple frameworks with zero third-party AI dependencies:

| Framework | Purpose |
|-----------|---------|
| **FoundationModels** | On-device LLM inference |
| **Vision** | OCR, document structure recognition |
| **NaturalLanguage** | NER, tokenization, language detection |
| **CoreML** | MiniLM embeddings, TinyBERT reranking |
| **PDFKit** | PDF text extraction and rendering |
| **Speech** | Audio transcription for voice files |
| **Metal** | GPU-accelerated vector operations |
| **CoreSpotlight** | System-wide document search integration |
| **StoreKit 2** | Subscription and purchase management |
| **TipKit** | Contextual user education |

### Why All-Apple Matters
- **No network dependency**: Everything works offline
- **No API keys**: Nothing to configure, leak, or pay for
- **No data egress**: Your documents never leave your device (or Apple PCC)
- **Optimized for hardware**: CoreML models exploit Neural Engine, GPU, and AMX units
- **Future-proof**: Built on Apple's roadmap, not a startup's funding runway
"""#
        ),
    ]

    /// Total number of sample documents, used for quota calculations.
    var sampleCount: Int { samples.count }

    /// Writes curated samples to disk and ingests them into the active RAG pipeline.
    /// Uses `.onboarding` context to prevent self-tuning rebuilds during initial setup.
    /// Now uses the ingestion queue so UI can observe progress via `ragService.ingestionItems`.
    func importSamples(
        into ragService: RAGService,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async throws {
        // Suppress reembed kicks during the entire batch import
        await MainActor.run { ragService.beginOnboardingBatch() }

        let urls = try writeSamplesToDocumentsDirectory()

        // Use queue-based ingestion so ragService.ingestionItems gets populated
        // This allows the UI to observe real-time pipeline stage updates
        let result = await ragService.ingestDocuments(urls, context: .onboarding)

        // Report final progress
        onProgress?(urls.count, urls.count, "Complete")

        // If any documents failed, throw an error
        if result.failureCount > 0 {
            throw NSError(
                domain: "SampleDocumentManager",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to import \(result.failureCount) sample(s)"]
            )
        }

        // Clear any pending reembed operations that may have been queued during import
        await MainActor.run { ragService.clearPendingReembeds() }
    }

    /// Persists each sample document in the app's Documents directory (permanent storage).
    private func writeSamplesToDocumentsDirectory() throws -> [URL] {
        guard let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw NSError(domain: "SampleDocumentManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Documents directory unavailable"])
        }
        let samplesDir = documentsDir.appendingPathComponent("SampleDocuments", isDirectory: true)

        try FileManager.default.createDirectory(at: samplesDir, withIntermediateDirectories: true)

        var urls: [URL] = []

        for sample in samples {
            let filename = sample.filename.replacingOccurrences(of: " ", with: "-")
            let fileURL = samplesDir
                .appendingPathComponent(filename)
                .appendingPathExtension(sample.extension)

            // Only write if file doesn't already exist (prevents duplicate ingestion)
            if !FileManager.default.fileExists(atPath: fileURL.path) {
                try sample.body.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            urls.append(fileURL)
        }

        return urls
    }
}
