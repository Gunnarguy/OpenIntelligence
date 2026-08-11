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
            filename: "OpenIntelligence Product Guide",
            extension: "md",
            body: #"""
# OpenIntelligence Product Guide

## What makes OpenIntelligence different?

OpenIntelligence is a document intelligence app built on Apple's native AI stack, not a generic cloud chat tool.

It stands apart in four important ways:

1. **It answers from your library.** The app retrieves relevant passages from your files before it writes a response.
2. **It keeps evidence visible.** You can inspect source cards, filenames, excerpts, and supporting passages instead of trusting a black box.
3. **It routes intelligently.** Standard queries run locally on Apple Silicon. Complex reasoning automatically escalates to Apple's zero-retention Private Cloud Compute when needed.
4. **It is built for Apple platforms.** The app uses WWDC26 FoundationModels APIs, Accelerate framework vector operations, and native Swift throughout.

The short version: OpenIntelligence combines grounded retrieval, visible evidence, dynamic model routing, and Apple-native AI in one document workflow.

---

## What files can OpenIntelligence accept?

OpenIntelligence supports 50+ file formats across five categories:

- **Documents:** PDF, DOCX, XLSX, PPTX, Pages, Numbers, Keynote, Markdown, CSV, RTF, TXT, HTML, JSON, XML, YAML
- **Code:** Swift, Python, JavaScript, TypeScript, Java, C, C++, C#, Go, Rust, Ruby, PHP, CSS, SQL, Shell, R, Kotlin, Dart, Lua, Perl, TOML, INI, and more
- **Audio:** M4A, MP3, WAV, AIFF — on-device transcription up to 2 hours per file
- **Video:** MP4, MOV — audio extraction with local transcription
- **Images:** JPEG, PNG, HEIC, TIFF, GIF, BMP, WebP — Vision OCR text extraction

If a file is messy or uses a legacy format, exporting it to PDF or a modern Office format usually improves results.

---

## How answers stay grounded

OpenIntelligence does not dump an entire document into one giant prompt. Instead, it uses a document pipeline:

1. **Parse the file** into readable text and structure.
2. **Chunk the content** into smaller sections that can be searched and cited.
3. **Index the chunks** for semantic and keyword retrieval.
4. **Retrieve the best evidence** for the user's question.
5. **Generate an answer from that evidence** instead of free-associating from model memory.
6. **Show source context** so the answer can be audited.

This is why the app can answer questions about a large library without pretending the whole library fits into one model prompt.

---

## What kinds of questions is the app good at?

OpenIntelligence is strongest on questions like:

- "What file types does OpenIntelligence handle best?"
- "How does the app route between on-device and Private Cloud Compute?"
- "What did this contract say about termination?"
- "Which section of this report explains the rollout model?"
- "Summarize the risks in this proposal and cite the sources."

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
- Up to 10 libraries
- Better room for large ongoing research and multi-project work

### Lifetime
- One-time unlock
- Unlimited documents
- Up to 20 libraries

The plan structure is about scale and organization. The core product idea stays the same: grounded answers over your own files.
"""#
        ),
        SampleDocumentDescriptor(
            filename: "RAG Technical Architecture",
            extension: "md",
            body: #"""
# RAG Technical Architecture

## How does dynamic model routing work?

OpenIntelligence uses a two-tier context window strategy based on query complexity and quality settings:

- **On-device:** Standard queries run locally on Apple Silicon using FoundationModels. Private, and never leaves the device. Measured on an iPhone A18 Pro: roughly 27 tokens/second, with time-to-first-token between 2.2 and 3.2 seconds. Routing escalates above a 4,096-token local budget.
- **Private Cloud Compute:** Complex reasoning, heavy synthesis, or deep comparisons escalate to Apple's PCC enclaves, which offer a larger context window than the device while maintaining zero-retention, end-to-end encrypted privacy. Measured on the same device: roughly 86 tokens/second, time-to-first-token 2.2 to 2.5 seconds. The exact PCC context size is reported by the system at runtime rather than fixed by this app.

Routing is automatic based on the complexity of your prompt, the selected quality mode, and your token requirements.

---

## Why retrieval matters

If you paste an entire manual into a model prompt:
1. The prompt becomes too noisy.
2. Important evidence gets buried.
3. Reliability drops.

RAG solves this by retrieving only the relevant snippets of your document set. This is effective whether using the 4K on-device window or the larger PCC window.

---

## The RAG Pipeline

### 1. Parse
The app reads 50+ formats using Apple-native parsing and Vision OCR.

