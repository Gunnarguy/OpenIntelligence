# OpenIntelligence v4.1 Update Notes

OpenIntelligence version 4.1 is a focused reliability and performance update that builds upon the Apple Intelligence architectural foundation introduced in version 4.0. 

This release focuses on local sentence embeddings acceleration, live reasoning feedback, robust error recovery, and strict file-system persistence and sandboxing compliance. Below is an exhaustive breakdown of every change made in this release.

---

## 1. Core AI Local Sentence Embeddings Acceleration

We introduced a dedicated local sentence embedding provider leveraging Apple Silicon hardware acceleration:

*   **`CoreAISentenceEmbeddingProvider`**: Replaces generic tokenization and embedding logic with native, hardware-optimized tensor calculations on device. It loads specialized local sentence embedding model configurations and tokenizers.
*   **Fallback Paths**: Automatically detects CPU/GPU capabilities to schedule embedding generation threads on the optimal hardware core.

---

## 2. Real-Time Thinking Telemetry UI

To make the underlying reasoning loops of on-device LLMs transparent, we added real-time visual progress telemetry:

*   **`ThinkingStreamView`**: Displays live, animated indicators during LLM thinking and reasoning phases.
*   **`UnifiedMetricsBar` Integration**: Integrates the thinking stream view directly into the metrics bar at the bottom of the chat interface, providing immediate telemetry feedback to the user on active tokens, duration, and routing.
*   **Ingestion Queue Overlay Transition**: Replaced CPU-bound layout dynamic hierarchy rendering with GPU-accelerated opacity, scale, and offset transitions to eliminate layout stutter.

---

## 3. Robust Suggested Questions & Grammar Safeguards

We refined the query planning and question suggestions pipeline to guarantee clean, high-quality follow-up questions:

*   **Two-Pass Diversity Selector**: Prevents duplicated categories or narrow section topics by running a section-isolation pass, falling back round-robin to ensure we always surface the target 12 diverse chunks.
*   **POS Grammar Filters**: Integrates `NLTagger` Part-of-Speech analysis to filter out adverb suffixes (e.g. `simply`, `merely`), layout noise, and verbs from generated conceptual topics, ensuring suggested follow-up questions are grammatically clean and topic-grounded.

---

## 4. Secure Sandbox-Persistent Folder Picker

We resolved path resolution issues with iOS document and attachment pickers in iCloud Drive and external File Providers:

*   **Security-Scoped File Bookmarks**: The picker now captures a secure, persistent bookmark of the selected files (stored under `"openIntelligence.lastPickedFileBookmark"`).
*   **Directory Mapping**: On presentation, the bookmark is resolved using iOS-native options, active security scope is initiated, and the parent directory is set as the `directoryURL` target.
*   **Lifecycle Management**: Cleanly stops resource access on deinit, selection, or cancellation to prevent sandbox resource leaks.

---

## 5. Atomic Vector Store Writes & Cascading Deletions

We hardened storage, indexing, and sync layers to eliminate file corruption and orphaned database artifacts:

*   **Atomic Database Writes**: Replaced inline `FileHandle` appending in `BNNSVectorDatabase` with thread-safe atomic data replacement on disk, resolving size mismatches and mmap crashes.
*   **Cascading Deletions**: Deleting or discarding interrupted/paused ingestion items now triggers a clean cascade that removes document metadata, purges FTS5 indexes, wipes partial vectors from disk, and removes physical files from storage.
*   **Orphaned Chunk & File Cleanup**: Scans and garbage-collects physical files and vector databases to purge orphaned chunks whose parent documents are no longer active.
*   **Sync Tombstones**: Leverages `deleted_documents.json` tombstones to prevent bi-directional sync from resurrecting deleted files.
