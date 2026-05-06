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
# OpenIntelligence Product Guide

## What makes OpenIntelligence different?

OpenIntelligence is a local-first document intelligence app, not a generic cloud chat tool.

It stands apart in four important ways:

1. **It answers from your library.** The app retrieves relevant passages from your files before it writes a response.
2. **It keeps evidence visible.** You can inspect source cards, filenames, excerpts, and supporting passages instead of trusting a black box.
3. **It keeps the workflow private.** Core parsing, OCR, chunking, retrieval, and indexing run on your device.
4. **It is built for Apple platforms.** The app is designed around Apple Intelligence, Apple frameworks, and private local workflows instead of third-party AI APIs.

The short version: OpenIntelligence combines grounded retrieval, visible evidence, local processing, and Apple-native AI in one document workflow.

---

## What files can OpenIntelligence accept?

### Strongest import formats

OpenIntelligence is strongest with:

- PDF
- DOCX, XLSX, PPTX
- Markdown and plain text
- CSV and RTF
- HTML, JSON, XML, YAML
- source code and technical notes
- JPEG, PNG, HEIC, TIFF, GIF
- MP3, M4A, WAV, AIFF, MP4, and MOV through transcription workflows

### Formats that usually need cleanup first

These formats still import, but they often lose structure or need conversion first:

- legacy Office files
- Apple iWork exports
- dense scanned tables
- unusual structured exports
- visually complex scientific PDFs

If a file is messy, exporting it to PDF or a modern Office format usually improves results.

---

## How answers stay grounded

OpenIntelligence does not dump an entire document into one giant prompt. Instead, it uses a document pipeline:

1. **Parse the file** into readable text and structure.
2. **Chunk the content** into smaller sections that can be searched and cited.
3. **Index the chunks** for semantic and keyword retrieval.
4. **Retrieve the best evidence** for the user’s question.
5. **Generate an answer from that evidence** instead of free-associating from model memory.
6. **Show source context** so the answer can be audited.

This is why the app can answer questions about a large library without pretending the whole library fits into one model prompt.

---

## What kinds of questions is the app good at?

OpenIntelligence is strongest on questions like:

- “What file types does OpenIntelligence handle best?”
- “How does OpenIntelligence work around the 4,096-token limit?”
- “What is the difference between on-device processing and Private Cloud Compute?”
- “What did this contract say about termination?”
- “Which section of this report explains the pricing model?”
- “Summarize the risks in this proposal and cite the sources.”

It is strongest when the answer should come from a document you can inspect afterward.

---

## Plans

### Free
- 5 documents
- 1 library
- Full grounded question answering
- All quality modes, with a daily quota on Maximum

### Pro Monthly / Annual
- Up to 1,000 documents
- Up to 5 libraries
- Better room for large ongoing research and multi-project work

### Lifetime
- One-time unlock
- Up to 1,000 documents
- Up to 10 libraries

The plan structure is about scale and organization. The core product idea stays the same: grounded answers over your own files.
"""#
        ),
        SampleDocumentDescriptor(
            filename: "RAG Technical Architecture",
            extension: "md",
            body: #"""
# RAG Technical Architecture

## What is the 4,096 token limit?

The 4,096 token limit is the size of the on-device model’s context window.

That limit is the total budget for:

- system instructions
- retrieved evidence
- the user’s question
- and space for the model to write an answer

OpenIntelligence does **not** literally exceed the 4,096-token limit. It works around the limit by selecting the most relevant evidence from the library and packing only that evidence into the available context window.

That is the core idea behind the product.

---

## Why the limit matters

If you paste an entire manual, policy set, or research paper into a small model context, three things happen:

1. the prompt becomes too large,
2. the important evidence gets buried,
3. and the answer becomes less reliable.

RAG solves this by retrieving the right slices of the document set instead of sending everything at once.

---

## How OpenIntelligence works around the limit

### 1. Parse

The app reads PDFs, modern Office files, notes, text, images, and transcriptable media using Apple-native parsing and OCR paths.

### 2. Chunk

Instead of storing one huge blob, the app breaks content into smaller sections that preserve headings, nearby context, and natural boundaries.

### 3. Embed

Each chunk is converted into a semantic vector so similar ideas can be found even when the wording changes.

