# Current State

Updated: 2026-11-10 about 16:20 PT
Branch/worktree: `main`, primary checkout
Last verified commit: b1b91cd7

## Objective

**Ship 5.8** (owner, 2026-11-10: "I feel like I should ship 5.8"). The board is 5.8 and Future Backlog only. What
remains: benchmark day (2026-11-11), the owner's short device pass, then a Xcode Cloud build and the App Store Connect
submission at his word. Every commit carries `[ci skip]` until he asks for a build.

## Status

Everything asked on 2026-11-10 is built, on his iPhone 16 Pro Max (development build) and pushed, except the item
under "Uncommitted". Simulator: 224 tests run, 0 failures, 1 skipped (silent-audio import; the test simulator is
erased before each run and has no speech model). Nothing below is checked on a device unless it says so.

| Area | State |
|---|---|
| Morning list (table title row, Quotes only, Deep Think panel, background wait and resume, one vector store per library, OCR off the main thread) | Committed 45cb980f and after; refuting reviews fixed |
| Cited passage marked in any document (`PassageFinder`) | Committed; 58.4% to 88.9% of 10,029 passages |
| X-Ray | Every outline is the chip package, traced from its own edges, placed with each model's real screen inset (Apple Tech Specs + Xcode simulator profiles). 18 layouts high, 11 medium; only iPad Air 13-inch M3/M4 and iPhone Duo draw nothing. Evidence: `BenchmarkRuns/2026-11-10-xray-chip-positions/` (4 passes). Label names the busy part (Neural Engine/GPU/CPU); Labels switch in Settings |
| Setup card ("Getting search ready") | HUD fades aside while it shows; a question asked meanwhile waits at the start and says so; Live Activity when the app is left |
| Live Activities and widgets | Use the person's accent colour through the existing App Group |
| Metrics panel | Fits its sections; drag clamped so the handle stays on screen; ring and "best match" are one number |
| Deep Think cut off in the background | Local only now holds the synthesis; a cut-off synthesis (`LLMResponse.streamCutOff`) is written again, never saved |
| Hazard-ratio miss (Standard) | Results tables with intervals take no contents-page penalty; statistical-value questions are value questions. **Unmeasured** |
| Compute Profile card (was GPU Acceleration) | Chip, ladder, jobs grouped by when they run, fixed heights |
| Maximum (compute profile) | Turns the work up on every device: 432 DPI on every page, full-size layout pass, 24 rescue regions, rerank up to 400, 120 keyword results, Core ML `fastPrediction`. `OI_MAXIMUM_FIDELITY=on\|off` overrides it. **Unmeasured; ships only if benchmarks hold** |
| Defects fixed for every profile | `VisionOCRThrottle` limits read at each use; import embedding batch follows the chip |
| Trace | Three new lines: which penalty moved the reranker's pick, why a lookup is a definition, why a call was not held in the background |

## Just landed (02a728f1)

Six "How hard" tiles on the Compute Profile card, everything under the card folded into a "More detail" row
(`FoldedDetails`), Maximum holds at least 2 pages at once. Installed 16:12; the owner checks it fits one screen.
A read-only audit of every per-device capability claim (background GPU, tier numbers, device mapping, unused
headroom) was running in the background; its report is not in the repo yet.

## Active Constraints

- `PROCEED: IMPLEMENT` before source edits; hard-boundary files only when he names them (`BNNSVectorDatabase.swift` not named).
- Accuracy first: anything that changes what is read or retrieved is measured on every benchmark set before it ships.
- No approximations on the X-Ray: an unmeasured device draws nothing.
- One `xcodebuild` at a time; builds run from `/private/tmp/oi-src`. Two overlapping chains hung or mixed twice today.
- Disk: 41 GiB free after cleanup; the test simulator is erased before each run (`scratchpad/build_test.sh`).

## Working Set

- `OpenIntelligence/Features/Settings/ComputeProfileCard.swift`: the card; reads `DeviceCapabilityService` rules.
- `OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift`: `MaximumFidelity`, `isMaximumFidelityActive`, per-profile rules.
- `OpenIntelligence/Features/Telemetry/Dashboard/MotherboardHUDView.swift`: X-Ray layouts, insets, legend window.
- `OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift`: contents-page penalty, rerank ceiling, reranker load.
- `OpenIntelligence/Services/Agentic/AgenticOrchestrator+ReasoningChain.swift`: synthesis cut-off handling.
- Build chain: `/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/a5622f44-45c7-4cc5-bbb8-ff09ee2a7ccb/scratchpad/chain2.sh` (tests, Mac build, phone build, install).

## Verification

- `chain2.sh` at 967c6e41 -> 224 tests, 0 failures, 1 skipped; Mac build and iPhone build succeeded; installed 16:03.
- `python3 .claude/codemap/codemap.py check` -> 0 errors.

## Blockers / Unknowns

- **Maximum, Performance's new depth and the retrieval fix are unmeasured.** Benchmark day: Balanced, Performance and Maximum (`OI_COMPUTE_PROFILE=balanced|performance|maximum`; Performance reranks 325, 90 keywords, 18 regions since 2026-11-10) on extraction fidelity, tables 158, QASPER 246; 5.7 vs 5.8; presets High Precision, Technical Manual, Exploratory; iOS 27 structured-generation failure rate; title-row fix on the 515 page checks; `fastPrediction` on and off (embedding and rerank ms).
- **GPU vector search** (Performance, Maximum) measured slower than CPU on an M3 Pro (`BenchmarkRuns/2026-10-19-metal-vs-vdsp-search`); not measured on iPhone. Measure, then move large searches to the CPU if it holds.
- **Settings values nothing reads**: done 2026-11-10 for `vectorBatchSize` (removed) and `embeddingBatchSize` (now the batch `EmbeddingService` uses). `maxChunksPerSearchYield` is defined in `DeviceCapabilityService` and read by nothing, shown nowhere; remove or wire it up.
- White Chat cause unknown (recovery in place). Rest of the Mac save crash needs `BNNSVectorDatabase.swift` named. `renderPageForParsing` still on the main thread.
- Device checks not done: Deep Think leave-and-return, hazard-ratio question again, X-Ray on the chip, setup card and its Live Activity on a fresh install, New Chat after relaunch, Spotlight tap (row `3ff49a74d54f81fea954d76ff336595e`), Instruments traces (Deep Think, 900-page import).
- Notion: X-Ray row `41449a74d54f81e4abfec4bba6a66124` In Progress; rows for Maximum, the hazard-ratio fix and the Deep Think cut-off are not filed yet.

## Exact Next Action

Start benchmark day: run the extraction-fidelity set three times on one build, `OI_COMPUTE_PROFILE=balanced`, then
`performance`, then `maximum`, and compare; then tables 158 and QASPER 246 the same way. Each profile ships its depth
only if it reads and finds at least as well as Balanced. The Active Device card (2026-11-10, b1b91cd7) and the
profile ramp still wait on the owner's look on his phone.
