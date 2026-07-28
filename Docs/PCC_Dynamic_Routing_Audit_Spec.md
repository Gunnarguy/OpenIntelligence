# PCC Dynamic Routing and Multi-Model Architecture Audit Specification

## Status

- [ ] Phase 0: Workspace and SDK verification
- [ ] Phase 1: Repository inventory
- [ ] Phase 2: Runtime execution tracing
- [ ] Phase 3: Apple SDK capability verification
- [ ] Phase 4: Implemented-versus-claimed matrix
- [ ] Phase 5: Routing ambiguity analysis
- [ ] Phase 6: Architecture comparison
- [ ] Phase 7: Target router design
- [ ] Phase 8: Dynamic Profiles assessment
- [ ] Phase 9: Evaluation design
- [ ] Phase 10: Final audit deliverables
- [ ] Human review completed
- [ ] Implementation authorized

## Controlling Rule

This document is the immutable audit specification.

The agent must not modify this file except to correct an objectively broken path or typographical error, and any such correction must be documented in the progress ledger.

Completion status belongs in:

`Docs/AUDIT/PCC_DYNAMIC_ROUTING_PROGRESS.md`

No production implementation changes are authorized until the user explicitly approves the completed audit and implementation proposal.

You are performing a comprehensive, evidence-first architecture audit of the OpenIntelligence repository.

Your job is to determine exactly what the application currently does with:

1. Apple Foundation Models
2. SystemLanguageModel
3. PrivateCloudComputeLanguageModel
4. PCC entitlement detection
5. automatic model routing
6. Standard, Deep Think, and Maximum modes
7. agentic and multi-session reasoning
8. Dynamic Profiles
9. the claimed 3B and 20B on-device model routes
10. local retrieval, RAG, citations, verification, and answer synthesis
11. cloud consent, privacy boundaries, fallbacks, and quota handling
12. UI and telemetry describing which model actually executed

This is an audit first. Do not modify implementation code until the audit report is complete and I explicitly approve a proposed implementation plan.

PRIMARY RULES

- Do not trust README files, comments, release notes, documentation, UI labels, enum names, or intended architecture without verifying them against executable code.
- Treat compiled source behavior and the installed Xcode SDK as the primary sources of truth.
- Treat Apple’s current official documentation, WWDC26 sessions, generated Swift interfaces, and framework headers as external sources of truth.
- Do not guess that an API exists.
- Do not infer that a model executed merely because a route, label, setting, or enum uses that model’s name.
- Every material conclusion must include file paths, symbols, and line ranges.
- Clearly separate:
  1. implemented and active,
  2. implemented but unreachable,
  3. compatibility fallback,
  4. simulated behavior,
  5. UI or documentation claim only,
  6. dead or obsolete code,
  7. unavailable because of the installed SDK,
  8. behavior requiring physical-device verification.
- Do not simplify the architecture based on assumptions.
- Do not delete or refactor anything during the audit.
- Do not commit or push changes.
- Do not create speculative APIs.

CONTEXT

The Apple Developer account now has the managed entitlement for:

com.apple.developer.private-cloud-compute

The app is intended to support:

- local-first document ingestion and storage,
- local OCR, indexing, embeddings, hybrid retrieval, and reranking,
- Apple’s on-device Foundation Model,
- Apple Private Cloud Compute,
- Standard, Deep Think, and Maximum quality modes,
- agentic RAG,
- explicit cloud consent,
- citation-grounded responses,
- transparent execution-path reporting.

The key question is whether OpenIntelligence should:

A. select one model automatically per query,
B. use a staged collaborative workflow where the local model and PCC have different roles,
C. use Apple Dynamic Profiles to switch models inside one logical session,
D. use phone-a-friend child sessions,
E. run parallel model candidates and synthesize them,
F. retain explicit user-selected modes rather than automatic routing,
G. use a constrained hybrid of these approaches.

A central concern is routing ambiguity for questions asked against complex document libraries.

The system must not route based only on whether a user’s wording appears simple or complex. A short question can require:

- corpus-wide retrieval,
- table interpretation,
- multi-document synthesis,
- contradiction resolution,
- numerical computation,
- temporal reasoning,
- citation validation,
- or abstention because evidence is insufficient.

PHASE 1: REPOSITORY INVENTORY

Locate and inspect every relevant implementation, including but not limited to:

