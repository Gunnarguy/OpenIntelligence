> **Documentation status:** [Archived]. This document is kept for historical evidence. Do not use as the source of truth for OpenIntelligence v4.3.

# Product Positioning & Evidence Threads Audit (V2)

## 1. Product Truth & Privacy Claim Audit
OpenIntelligence differentiates itself through transparency and privacy, but its claims must strictly reflect the codebase reality. 

**Corrected Privacy Claims:**
- **Local-First, Not 100% Local:** OpenIntelligence executes embeddings (CoreML) and standard inference (up to 4,096 tokens via Apple Foundation Models) directly on-device. However, it dynamically routes larger contexts and "Deep Think/Maximum" queries to Apple’s Private Cloud Compute (PCC) via `PrivateCloudComputeLanguageModel` and `FoundationModelRoutePolicy`.
- **Consent-Gated Cloud Routing:** We do not claim "zero-knowledge" or "documents never leave the device." Instead, we emphasize **visible processing boundaries** and **transparent routing**. The `CloudConsentPromptView` ensures users have strict control before any data escalates to Apple's PCC servers.
- **Core Truth:** OpenIntelligence is a "transparent, local-first orchestration engine" that defaults to device privacy but safely scales to Apple’s secure cloud when required.

## 2. Licensing & Proprietary Wording
Because OpenIntelligence is an MIT-licensed open-source project, marketing language must avoid calling the engine "proprietary." 
- **Instead of "proprietary RAG", use:** "Custom inspectable pipeline", "distinctive architecture", or "transparent local-first orchestration engine."
- This highlights the engineering value without contradicting the open-source license.

## 3. Evidence Threads Feasibility Audit
An audit of the persistence layer reveals significant constraints for implementing Evidence Threads:
- **Current State:** `ChatMessage` is currently held **in-memory only** (noted in `ChatMessage.swift`) and is not durably persisted between sessions in the modern V2 UI. 
- **Persistence Substrate:** The app does not currently use SwiftData or CoreData. Libraries (`KnowledgeContainer`), documents, and legacy chat histories rely on `Codable` structs saved to local JSON files (e.g., `containers.json`, `chat_history_<containerId>.json`) or SQLite vector backends. 
- **Implementation Decision:** Introducing SwiftData solely for Evidence Threads would fracture the storage paradigm. Threads should be implemented using `Codable` backed by robust JSON or SQLite storage to maintain consistency with the existing data layer.
- **iCloud Sync:** `WorkspaceSyncService` currently handles library replication. We cannot assume immediate iCloud support for live chat threads due to file-conflict complexities. Sync must be deferred to a later phase.

## 4. Revised Evidence Threads MVP
The rollout must be phased safely, starting with local-only storage.

### Phase 1: Local-Only Core
*Goal: Turn ephemeral chat into durable, retainable sessions.*
- Create the `EvidenceThread` model conforming to `Codable`.
- Implement local JSON persistence (`threads_<containerId>.json`).
- Associate threads with specific `KnowledgeContainer`s.
- Support thread creation, restoring upon reopen, renaming, and deletion.
- Persist messages and their sanitized citations (`RetrievedChunk`s) within the thread.

### Phase 2: Synthesis & Export
*Goal: Turn threads into shareable research assets.*
- Add ability to "pin" specific findings within a thread.
- Implement "Copy with citations."
- Export the entire thread as a Markdown brief using an extended `PipelineTraceExporter`.

### Phase 3: App Intents Integration
*Goal: Ambient research.*
- Add Siri intents to continue existing threads (e.g., "Add this to my Q3 Revenue thread").

### Phase 4: iCloud Sync (If Safe)
*Goal: Multi-device research.*
- Integrate thread JSON files into `WorkspaceSyncService`.
- Implement safe merge strategies for concurrent thread edits across devices.

## 5. Positioning Refresh
To escape the generic "chat with PDFs" category, we position the app around inspectability and evidence.

**Core Messaging Pillars:**
- "Private evidence engine for Apple files."
- "See exactly where the answer came from."
- "Local-first intelligence that shows its work."
- "Inspectable cited answer threads."

Avoid absolute claims (e.g., "absolute truth," "100% safe," "never cloud") and focus on the verifiable nature of the pipeline trace and cited chunks.

## 6. Monetization Refresh
Evidence Threads provide the ultimate lever for the Pro and Lifetime tiers (`EntitlementStore`). 

**Tier Breakdown:**
- **Free Tier:** Basic Q&A capabilities within standard document quotas. Evidence Threads are either disabled or capped (e.g., maximum of 3 active threads).
- **Pro / Lifetime Tier:** 
  - Unlimited Evidence Threads.
  - Thread export to Markdown briefs.
  - Access to Maximum mode (PCC routing for complex thread synthesis).
  - iCloud sync for threads (when Phase 4 launches).

**Recommendation:** Evidence Threads (Phase 1 & 2) should be introduced **before** or **alongside** major pricing changes. This ensures that when users hit a paywall, they are paying for a highly differentiated, durable workflow asset rather than just "more chat quotas." 

## 7. Affected Files, Risks, & Acceptance Criteria
- **Files Affected:** `ChatMessage.swift`, `ChatScreen.swift`, `KnowledgeContainer.swift`, `RAGService.swift`.
- **Risks:** Memory bloat if threads contain too many massive retrieved chunks. *Mitigation:* Ensure `sanitizedForPersistence()` strictly truncates string lengths before JSON encoding.

**Acceptance Criteria for MVP Phase 1:**
- [ ] Users can start a new thread or view a list of historical threads in the UI.
- [ ] Chat messages persist between app restarts via `Codable` JSON storage.
- [ ] Threads are correctly scoped to their parent `KnowledgeContainer`.
- [ ] Users can delete a thread, which removes its associated JSON file.
- [ ] The app maintains strict local-first execution unless the user explicitly triggers a PCC-routed deep-think mode and consents via `CloudConsentPromptView`.
