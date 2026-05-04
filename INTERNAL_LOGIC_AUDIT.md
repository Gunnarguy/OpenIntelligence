# Internal Logic Audit

This document is an internal map of the current answer-engine change set.
It is not written for the public repo surface. Its job is to explain what logic now exists, why it matters, what is safe to ship, and what still needs validation before release or buyer diligence.

## Executive Read

The current work improved the engine in the right direction.
It pushed the app away from "generic chat over documents" and toward a more disciplined retrieval-and-verification system.

The strongest logic assets now in the codebase are:

1. An explicit extraction lane for exact-value questions
2. A grounded generation contract that pushes evidence-first behavior
3. A source-only verification layer that can reject unsupported claims
4. Structured answer/trust payloads that make support visible in the UI
5. Audit tooling intended to catch regressions in abstention and citation behavior

The main weakness is architectural concentration.
Too much of the decision logic still lives inside `RAGService.swift`, which makes the behavior harder to reason about, validate, and transfer cleanly in a sale or diligence process.

## Current Query Policy Map

The active question-understanding stack is now best thought of as nine policy layers:

1. Canonical per-query profiling

- `OpenIntelligence/Services/Query/Analysis/QueryProfileService.swift`
- Builds one shared profile for a question: triviality, adaptive complexity, reasoning complexity, answer intent, search intent, RAPTOR-lite routing classification, and abstraction levels.
- This is now the first consolidation point used by the Standard pipeline and the full retrieval pipeline.

2. Intent and hybrid-search bias

- `OpenIntelligence/Services/Query/Enhancement/QueryEnhancementService.swift`
- Still owns the hardcoded answer-intent and search-intent phrase logic.
- The difference after consolidation is that the pipeline consumes those decisions through a shared `QueryProfile` instead of recomputing them ad hoc at each stage.

3. Retrieval threshold and fallback policy

- `OpenIntelligence/Services/RAG/Tuning/RetrievalPolicyService.swift`
- Owns dynamic similarity floors, retrieval-cascade policy, parent-document expansion defaults, and shared agentic retrieval thresholds.
- This is now the second major consolidation point for live retrieval behavior.

4. Summary-vs-detail routing

- `OpenIntelligence/Services/Query/Routing/QueryRouterService.swift`
- Still owns RAPTOR-lite routing heuristics for overview, detail, and cross-topic questions.
- These results now flow through `QueryProfile` for the main live paths instead of being re-queried independently later in the pipeline.

5. Adaptive device/cost complexity

- `OpenIntelligence/Services/Infrastructure/Optimization/AdaptivePipelineOptimizer.swift`
- Still owns device-pressure and coarse query-complexity adaptation.
- Its `QueryComplexity` estimate is now captured inside the shared `QueryProfile` for the main Standard path.

6. Evidence scoring and extractive prioritization

- `OpenIntelligence/Services/RAG/Tuning/EvidenceScoringPolicyService.swift`
- Owns precision-lock thresholds, sentence scoring, extractive candidate priority, corrective retrieval scoring, and the remaining cross-reference/spec-sniper evidence weights.
- This is now the shared scoring layer for the high-precision extraction path instead of leaving those weights scattered through `RAGService.swift`.

7. Confidence and safety policy

- `OpenIntelligence/Services/RAG/Tuning/ConfidencePolicyService.swift`
- `OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift`
- `OpenIntelligence/Services/RAG/Safety/ConfidenceCalibrationService.swift`
- Verification gate thresholds, abstention thresholds, and calibration parameters are now chosen through a shared per-query confidence policy instead of an ad hoc mix of mode checks and string matching in `RAGService.swift`.

8. Agentic stopping and escalation policy

- `OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift`
- Owns retrieval-quality grading, speculative acceptance thresholds, hard irrelevance gates, confidence progression, repetition/saturation stopping, and verification acceptance rules for Deep Think and Maximum.
- The agentic loop still orchestrates execution, but the live stop/escalation policy is no longer spread across the reasoning loop.

9. Orchestration and remaining policy islands

- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`
- Still contains the largest concentration of remaining decision policy: cascade thresholds, parent-document promotion rules, compression policy, evidence-first gates, verification entry conditions, and developer-only reasoning-chain overrides.
- This file is materially smaller in terms of threshold duplication than before, but it is still the main concentration risk.

## Consolidation Status

What is now consolidated:

1. Standard-mode query complexity, trivial-query detection, answer intent, search intent, and RAPTOR-lite routing are now built once via `QueryProfileService` and reused.
2. The full retrieval pipeline used by Deep Think and Maximum now reuses the same shared profile for routing, hybrid weight selection, and extractive-intent detection.
3. Hybrid weight clamping now has a single shared per-query calculation path via `QueryProfile.adjustedHybridWeights(from:)`.
4. Similarity floors, retrieval-cascade thresholds, parent-document expansion defaults, and agentic broad-search thresholds now flow through `RetrievalPolicyService`.
5. Verification gate strictness, verification pass thresholds, and calibration abstention thresholds now flow through `ConfidencePolicyService`.
6. Precision-lock thresholds, sentence scoring, extractive candidate ranking, cross-reference evidence weights, and spec-sniper scoring now flow through `EvidenceScoringPolicyService`.
7. Deep Think and Maximum retrieval grading, speculative acceptance, hard irrelevance gating, confidence progression, and evidence-driven stopping now flow through `AgenticPolicyService`.

What is still fragmented:

1. `RAGService.swift` still contains multiple remaining policy decisions around context packing, evidence-first fallback, compression, and corrective retrieval.
2. `AgenticOrchestrator.swift` still contains some answer-grading and synthesis heuristics, even though the main stop-confidence and escalation targets are now centralized.
3. There are still isolated score heuristics in answer-structure, claim filtering, and non-extractive grading paths that are not yet driven by a single policy layer.

## What The New Logic Actually Does

### 1. Deterministic Extraction Lane

Relevant files:

- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`
- `OpenIntelligence/Services/Query/Analysis/GroundedAnswerPolicy.swift`
- `OpenIntelligence/Services/Query/Enhancement/QueryEnhancementService.swift`

Purpose:

- Route direct factual lookups away from unnecessary recursive reasoning.

Why it matters:

- Questions about timing, dose, route, counts, sample size, or exact values should behave like disciplined reading, not synthesis.
- This reduces "thinking past the answer" and lowers the chance of contaminating the result with nearby but irrelevant content.

Core commercial value:

- This is one of the most defensible pieces of retrieval logic in the app because it is tied to observable product behavior and directly improves trust on high-friction questions.

Current status:

- `SHIP`, with regression coverage.

### 2. Grounded Prompt Contract

Relevant file:

- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`

Purpose:

- Replace loose generation instructions with an explicit evidence-grounded operating contract aligned to the `Future` guidance.

Why it matters:

- This is the highest-ROI prompt-layer improvement.
- It forces extraction vs synthesis behavior, conservative abstention, sentence-level discipline, and "shorter but faithful" answers.

Core commercial value:

- This is packaging-friendly logic because it can be described clearly to a buyer: the engine is instructed to answer from evidence, not from generic model prior.

Current status:

- `SHIP`, but it should not be oversold as the whole solution.

### 3. Source-Only Claim Verification

Relevant files:

- `OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift`
- `OpenIntelligence/Core/Models/StructuredAnswer.swift`
- `OpenIntelligence/Core/Models/ChatMessage.swift`
- `OpenIntelligence/Features/Chat/Response/ResponseDetailsView.swift`

Purpose:

- Take a candidate answer, decompose it into claims, verify those claims against retrieved evidence, and present only supported claims or abstain.

Why it matters:

- This is the main step that turns "cited answer" into "inspectable supported answer."
- It improves trust posture because unsupported claims can be dropped instead of silently passing through.

Important implementation note:

- The verifier now has two modes:
  - general evidence-grounded mode for ordinary document QA
  - strict scientific-domain mode for experimental literature

Why that split matters:

- Without it, the engine would overfit scientific logic onto manuals, playbooks, and ordinary business documents.

Core commercial value:

- High.
- This is one of the most saleable logic assets in the repo because it is concrete, inspectable, and product-visible.

Current status:

- `WATCH`.
- Strong logic, but needs lane-by-lane behavior validation so it does not over-block useful answers.

### 4. Verification Gates

Relevant file:

- `OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift`

Purpose:

- Run post-generation checks on retrieval confidence, evidence coverage, numeric sanity, contradiction risk, semantic grounding, answer completeness, and domain isolation.

Why it matters:

- Gives the engine an explicit refusal path instead of relying only on prompt compliance.

Core commercial value:

- Medium to high.
- Buyers like "it knows when not to answer" more than they like vague AI confidence language.

Current status:

- `WATCH`.
- Good direction, but verification policy is starting to overlap with source-only verification and needs careful regression coverage to avoid duplicated or conflicting failure paths.

### 5. Structured Trust Output

Relevant files:

- `OpenIntelligence/Core/Models/StructuredAnswer.swift`
- `OpenIntelligence/Features/Chat/Conversation/MessageBubbleV2.swift`
- `OpenIntelligence/Features/Chat/Response/AnswerIntelligenceView.swift`
- `OpenIntelligence/Features/Chat/Response/ResponseDetailsView.swift`

Purpose:

- Preserve claims, evidence, rejected claims, missing facets, and gate results in a structured model that the UI can inspect.

Why it matters:

- This converts hidden engine behavior into visible product trust behavior.
- It also makes buyer demos stronger because the engine can show why a claim survived or was dropped.

Core commercial value:

- High for demos, diligence, and transfer value.

Current status:

- `SHIP`.

### 6. Audit Tooling

Relevant files:

- `scripts/run_generation_audit.sh`
- `scripts/build_simulator_smoke.sh`
- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`

Purpose:

- Create a repeatable way to test source-faithful behavior instead of relying on ad hoc manual runs.

Why it matters:

- This is how the logic becomes defensible.
- Without regression checks, the engine will drift between releases.

Core commercial value:

- High internally, medium externally.
- A buyer may not care about the script itself, but they will care that the system has a validation story.

Current status:

- `SHIP`, but it needs a maintained scenario set.

## Ship / Watch / Risky

| Area                                      | Status | Why                                                                                     |
| ----------------------------------------- | ------ | --------------------------------------------------------------------------------------- |
| Deterministic extraction routing          | SHIP   | Clear upside, directly tied to observable failure reduction                             |
| Grounded generation prompt contract       | SHIP   | High-ROI, low-risk compared with deeper engine rewrites                                 |
| Structured answer / trust payloads        | SHIP   | Product-visible improvement with strong transfer value                                  |
| Source-only claim verification            | WATCH  | Strong logic, but can become too strict or slow if left uncalibrated                    |
| Scientific domain isolation               | WATCH  | Valuable for experimental literature, but must stay conditional                         |
| Expanded verification gates               | WATCH  | Good safety posture, but may overlap with claim verifier                                |
| Further giant edits to `RAGService.swift` | RISKY  | Too much policy already lives there; more changes increase transfer and regression risk |
| Large pre-release architecture refactor   | RISKY  | Correct in the long run, but not the right move immediately before shipping             |

## What Is Actually Sellable Here

The sellable logic is not "we used a model."
The sellable logic is:

1. The ingestion-to-answer pipeline that turns private documents into an answerable local knowledge asset
2. The query routing that distinguishes exact extraction from synthesis
3. The post-generation verification behavior that prefers supported answers and can abstain
4. The structured trust payload that makes support inspectable
5. The Apple-native deployment path for private, offline-first document QA

That bundle is more valuable than any single heuristic in isolation.

## Main Architectural Weakness

The weakest part of the current system is not the product idea.
It is concentration of logic.

The following files still carry too much policy:

- `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`
- `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift`
- `OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift`