### 2. Chunk
Content is broken into sections, preserving headings and natural boundaries.

### 3. Embed
Each chunk is converted into a semantic vector using the Accelerate framework, running on the GPU and Neural Engine.

### 4. Hybrid Search
We combine:
- **Semantic retrieval:** Finding meaning through vector similarity.
- **BM25 keyword retrieval:** Finding exact terms and identifiers.

### 5. Re-rank and Pack
The system scores, removes redundancies, and selects the most relevant evidence to fit into the active token window, whether that is the 4K on-device budget or the larger one PCC reports.

### 6. Generate and Verify
The answer is generated from evidence. A verification gate confirms the model's assertions against the source material before the answer appears in the Liquid Glass UI.

---

## Quality Modes

- **Standard:** Fast, concise, and typically runs on-device.
- **Deep Think:** Uses higher-effort reasoning for complex synthesis; may route to PCC.
- **Maximum:** Exhaustive retrieval and reasoning; uses full Neural Engine and PCC capacity.

---

## Telemetry HUD

Tap the status indicator during any query to open the Telemetry HUD. It shows:
- **Active Route:** On-Device vs. PCC.
- **Token Budget:** on-device vs. PCC usage against the active window.
- **Pathway:** Resolved execution steps.
- **Silicon Telemetry:** Live utilization stats.
"""#
        ),
        SampleDocumentDescriptor(
            filename: "Apple Intelligence & Private Cloud Compute",
            extension: "md",
            body: #"""
# Apple Intelligence & Private Cloud Compute

## What role does Apple Intelligence play in OpenIntelligence?

OpenIntelligence is built on Apple's WWDC26 FoundationModels framework. The app uses native Swift APIs for model access, parsing, OCR, indexing, retrieval, and language-model inference.

This matters because the product uses Apple's own AI infrastructure rather than a third-party hosted AI dependency.

---

## When does the app stay on-device?

The core document pipeline always runs locally:

- document parsing and OCR
- chunking and indexing
- semantic and keyword retrieval
- vector operations (Accelerate framework on GPU/Neural Engine)
- evidence packing

For answer generation, standard queries typically run on the 4K-token on-device model. The app prefers local execution first.

---

## What is Private Cloud Compute?

Private Cloud Compute (PCC) is Apple's zero-retention, end-to-end encrypted server-side inference path.

Key properties of PCC:

- No data retention after inference completes
- End-to-end encryption between device and enclave
- No developer access to user queries or responses
- A larger context window than the device allows, for complex reasoning

---

## When does PCC activate?

The app routes to PCC automatically when a query needs it:

- complex multi-step reasoning across multiple files
- synthesis that exceeds the 4K on-device token budget
- Deep Think or Maximum quality modes with heavy context

Routing is determined by query complexity, selected quality mode, and token requirements. You can see the active route in the Telemetry HUD.

---

## Why this is different from a normal cloud AI product

OpenIntelligence does not send your documents to a developer-operated backend.

1. Document handling, indexing, and retrieval are local.
2. Model access uses Apple's native FoundationModels APIs.
3. When PCC is used, it is Apple's privacy-preserving infrastructure — not a third-party API.
4. Every answer cites sources from your own library.

---

## Privacy summary

- No developer-operated cloud is involved in any part of the workflow.
- The app uses local storage, local indexing, and local retrieval.
- PCC, when used, is Apple's zero-retention encrypted infrastructure.
- Your documents are your library, not training data.
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

        let allURLs = try writeSamplesToDocumentsDirectory()

        // Skip samples already in the library.
        //
        // `RAGService` does have a duplicate check, but it compares the *managed* storage
        // path and cannot fire here: importing copies the file into managed storage first,
        // and `WorkspaceSyncService` uniquifies that copy against existing files by
        // appending "-2", "-3" and so on. By the time the check runs, the path no longer
        // matches the stored one, so the sample is admitted as a new document. That was
        // invisible until onboarding became replayable; replaying three times produced
        // nine sample documents, named `OpenIntelligence-Product-Guide-2.md` and upward.
        //
        // Matching on filename rather than hash is deliberate: these three files are
        // written by this app from string literals, so the name is a reliable identity,
        // and a user who renamed one should keep their copy rather than have it doubled.
        let existingNames = await MainActor.run {
            Set(ragService.documents.map { $0.filename })
        }
        let urls = allURLs.filter { !existingNames.contains($0.lastPathComponent) }

        guard !urls.isEmpty else {
            onProgress?(allURLs.count, allURLs.count, "Already imported")
            await MainActor.run { ragService.clearPendingReembeds() }
            return
        }

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
