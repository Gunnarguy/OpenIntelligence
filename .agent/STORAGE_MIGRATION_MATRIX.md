# OpenIntelligence Storage Migration Matrix

This matrix documents the persisted models, formats, and storage engines utilized in the application.

## Storage Components

### 1. SQLite Full-Text Search Database
*   **Implementation File:** `SQLiteFullTextService.swift`
*   **Format:** SQLite3 database file.
*   **Tables:** Full-text indexing tables for documents and chunks.
*   **Migration Protocol:** Dynamic column existence checks and index rebuilding on schema changes. `[evidence_level: code_verified, confidence: exact]`

### 2. BNNS Vector Database
*   **Implementation File:** `BNNSVectorDatabase.swift`
*   **Format:** Memory-mapped binary vector files + metadata JSON.
*   **Storage Directory:** Application Support / VectorCache.
*   **Migration Protocol:** Re-index vectors if dimension size changes from 384. `[evidence_level: code_verified, confidence: exact]`

### 3. Evidence Threads JSON
*   **Implementation File:** `WorkspaceSyncService.swift` / `EvidenceThreadStore.swift`
*   **Format:** JSON files.
*   **Storage Directory:** `Application Support/EvidenceThreads/<containerId>/` (Moved from legacy local `LocalCache` folder in Phase 1B).
*   **Sync Behavior:** Coordinated file coordinator (NSFileCoordinator) for bidirectional iCloud syncing. `[evidence_level: code_verified, confidence: exact]`

### 4. Settings and Preferences
*   **Implementation File:** `SettingsStore.swift`
*   **Format:** Plist key-value storage (`UserDefaults`).
*   **Migration Protocol:** Loaded dynamically on launch; defaults applied programmatically. `[evidence_level: code_verified, confidence: exact]`

## PR Impact on Storage Boundaries (Phase A, verified 2026-07-13)
| PR | Boundary | Change | Migration/Integrity Risk | Disposition |
| :-- | :-- | :-- | :-- | :-- |
| #27 | SQLite FTS5 (`ensureColumnExists`) | Regex identifier allowlist | `definition` still raw-interpolated; runtime rejection path added | REWORK → consolidate with #55 into closed migration-descriptor enum |
| #55 | SQLite FTS5 (`ensureColumnExists`) | Identifier quoting + quoted PRAGMA param | `definition` still raw; competing with #27 on same function | REWORK → same consolidation |
| #39 | SQLite FTS5 (chunk/row inserts) | Prepared-statement reuse in loops | No per-row step/reset/clear-binding error checks; no rollback on row failure; failure semantics change | REWORK_THEN_BENCHMARK |
| #40 | SQLite FTS5 (structured-metadata delete) | Bound params → interpolated multi-statement `sqlite3_exec` | De-parameterization at a protected boundary; error attribution collapses | CLOSE |
| #42 | SQLite FTS5 (container delete logging) | SELECT-count → `sqlite3_changes()` | `sqlite3_changes` semantics under FTS5 vtab/cascades unproven | REWORK (verify or close) |
| #45 | SQLite FTS5 (structured-metadata delete) | Loop unroll into two blocks | None (identical behavior, more code) | CLOSE |
| #66 | UserDefaults | NEW persisted key `OpenIntelligence.QueryHistory` (plaintext queries) | New data class without retention/deletion/disclosure | CLOSE (privacy) |
| #44 | Tokenizer contract | byte_fallback honored | Token IDs / citation-offset shifts for affected configs | BLOCKED pending fixtures |
| #49 | BNNS vector store | Norm computation via `vDSP_svesq` | Persisted-norm compatibility for mmap'd vectors must be proven | REWORK (consolidation benchmark) |

## Mandatory Storage Test Battery — STATUS: NOT EXECUTED
No legacy database fixtures exist. Per the master directive, no storage-cluster change may enter the integration branch before: clean/repeated/partial/interrupted migration, corrupt schema, locked/busy database, disk full, WAL recovery, checkpoint, orphan detection, cross-container isolation, container/document/structured-row deletion, exact FTS tokenization, Unicode normalization, downgrade, backup-restore. `[evidence_level: code_verified (absence), confidence: exact]`
