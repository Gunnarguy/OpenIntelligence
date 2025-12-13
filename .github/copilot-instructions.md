# OpenIntelligence AI Guide

## Project Overview

**Platform**: iOS 26.0+ (Swift 6.0, `-default-isolation=MainActor`)  
**Mission**: Privacy-first RAG (Retrieval-Augmented Generation) with on-device processing and optional Private Cloud Compute (PCC).

## Architecture (Protocol + Actor Pattern)

### Two-Actor Design

- **`RAGService`** (`@MainActor`): UI orchestrator. Source of truth for `documents`, `messages`, and all published state. All UI bindings flow through here.
- **`RAGEngine`** (`actor`): Background math worker. Handles MMR diversification, BM25 scoring, and RRF fusion. Never touches UI.

### Protocol-First Services

All major components are protocols—implementations swap via DI:

- `LLMService`: 7 implementations (`AppleFoundationLLMService`, `OpenAILLMService`, `LlamaCPPiOSLLMService`, `MLXLLMService`, `LocalOpenAIServerLLMService`, `OnDeviceAnalysisService`, etc.)
- `VectorDatabase`: `PersistentVectorDatabase` (JSON), `InMemoryVectorDatabase`, `VecturaVectorDatabase` (HNSW)
- `EmbeddingService`: `NLEmbedding` (512-dim)

### Container Isolation

Data is scoped to `KnowledgeContainer`s. **Always** access storage via:

```swift
let db = vectorRouter.db(for: container)  // Never instantiate VectorDatabase directly
```

## Data Flow

1. **Ingestion**: `DocumentProcessor` → `SemanticChunker` (400w/75w overlap) → `EmbeddingService` → `VectorStoreRouter`
2. **Retrieval**: `HybridSearchService` (Vector + BM25) → `RAGEngine.reciprocalRankFusion` → MMR
3. **Generation**: `LLMService` (with 12+ agentic `@Tool` functions for autonomous search)

## Privacy-Critical Pattern

Cloud calls **must** follow this pattern:

```swift
// 1. Check consent (presents UI if needed)
let decision = await ensureCloudConsentIfNeeded(for: .openai, promptTokens: tokens)
guard decision == .allow else { return }

// 2. Make API call...

// 3. Log transmission for transparency
await recordTransmission(CloudTransmissionRecord(...))
```

## Build & Test Commands

| Task           | Command                                                               |
| -------------- | --------------------------------------------------------------------- |
| **Build**      | ⌘R in Xcode (scheme: `OpenIntelligence`, device: `iPhone 17 Pro Max`) |
| **Clean**      | `./clean_and_rebuild.sh` — clears DerivedData; fixes stale UI         |
| **Smoke Test** | Manual: follow `smoke_test.md` (10 min)                               |
| **Unit Tests** | ⌘U — see `OpenIntelligenceTests/` for mocks in `TestDoubles.swift`    |

## Coding Conventions

### Concurrency

- Use `async/await` and `Task`. **Avoid** `DispatchQueue` unless wrapping legacy APIs.
- Background work → `RAGEngine` actor. UI state → `RAGService` on `@MainActor`.

### Logging

```swift
Log.info("Message", category: .retrieval)   // ✅ Correct
Log.error("Failed: \(error)", category: .llm)
print("debug")                               // ❌ Never in production
```

Categories: `.llm`, `.retrieval`, `.initialization`, `.performance`

### Settings Access

```swift
@EnvironmentObject var settings: SettingsStore  // ✅ In Views
UserDefaults.standard.bool(forKey: ...)          // ❌ Never directly in Views
```

### Error Handling

User-facing errors → `RAGService.lastError` (displayed by UI automatically).

## Test Mocks

Use `TestDoubles.swift` patterns:

```swift
let mock = MockLLMService(responseText: "test", latency: 0.1)
let failing = FailingLLMService()  // For fallback chain tests
```

## Key Files

| File                                  | Purpose                                   |
| ------------------------------------- | ----------------------------------------- |
| `Services/RAGService.swift`           | Main orchestrator (~4000 LOC)             |
| `Services/RAGEngine.swift`            | Background actor for MMR/BM25/RRF         |
| `Services/LLMService.swift`           | Protocol + all LLM implementations        |
| `Services/VectorStoreRouter.swift`    | Per-container vector DB routing           |
| `Services/SettingsStore.swift`        | Centralized preferences (debounced)       |
| `Services/LoggingConfiguration.swift` | Log levels and categories                 |
| `Models/KnowledgeContainer.swift`     | Container schema (embedding dim, DB kind) |
| `Docs/reference/ARCHITECTURE.md`      | Full technical reference                  |

## Common Pitfalls

1. **Stale UI after Settings changes** → Run `./clean_and_rebuild.sh`
2. **Vector dimension mismatch** → Check `container.embeddingDim` matches `EmbeddingService` output (512 for `NLEmbedding`)
3. **Simulator-only testing** → `AppleFoundationLLMService.isAvailable` returns `false` on Simulator; test fallback path
4. **Blocking main thread** → Move heavy compute to `RAGEngine` actor