- LLMService.swift
- FoundationModelRoute.swift
- FoundationModelRoutePolicy.swift
- FoundationModelSessionFactory.swift
- FoundationModelDynamicProfileRegistry.swift
- QueryRuntimeCoordinator.swift
- AgenticOrchestrator.swift
- RAGService.swift
- RAGQualityMode.swift
- LLMModel.swift
- SettingsStore.swift
- ModelResolutionService.swift
- ModelStatusIndicator.swift
- UnifiedMetricsBar.swift
- PCCRouteEvaluator.swift
- EntitlementChecker
- FoundationModelTokenBudget
- FoundationModelTranscriptStore
- FoundationModelPromptCompiler
- FoundationModelToolRegistry
- cloud-consent and PCC-cooldown implementations
- query profiling and query-planning services
- citation and grounding validators
- answer-intent classification
- retrieval confidence and contradiction detection
- telemetry, diagnostics, and response metadata
- tests covering any of the above

Search the entire repository for:

PrivateCloudComputeLanguageModel
SystemLanguageModel
LanguageModelSession
DynamicProfile
DynamicInstructions
FoundationModelsUtilities
onDeviceAdvanced
advanced20B
core3B
physicalMemory
supportsAdvancedOnDeviceModel
allowPrivateCloudCompute
executionContext
fmPreference
PCCReasoningLevel
quotaUsage
isLimitReached
contextSize
reasoningLevel
ActiveModelRouteResolved
actualRoute
cloudEligible
preferCloud
cloudOnly
session = nil
resetSession
restoreFromTranscript
agentic
plannerEscalated
citation
verification
grounding
confidence
abstain
contradiction
retrieval confidence

Produce a complete component map showing which code calls which code.

PHASE 2: TRACE REAL EXECUTION

Trace at least these query paths end to end:

1. Standard query with one strong matching document
2. Standard query requiring several documents
3. Short but computationally complex query
4. Long but simple summarization request
5. Deep Think query
6. Maximum query
7. Offline query
8. PCC unavailable
9. PCC quota exhausted
10. PCC entitlement absent
11. Cloud consent denied
12. Retrieval confidence low
13. Contradictory documents
14. No supporting evidence
15. User manually selects on-device
16. User manually selects PCC
17. User selects the claimed 20B model
18. A query that exceeds the local context window
19. An agentic query requiring multiple retrieval cycles
20. A follow-up question using a restored transcript

For each path, document:

- UI entry point
- quality mode
- settings read
- query profile generated
- execution plan generated
- retrieval behavior
- token estimate
- intended route
- actual model object instantiated
- actual `LanguageModelSession` initializer used
- whether a transcript is preserved or discarded
- whether tools are enabled
- whether PCC reasoning options are supplied
- fallback behavior
- response verification
- actual metadata and UI shown to the user
- any difference between intended route and actual route

Create a Mermaid sequence diagram for each major execution family rather than all 20 individually if several share the same path.

PHASE 3: VERIFY APPLE API REALITY

Using the installed Xcode SDK:

1. Inspect the generated Swift interface for FoundationModels.
2. Verify whether these symbols compile:
   - SystemLanguageModel.default
   - SystemLanguageModel()
   - SystemLanguageModel.advanced
   - any API that explicitly selects AFM 3 Core
   - any API that explicitly selects AFM 3 Core Advanced
   - PrivateCloudComputeLanguageModel()
   - LanguageModelSession.DynamicProfile
   - DynamicInstructions
   - Profile
   - `.model(...)`
   - `.reasoningLevel(...)`
   - historyTransform
   - session properties
   - mutable transcript
   - contextSize
   - token counting APIs
   - PCC quota APIs
3. Use minimal compiler probes rather than assuming availability.
4. Record the exact Xcode and Swift versions.
5. Record platform availability annotations.
6. Distinguish APIs available in:
   - the SDK,
   - the current deployment target,
   - the simulator,
   - a physical device,
   - signed distribution builds.
7. Determine whether Apple exposes separate developer-selectable APIs for AFM 3 Core and AFM 3 Core Advanced.
8. Determine whether the app’s physical-memory threshold has any official relationship to Apple’s model selection.
9. Determine whether `SystemLanguageModel` internally selects the appropriate device model without giving the app direct control.
10. Do not use model names in UI unless runtime behavior can substantiate them.

Compare repository behavior against Apple’s current official:

