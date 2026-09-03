# Module 16. Dormant, future, superseded, and commonly misnamed mechanisms

Twenty-five concepts, plus the ones this pass added. The blueprint shelf: things in the source that are not in the machine that runs today, and old names that mislead if taught as current.

## The ladder

**Like you're five.** Some drawings in the workshop are for machines that were never built, or were taken apart. If you learn them as if they were running, you'll describe a machine that doesn't exist.

**Like an idiot.** A codebase this size has scaffolds, reserved names, removed backends and withdrawn claims. This module lists them so you never say one of them in an interview as if it were live.

**Like less of an idiot.** Dormant means the code exists but isn't on any shipping path. Future means a reserved name. Historical means superseded or withdrawn, and misleading if taught as current. The dormant list as verified this week: the Apple Foundation Models embedding provider, the neural extractive QA span model, the dynamic Foundation Model profile registry, embedding-based chunk boundary detection, production Private Cloud Compute (compiled out of shipped builds), and one the word bank missed: the `SpeechAnalyzer` transcription branch. The historical list includes the removed local generative backends (GGUF, MLX, bundled Core ML), the 3B-versus-20B selector, the 32K cloud window, the 18-of-20 zero-hallucination figure, the unmeasured speed multipliers, "zero latency," "model judges," "PCC simulation," "default HNSW," and the "single 29-step pipeline" and "single recursive thought loop" shorthands.

**Average Joe.** Why keep dead code at all? Some of it is a real future (the QA span model has a protocol waiting for a trained model). Some is compatibility (old preference values must still resolve). Some is just not yet removed. The important skill is telling them apart, and the important habit is that a withdrawn claim is corrected in place with a dated note rather than deleted, so the record shows what was claimed and when it was withdrawn.

**Dot-connector.** Two shorthands in particular collapse real structure. "Single 29-step pipeline" hides that execution branches by file type, intent, mode, evidence, device state and route; teach a shared spine with conditional sub-pipelines. "Single recursive thought loop" hides that planning, iterative retrieval, recursive multi-session RAG, critique-and-refine and deterministic verification are five different mechanisms; teach them separately, then reconnect them in sequence, which is what modules 07, 08, 11 and 12 do.

**Expert.** Verified this pass: `FoundationModelDynamicProfileRegistry` has no active call sites; `SemanticChunker`'s embedding-based boundary method returns no boundaries because the chunker is never handed an `EmbeddingService`; `ExtractiveQAService`'s span model returns nil; `AppleFMEmbeddingProvider` declares 1,024 dimensions and is a placeholder; `SpeechAnalyzerService` is guarded by `canImport(SpeechAnalyzer)`, a module that does not exist, and calls an API shape the SDK does not declare; `Docs/SHIPPED_CAPABILITIES.json` records PCC as absent from shipped builds; `AutoTuneService` operates outside the live answer path and does not train models. Historical items are recorded in `CHANGELOG.md`, `RELEASE_NOTES.md`, `HOW_IT_WORKS.md` and `PROGRESSION.md` with dated withdrawals.

**Expert's expert.** Additions to the historical list from the trace: the `.cpuAndGPU` Maximum profile that excluded the Neural Engine (fixed 2026-08-26); the `NSImage.lockFocus` macOS render path that produced 4× oversize images (replaced by a bitmap context); the 0.98 Maximum verification bar (now 0.80); the 0.55 `tauNormal` (now 0.40); the transcript-carrying reasoning chain that overflowed at 4,521 tokens (replaced by the FactBank); the reorder stride of half the chunks-per-session (now equal); the hardcoded 0.70 audit similarity. And a correction to the bank itself: "fixed 384-dimensional architecture" is listed as a historical oversimplification, which is right, but in practice every shipping library is 384 unless someone chose an NL provider, so say "384 by default, resolved per library."

## Every concept

### 18-of-20 zero-hallucination result (Historical, documented)
- **Idiot:** a score that got thrown out.
- **Dot-connector:** the run was invalidly fast; generation likely never executed as assumed.
- **Expert:** withdrawn in `HOW_IT_WORKS.md` and `PROGRESSION.md`; never cite.

### 32K PCC window (Historical, documented)
- **Idiot:** a bigger desk that isn't real.
- **Dot-connector:** a compatibility fallback value; Apple's per-session limit is 4,096 on PCC too.
- **Expert:** `HARD_LIMITS.md`; `LLMModel.contextLength` returns 4,096 for every route.

### 3B versus 20B selector (Historical, verified) and AFM 3 Core Advanced label (Historical, verified)
- **Idiot:** a menu that pretended to pick a model size.
- **Dot-connector:** the framework exposes availability and execution, not parameter tiers; aliases resolve to on-device.
- **Expert:** `FoundationModelRoutePolicy`; `LLMModelType`; changelog.

### Approximate confidence probability (Historical, documented)
- **Idiot:** the 80% isn't an 80% chance.
- **Dot-connector:** a policy-calibrated trust signal, never validated against outcomes.
- **Expert:** `ConfidenceCalibrationService`; `EVALS.md`.

