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

| Area | Status | Why |
|---|---|---|
| Deterministic extraction routing | SHIP | Clear upside, directly tied to observable failure reduction |
| Grounded generation prompt contract | SHIP | High-ROI, low-risk compared with deeper engine rewrites |
| Structured answer / trust payloads | SHIP | Product-visible improvement with strong transfer value |
| Source-only claim verification | WATCH | Strong logic, but can become too strict or slow if left uncalibrated |
| Scientific domain isolation | WATCH | Valuable for experimental literature, but must stay conditional |
| Expanded verification gates | WATCH | Good safety posture, but may overlap with claim verifier |
| Further giant edits to `RAGService.swift` | RISKY | Too much policy already lives there; more changes increase transfer and regression risk |
| Large pre-release architecture refactor | RISKY | Correct in the long run, but not the right move immediately before shipping |

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

