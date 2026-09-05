# Edge to edge, re-verified at HEAD `d28f1b1` (2026-09-05)

`00_START_HERE.md` was written against `9c6fcbc` on 2026-09-02. Two Swift commits and nine
files have landed since. This pass re-checked the seventeen modules, `EDGE_TO_EDGE_FULL.md`, and
`Docs/Engineering/FULL_SYSTEM_TRACE.md` against the tree as it stands, then condensed the result
into one public page (`fascinaiting.me/how-it-runs.html`). Nothing here changes the modules;
it records what still holds, what moved, and one count the modules get wrong.

## What was checked, and how

| Check | Result |
| --- | --- |
| Code-shaped identifiers in `EDGE_TO_EDGE_FULL.md` (223 unique) | 210 found in the app target; 7 more in tests, benchmarks and scripts; 2 the document already labels unverified (`deterministicUUID`, `queryTimeout`); 3 are paraphrases of real names (below); 1 is a file that exists (`MonetizationPolicy.swift`) |
| The thirteen constants the modules assert | All present: 310 words, 430 tokens, 384 dimensions, RRF k = 60, weights 0.7 / 0.3, verification bar 0.80, agentic target 0.98, 1,000-vector Metal switch, 600-second audio segments, `pipelineStageWeights` with extraction 0.52, `cross-encoder/ms-marco-TinyBERT-L2-v2`, 360 DPI |
| Enum counts | `IngestionStage` 15 including `paused`; `RetrievalTraceCollector.Stage` 7; `RAGQualityMode` 7 cases of which 3 are user-facing; `ModelExecutionTarget` 4; `ModelRouteReason` 13; gates A to I in `VerificationGateService` |
| Per-mode numbers (`RAGQualityMode.swift`, `VerificationGateService.swift`, `FoundationModelTokenBudget.swift`, `AgenticOrchestrator.swift`) | topK 30 / 35 / 50; floor 0.28 / 0.25 / 0.20; λ 0.60 / 0.55 / 0.50; temperature 0.4 / 0.4 / 0.3; bar 0.50 / 0.60 / 0.80; τ 0.40 / 0.55, margin 0.03, grounding 0.50, strict 0.65 / 0.75 / 0.10 / 0.60; window 4,096, budget 3,200, reserve 256; profiles 2 / 5 / 8 / 50 steps at 0.70 / 0.85 / 0.95 / 0.98; research 180 s, 7 iterations |
| `FULL_SYSTEM_TRACE.md` line anchors | 55 anchors sit in a table cell that also names an identifier; 47 still have that identifier within 40 lines. Two point at a file that no longer carries the reference (below). The rest of the flags were the checker tripping on a file named after its own type. |
| The repository's own checkers | `verify_doc_claims.py`: 164 claims, all match. `verify_capabilities.py`: every declared capability present. Neither names `Docs/EdgeToEdge` or the trace, so those anchors had never been machine-checked before this. |

## Paraphrased names, so the next reader does not grep for them

| In the document | In the source |
| --- | --- |
| `AgenticDecision` (module 07) | `QueryExecutionPath`: `standard`, `agentic`, `forcedAgentic`, `plannerEscalated` |
| `filterAndDiversify` (module 08) | `RAGEngine.filterBySimilarity` then `RAGEngine.applyMMR` |
| `analyzeSequence` (module 02) | An Apple `SpeechAnalyzer` API, cited correctly as the reason the dormant branch does not compile |

## One correction to the modules

**Registered tools are six, not ten.** Module 10 says "ten `Tool` structs in the registry", and the
corrections table in `00_START_HERE.md` records "about six" being corrected to ten. The source says
otherwise. `FoundationModelToolRegistry.swift` defines twelve `*Tool` structs; `createTools`
constructs and appends exactly six: `RetrieveCorpusEvidenceTool`, `InspectDocumentTool`,
`CompareTopicAcrossDocumentsTool`, `GetLibraryOverviewTool`, `CountPatternTool`,
`SearchExactPatternTool`. The other six (`CompareDocumentsTool`, `FindRelatedDocumentsTool`,
`GetCorpusStatsTool`, `GetDocumentSummaryTool`, `ListDocumentsTool`, `SearchDocumentsTool`) are
defined and never registered, which makes them Dormant under the word bank's own vocabulary.
The public page says six.

## Two anchors that moved

| Anchor in the trace | Now |
| --- | --- |
| `ChatScreen.swift:2489` for `IngestionStageLedger` | The ledger is `Services/Document/Processing/IngestionStageLedger.swift:151`; `ChatScreen.swift` no longer references it |
| `AgenticPolicyService.swift:146` for `evaluateRetrievalQuality` | Lives in `Services/Agentic/AgenticOrchestrator.swift:1122` |

Both symbols are alive; only the citing file changed.

## The showcase site, measured against the same source

