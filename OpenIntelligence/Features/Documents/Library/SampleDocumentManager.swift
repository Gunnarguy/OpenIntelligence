import CryptoKit
import Foundation

/// Describes a built-in sample file packaged for onboarding.
struct SampleDocumentDescriptor {
    let filename: String
    let `extension`: String
    let body: String

    /// Filename as it lands on disk and in the library, spaces hyphenated.
    var storageFilename: String {
        filename.replacingOccurrences(of: " ", with: "-") + "." + `extension`
    }

    /// Fingerprint of the body text, used to notice when a shipped sample has been
    /// rewritten between app versions.
    var contentHash: String {
        let digest = SHA256.hash(data: Data(body.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// True when `filename` is this sample as it actually sits in a library, including a
    /// copy that managed storage renamed to `…-2.md`, `…-3.md` and so on.
    ///
    /// Managed storage uniquifies a colliding name by appending `-<n>` (`WorkspaceSyncService`,
    /// counter from 2). Every call site here used to match `storageFilename` exactly, which
    /// made those copies invisible: a refresh never deleted them, the import guard never
    /// counted them, so each pass left one more behind. A capture on 2026-08-27 showed a
    /// General library holding five documents for three samples, having previously reached
    /// `-3`. Matching the numbered form as well is what stops them accumulating.
    ///
    /// Deliberately strict: only `<stem>-<digits>.<same extension>` matches. A user's own
    /// `OpenIntelligence-Product-Guide-notes.md` is not a copy and is never touched.
    func matchesStoredCopy(_ filename: String) -> Bool {
        if filename == storageFilename { return true }
        guard (filename as NSString).pathExtension == `extension` else { return false }
        let stem = (storageFilename as NSString).deletingPathExtension
        let candidate = (filename as NSString).deletingPathExtension
        guard candidate.hasPrefix(stem + "-") else { return false }
        let suffix = candidate.dropFirst(stem.count + 1)
        return !suffix.isEmpty && suffix.allSatisfy(\.isNumber)
    }
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

OpenIntelligence is a document intelligence app built on Apple's native AI stack, not a wrapper around a cloud chat service.

It stands apart in four ways:

1. **It answers from your library.** Before it writes a word, the app retrieves the relevant passages from your own files, and the answer is built from those passages.
2. **It keeps the evidence visible.** Every answer carries source cards, filenames and excerpts, plus a metrics bar that shows how the answer was produced. You can audit it instead of trusting it.
3. **It runs on your device.** Reading, indexing, searching and answering all happen on Apple silicon. In this version every answer is produced on-device, and the app works with no connection at all. Support for Apple's Private Cloud Compute is built into the app and arrives with iOS and macOS 27; the guide "Apple Intelligence and Private Cloud Compute" in this library explains what that will add.
4. **It is Apple-native throughout.** Foundation Models for language, Vision for text recognition, Speech for transcription, Core ML for embeddings and re-ranking, Accelerate and Metal for the vector math. Swift end to end.

The short version: grounded answers, visible evidence, your device, Apple's own AI.

---

## What files can OpenIntelligence read?

- **Documents:** PDF, DOCX, XLSX, PPTX, Markdown, TXT, RTF, CSV, HTML, JSON, XML, YAML
- **Code:** Swift, Python, JavaScript, TypeScript, Java, C, C++, C#, Go, Rust, Ruby, PHP, CSS, SQL, shell scripts, R, Kotlin, Dart, Lua, Perl, TOML, INI and more
- **Audio:** M4A, AAC, MP3, WAV, AIFF, CAF. Transcribed on the device, up to two hours per file.
- **Video:** MP4, M4V, MOV. The audio track is transcribed on the device, with the same two-hour limit.
- **Images:** JPEG, PNG, HEIC, HEIF, TIFF, GIF, BMP, WebP. Text is recognised with Vision.

**Convert these first:** Pages, Numbers and Keynote files, and the older DOC, XLS and PPT formats. The import review tells you so when you select one, and an iWork file that is imported anyway fails with a clear error rather than adding an empty document to your library. Export to PDF or to the modern Office format and import that.

If a file is messy, scanned, or in a legacy format, exporting it to PDF usually gives the best results.

---

## How to add documents

- **The Add Documents button** opens the system file picker. You can select several files at once.
- **On the Mac, drag files from Finder** anywhere onto the library. Dropped files go through the same size and plan checks as picked ones. Folders are not accepted yet; drop the files from inside them.
- **In a chat,** the attachment button adds a file to the current library and to the conversation.

---

## What happens during an import

An import is a pipeline, and each stage runs on your device:

1. **Parse.** The file is read into text and structure. Pages that carry no usable text layer, such as scans, go through Vision text recognition. Pages laid out in two columns are read column by column rather than straight across.
2. **Detect the language once.** The document's language is worked out from the text it already contains, and text recognition is told that language rather than being asked to guess it on every page. A wrong guess corrects words against the wrong dictionary, so this matters for accuracy as well as speed.
3. **Chunk.** The text is split into passages along headings and natural boundaries, so a citation can point at a readable section.
4. **Embed and index.** Each passage is embedded by a Core ML sentence model and written to the vector index, and the same text goes into a full-text keyword index. Both are searched on every question.

**Large PDFs checkpoint as they go.** A PDF over 10 MB commits its progress page by page. If you quit the app or it is interrupted mid-import, the import resumes from the last page it finished, and the resumed item shows how far it already got. The one action that discards that progress is removing the item from the queue.

**Audio and video** are transcribed with the system's on-device speech recognition. The recording never leaves the device.

---

## How answers stay grounded

OpenIntelligence does not paste a whole document into one giant prompt. For every question it:

1. **Retrieves candidate passages** by meaning (vector similarity) and by exact words (keyword search), then merges the two lists.
2. **Re-ranks them** with a second, more precise model, and removes near-duplicates so the evidence covers more ground.
3. **Packs the best evidence** into the model's context window.
4. **Generates the answer from that evidence**, not from the model's memory.
5. **Verifies the answer against the passages** before showing it, and reports how each claim held up.
6. **Shows the sources**, so you can open the passage the answer came from.

This is why the app can answer over a large library without pretending the whole library fits in one prompt.

---

## What kinds of questions is the app good at?

It is strongest when the answer should come from a document you can inspect afterwards:

- "What file types does OpenIntelligence read?"
- "What happens if I quit while a large PDF is importing?"
- "What did this contract say about termination?"
- "Which section of this report explains the rollout model?"
- "Summarise the risks in this proposal and cite the sources."

It is weakest on questions your library says nothing about. When the evidence is thin, the answer says so rather than filling the gap from memory.

---

## Reading an answer

- **Source cards** under the answer open the passages it was built from.
- **The metrics bar** expands to show the route the query took (on-device in this version), the token budget it used against the model's window, the execution steps that ran, and the passages that were retrieved.
- **Response details** list each claim in the answer with its verification verdict.
- **The Silicon HUD** is a small floating readout of live CPU, GPU and Neural Engine activity. It is on by default, can be turned off in Settings under Appearance, and can be dragged anywhere. It sits over the place on the board where that silicon physically is.

---

## Plans

### Free
- 5 documents
- 1 library
- Full grounded question answering
- All three quality modes, with Maximum limited to three runs a day

### Pro Monthly / Annual
- Up to 1,000 documents
- Up to 10 libraries
- Unlimited Maximum mode
- Room for large ongoing research and multi-project work

### Lifetime
- One-time unlock
- Unlimited documents
- Up to 20 libraries
- Unlimited Maximum mode

The plans are about scale and organisation. The core idea does not change with the plan: grounded answers over your own files, on your own device.
"""#
        ),
        SampleDocumentDescriptor(
            filename: "RAG Technical Architecture",
            extension: "md",
            body: #"""
# RAG Technical Architecture

## Where the work runs

Every stage of OpenIntelligence runs on your device: parsing, text recognition, chunking, embedding, indexing, retrieval, re-ranking, packing, generation and verification.

- **Answer generation** uses Apple's on-device Foundation Model through the FoundationModels framework. Measured on an iPhone with the A18 Pro: roughly 27 tokens per second, with 2.2 to 3.2 seconds before the first token appears. The app asks the system for the model's real context window rather than assuming one. On current hardware that window is 4,096 tokens, which is the figure the rest of this document uses.
- **Private Cloud Compute** is Apple's server-side inference on Apple silicon servers, with no data retention and no access for the developer. Support for it is built into this app and is compiled out of App Store builds by the toolchain those builds use, so nothing escalates today and every answer is produced on this device. It arrives with iOS and macOS 27. On a local build with that toolchain, the same iPhone measured roughly 86 tokens per second from Private Cloud Compute with 2.2 to 2.5 seconds to first token. That measurement is real, and it was taken on a build that is not the one you are running.

When Private Cloud Compute is enabled, nothing is sent without asking. A consent sheet shows the request that would leave the device and its estimated size, and offers Always Allow or Just Once. The metrics bar under every answer names the route it actually took.

---

## Why retrieval matters

Paste an entire manual into a 4,096-token window and three things happen: most of it does not fit, what does fit buries the sentence that matters, and the answer degrades. Retrieval-augmented generation solves this by finding the handful of passages that answer the question and giving the model only those. A precise retriever beats a bigger model for this job.

---

## The pipeline

### 1. Parse
Each format has its own reader. Scanned pages go through Vision's document recognition, which on iOS and macOS 26 returns text with its layout, so two-column pages are read column by column. The document's language is detected once from its own text and passed to the recogniser, rather than letting it guess per page.

### 2. Chunk
Text is split into passages along headings and natural boundaries, and every passage remembers the document, page and byte range it came from so a citation can be exact.

### 3. Embed
Each passage becomes a semantic vector using the all-MiniLM-L6-v2 sentence model, run through Core ML, which schedules it on the Neural Engine where the device has one. Query embeddings use the same model.

### 4. Store
Vectors live in a memory-mapped file. Similarity search runs through Accelerate's vDSP routines on the CPU for libraries under 1,000 passages, and switches to a Metal compute shader for cosine similarity across larger libraries. The keyword index is SQLite FTS5.

### 5. Hybrid search
The vector search and the BM25 keyword search run independently on every question and are merged by reciprocal rank fusion, so a passage that only one of them found still gets a fair score. Identifiers, part numbers and exact phrases come through the keyword arm; paraphrases come through the vector arm.

### 6. Re-rank and diversify
The merged candidates are re-scored by a cross-encoder, the ms-marco-TinyBERT-L2-v2 model run through Core ML, which reads the question and each passage together rather than comparing two vectors. Maximal marginal relevance then removes near-duplicates so the evidence covers more of the document instead of repeating one paragraph.

### 7. Pack
The top passages are selected and trimmed to fit the 4,096-token budget alongside the instructions, the question and room for the answer.

### 8. Generate and verify
The answer is generated from the packed evidence. Verification gates then check the answer's claims against the passages, and each claim's verdict is shown in the response details. Every mode runs the gates; the modes differ in how strict the confidence bar is.

---

## Quality modes

All three modes run the full pipeline above, including cross-encoder re-ranking, duplicate removal and verification. None of them changes where the model runs. What they change is how much evidence is gathered and how hard the app works on it.

- **Standard.** One retrieval pass. 30 candidate passages, a similarity floor of 0.28, no query expansion, and the surrounding passages of each hit included for context. Verification confidence threshold 0.50. Fast, and the right default for lookups and direct questions.
- **Deep Think.** A multi-step research loop run by an agentic orchestrator. Each step retrieves 35 candidates with a wider similarity floor of 0.25, the question is expanded into up to 8 variants plus a hypothetical answer used as an extra search probe, and retrieved passages are compressed to what bears on the question. Verification threshold 0.60. For synthesis across documents and questions with several parts.
- **Maximum.** The same loop with the widest net: 50 candidates per step, a similarity floor of 0.20 that lets the re-ranker decide, up to 12 query variants, passages kept in full rather than compressed, and a verification threshold of 0.80. Free plans get three Maximum runs a day; Pro and Lifetime are unlimited.

---

## Seeing the work

Two surfaces show what happened, and they are easy to confuse.

**Under each answer** is the metrics bar. Expand it for the route the query took, the token budget it used against the active window, the execution steps that ran, and the passages it retrieved. Response details list every claim with its verification verdict.

**The Silicon HUD** is the small floating readout of live CPU, GPU and Neural Engine activity. It is on by default, can be switched off in Settings under Appearance, and can be dragged anywhere. It sits over the place on the board where that silicon physically is.
"""#
        ),
        SampleDocumentDescriptor(
            filename: "Apple Intelligence & Private Cloud Compute",
            extension: "md",
            body: #"""
# Apple Intelligence and Private Cloud Compute

## What role does Apple Intelligence play in OpenIntelligence?

OpenIntelligence is built on the FoundationModels framework that ships with iOS and macOS 26, which gives apps direct access to the on-device model behind Apple Intelligence. Around it the app uses Vision for text recognition, Speech for transcription, Core ML for embedding and re-ranking, and Accelerate and Metal for vector math. There is no third-party AI service anywhere in the pipeline.

This matters because the product runs on Apple's own AI infrastructure, on hardware you already own, rather than on a developer's servers.

---

## What stays on the device?

In this version, everything:

- document parsing and text recognition
- chunking and indexing
- semantic and keyword retrieval
- embedding on the Neural Engine, and vector math through Accelerate on the CPU with Metal for larger libraries
- evidence packing
- answer generation with the on-device Foundation Model
- verification of the answer against the evidence

The app needs no connection to do any of it. On a plane, in a dead zone, in a locked-down office, your library still answers.

---

## What is Private Cloud Compute?

Private Cloud Compute is Apple's server-side inference for Apple Intelligence. It runs on Apple silicon servers and is designed so that the request is processed and then gone. Apple's stated properties:

- No data retention after the request completes
- End-to-end encryption between the device and the server
- No access for the developer, and no access for Apple, to your request or its answer
- Independent verifiability of the server software

For OpenIntelligence it means the same grounded pipeline with more headroom for long, evidence-heavy questions.

---

## When does Private Cloud Compute arrive?

**Not in this build.** Support is built into the app and is compiled out of App Store builds by the toolchain they use, so every answer today is produced on this device, and the metrics bar under each answer will say so. It arrives with iOS and macOS 27.

When it is enabled, this is what changes:

- **Nothing is sent without asking.** A consent sheet appears before anything leaves the device, showing the request that would be sent and its estimated size, with Always Allow and Just Once.
- **Routing becomes a choice the app can make** for questions that need more than the device can give: complex multi-step reasoning across several files, synthesis that exceeds the on-device token budget, or Deep Think and Maximum runs with heavy context.
- **Every answer still names its route.** Expand the metrics bar to see whether it ran on the device or on Private Cloud Compute.
- **It is fast.** Measured on a local build with the iOS 27 toolchain, an iPhone with the A18 Pro received roughly 86 tokens per second from Private Cloud Compute, against 27 on the device.

---

## Why this is different from a normal cloud AI product

OpenIntelligence never sends your documents to a developer-operated backend.

1. Document handling, indexing, retrieval and verification are local.
2. Model access goes through Apple's FoundationModels framework, on the device.
3. When Private Cloud Compute is enabled, it is Apple's privacy-preserving infrastructure, consented to per request, and never a third-party API.
4. Every answer cites passages from your own library.

---

## Privacy summary

- No developer-operated server is involved in any part of the workflow.
- Storage, indexing, retrieval and answering are local in this version.
- Private Cloud Compute, when it arrives, is Apple's zero-retention encrypted infrastructure, and it asks first.
- Your documents are your library, not training data.
"""#
        ),
    ]

    /// Total number of sample documents, used for quota calculations.
    var sampleCount: Int { samples.count }

    /// Writes curated samples to disk and ingests them into the active RAG pipeline.
    /// Uses `.onboarding` context to prevent self-tuning rebuilds during initial setup.
    /// Now uses the ingestion queue so UI can observe progress via `ragService.ingestionItems`.
    /// - Parameter containerId: library to import into. `nil` uses the active library,
    ///   which is correct when the user pressed the button. The automatic refresh passes
    ///   an explicit id instead, because it fires on whatever screen the user happens to
    ///   be on and must not deposit samples into a library they were merely looking at.
    func importSamples(
        into ragService: RAGService,
        containerId: UUID? = nil,
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
        let urls = allURLs.filter { url in
            guard let sample = samples.first(where: { $0.storageFilename == url.lastPathComponent }) else {
                return !existingNames.contains(url.lastPathComponent)
            }
            return !existingNames.contains(where: { sample.matchesStoredCopy($0) })
        }

        guard !urls.isEmpty else {
            onProgress?(allURLs.count, allURLs.count, "Already imported")
            await MainActor.run { ragService.clearPendingReembeds() }
            return
        }

        // Use queue-based ingestion so ragService.ingestionItems gets populated
        // This allows the UI to observe real-time pipeline stage updates
        let result = await ragService.ingestDocuments(
            urls,
            context: .onboarding,
            containerId: containerId
        )

        // Stamp what was ingested. Without this a fresh install would immediately report
        // its brand-new samples as stale, because no hash would have been recorded.
        recordImportedHashes(for: samples)

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
    // MARK: - Keeping imported samples current

    /// UserDefaults key holding the content hash last ingested for a given sample.
    private func importedHashKey(for sample: SampleDocumentDescriptor) -> String {
        "samples.importedHash.\(sample.storageFilename)"
    }

    /// Samples whose shipped text differs from what is actually sitting in the library.
    ///
    /// This exists because editing a sample's Swift literal updates the file on disk but
    /// does nothing to a library that already ingested the old text: the chunks and
    /// vectors are built at import time. Between v4.9 and v5.0 the samples were corrected
    /// in five places — they claimed Pages/Numbers/Keynote support the app does not have,
    /// attributed embedding to the wrong framework, and documented a "Telemetry HUD"
    /// screen that does not exist. Anyone who onboarded before v5.0 is still being told
    /// those things by their own library, and being told them as sourced fact.
    func staleImportedSamples(in ragService: RAGService) -> [SampleDocumentDescriptor] {
        let defaults = UserDefaults.standard
        let importedNames = Set(ragService.documents.map(\.filename))

        return samples.filter { sample in
            // Only offer to refresh a sample the user actually has. Never re-add one
            // they deleted on purpose.
            guard importedNames.contains(where: { sample.matchesStoredCopy($0) }) else { return false }
            let recorded = defaults.string(forKey: importedHashKey(for: sample))
            return recorded != sample.contentHash
        }
    }

    /// Records what was ingested, so a later build can tell whether it has drifted.
    private func recordImportedHashes(for descriptors: [SampleDocumentDescriptor]) {
        let defaults = UserDefaults.standard
        for sample in descriptors {
            defaults.set(sample.contentHash, forKey: importedHashKey(for: sample))
        }
    }

    /// Replaces stale sample documents in place.
    ///
    /// Removes the old document first and then re-imports, rather than importing
    /// alongside. Managed storage uniquifies a colliding filename by appending `-2`
    /// (`WorkspaceSyncService`, counter starting at 2), and that rename happens *before*
    /// the duplicate check compares paths — so importing over the top produces
    /// "OpenIntelligence-Product-Guide-2.md" sitting next to the original rather than
    /// replacing it.
    ///
    /// - Returns: the display names refreshed, for the notice shown to the user.
    @discardableResult
    func refreshStaleSamples(in ragService: RAGService) async -> [String] {
        let stale = staleImportedSamples(in: ragService)
        guard !stale.isEmpty else { return [] }

        // Match numbered copies as well, not just the canonical name — otherwise a stray
        // `…-2.md` from an earlier refresh survives this pass and the re-import below adds
        // a fresh canonical copy beside it, which is exactly how a library reaches five
        // documents for three samples.
        let doomed = ragService.documents.filter { document in
            stale.contains { $0.matchesStoredCopy(document.filename) }
        }

        // Put them back where they were, never into whatever library is on screen.
        //
        // `ragService.documents` spans every container, so the samples are found no
        // matter which library is selected — but `enqueueDocuments` stamps the *active*
        // container onto each item. Opening Documents with "Library 2" selected would
        // therefore delete the samples from General and re-import them into Library 2.
        //
        // A document with a `nil` containerId belongs to the default library, which is
        // the same rule `documentsForContainer` applies, so `nil` resolves to
        // `containers.first` rather than to the active one.
        let defaultContainerId = ragService.containerService.containers.first?.id
        let targetContainerId = doomed.compactMap(\.containerId).first ?? defaultContainerId

        for document in doomed {
            do {
                try await ragService.removeDocument(document)
            } catch {
                Log.error(
                    "[SampleDocumentManager] Could not remove stale sample '\(document.filename)': \(error.localizedDescription)",
                    category: .ingestion
                )
                return []
            }
        }

        do {
            try await importSamples(into: ragService, containerId: targetContainerId)
            recordImportedHashes(for: stale)
            return stale.map(\.filename)
        } catch {
            Log.error(
                "[SampleDocumentManager] Re-import of refreshed samples failed: \(error.localizedDescription)",
                category: .ingestion
            )
            return []
        }
    }

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
