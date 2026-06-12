# Social Media Post Templates: OpenIntelligence v4.1

Changes covered: commit `a4c70383ad60c22faab6a44135d289a15488396f` through `fc076b637d1766ebefeb819dd997ef5133d955a0`.

Version 4.1 is a dedicated performance and reliability pass on top of the Apple Intelligence-native RAG foundation introduced in 4.0. The updates focus on hardware-accelerated local sentence embeddings, real-time reasoning feedback, folder persistence for iCloud, database anti-corruption, and high-fidelity suggested questions.

Project link: https://github.com/Gunnarguy/OpenIntelligence

---

## Full Pick-and-Choose Change Inventory

### Core AI Embeddings
- **CoreAISentenceEmbeddingProvider**: Custom provider running local, silicon-accelerated tokenization and embedding generation directly on Apple device hardware.

### UI Telemetry & Visuals
- **Thinking Telemetry**: Integrates `ThinkingStreamView` directly inside `UnifiedMetricsBar` to display live visual reasoning/thinking feedback while the model processes.
- **Lag-Free Overlay**: Refactored `IngestionQueueOverlay` transitions to use GPU-accelerated opacity, scale, and offset properties. Bypasses dynamic layout calculations, eliminating UI popup lag.

### iCloud Sandboxing & Persistence
- **Secure Folder Memory**: Implemented security-scoped file bookmark directory mapping, resolving iCloud Drive and File Provider path sandboxing constraints so the picker consistently remembers the last folder you used.
- **Resource Lifecycle**: Automatically manages security resource references, stopping access on deinit, cancel, or selection to prevent memory/sandbox leaks.

### Database Safety & Cascading Purges
- **Atomic Vector Store Writes**: Rewrote `BNNSVectorDatabase` disk saves to build a contiguous data buffer and perform thread-safe atomic replacements on disk, preventing file corruption and mmap crashes.
- **Cascading Discard**: Discarding or canceling incomplete uploads now triggers a clean cascading deletion across FTS5 database tables, vector chunks, physical files, and Spotlight indices.
- **Sync Tombstones**: Leverages `deleted_documents.json` tombstone synchronization to prevent bi-directional sync from resurrecting deleted library files.

### Suggested Questions
- **Two-Pass Diversity**: Resolves category repetition by running a section-isolation pass before falling back to relaxed round-robin.
- **POS Tag Grammar Filtering**: Uses `NLTagger` Part-of-Speech analysis to filter out adverb suffixes, layout noise, and verb endings from generated conceptual topics, ensuring grammatically clean follow-up questions.

---

## 1. Best Default Launch Post (X / Threads)

I just shipped OpenIntelligence v4.1, a reliability and performance pass for our Apple Intelligence-native document system. 

WWDC26 set the architecture, and v4.1 makes the local engine much faster and more transparent:

- **Core AI Embeddings**: Added a local `CoreAISentenceEmbeddingProvider` for hardware-accelerated sentence embeddings on device silicon.
- **Real-Time Thinking Telemetry**: Watch the model's reasoning loop live via `ThinkingStreamView` inside the metrics bar.
- **Lag-Free Overlay**: Optimized the upload overlay transition to be completely GPU-accelerated (no more layout stutters).
- **iCloud Folder Persistence**: Used security-scoped bookmarks so the file picker remembers exactly which folder you last opened.
- **Atomic Vector Writes**: Hardened local database writes to be fully atomic, preventing file corruption.
- **Cascading Deletions**: Discarding uploads now completely purges database entries, physical files, and Spotlight indexes.

Open source:
https://github.com/Gunnarguy/OpenIntelligence

#WWDC26 #AppleIntelligence #SwiftUI #RAG #OpenSource #iOSDev

---

## 2. Technical LinkedIn Post

OpenIntelligence v4.1 is now live! 🚀

Following the major v4.0 overhaul, v4.1 focus is on local silicon performance, UI rendering telemetry, and hardening app storage boundaries under iOS sandbox constraints.

Key Technical Highlights:
1. **Core AI local embeddings**: Swapped the generic vector pipeline for `CoreAISentenceEmbeddingProvider`, routing tokenization and dense embedding math directly through Apple Silicon tensor accelerators.
2. **MainActor Safety**: Enforced strict `@MainActor` isolation for system LLM availability routing to eliminate background thread assertions.
3. **iCloud & File Provider Sandboxing**: Solved persistent directory mapping in `UIDocumentPickerViewController`. By saving security-scoped file bookmarks and resolving them with iOS-compatible options, the picker now has valid permissions to open back to the user's last picked directory.
4. **Anti-Corruption DB Saves**: Switched the `BNNSVectorDatabase` save mechanism from `FileHandle` appends to atomic file replacements, resolving memory-mapped alignment conflicts and size mismatch crashes.
5. **Zero-Remnant Cascading Purges**: Integrated sync tombstones (`deleted_documents.json`) and cascading RAG deletions to purge FTS5 indices, physical documents, and Spotlight items whenever an ingestion is canceled or discarded.
6. **Live Telemetry & UI**: Added an animated `ThinkingStreamView` for real-time model reasoning states, and optimized the ingestion overlay transitions to run entirely on the GPU.

Check out the code:
https://github.com/Gunnarguy/OpenIntelligence

#iOSDevelopment #Swift #SwiftUI #RAG #AppleIntelligence #CoreAI #OpenSource

---

## 3. Single Post (X / Threads)

OpenIntelligence v4.1 brings local Core AI sentence embeddings, live LLM reasoning/thinking telemetry, and robust iCloud folder picker memory to the app. 

We hardened the storage layer with atomic vector database writes and cascading file purges, and updated overlay animations to run entirely on the GPU for a lag-free UI experience.

Full code:
https://github.com/Gunnarguy/OpenIntelligence

---

## 4. X Thread

1/ OpenIntelligence v4.1 is out, refining the Apple Intelligence-native RAG engine we introduced in v4.0. 

Most of this release is about local silicon speed, storage safety, and visual refinement. Here is what changed:

2/ **Core AI local embeddings**: We added `CoreAISentenceEmbeddingProvider` to run tokenization and vector calculations directly on device hardware, utilizing GPU and Neural Engine clusters for high-speed local processing.

3/ **Live Thinking Telemetry**: We added `ThinkingStreamView` inside the chat metrics bar. You can now see the model's active reasoning state in real-time as it gathers thoughts, resolves routing, and writes answers.

4/ **iCloud Picker Memory**: Replaced raw paths with security-scoped file bookmarks. The iOS document picker now securely remembers the exact iCloud Drive or File Provider folder you last imported from, opening there by default.

5/ **Atomic Vector Writes**: Hardened `BNNSVectorDatabase` disk saves. Instead of appending to memory-mapped files via `FileHandle` (which caused size mismatches), we write the database atomically, resolving file corruption.

6/ **Zero-Remnant Purging**: Canceling or discarding a document now triggers a clean cascading deletion across SQLite FTS5 search indexes, vector database chunks, physical files, and Spotlight indices. No data fragments left behind.

7/ **Suggested Questions Polish**: Integrated `NLTagger` Part-of-Speech analysis to filter out adverb suffixes and layout noise, ensuring suggested follow-up questions are grammatically clean and grounded.

8/ **GPU-Accelerated Visuals**: Replaced dynamic view layout changes in the ingestion queue with GPU-driven scale and opacity transitions, eliminating UI popup lag.

9/ Get the open-source code here:
https://github.com/Gunnarguy/OpenIntelligence

#AppleIntelligence #SwiftUI #IndieDev #RAG #OpenSource
