# RepoOS 02 — Agent Prompt Compiler

Copy-paste templates for spawning safe agent tasks in this repository. Every template already embeds the governance preamble; fill the `<...>` slots. Machine-readable routing: `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv`.

## Shared preamble (include verbatim in every prompt)
```text
You are operating in Gunnarguy/OpenIntelligence.
Before anything else, read in order:
1. AGENTS.md
2. Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md
3. Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md
4. Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md
5. Docs/RepoOS/01_TASK_ROUTER.md and Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md
6. Docs/AppleIntelligenceTransitionPlan.md (to confirm the current active phase)
Rules: no destructive git commands; no edits to project.pbxproj, .storekit, or .entitlements;
tag all architecture claims with evidence_level and confidence; produce an implementation
plan and STOP until the user replies exactly PROCEED: IMPLEMENT; after implementing, update
the docs listed in AGENTS.md rule 14 and run the verification commands from the router.
```

## a. Retrieval change
```text
<preamble>
Task: <describe retrieval/ranking change>.
Owning subsystem: retrieval (Docs/RepoOS/01_TASK_ROUTER.md route 1).
Also read: Docs/RETRIEVAL_PIPELINE.md.
Edit only: OpenIntelligence/Services/RAG/Retrieval/**, OpenIntelligence/Services/Query/**,
OpenIntelligence/Services/RAG/Tuning/**, and their tests.
Do not touch: SQLiteFullTextService.swift schema, BNNSVectorDatabase.swift, RAGService streaming contract.
Verify: xcodebuild test -scheme OpenIntelligence -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
  -only-testing:OpenIntelligenceTests/HybridSearchServiceTests
  -only-testing:OpenIntelligenceTests/ContextPackingServiceTests
then bash scripts/build_simulator_smoke.sh.
Update Docs/RETRIEVAL_PIPELINE.md and CHANGELOG.md.
```

## b. Embedding provider change
```text
<preamble>
Task: <describe provider change>. HIGH CAUTION: stored vectors in BNNSVectorDatabase are
memory-mapped; any dimension/pooling change requires an explicit re-index plan in your proposal.
Also read: Atlas §17, canonical §3 (Core AI production status, Rust tokenizer byte offsets).
Edit only: OpenIntelligence/Services/Embedding/** provider-selection logic.
Do not touch: CoreAISentenceEmbeddingProvider.swift / CoreMLSentenceEmbeddingProvider.swift internals,
vector storage, tokenizer package pins in Package.swift.
Your plan must state: index compatibility impact, fallback chain impact (Core AI -> Core ML -> NL),
and the diagnostics card check (ContainerSettingsSheet+Sections.swift).
Verify: full test suite + build smoke. Approval required before any edit.
```

## c. Core AI / iOS 27 change
```text
<preamble>
Task: <describe Core AI / Apple Foundation Models change>. This touches a HIGH-risk subsystem.
Also read: Atlas §10 and §17, canonical §3 and §8, Docs/PRIVACY_AND_ROUTING.md.
Hard constraints: never instantiate PrivateCloudComputeLanguageModel outside the
EntitlementChecker gate (fatal crash); do not edit FoundationModelRoutePolicy.swift,
FoundationModelSessionFactory.swift, EngineSDKCompatibility.swift, or OpenIntelligence.entitlements
unless the user names them in the approval; preserve local SystemLanguageModel fallback.
Verify: grep -rn "PrivateCloudComputeLanguageModel" OpenIntelligence/ (all uses gated),
build smoke, full tests. Present plan and STOP for approval — no exceptions.
```

## d. Evidence Threads change
```text
<preamble>
Task: <describe Evidence Threads change>. Note: Evidence Threads are IMPLEMENTED
(canonical §11–12); do not re-run Phase 1A plans from the stale FinalReview gate.
Also read: Docs/AgentPlaybooks/05_EVIDENCE_THREADS_IMPLEMENTATION_GUARDRAILS.md,
Docs/AuditArtifacts/ArchitectureAtlas/evidence_threads_design_decision.md.
Edit only: EvidenceThread.swift, EvidenceThreadStore.swift, ThreadSidebarView.swift,
Features/Debug/EvidenceThread* files.
Do not touch: ChatMessage.swift (immutability contract), WorkspaceSyncService.swift,
QuotaPolicy.swift tier limits (5/20/unlimited).
Verify: JSON round-trip serialization test; confirm quota gating still applies; build smoke.
```

## e. Documentation governance change
```text
<preamble>
Task: <describe doc reconciliation/update>. Docs-only task class.
Also read: Docs/AgentPlaybooks/02_DOCUMENTATION_RECONCILIATION.md,
03_CHANGE_IMPACT_DOC_UPDATE.md, Docs/DOCUMENTATION_CONSISTENCY_AUDIT.md.
Edit only: Docs/**, README.md, PRIVACY.md, CHANGELOG.md. Never delete docs — archive or supersede.
Every changed claim must carry [evidence: level, confidence, source] tags.
Canonical docs may only be changed to MATCH code, never to contradict it, per canonical §16.
Verify: git status --porcelain shows only doc files; no Swift/config diffs.
```

## f. Release readiness check
```text
<preamble>
Task: run the release readiness dashboard. READ-ONLY on source.
Work through every row of Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md, marking
PASS/FAIL/BLOCKED with a specific evidence path or command output for each.
Allowed writes: a dated report under Docs/AuditArtifacts/ (do not overwrite prior reports).
Finish with an overall verdict and the ordered list of blocking items. Do not fix anything
in the same run — fixes are separate routed tasks.
```

## g. App Store / product copy update
```text
<preamble>
Task: <describe copy/metadata change>.
Also read: Docs/PRIVACY_AND_ROUTING.md, Docs/LIMITATIONS.md, canonical §3–§4.
Claim rules: sync is iCloud Drive (never say CloudKit); PCC has a runtime-entitlement fallback
to on-device models (never promise enclave execution unconditionally); the app is local-first;
quotas are 5/20/unlimited threads by tier. Any claim not supported by canonical §3 is forbidden.
Edit only: fastlane/** metadata, WHATS_NEW.md, Docs/USER_CHANGELOG.md, PRIVACY.md.
Verify: table mapping every user-facing claim -> canonical §3 line. STOP for approval before publishing.
```
