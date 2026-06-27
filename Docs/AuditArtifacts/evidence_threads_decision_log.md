# Evidence Threads Design & Decision Log

This document evaluates the two proposed architectural designs for storing and managing **Evidence Threads** in OpenIntelligence. The analysis is performed against the constraints of the existing local-first architecture, App Store Review guidelines, memory limits, and future synchronization roadmaps.

---

## 1. Architectural Designs under Evaluation

### Design A: Monolithic Message Storage
*   **Concept:** Add an optional `threadId: UUID?` property to the existing `ChatMessage` model. Store all messages across all threads in the library's unified `chat_history_<containerId>.json` file.
*   **State Resolution:** When loading a thread, load the entire library's history and filter messages by `threadId` in-memory.

### Design B: Isolated Thread Storage
*   **Concept:** Store each Evidence Thread as a separate JSON file under a dedicated directory structure:
    `LocalCache/EvidenceThreads/<containerId>/thread_<threadId>.json`
*   **Index File:** Maintain a directory index:
    `LocalCache/EvidenceThreads/<containerId>/index.json`
    to store high-level thread metadata (e.g., titles, pinned findings count, timestamps) for fast sidebar rendering.

---

## 2. Comparative Evaluation Matrix

| Evaluation Criterion | Design A: Monolithic Storage | Design B: Isolated Thread Storage | Chosen Design & Justification |
| :--- | :--- | :--- | :--- |
| **Data Loss Risk** | **Critical Risk:** `RAGService.swift` enforces a hard limit of `maxMessagesPerContainer = 200`. In a monolithic file, when the total message count across all threads in a library exceeds 200, older threads' messages are silently deleted during trimming. | **Negligible Risk:** Each thread is isolated in its own file. Individual thread histories are capped at 100 messages, protecting inactive threads from pruning. | **Design B:** Design A's silent message pruning violates the core requirement of durable, long-term inquiry tracking. |
| **Migration Complexity** | **Low:** Only requires adding `threadId: UUID?` to `ChatMessage.CodingKeys` and initializing it as `nil` for legacy messages. | **Medium:** Requires directory creation and a metadata index file. Legacy messages can be migrated into a designated "Default Thread" file upon first launch. | **Design B:** The small complexity increase is offset by the elimination of schema migrations on the core chat history file. |
| **Corruption Blast Radius** | **High:** Any JSON encoding/decoding error or file write failure during concurrent operations corrupts `chat_history_<containerId>.json`, wiping out all threads in that library. | **Low:** Corrupting a single `thread_<threadId>.json` file only affects that specific conversation. The index and other threads remain intact. | **Design B:** Separating files limits the blast radius of unexpected disk failures or schema mismatches. |
| **UI Complexity** | **Medium:** View layers must filter, sort, and slice the monolithic message array in-memory. Switching threads requires resetting state hooks. | **Low:** The UI binds directly to the active thread's loaded array. The sidebar loads titles instantly from the lightweight `index.json` without parsing full transcripts. | **Design B:** Keeps the view model logic clean and responsive by separating metadata retrieval from message parsing. |
| **Sync Future (iCloud)** | **Critical Conflict Risk:** Monolithic sync uses a last-write-wins policy. Concurrent writes on two devices (e.g., editing Thread 1 on iPhone and Thread 2 on Mac) will overwrite each other, causing complete data loss for one device. | **Low Conflict Risk:** Since threads are isolated, editing Thread 1 and Thread 2 concurrently merges cleanly, as they are separate files. Conflict only arises if the same thread is edited. | **Design B:** Design B is the only viable path to support eventual multi-device syncing without a complex merge engine. |
| **Delete/Export Simplicity** | **High:** Deleting a thread requires filtering a large array and rewriting the monolithic file. Exporting requires filtering and transforming in-memory. | **Very Low:** Deleting is a standard file deletion (`removeItem(at:)`). Exporting reads the thread file directly and writes it to the destination. | **Design B:** Clean file-level deletions are faster and minimize CPU/disk overhead. |
| **Compatibility with Existing Chat** | **High:** Directly reuses the existing `RAGService.persistChatHistory` pipeline. | **High:** Existing single-thread chat history is treated as the "Default Thread" and migrated, leaving the core RAG runtime unchanged. | **Design B:** Offers a clean path to backward compatibility without polluting the active namespace. |
| **Performance with Large Thread Counts** | **Poor:** Reading, parsing, and writing a single large JSON file containing hundreds of messages increases latency as the thread count grows. | **High:** Reads and writes are isolated to the active thread file (typically < 10KB). Sidebar rendering uses the pre-indexed metadata file. | **Design B:** Prevents UI stutters and heavy disk operations as the user creates more threads. |

---

## 3. Final Recommendation: Design B (Isolated Thread Files)

Design B is the selected storage architecture for Evidence Threads. 

### Implementation Rules:
1.  **Exclusion from Backup and Sync:** To enforce Phase 1 local-only requirements, thread files and indexes **must** be stored under the `LocalCache` directory:
    `AppSupportPaths.localCacheDir().appendingPathComponent("EvidenceThreads", isDirectory: true)`
    Because `LocalCache` is explicitly declared in `WorkspaceSyncService.localOnlyEntryNames`, this path is recursively excluded from iCloud sync and local migration sweeps.
2.  **Atomic Local-Only Writes:** To prevent the `.localWorkspaceDidChange` notification (which triggers background sync evaluations) from firing on every token stream write, the thread store must bypass `WorkspaceSyncService.coordinatedWriteData` and utilize a dedicated local-only atomic writer:
    `coordinatedWriteLocalOnlyData(_:to:)`
3.  **Default Thread Migration:** On the first launch of Version 27, the application will check if a legacy `chat_history_<containerId>.json` file exists. If found, its messages will be parsed, assigned a constant `defaultThreadId`, and migrated to `thread_defaultThreadId.json` under `LocalCache/EvidenceThreads/<containerId>/`. The legacy file is then safely archived.
