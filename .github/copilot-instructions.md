# OpenIntelligence AI Guide

> **This file is auto-injected into every Copilot session.** It is the single source of truth for how to work in this codebase. Read it fully before making any changes.

## Prime Directives (STRICT)

1. **Context First**: Before generating code, read `ROADMAP.md` (for current status) and `Docs/reference/ARCHITECTURE.md` (for patterns).
2. **Zero-Sprawl Policy**: You are PROHIBITED from creating new markdown files (like `plan.md`, `update_log.md`) to document your work.
3. **Single Source of Truth**: All task tracking happens in `ROADMAP.md`. Technical notes go in inline code comments.
4. **Silent Alignment**: Do not explain that you are following these rules; just follow them.

## Agent Mode Behavior

- **Plan**: Propose your plan in Chat only—NO new files.
- **Edit**: Apply changes directly to code files.
- **Verify**: Run a build/lint check before confirming done.
- **Update**: Check off tasks in `ROADMAP.md` (`[x]`) immediately upon completion.

---

## Directory Structure (Memorize This)

```
OpenIntelligence/
├── OpenIntelligenceApp.swift    # App entry point
├── ContentView.swift            # Root view (tab bar)
├── Models/                      # Data types (ChatMessage, KnowledgeContainer, etc.)
├── Services/                    # ALL business logic lives here
│   ├── RAGService.swift         # 🔑 Main orchestrator (@MainActor, ~4000 LOC)
│   ├── RAGEngine.swift          # Background actor (MMR, BM25, RRF)
│   ├── LLMService.swift         # Protocol + 7 implementations
│   ├── VectorStoreRouter.swift  # Per-container DB routing
│   ├── SettingsStore.swift      # Centralized preferences
│   └── ...                      # Other services (chunking, search, etc.)
├── Views/                       # SwiftUI views organized by feature
│   ├── ChatV2/                  # Main chat interface
│   ├── Settings/                # Settings screens
│   ├── Documents/               # Document management
│   ├── Billing/                 # StoreKit/subscription UI
│   └── ...
├── Shared/                      # Cross-cutting utilities (DesignSystem, QuotaPolicy)
├── StoreKit/                    # StoreKit 2 integration
└── Utilities/                   # Keychain, MarkdownRenderer

Docs/
├── reference/
│   ├── ARCHITECTURE.md          # Full technical reference (READ THIS)
│   ├── RELEASE.md               # Release checklist, smoke tests, StoreKit testing
│   └── PRICING_STRATEGY.md      # Business docs (don't modify)
└── TestDocuments/               # Test fixtures for DocumentProcessor

OpenIntelligenceTests/           # Unit tests + TestDoubles.swift for mocks
Vendor/LocalLLMClient/           # llama.cpp + MLX (DON'T TOUCH - vendored dependency)
scripts/                         # CI/CD helpers (secret_scan, preflight_check)
```

### Don't Touch Zones
- `Vendor/` — Vendored llama.cpp/MLX binaries. Never modify.
- `*.xcodeproj/` — Xcode manages this. Don't hand-edit.
- `PRICING_STRATEGY.md` — Business-sensitive, gitignored from public.

---

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

1. **Ingestion**: `DocumentProcessor` → `SemanticChunker` (280-400w/17% overlap) → `EmbeddingService` → `VectorStoreRouter`
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

| Task              | Command                                                                  |
| ----------------- | ------------------------------------------------------------------------ |
| **Build**         | `xcodebuild -scheme OpenIntelligence -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build` |
| **Clean Build**   | `./clean_and_rebuild.sh` — clears DerivedData; fixes stale UI           |
| **Smoke Test**    | Follow `Docs/reference/RELEASE.md` § Smoke Test Checklist               |
| **Unit Tests**    | `xcodebuild test -scheme OpenIntelligence -destination 'platform=iOS Simulator,name=iPhone 16 Pro'` |
| **Lint**          | `swiftlint` (auto-runs on save in VS Code)                              |

