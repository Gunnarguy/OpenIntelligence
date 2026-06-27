# Specificity Preservation Review

This document presents a verification review of OpenIntelligence documentation specificity, confirming that technical details and architectural pathways are preserved while keeping all claims factually accurate, code-supported, and aligned with the canonical source of truth.

---

## 1. Core Architectural Pillars Preserved

The documentation maintains explicit, qualified terminology for all core subsystems rather than using simplified generalizations:

*   **Apple-Native Architecture:** Explicitly describes native Swift, PDFKit, Apple Vision OCR, and CoreML integration rather than generic web wrappers.
*   **Local-First RAG:** Differentiates between standard local-only routes and Private Cloud Compute (PCC) enclaves, avoiding misleading absolute terms like "100% local" or "never sends data to the cloud."
*   **CoreML Sentence Embeddings:** Documents the use of BNNS-accelerated vector indexes and 384-dimensional dense vectors mapped directly to local storage.
*   **Apple Foundation Models:** Identifies specific AFM targets (`SystemLanguageModel.default` and local fallbacks for testing).
*   **PCC Routing Boundaries & Consent:** Retains detailed descriptions of the 4,096-token local limit, token budget discrepancies, settings consent keys (`"cloudConsent.applePCC"`), and background task continuation deadlock risks.
*   **KnowledgeContainer Isolation:** Restores library boundary rules mapping document indexes to isolated `container_id` fields.
*   **Persistence Structures:** Explicitly documents JSON persistence files (`chat_history_<containerId>.json`), the `sanitizedForPersistence()` utility, and the strict exclusion of heavy traces or embeddings (`pipelineTrace`).
*   **Sync Boundaries:** Retains rules detailing the exclusion of `localCacheDir()` (guaranteeing local-only execution for SQLite FTS5) and warning against `baseDir()/threads/` path allocations due to active iCloud sweeps.
*   **Evidence Threads Phase 1 Planning:** Retains technical specifications of isolated local-only Codable JSON transcripts under `LocalCache/EvidenceThreads/<containerId>/` avoiding sync sweeping.

---

## 2. Claim Classification Register

To prevent future regression, all claims are categorized and qualified:

| Claimed Feature | Actual Code / Architectural Status | Status Label | Safe Qualified Wording |
| :--- | :--- | :--- | :--- |
| **On-Device Inference** | Local execution is default but scales to PCC enclaves under overflows or Deep Think. | Shipped / Route-Gated | "Local-first processing with secure Private Cloud Compute escalation." |
| **iCloud Sync** | WorkspaceSyncService sweeps `baseDir()` for container metadata and chat histories. | Shipped / Gated | "Coordinated metadata and chat history syncing." |
| **Evidence Threads** | Isolated Codable JSON files under `LocalCache/` to bypass iCloud sweeps. | Planned (Phase 1) | "Local-only isolated thread storage." |
| **Siri & App Intents** | Siri shortcuts registered via `RAGAppShortcutsProvider` (9 shortcuts active). | Shipped / Gated | "Voice Shortcuts search integration." |
| **StoreKit Billing Tiers** | QuotaPolicy hardcodes limits (Pro is capped at 1,000 docs). | Shipped / Gated | "Pro tier supports up to 1,000 documents." |

---

## 3. Specificity Preservation Audit Conclusions

This pass successfully restores architectural terminology to the root `README.md`, `Docs/PRIVACY_AND_ROUTING.md`, and the master `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md` without re-introducing unsafe or un-supported marketing claims.

VERIFIED: DOCUMENTATION SPECIFICITY RESTORED WITHOUT UNSAFE CLAIMS
