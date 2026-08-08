---
paths:
  - "OpenIntelligence/Services/Document/**"
  - "OpenIntelligence/Services/Embedding/**"
  - "OpenIntelligence/Services/Storage/**"
  - "OpenIntelligence/Services/VectorStore/**"
---

# Ingestion, embedding, and index storage

**Same turn as the code change:**

| You edited | Update | CHANGELOG tag | Notion Component |
|---|---|---|---|
| `Services/Document/**` | `Docs/INGESTION_PIPELINE.md` and its Mermaid | `[Ingestion]` or `[Chunking]` | Ingestion / Chunking |
| `Services/Embedding/**` | `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md` §17 | `[Indexing]` | Indexing |
| `Services/Storage/**`, `Services/VectorStore/**` | Atlas §9 and its storage sections | `[Indexing]` | Indexing |

**Tests:** `bash scripts/build_simulator_smoke.sh` plus the full `xcodebuild test`. An embedding
provider change also needs a manual check of the AI Subsystem Diagnostics card.

## Boundaries inside this area

- `SQLiteFullTextService.swift` schema and `BNNSVectorDatabase.swift` on-disk format are
  hard-boundary. Changing either forces every existing user to reindex their entire library.
- `CoreAISentenceEmbeddingProvider` and `CoreMLSentenceEmbeddingProvider` internals are out of
  bounds; embedding *selection* logic is in bounds.
- Changing an embedding model changes vector dimensionality and invalidates every stored vector.
  Migrations here must be additive first, then swap, never in-place.

## Naming discipline

Do not label a mechanism with a published technique's name unless the code implements that
technique. `SemanticChunker` was called "Late Chunking" for six occurrences while doing sentence-pair
boundary detection, which is a different algorithm. Describe what the code does.
