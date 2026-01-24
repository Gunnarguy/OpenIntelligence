# OpenIntelligence AI Guide

> **Auto-injected into every Copilot session.** Read before making changes.

## 🎯 MISSION: Universal RAG Engine

Ingest ANY document, ANY size. Answer questions using Apple Intelligence. **ZERO DATA LOSS.**

### Hard Limits (MEMORIZE)

| Constraint       | Value         | Notes                                   |
| ---------------- | ------------- | --------------------------------------- |
| Embedding tokens | 510 max       | CoreML MiniLM-L6-v2 (512 - CLS/SEP)     |
| Chunk size       | 310 words max | 340 - 30 for contextual prefix overhead |
| Chunk limit      | 50000 max     | Supports ~65,000 pages per container    |
| LLM context      | 4096 tokens   | Apple FM TN3193 on-device limit         |
| Context chars    | 5500 max      | ~4000 tokens with margin                |
| Embedding dim    | 384           | MiniLM output                           |

**If you touch chunking/embedding/context packing → VERIFY these limits.**

---

## Directives

1. Read `ROADMAP.md` + `Docs/reference/ARCHITECTURE.md` first
2. NO new markdown files for plans/logs
3. Tasks tracked in `ROADMAP.md` only
4. Use iOS 26.0+ APIs (`FoundationModels`, `@Tool`, Vision structured parsing)

---

## Architecture

- **RAGService** (`@MainActor`): UI orchestrator, published state
- **RAGEngine** (`actor`): Background math (MMR, BM25, RRF)
- **Containers**: Data scoped via `VectorStoreRouter`
- **FullTextStorageService** (`actor`): Complete original document storage for exact queries

### Pipeline

```
Ingestion: Vision → SemanticChunker (≤310w) → Token Validation → CoreML Embed → HNSW
                                          ↓
                            FullTextStorageService.store() ← Complete original text
Retrieval: HyDE → Hybrid Search → RRF → MMR → ReRank → Context Pack
           countPatternInCorpus() → exact count across ALL text (no chunking)
Generation: LLMService + 14 @Tool functions for agentic search
```

### Multi-Session (Breaks 4096 Limit)

Maximum mode chains 4-50 sessions × 4096 tokens. Each session gets fresh budget + condensed insight from prior session.

---

## Key Files

| File                                                       | Purpose                                 |
| ---------------------------------------------------------- | --------------------------------------- |
| `Services/RAG/RAGService.swift`                            | Main orchestrator, token validate       |
| `Services/Agentic/AgenticOrchestrator.swift`               | Multi-session reasoning                 |
| `Services/Document/SemanticChunker.swift`                  | Chunking (310w max, 50000 limit)        |
| `Services/Storage/FullTextStorageService.swift`            | Complete text storage for exact queries |
| `Services/Embedding/CoreMLSentenceEmbeddingProvider.swift` | 384-dim embeddings + BertTokenizer      |

---

## Commands

```bash
xcodebuild -scheme OpenIntelligence -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
./clean_and_rebuild.sh  # Fixes stale UI
```

---

## Pitfalls

1. **Token truncation** → Use `countTokens()`, not word count! Technical text ≠ 1.5 tokens/word
2. **NLTokenizer ≠ BertTokenizer** → `VHA21\VHAPALGarciG1` = 1 NL word but 10+ embedding tokens
3. **Context overflow** → >5500 chars = LLM error
4. **Dimension mismatch** → Must be 384-dim
5. **Simulator** → Apple FM unavailable; test fallbacks
6. **CSV data** → No row limits; tabs/special chars handled
