# OpenIntelligence v4.1 Technical Changelog

Changes covered: commit `a4c70383ad60c22faab6a44135d289a15488396f` through `fc076b637d1766ebefeb819dd997ef5133d955a0`.

This document summarizes the technical implementation changes behind the version 4.1 release.

---

## 1. Core AI Local Embeddings
*   **`CoreAISentenceEmbeddingProvider`**: Replaces the generic tokenizer and embedding interface with a dedicated local execution model. Utilizes local tokenizers and dense vector models directly on device.
*   **Hardware Scheduling**: Thread-safe configuration to schedule tensor calculations across available CPU and GPU clusters based on system capability and model configuration.

---

## 2. Telemetry and Visual Pipeline Telemetry
*   **`ThinkingStreamView`**: Added a dedicated subview in `UnifiedMetricsBar` to display real-time animation state during active LLM thinking/reasoning cycles.
*   **GPU-Accelerated Popups**: Refactored `IngestionQueueOverlay` transitions to utilize static layout hierarchy with reactive `.opacity`, `.scaleEffect`, and `.offset` view modifiers animated via spring transitions (`.spring(response: 0.35, dampingFraction: 0.82)`). Bypasses dynamic layout hierarchy calculations, eliminating visual lag during transition.

---

## 3. Suggested Questions & Grammar Pipelines
*   **Two-Pass Diversity Selection**: Refactored `SuggestedQuestionsService.selectDiverseChunks` to perform a first pass isolating unique section titles. Falls back to a relaxed round-robin backfill in the second pass to guarantee a full set of candidate chunks (up to target count 12).
*   **NLTagger POS Verification**: Implemented Part-of-Speech tagging analysis in `isValidConceptualTopic` using `NLTagger`. Rejects phrases containing adverbs, layout noise, or ending in invalid parts of speech (verbs, pronouns, conjunctions, prepositions), ensuring high grammatical quality of suggestions.

---

## 4. Security-Scoped Folder Picker Persistence
*   **File Bookmark Storage**: Captures a security-scoped bookmark of the selected file (`firstURL.bookmarkData(options: [], ...)`) and stores the resulting `Data` block in `UserDefaults` under key `"openIntelligence.lastPickedFileBookmark"`.
*   **Directory URL Hints**: Resolves the bookmark during view controller construction using `URL(resolvingBookmarkData:options:[], ...)`, starts the security-scoped access, and assigns its parent directory (`deletingLastPathComponent()`) to the picker's `directoryURL`.
*   **Lifecycle Management**: Invokes `stopAccessingSecurityScopedResource()` inside the coordinator's `deinit`, selection handler, and cancel handler to prevent system sandbox leaks.
*   **Path-Based Fallback**: Retains `"openIntelligence.lastPickedDirectoryPath"` path storage using `URL(fileURLWithPath:path, isDirectory: true)` as a secondary fallback if the bookmark is missing or fails to resolve.

---

## 5. Storage Safety & Deletion Cascades
*   **Atomic Vector DB Saves**: Updated `BNNSVectorDatabase.saveToDisk()` to build a contiguous memory buffer and perform atomic file replacement on disk instead of appending via mutable `FileHandle` writes. This resolves cache incoherency, memory-map alignment crashes, and file size conflicts.
*   **Cascading Ingestion Deletions**: Hardened `discardPausedIngestionQueue()` in `RAGService.swift` to invoke `removeDocument()`, triggering a cascading purge across:
    *   FTS5 SQLite search indexes.
    *   Spotlight / Entity Search indexes.
    *   Vector database chunks and norms.
    *   Local document storage directories.
*   **Tombstone Merging**: Updated `WorkspaceSyncService.swift` to synchronize `deleted_documents.json` tombstones bi-directionally, preventing files from being resurrected during sync.
*   **Automated Garbage Collection**: Added cleanup routines inside `WorkspaceSyncService` to prune unreferenced physical files in `ImportedDocuments` and orphaned vector store chunks whose parent documents are no longer active in metadata.