### Common Agent Tasks

**"Add a new LLM provider"**
1. Create `Services/MyNewLLMService.swift` conforming to `LLMService` protocol
2. Add case to `LLMModelType` enum in `Models/LLMModelType.swift`
3. Register in `RAGService.buildLLMFallbackChain()`
4. Add UI toggle in `Views/Settings/`

**"Add a new setting"**
1. Add `@AppStorage` property to `Services/SettingsStore.swift`
2. Add UI control in appropriate `Views/Settings/` screen
3. Access via `@EnvironmentObject var settings: SettingsStore` in views

**"Fix a retrieval bug"**
1. Check `Services/HybridSearchService.swift` for search logic
2. Check `Services/RAGEngine.swift` for ranking (MMR, RRF)
3. Check `Services/VectorStoreRouter.swift` for DB routing
4. Run `HybridSearchServiceTests` to verify

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

---

## Copilot Universal Constitution (Extended)

- **Context First**: Always read `ROADMAP.md` and `Docs/reference/ARCHITECTURE.md` before generating code.
- **Zero-Sprawl Policy**: Do not create new markdown/text logs (e.g., `plan.md`, `update_log.md`).
- **Single Source of Truth**: Track tasks in `ROADMAP.md`. Put technical notes in inline code comments.
- **Silent Alignment**: Follow these rules without narrating that you are doing so.

### iOS & Swift Standards

- Build with SweetPad + `xcode-build-server`; inspect `compile_commands.json` on build issues.
- Prefer SwiftUI; use `async/await` for concurrency.
- Follow `ARCHITECTURE.md` patterns; if undefined, default to MVVM with protocol-oriented DI.

### Pipeline & DevOps Standards

- Scripts must be idempotent.
- Never hardcode secrets; use environment/CI variables.
- Docker: prefer multi-stage builds (builder vs runner).

### Agent Mode Behavior (Reminders)

- Plan in chat only. No new planning files.
- Edit code directly; keep changes concise and well-commented where needed.
- Verify via build/lint/tests before calling work “done.”
- Update `ROADMAP.md` with `[x]` immediately when tasks complete.

---

## Code Archaeology Prompts (for regeneration only)

Use these canned prompts **inside Agent Mode** when asked to regenerate documentation:

- **ARCHITECTURE.md Deep Scan**: Document high-level goal, data flow, tech stack, key components, and design patterns observed.
- **ROADMAP.md Audit**: List completed features, technical debt, and three future steps. Single file only.
- **Directory Standards Add-on**: Append section:
	- `/App`: Entry points and configuration
	- `/Features`: By domain (Views, ViewModels, Models per feature)
	- `/Core`: Shared utilities, networking, extensions
	- `/UI`: Reusable design-system components
	- `/Pipelines`: CI/CD YAMLs and build scripts

---

## Daily Driver (Activator Prompt)

When starting work:

1. Read `ROADMAP.md` and `Docs/reference/ARCHITECTURE.md`.
2. Find the next unchecked `[ ]` in `ROADMAP.md`.
3. Propose a plan in chat (no files).
4. Implement code.
5. Update `ROADMAP.md` with `[x]` for the item.

---

## Cleanup Protocols

- **Janitor**: If stray markdown files exist (outside `ROADMAP.md`, `ARCHITECTURE.md`, `README.md`), merge useful info into `ARCHITECTURE.md` as bullets, then delete the extras.
- **Housekeeper**: Audit file locations against Directory Standards; propose moves (e.g., `UserView.swift` → `/Features/Auth/UserView.swift`), then execute with references updated after approval.

---

## Interview Pitch (Talking Points)

- Modularized VS Code with SweetPad + build server; headless CI simulation locally.
- Static analysis enforced on save (SwiftFormat/SwiftLint) to avoid style debates.
- Cognitive load tools (Todo Tree, Error Lens) keep feedback fast.
- IaC validated locally (YAML/Docker) before pushing.
