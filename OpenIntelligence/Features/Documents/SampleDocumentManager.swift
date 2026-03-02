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
OpenIntelligence is a privacy-first AI document assistant that runs entirely on your device. It uses Retrieval-Augmented Generation (RAG) to answer questions from your imported documents.

## Pricing Tiers

### Free Tier
- 5 documents maximum
- 1 library/container
- Full privacy dashboard
- On-device AI processing
- No account required

### Pro Subscription
- **Monthly**: $5.99/month
- **Annual**: $49.99/year (save 30%)
- Up to 1,000 documents
- 5 libraries for organization
- Priority ingestion queue
- Advanced RAG features

### Lifetime License
- **One-time**: $59.99
- Up to 1,000 documents forever
- 10 libraries maximum
- All Pro features included
- No recurring payments

## Key Features
1. **100% Private**: All processing happens on-device or via Apple's Private Cloud Compute
2. **Hybrid Search**: Combines semantic vectors + keyword matching for accurate retrieval
3. **Works Offline**: Query your documents without internet connection
4. **Multi-format**: Supports PDF, Word, Excel, Markdown, and text files
"""#
        ),
        SampleDocumentDescriptor(
            filename: "RAG Technical Guide",
            extension: "md",
            body: #"""
# RAG Technical Architecture

## What is RAG?
RAG (Retrieval-Augmented Generation) is an AI technique that grounds language model responses in your actual documents, reducing hallucinations and providing accurate, sourced answers.

## How OpenIntelligence RAG Works

### Step 1: Document Ingestion
When you import a document:
1. Text is extracted (OCR for scanned PDFs)
2. Content is split into semantic chunks (~300 words each)
3. Each chunk is converted to a 384-dimensional embedding vector
4. Vectors are indexed in an HNSW graph for fast similarity search

### Step 2: Query Processing
When you ask a question:
1. Your question is embedded using the same 384-dimensional model
2. Hybrid search finds relevant chunks (vector similarity + BM25 keywords)
3. Top chunks are re-ranked using a cross-encoder model
4. MMR diversification ensures variety in sources

### Step 3: Answer Generation
1. Retrieved context is packed into the LLM prompt
2. Apple's Foundation Model generates a grounded response
3. Citations link back to source documents

## Technical Specifications

| Component | Technology |
|-----------|-----------|
| Embeddings | MiniLM-L6-v2 (384 dimensions) |
| Vector Index | HNSW graph (BNNS accelerated) |
| Keyword Search | SQLite FTS5 with BM25 |
| Re-ranker | Cross-encoder neural model |
| LLM | Apple Foundation Model (3B on-device) |

## Performance Targets
- Embedding: <100ms per chunk
- Retrieval: <500ms for 10,000 chunks
- Generation: 15-25 tokens/second
"""#
        ),
        SampleDocumentDescriptor(
            filename: "Apple Private Cloud Compute",
            extension: "md",
            body: #"""
# Apple Private Cloud Compute (PCC)

## What is Private Cloud Compute?
Apple Private Cloud Compute (PCC) is Apple's secure cloud AI infrastructure. When on-device processing isn't sufficient, PCC handles complex AI tasks while maintaining strong privacy guarantees.

## How PCC Works

### Request Flow
1. Your device encrypts the request with a one-time key
2. Request is sent to a verified PCC node
3. The node processes in isolated memory
4. Response is encrypted and returned
5. All data is immediately purged

### Privacy Guarantees
PCC provides these security promises:
- **No Persistence**: User data never written to disk
- **No Logging**: Prompts and responses are never logged
- **No Access**: Even Apple engineers cannot view request content
- **Verifiable Code**: All server images are cryptographically signed

## When is PCC Used?

### On-Device (3B Model)
- Simple queries
- Quick lookups
- Offline operation
- Maximum privacy

### Private Cloud Compute
- Complex reasoning tasks
- Multi-step analysis
- Large context processing
- When device is resource-constrained

## The 4096 Token Limit
Apple's on-device model has a strict 4096 token context limit. This means:
- ~3000 words of English text maximum
- Conversations must be managed carefully
- RAG helps by retrieving only relevant context

## Transparency Features
Apple publishes:
- Cryptographic attestations for each PCC node
- Software images for security researcher verification
- Transparency logs of all signed builds
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
