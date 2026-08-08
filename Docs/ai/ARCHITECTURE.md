# Architecture map

A routing map, not a description. `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` is the deep
reference and this file exists to get you to the right part of it, and to the right source file,
without reading the whole set.

`[evidence_level: code_verified, confidence: high, evidence_source: directory listing of
OpenIntelligence/Services, file existence checks 2026-08-07]`

## Targets, and why it matters

Two build targets share the tree:

- **`OpenIntelligence`**, the app.
- **`OpenIntelligenceEngine`**, a SwiftPM target whose synchronized root groups include
  `Services/RAG` but not `Services/Evaluation`.

That is not trivia. A type referenced by a file in the Engine target must live in a folder the
Engine target also builds, which is why `RetrievalTraceCollector` sits in
`Services/RAG/Retrieval/` rather than beside the metrics that score it. Check target membership
before deciding where a new file goes.

`OpenIntelligenceLiveActivities` is a separate widget extension.

## Where each area lives

| Area | Source | Owning document |
|---|---|---|
| Ingestion, chunking, OCR | `OpenIntelligence/Services/Document/` | `Docs/INGESTION_PIPELINE.md` |
| Embedding and providers | `OpenIntelligence/Services/Embedding/` | Atlas §17 |
| Vector storage | `OpenIntelligence/Services/VectorStore/` | Atlas §9 |
| Keyword index (SQLite FTS5) | `OpenIntelligence/Services/Storage/` | Atlas §9 |
| Hybrid retrieval, fusion, rerank | `OpenIntelligence/Services/RAG/Retrieval/` | `Docs/RETRIEVAL_PIPELINE.md` |
| Query understanding, rewriting | `OpenIntelligence/Services/Query/` | `Docs/RETRIEVAL_PIPELINE.md` |
| Retrieval tuning knobs | `OpenIntelligence/Services/RAG/Tuning/` | `Docs/RETRIEVAL_PIPELINE.md` |
| RAG orchestration | `OpenIntelligence/Services/RAG/Orchestration/` | Atlas service map |
| Model routing, on-device vs PCC | `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/` | `Docs/PRIVACY_AND_ROUTING.md`, Atlas §10 |
| LLM execution | `OpenIntelligence/Services/LLM/` | `Docs/PRIVACY_AND_ROUTING.md` |
| Agentic tools, App Intents, Siri | `OpenIntelligence/Services/Agentic/` | Atlas §12 |
| Evidence Threads | `OpenIntelligence/Core/Models/EvidenceThread.swift`, `Services/Storage/EvidenceThreadStore.swift` | Atlas §15, canonical §11 |
| iCloud workspace sync | `OpenIntelligence/Services/Infrastructure/Storage/` | Atlas |
| Billing, entitlements, quotas | `OpenIntelligence/Services/Billing/`, `Services/Infrastructure/Configuration/` | `Docs/BILLING_AND_LIMITS.md` |
| Evaluation harness | `OpenIntelligence/Services/Evaluation/` | `Docs/EVALS.md` |
| UI | `OpenIntelligence/Features/`, `OpenIntelligence/UI/` | `WHATS_NEW.md`, `Docs/USER_CHANGELOG.md` |

## Data flow

Import → `Services/Document` extracts and chunks → `Services/Embedding` vectorises →
vectors land in `Services/VectorStore`, text lands in the FTS5 index in `Services/Storage`.

Query → `Services/Query` rewrites and classifies intent → `HybridSearchService` runs dense vector
search and lexical scoring concurrently, fuses them with reciprocal rank fusion, applies boosts,
reranks with a cross-encoder, and returns a top-K → `Services/RAG/Orchestration` packs context →
`Services/AIPlatform` decides where to execute → `Services/LLM` generates → the answer carries
citations back to the chunks that produced it.

The stage names in that pipeline are enumerated in `RetrievalTraceCollector.Stage`: `vector`,
`lexical`, `fusion`, `boosted`, `rerank`, `final`.

## Persistence

Vectors in `BNNSVectorDatabase`, text and metadata in SQLite with an FTS5 index, threads in
`EvidenceThreadStore`, library state reconciled across devices by `WorkspaceSyncService`. All four
are hard-boundary in some respect. A schema, format, or model-dimension change forces existing users
to reindex their entire library, which is why they are gated.

## Security and privacy boundaries

The privacy claim is the product, so these are the invariants worth checking on any change:

- Ingestion, indexing, retrieval, and ranking are local. Nothing is uploaded to make search work.
- Only final answer generation may leave the device, only to Apple Private Cloud Compute, only with
  consent, and only after the user has seen which excerpts would be sent.
- Every use of `PrivateCloudComputeLanguageModel` must be gated behind `EntitlementChecker`.
- The answer's execution badge is read from an execution receipt, not from what was requested.
- There is no account, no server operated by this project, and no third-party AI service in the path.

## External couplings

Four systems the app does not control. Each one's failure mode is different, and the app is expected
to keep working without three of them.

| System | Code boundary | If unavailable |
|---|---|---|
| Apple Foundation Models (on-device and PCC) | `Services/AIPlatform/AppleFoundationModels/` | No answer generation. Retrieval still works, so citations and evidence remain available. The public SDK exposes no tier selector, no server architecture, and no server context window; do not name any of them. |
| CloudKit / iCloud Drive | `Services/Infrastructure/Storage/WorkspaceSyncService.swift` | Library stops reconciling across devices. Local library keeps working. Sync interleaving is a known source of defects and has no test coverage. |
| StoreKit 2 | `Services/Billing/`, `EntitlementStore.swift` | Entitlement state cannot refresh. Must degrade toward the user keeping what they paid for, never toward revoking it. |
| Core ML reranker | `Resources/MLModels/ReRankerModel.mlpackage` | Reranking stage drops out; fusion output passes through. Bound to `cross-encoder/ms-marco-TinyBERT-L2-v2` by exact path in `THIRD_PARTY_NOTICES.md`, which is the provenance of record. |

Nothing else is external. There is no server operated by this project and no third-party AI service
in the path, which is a product guarantee rather than a current state.

## Non-obvious constraints

- **The repository lives in iCloud-synced `~/Documents`.** Synchronized file groups plus iCloud
  conflict copies produce duplicate-symbol errors that point at innocent code. `.git` is a file
  pointing at `.git.nosync` for the same reason.
- **`RAGAppIntents.swift` uses 9 of 10 available Siri shortcut slots.** The tenth is close to a
  one-way door.
- **The evaluation harness has never measured retrieval.** See `Docs/ai/STATE.md`; that is the
  current work.
