# Phase 6 Documentation Audit Summary

## Scanned Documentation Overview
A broad scan of the repository's documentation directory was performed, covering the primary architectural and product-facing files. In total, **13 key markdown documents and changelogs** were analyzed to verify alignment with Phase 1–5 code and storage artifacts:
- `Docs/ARCHITECTURE.md`
- `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`
- `Docs/BILLING_AND_LIMITS.md`
- `Docs/INGESTION_PIPELINE.md`
- `Docs/PRIVACY_AND_ROUTING.md`
- `Docs/RETRIEVAL_PIPELINE.md`
- `Docs/Engineering/RAG_TECHNICAL.md`
- `Docs/Engineering/STORAGE_AND_PIPELINE_TRACE.md`
- `Docs/LIMITATIONS.md`
- `Docs/RELEASE_NOTES.md`
- `Docs/ROADMAP.md`
- `Docs/USER_CHANGELOG.md`
- `CHANGELOG.md`

---

## Key Categories of Contradictions Found

### 1. iCloud Sync Engine: CloudKit vs. iCloud Drive (Ubiquity)
- **Claimed in Docs**: `subsystem_map.md`, `component_inventory.csv`, and `data_flow_map.csv` claim that workspaces, metadata, and containers are synchronized across devices using a private CloudKit database.
- **Reality in Code**: `WorkspaceSyncService.swift` explicitly utilizes iCloud Drive Ubiquity containers (`NSFileCoordinator` and `NSMetadataQuery` file sweeps) to sync files in the base directory; no CloudKit database API calls are implemented.
- **Severity**: **HIGH**

### 2. Private Cloud Compute (PCC): Remote Enclaves vs. Local Simulation
- **Claimed in Docs**: `Docs/PRIVACY_AND_ROUTING.md` and `Docs/RETRIEVAL_PIPELINE.md` present Private Cloud Compute (PCC) remote enclave execution as fully active for escalated queries.
- **Reality in Code**: PCC execution is simulated entirely locally on `SystemLanguageModel.default` using a compatibility wrapper in `EngineSDKCompatibility.swift`. No secure enclave cryptographic connection or network execution is compiled in.
- **Severity**: **HIGH**

### 3. Database Architecture: Shared SQLite vs. Isolated Databases
- **Claimed in Docs**: `component_inventory.csv` implies that individual knowledge libraries utilize separate, isolated SQLite database files to guarantee isolation.
- **Reality in Code**: `SQLiteFullTextService.swift` uses a shared database file with shared tables, relying on column-based `container_id` isolation to prevent cross-container leaks.
- **Severity**: **MEDIUM**

### 4. Billing Storage: UserDefaults vs. Keychain Entitlements
- **Claimed in Docs**: `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` claims that purchase ledger entitlements and quota limits are secured in `KeychainStorage`.
- **Reality in Code**: `EntitlementStore.swift` stores subscription entitlements and document/library limits in `UserDefaults` via property bindings, while `KeychainStorage` is used strictly to save custom local API keys.
- **Severity**: **MEDIUM**

### 5. Embedding Infrastructure: Core ML vs. Core AI
- **Claimed in Docs**: `Docs/RELEASE_NOTES.md` describes Core AI sentence embeddings as active in the production build.
- **Reality in Code**: `CoreAISentenceEmbeddingProvider` is experimental scaffolding wrapped in `#if false` compile guards. Production sentence embeddings run exclusively on the Core ML provider.
- **Severity**: **MEDIUM**

### 6. Code Comments: In-Memory vs. Serialized Chat
- **Claimed in Docs**: `ChatMessage.swift` has a comment claiming that ChatV2 messages are transient and in-memory only.
- **Reality in Code**: Chat history is persisted and serialized to JSON on changes, matching `ChatV2` persistence logic.
- **Severity**: **LOW**

---

## Objective Tone & Pronoun Rule Violations

During the scan, **8 instances of first-person pronouns ("I")** and **1 instance of an informal developer greeting** were identified, violating the solo-developer communication rules:
- `Docs/ARCHITECTURE.md`: "I designed the codebase..."
- `Docs/PRIVACY_AND_ROUTING.md`: "I built OpenIntelligence...", "I built local user consent..."
- `Docs/RETRIEVAL_PIPELINE.md`: "I built this app...", "I designed the app...", "I included diagnostic..."
- `Docs/BILLING_AND_LIMITS.md`: "I define these...", "I implemented a sticky..."
- `Docs/INGESTION_PIPELINE.md`: "I use StructuredDocumentParser.swift..."
- `CHANGELOG.md`: "Shoutout to Tim for asking for this."

---

## High-Level Recommendations for Next Phase (Phase 6B)
1. **Reconcile Terminology**: Replace all false CloudKit claims with iCloud Ubiquity (NSFileCoordinator / NSMetadataQuery) descriptions.
2. **Clarify PCC Status**: Clearly label PCC enclaves as simulated and run locally via the compatibility wrapper in the current build.
3. **Correct SQLite Details**: Explicitly document column-level `container_id` isolation rather than separate SQLite files.
4. **Correct Billing Details**: Clarify that entitlement limits are stored in `UserDefaults` and grandfathered states are evaluated on launch.
5. **Enforce Communication Rules**: Rewrite all first-person pronoun references to objective/passive phrasing (e.g. "The system defines...", "An entitlement checks...").
6. **Purge Informal Text**: Remove the informal developer shoutout in `CHANGELOG.md`.

---

> **Status Statement**: This Phase 6A documentation scan is draft-only and requires Gemini 3.1 Pro review for final reconciliation.