- Foundation Models documentation
- PCC documentation
- WWDC26 “What’s new in the Foundation Models framework”
- WWDC26 “Build agentic app experiences with the Foundation Models framework”
- Foundation Models Utilities package
- Apple third-generation foundation-model research

Provide official source references for each API-level conclusion.

PHASE 4: DETERMINE WHAT IS ALREADY INTEGRATED

Produce a matrix with these columns:

| Capability | Claimed | Code exists | Reachable | Compiles | Executes | Device verified | Production ready | Evidence |

Include at minimum:

- on-device generation
- PCC generation
- PCC entitlement check
- PCC availability check
- PCC quota handling
- PCC reasoning levels
- dynamic token budgeting
- automatic routing
- manual route override
- advanced 20B route
- Standard mode
- Deep Think
- Maximum
- agentic RAG
- transcript persistence
- Apple Dynamic Profiles
- baton-pass orchestration
- phone-a-friend orchestration
- parallel model execution
- local verification after PCC
- PCC repair after failed verification
- transparent execution receipts
- privacy-safe evidence minimization
- cloud-consent enforcement
- fallback behavior
- route telemetry accuracy

For every partially implemented capability, state exactly what is missing.

PHASE 5: AUDIT ROUTING AMBIGUITY

Evaluate whether the current router makes decisions using sufficient evidence.

Do not treat query length or quality-mode selection as a complete complexity signal.

Inspect whether routing incorporates:

- actual retrieved context size,
- number of relevant documents,
- retrieval confidence,
- score distribution,
- citation density,
- table or numerical content,
- detected contradictions,
- temporal questions,
- multi-hop requirements,
- corpus-wide operations,
- tool requirements,
- prior conversation context,
- response-length requirements,
- local context capacity,
- PCC availability and quota,
- network state,
- privacy preference,
- battery and thermal state,
- failure history,
- observed route performance.

Identify false-negative cases where a seemingly simple question should escalate.

Identify false-positive cases where a long query should remain local.

Create at least 25 concrete query scenarios based on document-library use and state the expected route and justification.

The router must be conservative about ambiguity:

- deterministic extraction should be preferred for exact lookup,
- retrieval quality should be assessed before model escalation,
- PCC must not compensate for missing evidence,
- low retrieval confidence must produce broader retrieval or abstention rather than a more authoritative hallucination,
- the selected route must never weaken citation requirements,
- a cloud model must receive only the evidence necessary for its assigned role.

PHASE 6: COMPARE ARCHITECTURES

Evaluate these architectures against the actual codebase:

1. Single-model deterministic routing
2. On-device primary with PCC escalation
3. PCC primary with local fallback
4. Local planner → PCC synthesizer → deterministic verifier
5. Local planner → PCC synthesizer → local-model critic → deterministic verifier
6. Dynamic Profile baton-pass
7. PCC parent with on-device phone-a-friend
8. On-device parent with PCC phone-a-friend
9. Parallel local and PCC candidate generation
10. Multi-candidate voting
11. Adaptive policy selecting among several execution graphs

Score each from 1 to 10 for:

- grounded accuracy,
- citation fidelity,
- latency,
- PCC quota efficiency,
- battery impact,
- thermal impact,
- implementation complexity,
- debuggability,
- user explainability,
- privacy clarity,
- offline resilience,
- context management,
- risk of recursive loops,
- compatibility with existing architecture.

Do not recommend an architecture because it sounds advanced.

Recommend it only if it addresses measurable failure modes in OpenIntelligence.

PHASE 7: DESIGN THE RECOMMENDED ROUTER

If a new router is warranted, define a typed execution-plan model such as:

struct ModelExecutionPlan {
    let stages: [ExecutionStage]
    let reasonCodes: [RouteReason]
    let privacyBoundary: PrivacyBoundary
    let fallbackPlan: FallbackPlan
    let verificationPlan: VerificationPlan
}

The exact implementation can differ, but the plan must represent:

- zero, one, or multiple model stages,
- the role of each model,
- what evidence each stage receives,
- whether stages are sequential or parallel,
- whether PCC is optional or mandatory,
- reasoning level,
- context budget,
- fallback behavior,
- verification requirements,
- route explanation,
- actual execution results.

Separate:

1. intended plan,
2. attempted route,
3. actual route,
4. fallback route,
5. final completed execution path.