`fascinaiting.me`'s "Under the Hood" playground describes a "29-step pipeline: a 6-step ingestion
lane plus a 23-step agentic query loop", which module 16 lists as Historical, and its node labels
include "AFM 3 Core Advanced" and "32K Context Packing" (both Historical), and "FlashRank" and
"Semantic Cache Check", which do not appear in the source at all. "Token Boundary Enforcer" and
"Complexity Pre-Scan" name real mechanisms (`enforceTokenLimitOnChunks`, `PageComplexityAnalyzer`)
under invented labels. The new page replaces none of the playground; it stands beside it with names
that grep.

## What this pass could not settle

The 384 dimension is the default (MiniLM); module 16 is right that "always 384" oversimplifies, and
the page says "by default". Placement of any Core ML or Foundation Models work on a specific unit
remains a request, not a fact, exactly as module 05 says. Nothing on device was run.

## Second pass, same day: the quality modes, value by value

Requested after the page went up, because the modes table is the whole app in one place. Every
cell was re-read from source rather than from the trace. Four things the first pass got wrong or
under-stated, and where the truth is:

| Claim | Correction | Source |
| --- | --- | --- |
| Deep Think runs "up to 5 steps" and stops at 0.85 | Deep Think does not use `RAGQualityMode.agenticConfig` (`.thorough`) at all. `RAGService` takes `DeviceCapabilityService.optimizedAgenticConfig()` for every non-Maximum run: 5 steps / 0.85 on `.baseline` (A17 Pro), 8 / 0.90 on `.enhanced`, 10 / 0.92 on `.advanced`, `min(32, 12 × RAM/16 GB)` / 0.95 on `.ultraAdvanced`. Only Maximum takes the mode's own profile, `.unlimited` (50 / 0.98). | `RAGService.swift:8528-8535`, `DeviceCapabilityService.swift:985-1032`, `RAGQualityMode.swift:178-183` |
| "Up to 7 iterations" of recursive research | 7 is the default parameter and no call site uses it. The main path passes 5; the verification loop passes 3. Budget 180 s per pass. | `AgenticOrchestrator.swift:683, 3625, 2757, 2761` |
| Cooldown "100 ms on baseline, 0 on M-series" | 100 / 50 / 25 / 0 ms across the four tiers. | `DeviceCapabilityService.swift`, `agenticStepCooldownMs` |
| Deep Think adds "a verification loop" | Only when the device profile grants 8 or more steps (`config.maxSteps >= 8 && !config.isUnlimited`); an A17 Pro never runs it, Maximum never does. | `AgenticOrchestrator.swift:735-737, 837-839` |

Facts the modules and the trace state that this pass confirmed, and the page now shows: sessions
per chain 3 / 4 / 5 / 50, chosen from the step count (≥ 8 → `.deep`, ≥ 5 → `.standard`, else
`.light`) so Deep Think runs 4 sessions on an A17 Pro and 5 above it, with a policy cap of
`min(8, sessions + 4)` = 8 and early stopping allowed after 4; Maximum caps at
`min(50, max(8, ⌈chunks ÷ 3⌉ × 1.5))` with no early stop before 8 and stops on `confidenceReached`,
`contentSaturated`, the cap, or cancellation; tools are attached in Deep Think and switched off
inside Maximum's sessions. The two numbers that read alike are different gates: Maximum's loop
stops at 0.98 (`executeTrueUnlimitedReasoning(targetConfidence: 0.98)`) and its verification bar
is 0.80 (`verificationConfidenceThreshold`, whose comment reads "0.98 was unreachable"). Both are
correct; neither is the other.

From `ConfidencePolicyService.swift`, not previously on any page: strictness lift 0 / +0.05 /
+0.10 applied to every gate threshold (capped at 0.60 / 0.75 / 0.10 / 0.60); calibration default /
conservative / conservative; abstention floor 0.35 / 0.45 / 0.55; extractive-first questions halve
the verification bar (floor 0.25) and lower the abstention floor by 0.05; touchy topics use
`min(0.80, max(abstention + 0.15, pass bar))`. From `RAGQualityMode.swift`: query expansions off /
8 / 12, neighbouring chunks 2 / 3 / 5, contextual compression off / on / off, conversation turns
5 / 10 / 20, specification boost 1.2 / 1.3 / 1.5. From `QuotaPolicy.swift`: free-tier Maximum is 3
uses a day.

Two properties in `RAGQualityMode.swift` are read by nothing outside their own file and belong in
module 16: `maxRetrievalIterations` (2 / 5 / 20) and `preferSummariesForOverview`. Two strings in
the app itself overstate: the pipeline log prints `confTarget 85%` for every Deep Think run
regardless of tier (`RAGService.swift:8515`), and the Settings copy says Maximum "utilizes
exhaustive Neural Engine synthesis" (`SettingsView.swift:1488`), which module 05 explains is a
request the app cannot verify.
