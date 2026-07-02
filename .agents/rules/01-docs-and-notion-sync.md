# Rule: Automatic Docs & Notion Roadmap Sync (always on)

Documentation drift is prohibited (AGENTS.md rules 14 & 16). You do NOT wait to be told to update docs or Notion. The moment you modify code, the matching doc + roadmap updates become part of the same task. A task with code changes but no doc/roadmap sync is INCOMPLETE.

## Path-triggered doc updates
When you edit files matching a pattern below, update the listed docs in the same turn (including any Mermaid diagrams inside them):

| You edited... | You must update... | Notion Component |
|---|---|---|
| `Services/RAG/Retrieval/**`, `Services/Query/**`, `Services/RAG/Tuning/**` | `Docs/RETRIEVAL_PIPELINE.md` (+ its Mermaid), `CHANGELOG.md` | Retrieval |
| `Services/Document/**` (processing, chunking, OCR) | `Docs/INGESTION_PIPELINE.md` (+ its Mermaid), `CHANGELOG.md` | Ingestion or Chunking |
| `Services/Embedding/**` | `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` §17, `CHANGELOG.md` | Indexing |
| `Services/Storage/**`, `Services/VectorStore/**` | Atlas §9 + storage sections, `CHANGELOG.md` | Indexing |
| `Services/AIPlatform/**`, `Services/LLM/**` | `Docs/PRIVACY_AND_ROUTING.md`, Atlas §10, `CHANGELOG.md` | Orchestration |
| `Services/RAG/Orchestration/**`, `Services/Agentic/**` | Atlas service map, `CHANGELOG.md` | Orchestration |
| `RAGAppIntents.swift`, `Services/Agentic/Entities/**` | Atlas §12, `CHANGELOG.md` | Shortcuts |
| `Services/Billing/**`, `Features/Billing/**` | `Docs/BILLING_AND_LIMITS.md`, `CHANGELOG.md` | General |
| `EvidenceThread*`, `ThreadSidebarView.swift` | Atlas §15, canonical §11, `CHANGELOG.md` | Orchestration |
| `Features/**`, `UI/**` (user-visible) | `WHATS_NEW.md`, `Docs/USER_CHANGELOG.md` | UI |
| Any phase/milestone completion | Full AGENTS.md rule 14 list: `README.md`, Atlas, `Docs/AppleIntelligenceTransitionPlan.md`, `CHANGELOG.md`, `Docs/RELEASE_NOTES.md`, canonical doc, `Docs/ROADMAP.md` + Notion | (as appropriate) |

CHANGELOG bullets always carry the architectural tag: `[Retrieval]`, `[Ingestion]`, `[Chunking]`, `[Indexing]`, `[Orchestration]`, `[Shortcuts]`, `[UI]`, or `[General]`.

## Notion Roadmap — when to touch it (unprompted)
Database ID: `37f49a74-d54f-81b7-9424-dae1288c0043` (data source: `collection://37f49a74-d54f-81b0-92d9-000bce5e05fa`). Never search for the DB; use this ID.

- **Starting a feature/task** → query the DB for a matching row. If found, set `Status` = `In Progress`. If not, create one (`Name` = feature summary, `Status` = `In Progress`, `Component`, `Priority`, `Target Release`, `Added` = today).
- **Completing a feature/task** → set `Status` = `Completed` AND set the `Completed` date to today.
- **User mentions roadmap/plans/backlog** → pull current rows from the DB first; never answer from memory.
- **Pure docs-only or refactor-only changes** → no Notion row required unless it closes a roadmap item.

## Notion schema — exact values only (do not invent options)
- `Status`: `To Do` | `In Progress` | `Completed` — there is NO "Shipped" option.
- `Component`: `Ingestion` | `Chunking` | `Indexing` | `Retrieval` | `Orchestration` | `Shortcuts` | `General` | `UI`
- `Priority`: `High` | `Medium` | `Low`
- `Target Release`: `v4.0`–`v4.4`, `v4.5 (Phase 2B)`, `v4.6`, `Future Backlog`
- Dates: `Added`, `Completed` (ISO dates).

## Verification before ending any code-modifying turn
1. Warning-free build: `bash scripts/build_simulator_smoke.sh` (AGENTS.md rule 14).
2. Docs updated per the table above — confirm by listing them in your summary.
3. Notion updated if a feature started/finished — state the row you touched.