Do not overload a single enum with all five meanings.

Routing should occur after enough retrieval information exists to understand the true task, unless a hard constraint already determines the path.

Consider a two-stage decision:

Stage A, pre-retrieval:
- privacy
- connectivity
- user preference
- obvious exact-lookup intent
- device and model availability

Stage B, post-retrieval:
- evidence volume
- score distribution
- contradictions
- missing evidence
- number of documents
- computation requirements
- remaining context budget
- need for synthesis

PHASE 8: DYNAMIC PROFILES ASSESSMENT

Determine whether Apple Dynamic Profiles provide meaningful value over the current session-factory approach.

Specifically evaluate:

- shared transcript requirements,
- context-window mismatch between local and PCC,
- redaction before PCC,
- evidence minimization,
- history transforms,
- KV-cache invalidation,
- session lifetime,
- current forced statelessness,
- tool changes,
- model handoff behavior,
- cancellation and transcript rollback,
- concurrency,
- error recovery,
- testability.

Determine whether OpenIntelligence should use:

- one persistent Dynamic Profile session,
- separate short-lived sessions,
- a phone-a-friend child session,
- or no Dynamic Profiles for the first implementation.

Do not assume Dynamic Profiles are automatically superior.

PHASE 9: EVALUATION PLAN

Design an evaluation suite that can determine whether hybrid routing is actually better.

Create evaluation categories for:

- exact fact retrieval
- multi-document synthesis
- conflicting documents
- tables and numbers
- temporal reasoning
- procedure reconstruction
- unanswerable questions
- citation support
- citation completeness
- abstention
- tool selection
- follow-up questions
- long transcripts
- context overflow
- route correctness
- PCC failure and fallback

Compare:

A. on-device only
B. PCC light
C. PCC moderate
D. PCC deep
E. current automatic routing
F. proposed collaborative route
G. parallel ensemble, if technically viable

Measure:

- answer correctness
- claim-level citation precision
- citation completeness
- unsupported-claim rate
- correct abstention
- retrieval recall
- route-selection correctness
- tool-call correctness
- structured-output validity
- time to first token
- total latency
- PCC calls per user query
- token usage
- thermal impact
- battery impact
- failure rate
- fallback success
- user-visible route accuracy

Propose objective promotion gates.

Do not fabricate baseline results.

PHASE 10: REQUIRED OUTPUT

Create:

Docs/AUDIT/PCC_DYNAMIC_ROUTING_CODEBASE_AUDIT.md

The report must contain:

1. Executive verdict
2. Confidence level and evidence quality
3. Current architecture diagram
4. Actual execution-path diagrams
5. Implemented-versus-claimed matrix
6. Apple SDK capability verification
7. 3B versus 20B findings
8. PCC integration findings
9. Dynamic Profiles findings
10. Agentic orchestration findings
11. Routing ambiguity analysis
12. Privacy and evidence-boundary analysis
13. Telemetry and UI-truthfulness analysis
14. Failure modes
15. Architecture comparison matrix
16. Recommended target architecture
17. Minimal migration plan
18. Evaluation and benchmarking plan
19. Required physical-device tests
20. Open questions that cannot be resolved statically
21. Exact files requiring changes, without changing them
22. Final go/no-go recommendation

Also create:

Docs/AUDIT/PCC_DYNAMIC_ROUTING_EVIDENCE_MATRIX.csv

Columns:

claim_id,
claim,
status,
file,
symbol,
line_range,
runtime_verification_needed,
official_apple_source,
confidence,
notes

And create:

Docs/AUDIT/PCC_DYNAMIC_ROUTING_TEST_MATRIX.csv

Columns:

test_id,
scenario,
current_expected_route,
current_actual_route,
proposed_route,
models_used,
retrieval_state,
privacy_state,
network_state,
quota_state,
expected_fallback,
validation_required,
result,
notes

FINAL RESPONSE TO ME

After writing the reports, respond with:

1. The blunt verdict in no more than 10 sentences.
2. What is genuinely working now.
3. What only appears integrated.
4. Whether the 20B option is real and separately selectable.
5. Whether Apple Dynamic Profiles are already used.
6. Whether current automatic routing is safe for complex libraries.
7. The recommended architecture.
8. The five highest-risk changes.
9. The exact physical-device tests still required.
10. The paths of all generated audit files.

Do not implement the new architecture until I review and approve the audit.