This is a transfer-risk issue.
A buyer can understand the product quickly, but a buyer engineering team will still see a lot of critical behavior concentrated in a few oversized files.

## What Must Happen Before Release

1. Run a small regression set across the major answer lanes.
2. Confirm the scientific-domain logic does not degrade ordinary document QA.
3. Confirm abstention behavior is useful, not over-triggered.
4. Keep additional pre-release edits focused and narrow.

## What Must Happen Before Diligence

1. Prepare a short internal walkthrough of the answer pipeline.
2. Keep a canonical scenario set with expected outcomes.
3. Be able to explain where trust behavior comes from:
   prompt contract, routing, gates, claim filtering, and UI surfacing.
4. Be honest that the next medium-term engineering step is splitting policy out of `RAGService.swift`.

## What This Means In Product Terms

From a user perspective, the engine now behaves less like an eager chatbot and more
like a careful reader.

The biggest visible improvements are:

1. More exact-value questions route toward extraction instead of over-synthesis.
2. Answers are more likely to stay inside the boundary of retrieved evidence.
3. Unsupported or weakly supported claims are more likely to be dropped or softened.
4. Trust behavior is more inspectable because claims and evidence survive into the UI.

That is the right direction for both product trust and commercial positioning.

## What Is Actually New In This Change Set

Compared with the earlier state of the app, the meaningful delta is not a new
model or a new UI shell.

The meaningful delta is:

1. Better query-lane selection for direct lookup questions
2. Better evidence discipline in generation
3. Better post-generation verification and abstention behavior
4. Better user-visible trust surfacing
5. Better internal auditability of answer quality

That is a coherent engine story.
It should be described as an evidence-grounded document reasoning system, not as
"chat with PDFs."

## What Still Needs Care

The main failure modes to watch now are:

1. Over-strict refusal on ordinary business or consumer documents
2. Verification overlap that duplicates rejection logic in multiple places
3. Slow or brittle behavior caused by too much policy inside `RAGService.swift`
4. Regression risk when new answer heuristics are added without scenario checks

Those are manageable, but only if the next edits stay focused.

## Safe Demo Claims

These are safe claims to make in demos or diligence conversations:

1. The engine distinguishes direct extraction questions from synthesis-heavy questions.
2. The engine is designed to answer from retrieved evidence rather than generic model prior.
3. The engine can suppress or reject claims that are not supported by retrieved material.
4. The app exposes evidence and trust details in a way that a user can inspect.
5. The current system is optimized for Apple-native, privacy-conscious document QA.

These are not safe claims yet:

1. "Every answer is guaranteed correct."
2. "The engine fully solves hallucinations."
3. "Scientific-document logic is fully validated across all domains."
4. "The architecture is already cleanly modularized for external diligence."

## Packaging Implications

From an SDK or diligence perspective, the strongest transferable assets are:

1. The routing policy
2. The grounded prompt contract
3. The claim verification layer
4. The structured trust payload
5. The regression tooling and scenario philosophy

The weakest transferable asset is the current code organization.
A buyer can value the behavior before they value the code shape, but code shape
still matters once diligence becomes technical.

## Recommended Next Engineering Move

The next move should not be another giant logic expansion.
The next move should be controlled decomposition.

Recommended order:

1. Lock a small regression set for the main answer lanes.
2. Finish SDK-boundary cleanup so the engine target becomes real and narrow.
3. Extract verification and routing policy out of `RAGService.swift` in slices.
4. Preserve current product behavior while making the logic easier to explain and package.

That sequence protects both shipping velocity and saleability.

## Final Internal Verdict

The current answer-engine work is directionally strong and commercially relevant.

It materially improves:

1. Trust posture
2. Exact-answer behavior
3. Inspectability
4. Diligence narrative

It does not yet justify saying the system is fully mature or fully productized as
a buyer-ready SDK.

The honest verdict is:

- logic quality: `stronger`
- product trust: `meaningfully improved`
- commercial story: `credible`
- code transfer readiness: `improving but not clean yet`
- immediate release posture: `ship with focused validation`