### 4. Search two ways

OpenIntelligence combines:

- **semantic retrieval** for meaning
- **keyword retrieval** for exact terms and phrases

This hybrid approach is more reliable than using only embeddings or only keywords.

### 5. Re-rank and diversify

The system scores candidates again, removes redundant chunks, and tries to keep the evidence set varied but relevant.

### 6. Pack the context window carefully

Only the strongest passages make it into the final prompt. The app uses a compact evidence pack instead of raw full-document stuffing.

### 7. Generate a grounded answer

The answer is generated from retrieved evidence, and the user can inspect where it came from.

---

## Why this is better than pasting whole documents

This approach gives OpenIntelligence four advantages:

- it answers questions over documents that are much larger than the model context window,
- it stays faster on-device,
- it preserves citations and evidence review,
- and it reduces hallucination compared with generic chat workflows.

The app’s value is not that it has an unusually large model. The value is that it makes a smaller local model useful over larger document collections.

---

## Quality modes

### Standard

Standard is the fast grounded mode. It aims for concise, source-backed answers and should be the default for most lookups.

### Deep Think

Deep Think is the higher-effort reasoning mode for broader synthesis, comparison, and more involved document reasoning.

### Maximum

Maximum is the highest-effort mode. It is for cases where you want the system to spend more effort on retrieval and reasoning before answering.

---

## What makes the architecture trustworthy?

OpenIntelligence is designed to keep the retrieval layer visible:

- answers cite sources,
- retrieved evidence is inspectable,
- exact-value questions stay concise,
- and the app abstains when the evidence is weak.

That combination of grounded retrieval, inspectable evidence, and Apple-native execution is what makes the architecture useful in a real product.
"""#
        ),
        SampleDocumentDescriptor(
            filename: "Apple Intelligence & Private Cloud Compute",
            extension: "md",
            body: #"""
# Apple Intelligence & Private Cloud Compute

## What role does Apple Intelligence play in OpenIntelligence?

OpenIntelligence is built around Apple’s native AI stack. The app uses Apple platform frameworks for parsing, OCR, indexing, retrieval, and language-model workflows.

This matters because the product is designed around privacy, local execution, and Apple hardware rather than a third-party hosted AI dependency.

---

## When does the app stay on-device?

For the main document workflow, the app is local-first.

Core tasks that stay on-device include:

- document parsing
- OCR and visual recovery
- chunking
- indexing
- semantic retrieval
- keyword retrieval
- evidence packing
- and many everyday question-answering tasks

The short answer is simple: the core document pipeline stays local.

---

## What is Private Cloud Compute?

Private Cloud Compute, or PCC, is Apple’s privacy-preserving server-side compute path for requests that benefit from more remote inference capacity.

In OpenIntelligence, PCC is not the identity of the app. It is the higher-capacity path for requests that benefit from Apple’s private cloud.

---

## When can PCC enter the picture?

PCC enters the picture for harder requests such as:

- broader synthesis over retrieved evidence,
- more demanding multi-step reasoning,
- or tasks where on-device processing is not the best fit.

The product still prefers local execution first.

If someone asks, “When does a question stay on-device versus use Private Cloud Compute?”, the answer is:

- straightforward retrieval and many grounded answers stay local,
- while more demanding reasoning uses Apple’s private cloud path when the platform routes it there.

---

## Why this is different from a normal cloud AI product

OpenIntelligence is not built around sending your library to a developer-run AI backend.

Its design priorities are:

1. local document handling,
2. Apple-native model access,
3. cited retrieval over your own files,
4. and private higher-capability fallback through Apple infrastructure instead of a generic third-party API.

That is a major part of what makes the app feel different from a generic AI chat app.

---

## Privacy summary

- No developer-operated cloud is required for core document question answering.
- The app is designed around local storage, local indexing, and local retrieval.
- PCC, when used, is Apple’s privacy-preserving cloud path rather than an ordinary app vendor backend.

The product goal is simple: your documents should feel like your library, not like training data that escaped your control.
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

            let existingBody = try? String(contentsOf: fileURL, encoding: .utf8)
            if existingBody != sample.body {
                try sample.body.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            urls.append(fileURL)
        }

        return urls
    }
}
