# OpenIntelligence — Copilot Instructions

> **Auto-injected into every Copilot session.** Follow existing code patterns — they are the style guide.

---

## Mission

100% native iOS RAG engine. Ingest any document, any size, answer via Apple Intelligence. Zero data loss. No third-party AI. On-device by default.

---

## Hard Limits

| Constraint       | Value     | Why                                   |
| ---------------- | --------- | ------------------------------------- |
| Embedding tokens | 510       | CoreML MiniLM-L6-v2 (512 − CLS/SEP)   |
| Chunk size       | 310 words | 340 target − 30 contextual prefix     |
| LLM context      | 4 096 tok | Apple FM on-device (TN3193)           |
| Context chars    | 5 500     | ~4 000 tokens with margin             |
| Embedding dim    | 384       | MiniLM — every vector path must match |
| OCR DPI          | 360       | 5× scale for PDF; 144 DPI for images  |

**If you touch chunking, embedding, or context packing → verify these limits.**

---

## Non-Negotiable Rules

1. **Read `HOW_IT_WORKS.md` + `ARCHITECTURE.md` before touching pipeline code**
2. **No third-party AI** — no OpenAI, no HuggingFace Hub, no LangChain
3. **No random markdown files** — productization docs live in `SDK_BOUNDARY_AUDIT.md` and `output/OpenIntelligence-SDK-Package/`
4. **iOS 26.0+ only** — use `FoundationModels`, `@Tool`, `@Generable`
5. **100% on-device** — no servers; solo developer; optional PCC
6. **No `.strings` / `.xcstrings`** — all strings inline
7. **Don't modify `swift-transformers/`** — it's an upstream submodule

---

## Project Config

- Bundle: `Gunndamental.OpenIntelligence` | Team: `Z3E334EXZD`
- Swift 5.0 with Swift 6 concurrency | `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
- 2 native targets: `OpenIntelligence` app + `OpenIntelligenceEngine` framework | 2 CoreML models (MiniLM-L6-v2, TinyBERT)
- Version: `MARKETING_VERSION` (semver) + `CURRENT_PROJECT_VERSION` (int) in pbxproj — **bump both Debug and Release**

## Two Delivery Lanes

- `OpenIntelligence` is the App Store app track: `App/`, `Features/`, `UI/`, screenshots, onboarding, billing surfaces.
- `OpenIntelligenceEngine` is the SDK track: packaging, framework-safe runtime paths, buyer-facing binary delivery.
- Do not assume an app fix belongs in the SDK, and do not assume SDK packaging work belongs in the app UX.

## SDK Guardrails

- Public SDK surface lives in `OpenIntelligence/SDK/`, currently `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`.
- Framework-safe resource lookup uses `OpenIntelligenceResourceBundle`, never `Bundle.main`, for engine-owned resources.
- Framework-safe storage goes through `AppSupportPaths.baseDir()` / `OpenIntelligenceRuntimePaths` or caller-provided storage URLs.
- Keep app-only areas out of SDK productization work unless explicitly asked:
  - `OpenIntelligence/App/*`
  - `OpenIntelligence/Features/*`
  - `OpenIntelligence/UI/*`
  - billing / tips / diagnostics surfaces
- For SDK work, read `SDK_BOUNDARY_AUDIT.md` and `output/OpenIntelligence-SDK-Package/Internal/BUILD_NOTES.md` before changing target membership or packaging.

---

## What Copilot Can't Infer

### Concurrency (default MainActor changes everything)

- Every type is `@MainActor` by default — use `nonisolated` or `actor` to opt out
- `[weak self]` in ALL `Task` / closure captures
- Store tasks as `Task<Void, Never>?`, cancel in `deinit`
- `Task.checkCancellation()` in LLM loops (prevents Deep Think freeze)

### Logging (custom system)

- Use `Log.info/error/debug/verbose("message", category: .retrieval)` — never `print()`, `os_log`, or `Logger`
- Categories: `.initialization`, `.ingestion`, `.embedding`, `.vectorDB`, `.retrieval`, `.llm`, `.pipeline`, `.performance`, `.streaming`, `.telemetry`, `.ui`, `.billing`, `.pipelineTrace`
- All `print()` must be wrapped in `#if DEBUG`

### Container Isolation (shipped bug class)

- EntityIndexService, FullTextStorageService, chat history — ALL per-container scoped
- Always scope by `containerId`. Cross-container bleed = real bug.

### Billing

- 3 tiers: `.free` / `.pro` / `.lifetime` via `WorkspaceTier.isAtLeast(_:)`
- Code still defines 4 StoreKit product IDs: `pro_monthly`, `pro_annual`, `lifetime_cohort`, `doc_pack_addon`
- Literal repo state: `doc_pack_addon` still has active purchase UI, entitlement handling, quota math, and App Store metadata, while some app copy still says document packs are no longer sold in-app; call that inconsistency out directly when documenting billing
- Every feature in upgrade UI MUST be enforced in code — no aspirational claims

---

## Pitfalls

1. **Token ≠ word** → Use `countTokens()`. Technical text like `VHA21\VHAPALGarciG1` = 1 word but 10+ tokens.
2. **Context overflow** → >5 500 chars = Apple FM error.
3. **384-dim everywhere** → Dimension mismatch = crash.
4. **Markdown rendering** → Apple FM concatenates on one line. `normalizeInlineMarkdown()` fixes it. Don't strip markdown from `cleanupResponseText()` or `cleanupFinalAnswer()`.
5. **Response cleaning** → 7 functions in sequence. Changing one affects all downstream.
6. **Large PDF OOM** → 500+ pages: 5-page batches, 144 DPI, `autoreleasepool`, `results.removeAll()`.
7. **Rate limits** → Compression capped at 5 chunks, fresh `LanguageModelSession` per chunk.
8. **Tables are atomic** → Chunker never splits through a table.
9. **Font cipher PDFs** → PHASE -1 Jaccard detection (< 0.15 = garbled → force OCR).
10. **Self-RAG enrichment** → Sessions ADD details, never contradict valid answers.
11. **`GeometryReader`** → Don't use in nav stacks. Use `.frame(maxWidth: .infinity)`.
12. **Simulator** → Apple FM unavailable. Test fallback paths on device.

---

## Build & Validate

```bash
xcodebuild -scheme OpenIntelligence -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
xcodebuild -scheme OpenIntelligenceEngine -project OpenIntelligence.xcodeproj -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
./clean_and_rebuild.sh                    # Clean + DerivedData purge
./scripts/build_engine_xcframework.sh     # Build binary SDK artifact
./scripts/validate_sdk_package.sh         # Check deliverable scaffold/artifact
./scripts/preflight_check.sh              # Secrets scan + encryption check
bundle exec fastlane beta                 # Build + TestFlight
bundle exec fastlane release              # Build + App Store Connect
```

Always run `xcodebuild build` after making changes to verify compilation. Run `./scripts/preflight_check.sh` before any commit to catch secrets or encryption flag issues.

---

## Key Files

| Path                                   | What's there                               |
| -------------------------------------- | ------------------------------------------ |
| `ARCHITECTURE.md`                      | 102-service inventory, all data structures |
| `HOW_IT_WORKS.md`                      | 29-step pipeline walkthrough               |
| `ROADMAP.md`                           | Task tracking (the ONLY place for tasks)   |
| `CHANGELOG.md`                         | Version history                            |
| `SDK_BOUNDARY_AUDIT.md`                | Internal map of app-vs-SDK boundary        |
| `output/OpenIntelligence-SDK-Package/` | Deliverable docs + packaging notes         |
