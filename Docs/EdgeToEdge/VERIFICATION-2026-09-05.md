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