### Automatic online self-training (Historical, verified) and AutoTuneService (Support, verified)
- **Idiot:** the app does not learn from your documents by retraining.
- **Dot-connector:** it adjusts policy and thresholds from evaluation data under constraints; the embedding and reranker models are never trained on user content.
- **Expert:** `AutoTuneService` outside the live path; `EmbeddingService` never fine-tunes.

### Bundled Core ML generative backend (Historical, verified), Local GGUF backend (Historical, verified), Local MLX generative backend (Historical, verified)
- **Idiot:** three writers that were fired.
- **Dot-connector:** the app consolidated on Apple's system model plus deterministic analysis; multiple runtimes fragmented routing.
- **Expert:** absent from `RAGService` model resolution.

### Default HNSW architecture (Historical, verified)
- **Idiot:** the app does not use the shortcut index.
- **Dot-connector:** exact scan over mmap is the default; HNSW belongs to the optional Vectura path.
- **Expert:** `VectorStoreRouter`.

### Dynamic Foundation Model profiles (Dormant, verified)
- **Idiot:** a registry nobody calls.
- **Dot-connector:** anticipated a more observable model-tier API that never came.
- **Expert:** `FoundationModelDynamicProfileRegistry.swift`, no active call sites.

### Embedding-based chunk boundary detection (Dormant, verified)
- **Idiot:** a cleverer cutter that's switched off.
- **Dot-connector:** would split where adjacent sentence embeddings diverge; the chunker is never given an embedding service, so it returns no boundaries.
- **Expert:** method in `SemanticChunker`; `embeddingService` never assigned.

### Fixed 384-dimensional architecture (Historical, documented)
- **Idiot:** "always 384" is an oversimplification.
- **Dot-connector:** 384 by default (MiniLM), 512 for NL providers, 1,024 declared by the dormant scaffold; resolved per library via the fingerprint.
- **Expert:** `EmbeddingProvider`, `EmbeddingFingerprint`.

### Late chunking (Historical, documented)
- **Idiot:** a research trick the app doesn't do.
- **Dot-connector:** embedding a long document jointly and pooling per span; not what `SemanticChunker` does.
- **Expert:** discussed in `EMBEDDING_AND_INGESTION_UPGRADE_2026-08.md`.

### Live Neural Engine utilization (Future, verified absent)
- **Idiot:** a gauge that can't exist yet.
- **Dot-connector:** no public API; the HUD pulse is synthetic.
- **Expert:** `HardwareTelemetryState`, `DeviceCapabilityService`.

### Model judges (Historical, verified absent)
- **Idiot:** no second AI grades the first one.
- **Dot-connector:** deterministic gates and benchmark ground truth do different jobs; no model-as-judge service exists.
- **Expert:** `VerificationGateService`; changelog.

### Neural extractive QA model (Dormant, verified)
- **Idiot:** the reader on the shelf.
- **Dot-connector:** protocol and stub exist; heuristic extraction runs instead.
- **Expert:** `ExtractiveQAService` returns nil.

### PCC simulation (Historical, documented) and Production PCC (Dormant, verified)
- **Idiot:** older phones don't pretend to use the cloud, and shipped builds don't have the cloud.
- **Dot-connector:** no simulation stage exists; the real route compiles under Swift 6.4 and iOS 27 but shipped binaries were built without it.
- **Expert:** `SHIPPED_CAPABILITIES.json`; `isPCCAvailable` guards; iOS 26 users always get on-device.

### RAPTOR L2/L3 hierarchy (Future, verified)
- **Idiot:** two summary levels that are only names.
- **Dot-connector:** section- and corpus-level summaries above the per-document L1; reserved in the enum.
- **Expert:** `ChunkAbstractionLevel`.

### Single 29-step pipeline (Historical, documented) and Single recursive thought loop (Historical, documented)
- **Idiot:** two old shorthands that flatten the real shape.
- **Dot-connector:** execution branches by type, intent, mode, evidence, device and route; the "loop" is five mechanisms.
- **Expert:** `HOW_IT_WORKS.md`, `RETRIEVAL_PIPELINE.md`; modules 07, 08, 11, 12 here.

### Unmeasured speed multipliers (Historical, documented) and Zero latency (Historical, documented)
- **Idiot:** "1,000× faster" and "instant" were removed.
- **Dot-connector:** mechanisms are real; the factors were never benchmarked; device measurements show nonzero time to first token.
- **Expert:** withdrawn in `CHANGELOG.md` and `RELEASE_NOTES.md`; describe mechanisms or cite the ledger.

### Added by this pass: SpeechAnalyzer transcription branch (Dormant, verified)
- **Idiot:** the newer speech reader that never compiles.
- **Dot-connector:** guarded by a module that does not exist; calls an API shape the SDK doesn't declare; `SFSpeechRecognizer` runs instead; nothing is broken for the user.
- **Expert:** `SpeechAnalyzerService.swift:17, 94, 141, 160`; Future Backlog row filed 2026-09-02.
