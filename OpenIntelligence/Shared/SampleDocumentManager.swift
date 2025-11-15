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
            filename: "Sample Pricing Brief",
            extension: "md",
            body: #"""
# Sample Pricing Brief

## Value Ladder
- **Free**: 10 docs, 1 library, telemetry opt-in.
- **Starter ($2.99/mo)**: 40 docs, 3 libraries, weekly rerank refresh.
- **Pro ($8.99/mo or $89/yr)**: Unlimited docs, automation hooks, priority compute.

## Messaging Pillars
1. *Privacy-first*: Data stays on-device or Apple PCC.
2. *Retrieval speed*: Hybrid search + MMR for grounded answers.
3. *Collaboration*: Share libraries and automate exports.

## Launch Tasks
- Sync App Store screenshots with this pricing grid.
- Include privacy copy on paywall and onboarding surfaces.
- Instrument upgrade funnels (quota hits, paywall views).

## Talking Points
> “OpenIntelligence keeps your knowledge base local and lets you scale when you’re ready. The Starter plan is perfect for vibe-checking, while Pro unlocks the full RAG stack.”
"""#
        ),
        SampleDocumentDescriptor(
            filename: "Sample Technical Overview",
            extension: "md",
            body: #"""
# Technical Documentation: RAG Implementation

## Architecture Overview

This document provides technical specifications for the RAGMLCore implementation.

### Core Components

#### DocumentProcessor
```swift
class DocumentProcessor {
    private let targetChunkSize: Int = 400
    private let chunkOverlap: Int = 50
    
    func processDocument(at url: URL) async throws -> (Document, [String]) {
        // Implementation details
    }
}
```

**Key Features:**
- Semantic paragraph-based chunking
- Configurable chunk size and overlap
- Support for PDF, TXT, MD, RTF formats

#### EmbeddingService
Uses Apple's NLEmbedding framework for 512-dimensional semantic vectors.

**Algorithm:**
1. Split text into words
2. Generate word-level embeddings
3. Average vectors for chunk representation

**Performance Targets:**
- <100ms per chunk
- Batch processing support
- Memory-efficient implementation

### Vector Search

Cosine similarity formula:
```
similarity = (A · B) / (||A|| × ||B||)
```

Where A and B are embedding vectors.

### Configuration Parameters

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| chunk_size | 400 | 200-800 | Words per chunk |
| chunk_overlap | 50 | 0-100 | Word overlap |
| top_k | 3 | 1-10 | Results returned |
| temperature | 0.7 | 0.0-1.0 | LLM randomness |

## Edge Cases

### Unicode Support
Test strings: 你好世界, مرحبا, Здравствуй, 🚀🎯✨

### Special Characters
Test: !@#$%^&*()_+-=[]{}|;':",./<>?

### Performance Tests
- Document size: 1KB - 10MB
- Chunk count: 1 - 10,000+
- Concurrent queries: 1 - 100

## Error Handling

All components implement proper error handling:
```swift
enum DocumentProcessingError: Error {
    case unsupportedFormat
    case pdfLoadFailed
    case emptyDocument
    case corruptedFile
}
```

## Testing Checklist

- [ ] Import various document types
- [ ] Verify chunk boundaries
- [ ] Validate embedding dimensions
- [ ] Test retrieval accuracy
- [ ] Measure performance metrics
- [ ] Handle edge cases gracefully

## References

- Apple NLEmbedding: https://developer.apple.com/documentation/naturallanguage/nlembedding
- Vector similarity: https://en.wikipedia.org/wiki/Cosine_similarity
- RAG paper: arXiv:2005.11401
"""#
        )
    ]

    /// Total number of bundled sample documents, used for quota calculations.
    var sampleCount: Int { samples.count }

    /// Writes curated samples to disk and ingests them into the active RAG pipeline.
    func importSamples(into ragService: RAGService) async throws {
        let urls = try writeSamplesToTemporaryDirectory()
        for url in urls {
            try await ragService.addDocument(at: url)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Persists each sample document in a temp directory and returns the file URLs.
    private func writeSamplesToTemporaryDirectory() throws -> [URL] {
        let tempDir = FileManager.default.temporaryDirectory
        var urls: [URL] = []
        for sample in samples {
            let filename = sample.filename.replacingOccurrences(of: " ", with: "-")
            let fileURL = tempDir
                .appendingPathComponent(filename + "-" + UUID().uuidString)
                .appendingPathExtension(sample.extension)
            try sample.body.write(to: fileURL, atomically: true, encoding: .utf8)
            urls.append(fileURL)
        }
        return urls
    }
}
