# OPENINTELLIGENCE ZERO-REGRESSION WWDC 2026 AUDIT AND INTEGRATION DIRECTIVE

You are the principal Apple-platform, retrieval-augmented generation, ML inference, database, concurrency, privacy, and release engineer responsible for auditing and safely integrating the pull-request backlog in the local `Gunnarguy/OpenIntelligence` repository.

OpenIntelligence is the repository owner’s most important application.

This is not a PR-clearing exercise.

Your responsibility is to prove that every accepted change:

* preserves or improves answer quality
* preserves citation correctness
* preserves retrieval recall
* preserves existing user data
* preserves vector-index compatibility
* preserves model-routing behavior
* preserves billing and entitlement behavior
* preserves iCloud and local-file safety
* preserves App Intent behavior
* preserves supported operating-system fallbacks
* does not introduce an adjacent-component regression
* uses only real, current, publicly available Apple APIs
* builds and runs under the actual installed Xcode and SDK
* survives physical-device validation where simulator testing is insufficient

A small theoretical optimization is never more important than correctness, retrieval quality, user data, privacy, deterministic behavior, or maintainability.

## Known pull-request topology

At the beginning of this audit, the repository has 68 pull requests:

### Currently open

PRs:

```text
#26 through #68 inclusive
```

Total open:

```text
43
```

### Previously merged

```text
#1
#3
#6
```

### Previously closed without merging

```text
#2
#4
#5
#7 through #25
```

Do not trust these states as proof that code is or is not present in current `main`.

For every PR, compare its actual patch against current `origin/main` at the symbol and behavior level. Code from a closed PR may have entered through another branch, later commit, direct merge, agent action, or reimplementation.

The newer PRs were initially based around:

```text
7eeee45c7aa2d9e6b8c545355c7f2239c7101b76
```

Older open PRs were based around:

```text
bf3a931a7b68552b20f384f0f19bf08fc33138e5
```

These are historical reference points only. Refresh the remote and record the actual current `origin/main` SHA before drawing conclusions.

# Governing repository instructions

Before doing anything else, read these files in this order:

```text
Docs/AgentPlaybooks/00_SUPERSEDING_EVIDENCE_PROTOCOL.md
Docs/AgentPlaybooks/07_TASK_ROUTER_AND_CHANGE_CONTROL.md
Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md
Docs/RepoOS/01_TASK_ROUTER.md
Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md
Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv
Docs/AuditArtifacts/RepoOS/subsystem_invariant_matrix.csv
Docs/AuditArtifacts/ArchitectureAtlas/subsystem_map.md
Docs/AuditArtifacts/ArchitectureAtlas/OPEN_QUESTIONS_AND_RISKS.csv
Docs/AuditArtifacts/ArchitectureAtlas/future_agent_checklist.md
.geminirules
```

Apply this precedence:

1. `00_SUPERSEDING_EVIDENCE_PROTOCOL.md`
2. `07_TASK_ROUTER_AND_CHANGE_CONTROL.md`
3. `CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`
4. `03_FORBIDDEN_EDIT_BOUNDARIES.md`
5. Current code
6. Current installed Apple SDK interfaces
7. Other repository documents
8. PR descriptions and generated reviews

For actual Apple API existence, signatures, availability, and behavior, the installed SDK and current official Apple documentation outrank repository documentation.

The `.geminirules` file claims a particular Xcode beta environment. PR descriptions claim other Xcode versions. Do not trust either claim without checking the installed environment.

# Absolute operating restrictions

## Audit phase is read-only

This initial instruction authorizes an audit and implementation plan only.

It does not authorize source-code changes.

During the audit phase, you may:

* create an audit branch
* create and update `.agent` audit artifacts
* run builds and tests
* inspect source and history
* inspect SDK interfaces
* run benchmarks
* construct temporary external test harnesses outside tracked production paths
* inspect GitHub PRs, reviews, checks, and comments
* prepare a proposed implementation plan

You may not modify:

* Swift production source
* tests
* project configuration
* entitlements
* StoreKit configuration
* package manifests
* persisted resources
* release metadata
* GitHub PR states

At the end of the audit phase, stop and present the implementation plan.

The user must respond with exactly:

```text
PROCEED: IMPLEMENT
```

before any source edit begins.

## Protected-file authorization

Even after `PROCEED: IMPLEMENT`, files listed by the repository as forbidden or Tier 1/Tier 2 boundaries require explicit file-by-file authorization.

The implementation plan must identify every protected file that needs modification, including the reason, blast radius, and validation plan.

Do not interpret this prompt as blanket authorization to edit protected files.

## GitHub restrictions

Without separate explicit authorization, do not:

* merge a PR
* close a PR
* reopen a PR
* comment on a PR
* submit a review
* push to `main`
* delete a branch
* force-push
* change PR metadata
* mark a PR ready
* resolve review threads
* create a final consolidation PR

Local audit work and local commits on the audit branch are permitted.

## Destructive-command prohibition

Never run:

```text
git reset --hard
git clean
rm -rf
git checkout -- .
git restore .
```

Do not discard unknown local changes.

# Audit branch and persistent control system

Fetch the remote and create:

```text
audit/openintelligence-zero-regression-2026-07-10
```

from the current `origin/main`.

Before modifying source code, create these audit artifacts:

```text
.agent/OPENINTELLIGENCE_AUDIT_CONTROL.md
.agent/pr_manifest.json
.agent/DECISION_LOG.md
.agent/TEST_EVIDENCE.md
.agent/RISK_REGISTER.md
.agent/AUTHORIZATION_LEDGER.md
.agent/APPLE_API_COMPATIBILITY_MATRIX.md
.agent/RAG_QUALITY_BASELINE.md
.agent/PERFORMANCE_BASELINE.md
.agent/ADJACENT_COMPONENT_BLAST_RADIUS.md
.agent/STORAGE_MIGRATION_MATRIX.md
.agent/MODEL_TOKENIZER_COMPATIBILITY_MATRIX.md
.agent/FINAL_REPORT_DRAFT.md
```

These files must survive context resets.

They may be committed to the audit branch during the audit phase.

Remove `.agent` from the eventual production diff after transferring its final evidence into the consolidation PR, permanent test artifacts, or an approved audit report.

# Session-start protocol

At the start of every session, run:

```bash
git status --short --branch
git remote -v
git fetch --all --prune
git rev-parse HEAD
git rev-parse origin/main
git log --oneline --decorate -15
gh auth status
xcode-select -p
xcodebuild -version
xcrun swift --version
xcodebuild -showsdks
xcrun --sdk iphoneos --show-sdk-path
xcrun --sdk iphonesimulator --show-sdk-path
xcrun --sdk macosx --show-sdk-path
```

Then:

1. Read all `.agent` files.
2. Confirm the active branch.
3. Confirm whether the working tree is clean.
4. Record the current `origin/main` SHA.
5. Refresh all 68 PR states and head SHAs.
6. Detect force-pushes or newly added commits.
7. Check whether another agent changed the branch.
8. Recheck authorization status.
9. State the exact active audit phase.
10. State one exact next action.

Never write:

```text
Continue reviewing PRs.
```

Write a concrete continuation instruction, for example:

```text
NEXT ACTION:
Compare the current FoundationModelSessionFactory on origin/main with PR #54,
inspect the installed FoundationModels.swiftinterface for SystemLanguageModel
members, compile an isolated symbol probe, and update
APPLE_API_COMPATIBILITY_MATRIX.md without editing production source.
```

# Evidence requirements

Every architectural or behavioral claim must include:

```text
evidence_level
confidence
evidence_source
evidence_command_or_file
verification_notes
```

Allowed evidence levels:

```text
code_verified
grep_verified
sdk_interface_verified
compile_verified
runtime_verified
physical_device_verified
artifact_derived
doc_claim_only
inferred
conceptual
unknown
```

Allowed confidence values:

```text
exact
high
medium
low
conceptual
unknown
```

PR descriptions, Sourcery summaries, Jules explanations, code comments, README claims, and historical Apple research documents are not implementation evidence.

# PR manifest schema

Create one entry for every PR from #1 through #68:

```json
{
  "pr": 0,
  "title": "",
  "state": "open|closed",
  "merged": false,
  "draft": false,
  "base_sha": "",
  "head_sha": "",
  "merge_commit_sha": "",
  "changed_files": [],
  "symbols_changed": [],
  "actual_patch_summary": "",
  "description_matches_patch": false,
  "present_in_current_main": false,
  "current_main_differs_from_patch": false,
  "overlaps_with": [],
  "contradicts": [],
  "generated_artifacts": [],
  "protected_files_touched": [],
  "persisted_formats_touched": [],
  "apple_apis_touched": [],
  "adjacent_components": [],
  "risk": "low|medium|high|critical",
  "historical_disposition": "OPEN|MERGED|CLOSED_UNMERGED",
  "audit_disposition": "UNREVIEWED|KEEP|SQUASH|REWORK|SUPERSEDE|REVERT_EXISTING|CLOSE|BLOCKED",
  "evidence_level": "",
  "confidence": "",
  "reason": "",
  "baseline_tests": [],
  "required_tests": [],
  "performance_evidence": [],
  "integration_commit": ""
}
```

No PR may be omitted because it is old, closed, merged, empty, duplicated, trivial, test-only, or apparently unrelated.

# Phase A: audit and baseline only

## Phase A1: freeze the current baseline

Before evaluating proposed changes:

1. Record the current `origin/main` SHA.
2. Record the current version and build number.
3. Record schemes, targets, configurations, deployment targets, supported destinations, package targets, and enabled capabilities.
4. Record all build warnings and existing failures.
5. Record all current Apple framework imports.
6. Record all persisted file and database formats.
7. Record all model routes and fallbacks.
8. Record the current RAG benchmark result set.
9. Record current app-launch, ingestion, retrieval, generation, and memory measurements.
10. Capture representative UI screenshots for touched surfaces.
11. Preserve a copy of the baseline evidence in `.agent`.

Run:

```bash
xcodebuild -list -project OpenIntelligence.xcodeproj
xcodebuild -showBuildSettings -project OpenIntelligence.xcodeproj -scheme OpenIntelligence
git ls-files
git diff --check
```

Discover the actual supported platform matrix from the project and package rather than assuming it.

## Phase A2: baseline build matrix

Attempt, where supported:

* iOS Debug generic-device build
* iOS Release generic-device build
* latest installed iOS simulator build
* oldest supported installed iOS simulator build
* macOS Debug build
* macOS Release build
* Swift package build
* Swift package tests
* archive or archive-equivalent compile validation
* signed physical-device build where entitlement behavior matters

Use actual installed destinations.

Do not hide failures.

For every command, record:

* full command
* configuration
* destination
* SDK
* Xcode version
* Swift version
* exit code
* duration
* warnings
* failures
* skipped targets
* environment limitation

## Phase A3: restore a valid testing strategy

Historical PR #3 removed the test target and fifteen mock-based test files.

Do not accept “some Apple frameworks do not run in the simulator” as justification for having no layered test architecture.

Design a replacement testing strategy with separate layers:

### Layer 1: deterministic pure-unit tests

For:

* query classification
* token-budget calculations
* rank fusion
* citation parsing
* configuration migration
* launch arguments
* text normalization
* markdown parsing
* tokenizer fixtures
* SQL query construction
* retrieval scoring
* evidence deduplication
* model-route policy decisions

### Layer 2: service tests with controlled fakes

For:

* RAG orchestration
* vector database contracts
* SQLite storage
* document processing
* model routing
* PCC consent decisions
* App Intent handoff
* cancellation
* retry behavior
* error propagation

### Layer 3: simulator-supported integration tests

For:

* database migrations
* file ingestion without unavailable model execution
* UI state
* DocumentPicker coordination
* app routing
* persistence
* StoreKit configuration where supported
* App Intent entity queries

### Layer 4: physical-device tests

For:

* Foundation Models
* advanced on-device model, if real
* Private Cloud Compute
* Core AI
* Core ML compute-device behavior
* Natural Language models unavailable in the simulator
* Metal and BNNS performance
* Vision document recognition
* Apple Intelligence availability states
* entitlement and consent behavior

### Layer 5: performance and energy tests

For:

* ingestion throughput
* vector search
* hybrid retrieval
* context assembly
* model prewarming
* memory pressure
* database insertion
* scrolling and SwiftUI updates
* battery and thermal behavior

Do not modify `project.pbxproj` or `Package.swift` during Phase A.

If restoring a committed test target requires those files, identify them in the implementation plan and request named authorization.

# Definition of “no degradation”

A PR is not safe because it compiles.

It must satisfy every applicable non-regression category.

## Functional equivalence

For a change presented as a refactor or optimization:

* deterministic outputs must remain exact
* ordering must remain exact
* error semantics must remain exact
* cancellation semantics must remain exact
* persistence behavior must remain exact
* logging privacy must remain equal or stronger
* availability fallbacks must remain exact

Any intentional behavior change must be identified and separately approved.

## RAG quality

Build a fixed, versioned benchmark corpus containing:

* exact keyword needles
* exact numeric values
* units and specifications
* tables
* repeated identifiers
* definitions
* procedures
* narrative prose
* long technical manuals
* degraded OCR
* font-substitution PDFs
* multilingual documents
* code and API references
* multi-hop questions
* cross-document questions
* conflicting source documents
* unanswerable questions
* summary requests
* highly specific extractive questions
* citation-sensitive questions

Record, where applicable:

```text
Recall@K
Precision@K
MRR
nDCG
lexical-only hit rate
vector-only hit rate
hybrid hit rate
exact needle recovery
citation precision
citation recall
citation-source alignment
answer faithfulness
answer completeness
correct abstention
false abstention
unsupported-claim rate
context utilization
latency
peak memory
```

Hard requirements:

* No previously passing critical exact-match case may fail.
* No previously correct citation may point to a different unsupported source.
* No previously grounded answer may become ungrounded.
* No aggregate retrieval metric may decline beyond measured baseline variance.
* Establish noninferiority bounds from repeated baseline measurements.
* Do not choose a permissive margin after seeing a regression.
* Semantic changes require paired before-and-after evidence.
* Nondeterministic generation requires repeated trials plus evidence-level comparison.

## Performance

Measure Release builds on physical hardware.

Record:

* median
* p90
* p95
* peak resident memory
* allocations
* CPU time
* GPU time
* energy impact
* thermal state
* cold and warm behavior

A claimed optimization without native measurement is unproven.

Reject micro-optimizations when:

* improvement is within measurement noise
* code complexity increases materially
* behavior becomes less clear
* deprecated APIs are introduced
* allocations merely move elsewhere
* retrieval quality changes
* numerical behavior changes
* maintenance cost exceeds demonstrated benefit

By default, a regression greater than 5% in a user-critical performance metric requires explicit owner approval and a documented quality or correctness benefit.

## Persisted data

Prove compatibility with:

* existing SQLite files
* FTS5 indexes
* structured table metadata
* memory-mapped BNNS vector files
* stored embedding dimensions
* chat JSON arrays
* Evidence Thread files
* ingestion checkpoints
* iCloud Drive workspace state
* UserDefaults settings
* StoreKit entitlements
* model-route preferences

No migration may silently:

* delete data
* reinterpret identifiers
* change vector dimensions
* change tokenizer offsets
* orphan rows
* cross container boundaries
* break old Codable payloads
* force an unnecessary re-index
* strand a paid entitlement

## Adjacent components

For every proposed changed symbol, record:

* direct callers
* indirect callers
* protocols
* conformers
* actor boundaries
* persisted structures
* files written
* database tables touched
* UI surfaces
* App Intents
* background tasks
* billing gates
* model routes
* logging
* documentation claims

No implementation commit may touch a file absent from its approved blast-radius allowlist.

Unexpected files in a diff are a stop condition.

# Current Apple and WWDC 2026 API audit

Create:

```text
.agent/APPLE_API_COMPATIBILITY_MATRIX.md
```

For every Apple API used or claimed by the repository, record:

```text
framework
symbol
repo call sites
repository claim
official documentation status
installed SDK path
swiftinterface or symbol-graph evidence
compiler-probe result
deployment availability
simulator support
physical-device result
hardware requirements
entitlement requirements
App Store third-party availability
fallback behavior
deprecation status
final classification
```

Use these final classifications:

```text
DOCUMENTED
SDK_PRESENT
COMPILE_VERIFIED
SIMULATOR_VERIFIED
PHYSICAL_DEVICE_VERIFIED
ENTITLEMENT_REQUIRED
ENTITLEMENT_BLOCKED
DEPRECATED
UNAVAILABLE_IN_INSTALLED_SDK
SPECULATIVE
PRIVATE_OR_UNUSABLE
FALLBACK_VERIFIED
```

## Apple API proof procedure

For every new or changed symbol:

1. Find it in current official Apple Developer documentation.
2. Find it in the installed SDK `.swiftinterface`, module interface, generated header, or symbol graph.
3. Record its exact availability annotation.
4. Compile a minimal isolated probe.
5. Build it against every relevant deployment target.
6. Run it where runtime behavior matters.
7. Verify entitlement requirements.
8. Verify App Store eligibility.
9. Verify fallback behavior when unavailable.
10. Record the evidence.

Useful tools include:

```bash
xcrun swift-symbolgraph-extract
xcrun swiftc -typecheck
xcrun --sdk iphoneos --show-sdk-path
xcrun --sdk iphonesimulator --show-sdk-path
xcrun --sdk macosx --show-sdk-path
nm
otool
plutil
codesign -d --entitlements :-
```

Do not use a compiler-version conditional as a proxy for SDK symbol existence unless the actual compiler syntax or module interface requires it and the probe proves it.

Do not infer an API from:

* a PR description
* a generated comment
* a repository research document
* a WWDC rumor
* another developer’s code
* a symbol name that “sounds right”

## Foundation Models

Audit all usage of:

```text
SystemLanguageModel
LanguageModelSession
PrivateCloudComputeLanguageModel
GenerationOptions
Transcript
Instructions
Tool
@Generable
@Guide
prewarm
availability
guardrails
reasoning transcript entries
dynamic profiles
locale or use-case configuration
```

Verify:

* actual standard on-device model API
* actual advanced-model API, if any
* actual PCC model construction API
* exact OS and SDK availability
* context-window behavior
* transcript compatibility between model routes
* tool compatibility
* guided-generation compatibility
* cancellation
* session reuse
* prewarming behavior
* availability reason handling
* Apple Intelligence disabled
* model downloading
* ineligible device
* offline mode
* memory pressure
* background execution
* App Intent execution
* missing PCC entitlement
* denied cloud consent
* revoked cloud consent
* route telemetry accuracy

Never instantiate PCC before proving the entitlement is present.

The missing-entitlement path must not crash.

A background or App Intent path must not block while waiting for a UI consent sheet.

## Core AI and Core ML

Audit:

* active Core AI embedding provider
* Core ML fallback provider
* model resource packaging
* embedding dimension
* pooling
* normalization
* tokenizer compatibility
* model versioning
* index compatibility
* compute-device selection
* stateful KV cache
* `MLTensor`
* mask scalar types
* model input descriptors
* model output descriptors
* model-state lifetime
* cancellation
* device memory

A change to embedding dimension, pooling, normalization, tokenizer behavior, or model identity requires an explicit index-version migration and re-index plan.

Do not silently search existing vectors with a changed embedding contract.

## Vision and document intelligence

Audit:

* `RecognizeDocumentsRequest`, if present in the SDK
* existing OCR path
* table and structure recognition
* Vision request revisions
* language correction
* custom words
* PDFKit text-layer extraction
* image rendering
* page concurrency
* cancellation
* memory pressure
* degraded documents
* fallback behavior on older systems

Do not replace a proven OCR path solely because a newer request exists.

Compare extraction quality, ordering, bounding boxes, tables, latency, and memory on a representative PDF corpus.

## Metal, Accelerate, and BNNS

Audit:

* Metal 4 residency-set usage
* command queue and buffer lifetime
* memory-warning behavior
* cache eviction
* mapped-vector lifetime
* Accelerate deprecations
* BNNS behavior
* scalar fallback
* numerical precision
* energy and thermal impact

Do not accept theoretical SIMD claims without device evidence.

## App Intents, Siri, and Spotlight

Audit all App Intents and entities, including:

```text
RAGAppIntents
ScreenAwarenessIntents
VisualIntelligenceIntents
OIDocumentEntity
OILibraryEntity
OIEntityQueries
AppShortcutsProvider
```

Verify:

* shortcut count remains within the current system limit
* stable entity identifiers
* entity queries do not leak content across libraries
* invocation does not require inaccessible UI
* PCC consent cannot deadlock
* intent business logic remains in services
* deep-link routing is deterministic
* old shortcuts continue to resolve
* deleted documents do not remain resolvable
* privacy-sensitive document text is not placed in system metadata
* Spotlight indexing, if present, is scoped and removable

Do not add new shortcuts during this PR audit unless explicitly approved.

## SwiftUI and Liquid Glass

Audit current SwiftUI usage against the installed SDK.

Where Liquid Glass is already used, verify:

* correct availability gates
* native APIs
* modifier order
* `GlassEffectContainer` grouping
* interactive glass only on interactive controls
* Reduce Transparency
* Increase Contrast
* VoiceOver
* Dynamic Type
* keyboard navigation
* pointer behavior
* older-OS fallback
* rendering and scrolling performance

Do not perform an opportunistic visual redesign while integrating unrelated PRs.

List modernization opportunities separately.

## Swift concurrency

Compile first-party code with strict concurrency diagnostics.

Audit:

* every `@unchecked Sendable`
* every new `nonisolated`
* actor reentrancy
* detached tasks
* task-group cancellation
* unstructured tasks
* shared caches
* notification callbacks
* continuation completion
* MainActor hops
* mutable Foundation objects
* stale asynchronous results
* background-to-UI transitions

Do not mark something `nonisolated` or `@unchecked Sendable` merely to silence the compiler.

# PR cluster directives

## Cluster 1: Apple Foundation Models routing

### PR #54

This PR attempts to use:

```swift
SystemLanguageModel.advanced
```

under:

```swift
#if compiler(>=6.4)
```

Do not merge it directly.

Required work:

1. Prove whether `SystemLanguageModel.advanced` exists in the installed SDK.
2. Record its exact type and availability.
3. Prove it with a minimal compiler probe.
4. Prove runtime availability on eligible physical hardware.
5. Verify whether it supports tools.
6. Verify whether it supports transcript restoration.
7. Verify whether it has a different context limit.
8. Verify actual fallback behavior.
9. Verify telemetry reports the actual route.
10. Verify it is a public third-party API.
11. Verify its relationship to PCC.
12. Verify that compiler-version gating is appropriate.

Preliminary disposition:

```text
BLOCKED_PENDING_SDK_PROOF
```

Current protected files likely affected:

```text
FoundationModelSessionFactory.swift
FoundationModelRoutePolicy.swift
EngineSDKCompatibility.swift
```

Do not edit them without named authorization.

Also audit relevant behavior introduced by merged PR #3.

## Cluster 2: RAG retrieval and answer quality

This cluster includes:

```text
#53
#56
#57
#59
#60
#62
#63
#64
#68
```

Treat it as one semantic-quality cluster.

### PR #53: specification lookup detection

The proposed dynamic regex must be audited for:

* literal-pattern escaping
* multiword phrases
* irregular plurals
* possessives
* hyphens
* punctuation
* Unicode word boundaries
* accented text
* abbreviations
* performance
* false positives
* false negatives

Do not interpolate unescaped strings into regex patterns.

Precompile only after proving exact behavior.

Likely disposition:

```text
REWORK
```

### PR #56: HyDE newline-to-space change

This changes only the separator between the original query and hypothetical document.

Do not assume it improves embeddings.

Run paired retrieval benchmarks across:

* exact lookup
* broad conceptual questions
* multiword phrases
* code
* specifications
* multilingual text
* long hypothetical documents

Keep only if native benchmark evidence shows equal or better retrieval.

Likely disposition:

```text
CLOSE_OR_SQUASH_AFTER_EVIDENCE
```

### PR #57: ExtractiveQA regex caching

Potentially useful, but:

* remove `try!`
* avoid unjustified `@unchecked Sendable`
* verify UTF-16 range handling
* prove case-sensitivity equivalence
* prove exact extraction equivalence
* measure actual hot-path benefit
* consider current Swift Regex APIs only if they are SDK-appropriate and demonstrably better

Likely disposition:

```text
REWORK
```

### PR #59: OCR fallback quality score

Do not treat PDFKit native word count as unquestioned ground truth.

Test:

* clean text layer
* garbled text layer
* duplicated hidden text
* zero native words
* OCR with more words than native extraction
* OCR with fewer but more accurate words
* scanned documents
* tables
* multi-column pages
* CJK
* ligatures
* font substitution

Define what `qualityScore` actually means and how downstream code uses it.

Prefer a composite quality metric rather than a raw word-count ratio.

Remove any placeholder submission scripts.

Likely disposition:

```text
REWORK
```

### PR #60: dropped-chunk rescue naming

The actual patch appears documentation- and naming-oriented.

Verify that the renamed variable accurately represents behavior.

Squash into a related retrieval commit only if useful.

Likely disposition:

```text
SQUASH
```

### PR #62: hard zero for spec answers without “technical content”

Do not merge.

The heuristic may reject valid answers such as:

* material names
* product categories
* color specifications
* plain-language compatibility answers
* definitions
* safety classifications
* prose descriptions without digits
* correct negative answers

Calibrate against a labeled evaluation set.

Do not use an unconditional zero until false-rejection behavior is proven acceptable.

Remove `plan.txt` and all agent scratch artifacts.

Likely disposition:

```text
SUPERSEDE
```

### PR #63: always-run concurrent lexical recall

Do not merge directly.

Problems requiring investigation:

* generated `fix.py`
* generated `test_compile.sh`
* vector-result-dependent recall sizing was removed
* lexical failure may alter whole-search failure behavior
* cancellation behavior changes
* database/cache concurrency may change
* energy and latency increase
* deterministic ordering may change
* candidate fusion may change

The correct goal is high lexical recall without degrading latency, ordering, or cancellation.

Test sequential and concurrent strategies under weak and strong vector retrieval.

Preserve vector-confidence-based scaling unless evidence proves another policy is superior.

Likely disposition:

```text
SUPERSEDE
```

### PR #64: query-aware contextual-compression fallback

Useful intent, but simple substring bonuses are insufficient.

Test:

* stopwords
* stemming
* pluralization
* exact phrases
* identifiers
* punctuation
* Unicode
* CJK
* negation
* query terms occurring in irrelevant sentences
* duplicated terms
* long queries
* context-budget effects
* ordering and tie behavior

Use the same normalized lexical policy as retrieval where practical.

Likely disposition:

```text
REWORK
```

### PR #68: supplementary query expansions

Do not regenerate expansions from the raw query with a new enhancer lacking corpus vocabulary.

Reuse the already computed expansion set when possible.

Preserve:

* effective query
* corpus vocabulary
* translated query
* HyDE decisions
* extractive gating
* trivial-query gating
* expansion order
* duplicate suppression
* retrieval budget

Measure extra embedding calls and vector searches.

Likely disposition:

```text
REWORK
```

### Historical RAG PRs

Compare current `main` against closed PRs:

```text
#7
#11
#12
#13
#14
#16
#17
#18
#19
#21
#23
#24
#25
```

Determine whether equivalent behavior or tests entered through later work.

Do not resurrect an old patch without comparing it to current architecture.

## Cluster 3: vector math, compute, and memory

This cluster includes:

```text
#28
#31
#35
#47
#49
#61
#67
```

### PRs #47, #49, and #61

These are competing vector-math implementations.

They use different APIs:

* Swift Accelerate overlay
* legacy vDSP C functions
* CBLAS functions

Do not stack them.

Benchmark these strategies against the current scalar implementation:

```text
manual scalar
Swift Accelerate overlay
vDSP C APIs
CBLAS
BNNS
Metal scalar
Metal SIMD
Metal threadgroup
```

Validate:

* empty vectors
* one-element vectors
* dimensional mismatch
* zero vectors
* all-negative vectors
* large values
* subnormal values
* NaN
* positive and negative infinity
* 384 dimensions
* every other supported dimension
* persisted norm compatibility
* ranking equivalence
* tie ordering
* numerical tolerance
* result range

Do not introduce a deprecated Accelerate API.

Do not replace an existing modern overlay with a lower-level C API solely because a generated PR calls it faster.

Likely disposition:

```text
CONSOLIDATE_AND_REIMPLEMENT
```

### PR #28

Unify its magnitude calculation with the selected vector-math policy.

Do not create a separate inconsistent normalization implementation.

### PR #31

The Embedding3D min/max optimization is low risk only if:

* empty input is handled
* prefix-limit semantics remain exact
* NaN and infinity behavior remain exact
* coordinate ordering remains unchanged
* UI output remains visually identical

Require an actual Swift/device benchmark.

### PR #35

Verify exact variance semantics, precision, overflow behavior, and empty-input behavior.

Reject exaggerated performance claims based only on Python analogies.

### PR #67

The observer capture appears to address a real compile or capture issue, but validate:

* observer token removal
* no retain cycle
* buffer-pool thread safety
* Metal command-buffer lifetime
* residency-set behavior
* memory warning on iOS
* memory pressure on macOS
* repeated warnings
* deinitialization
* purge during active search
* peak-memory reduction

Do not retain `commit_message.txt` or any generated metadata artifact.

Likely disposition:

```text
KEEP_INTENT_REIMPLEMENT_CLEANLY
```

## Cluster 4: SQLite, FTS5, and storage integrity

This cluster includes:

```text
#27
#39
#40
#42
#45
#55
```

Treat `SQLiteFullTextService.swift` as a protected data-integrity boundary.

### PRs #27 and #55

Do not expose arbitrary schema identifiers and column definitions to runtime string construction.

Prefer:

* a closed internal migration enum
* fixed migration descriptors
* compiler-owned table and column names
* fixed SQL definitions
* transaction-scoped migrations
* explicit schema versions
* idempotent migration checks

Identifier validation and identifier quoting may both be useful, but neither makes an arbitrary column definition safe.

Likely disposition:

```text
CONSOLIDATE_AND_REIMPLEMENT
```

### PR #39

Prepared-statement reuse may materially improve ingestion.

Before accepting:

* check every `sqlite3_step` result
* handle reset errors
* handle clear-binding errors
* rollback on any row failure
* verify nested structured-row writes
* verify statement lifetime
* verify transaction lifetime
* inject disk-full failures
* inject locked/busy errors
* compare exact row counts
* compare FTS results
* verify no partial document state remains

Likely disposition:

```text
REWORK_THEN_BENCHMARK
```

### PR #40

This replaces bound parameters with interpolated multi-statement SQL.

Reject it unless an extraordinary, measured reason exists.

The saved overhead from two prepared statements does not justify reducing parameterization, error attribution, or maintainability.

Preliminary disposition:

```text
CLOSE
```

### PR #42

Verify what the logged deletion count is intended to represent.

`sqlite3_changes()` may have different semantics from counting selected documents when triggers, cascades, virtual tables, or related cleanup are involved.

Keep only if exact intended semantics are proven.

### PR #45

Unrolling two static prepared statements is unlikely to provide meaningful benefit.

Do not accept extra code merely to avoid a two-element array.

Likely disposition:

```text
CLOSE_OR_SQUASH
```

### Mandatory storage tests

Use database fixtures from every supported prior app version.

Test:

* clean migration
* repeated migration
* partial migration
* interrupted migration
* corrupt schema
* locked database
* busy database
* disk full
* WAL recovery
* checkpoint
* foreign-key behavior
* orphan detection
* cross-container isolation
* container deletion
* document deletion
* structured-row deletion
* exact FTS tokenization
* Unicode normalization
* app downgrade behavior where relevant
* restoration from backup

No database optimization may enter the integration branch without these tests.

## Cluster 5: vendored model and tokenizer code

This cluster includes:

```text
#37
#41
#44
```

### PRs #37 and #41

These are duplicates.

Both infer only:

```text
float32
otherwise float16
```

That is not sufficient evidence.

Inspect:

* all possible `MLMultiArrayDataType` cases
* actual mask input descriptors
* actual model fixtures
* shape requirements
* model-state lifetime
* CPU, GPU, and Neural Engine execution
* `MLTensor` supported scalar types
* generation parity
* numerical outputs
* KV-cache behavior

Remove `pre_commit.sh`.

Compare the local fork with the upstream `swift-transformers` implementation and current upstream fixes.

Do not create an untracked long-term fork deviation without documenting it.

Likely disposition:

```text
CONSOLIDATE_REWORK_OR_UPSTREAM
```

### PR #44

This changes unknown-token behavior.

Use real tokenizer fixtures with:

* `byte_fallback = true`
* `byte_fallback = false`
* missing `byte_fallback`
* unknown token configured
* unknown token missing
* fused unknown tokens
* ASCII
* accented Latin text
* emoji
* combining marks
* CJK
* invalid or unusual Unicode sequences

Verify exact token IDs and decode round trips against upstream reference behavior.

Tokenizer changes can invalidate citation offsets and model behavior.

Do not merge without exact fixture equivalence.

Likely disposition:

```text
BLOCKED_PENDING_FIXTURE_TESTS
```

## Cluster 6: tests, migrations, and visibility changes

This cluster includes:

```text
#26
#29
#30
#32
#36
#38
#43
#46
#50
#51
```

### Duplicate test PRs

Consolidate:

```text
#26 and #46: WorkspaceTier
#32 and #50: LLMModelType
```

Do not merge duplicate suites.

### PRs #29 and #38

Do not relax private implementation details solely to test them.

Prefer:

* testing public behavior
* extracting a coherent internal pure helper
* a dedicated test seam with architectural value

Avoid broadening production API surface for a tiny test.

### PR #30

Do not embed unit tests in the product’s diagnostic UI when a real test target is appropriate.

Move deterministic validation to XCTest or Swift Testing after authorization to restore the test architecture.

### PR #36

Validate every recommendation threshold and boundary, not only representative values.

### PR #43

Do not place a broad markdown test suite inside `CoreValidationView.swift`.

Test the parser in a dedicated target.

Do not expose parser internals without a justified seam.

### PR #51

Likely useful, but test:

* no arguments
* duplicate flags
* `--key=value`
* `--key value`
* missing value
* empty value
* next token is another flag
* terminator `--`
* case behavior
* malformed input
* precedence in `valueEither`
* preservation of current global default behavior

## Cluster 7: UI, cleanup, and small optimizations

This cluster includes:

```text
#33
#34
#48
#52
#58
#60
```

### PR #33

Keep the division-by-zero fix if real.

Benchmark the allocation optimization natively.

### PR #34

Prove horizontal-rule parsing equivalence for:

* spaces
* tabs
* mixed markers
* Unicode whitespace
* three markers
* more than three markers
* embedded text
* Markdown edge cases

### PRs #48, #52, and #60

These appear to be cleanup or comment changes.

Squash them into related logical commits only if still accurate.

Do not create separate production commits for negligible comment churn.

### PR #58

The actual UTType extraction is a small refactor, but the branch contains:

```text
fix.py
refactor.py
```

Do not merge it.

Also audit:

* whether UIKit DocumentPicker remains the correct architecture
* security-scoped URL lifetime
* `asCopy`
* iCloud download state
* multiple selection
* cancellation
* inaccessible files
* macOS and Catalyst behavior
* duplicate imports
* recently copied file mtime protection
* supported UTTypes
* media memory pressure

Likely disposition:

```text
SUPERSEDE
```

## Cluster 8: privacy and query-history persistence

### PR #66

Reject the description that this is merely a memory-leak fix.

It adds query-history persistence to UserDefaults and introduces side effects into query expansion.

User queries can contain:

* confidential document details
* personal information
* medical information
* proprietary identifiers
* legal questions
* workplace data

Do not persist queries without an explicit product requirement, retention policy, deletion control, privacy disclosure, and user control.

Additional problems:

* unstructured tasks can reorder writes
* duplicate queries accumulate
* expansion is no longer pure
* truncation may split grapheme clusters or preserve sensitive prefixes
* UserDefaults is not a query-history database
* no migration or clear path exists

Preliminary disposition:

```text
CLOSE
```

A separate, explicitly approved query-history feature may be designed later.

## Cluster 9: invalid, mismatched, and contaminated PRs

### PR #65

The title and body claim that the custom-word capture fix already exists and no code is required.

The actual patch changes:

```swift
private struct ConsolidatedMetrics
```

to:

```swift
struct ConsolidatedMetrics
```

inside `ChatScreen.swift`.

This is unrelated.

Do not merge.

Verify whether the custom-word concurrency fix exists in current code, record that result independently, and close or supersede the PR after owner authorization.

Preliminary disposition:

```text
CLOSE
```

### Artifact scan

Scan every PR and branch for:

```text
*.orig
*.rej
*.patch
patch.diff
update.patch
plan.txt
commit_message.txt
fix.py
refactor.py
test.py
test.swift
test_compile.sh
pre_commit.sh
submit_script.sh
temporary benchmark scripts
agent transcripts
generated summaries
404 placeholder files
```

A useful patch on a contaminated branch must be reimplemented cleanly.

Do not cherry-pick the contaminated commit.

# Historical merged PR audit

## PR #1

Audit the current effects of:

* Motherboard HUD
* Metal search tiers
* OCR concurrency
* cross-encoder concurrency
* embedding pipeline
* StoreKit timeout
* markdown rendering
* MMR safety
* privacy manifest

Confirm these behaviors remain intact after the integration.

## PR #3

Audit the current effects of:

* Foundation Models tools
* Image Playground
* AI Hub
* Knowledge Atlas
* BM25 refactor
* concurrency annotations
* hardening changes
* test-target removal
* deprecated Accelerate usage
* actor-isolation warnings

The removed testing architecture must not remain an excuse for accepting unverified code.

## PR #6

Verify that the public repository remains free of:

* private sales material
* employer references
* hospital references
* patient information
* credentials
* private buyer documents
* internal pricing documents

Do not let audit artifacts reintroduce private content.

# Adjacent-component blast-radius procedure

Before implementing any approved PR cluster, create a blast-radius record containing:

```text
target files
target symbols
direct callers
indirect callers
protocols
conformers
actor boundaries
persisted models
database tables
vector formats
UI surfaces
App Intents
background execution
cloud routing
billing gates
sync paths
logging
privacy implications
tests
rollback point
```

Then create a path allowlist for that implementation commit.

Before committing, run:

```bash
git diff --name-only
git diff --stat
git diff --check
```

If an unexpected file appears:

1. stop
2. do not stage it
3. investigate its origin
4. update the risk register
5. request authorization if the blast radius must expand

No drive-by refactors.

No opportunistic renames.

No formatting entire files.

No access-level widening unrelated to the approved change.

No documentation claims before runtime behavior is proven.

# Review-comment processing

For all 68 PRs:

1. Fetch top-level comments.
2. Fetch inline review comments.
3. Fetch review submissions.
4. Identify unresolved review threads.
5. Fetch CI checks and logs.
6. Classify every meaningful item:

```text
ACTIONABLE
OUTDATED
INCORRECT
STYLE_ONLY
SUMMARY_ONLY
ALREADY_ADDRESSED
BLOCKED
```

Record evidence and rationale.

Do not let Sourcery, Copilot, Jules, or any other generated reviewer override code evidence.

# Phase A completion output

At the end of Phase A, produce:

1. The complete 68-PR ledger.
2. Apple API compatibility matrix.
3. Current build matrix.
4. Existing warning inventory.
5. RAG quality baseline.
6. Performance baseline.
7. Storage compatibility matrix.
8. Model and tokenizer compatibility matrix.
9. Adjacent-component blast-radius map.
10. Proposed terminal disposition for every PR.
11. Proposed logical implementation commits.
12. Exact protected files requiring authorization.
13. Exact tests required.
14. Exact physical-device work required.
15. Risks that cannot be eliminated.
16. Rollback strategy.

Then stop.

The final line must be:

```text
AUDIT COMPLETE. SOURCE CODE HAS NOT BEEN MODIFIED.
AWAITING: PROCEED: IMPLEMENT
```

Do not implement until the exact authorization is received.

# Phase B: implementation after authorization

After receiving:

```text
PROCEED: IMPLEMENT
```

and any required protected-file authorization:

1. Refresh `origin/main`.
2. Rebase or merge safely without rewriting public history.
3. Confirm all PR head SHAs remain unchanged.
4. Update the authorization ledger.
5. Implement one approved logical cluster at a time.
6. Add tests before or with the implementation.
7. Run cluster-specific tests.
8. Run adjacent-component tests.
9. Commit the cluster.
10. Update all `.agent` evidence.
11. Re-run RAG benchmarks after semantic changes.
12. Re-run storage fixtures after database changes.
13. Re-run API probes after Apple-framework changes.
14. Re-run device performance after compute changes.
15. Stop immediately on unexplained regression.

# Suggested implementation commit structure

Use logical commits such as:

```text
test(openintelligence): restore layered regression coverage

fix(apple-models): verify and gate current Foundation Models routes

fix(retrieval): preserve lexical recall without changing failure semantics

fix(compression): make fallback extraction query-aware and deterministic

perf(vector): consolidate measured Accelerate implementation

fix(gpu): make memory-pressure cache eviction lifecycle-safe

fix(storage): harden fixed SQLite schema migrations

perf(storage): reuse prepared statements with transactional failure handling

fix(tokenizer): honor byte fallback using upstream-compatible semantics

test(rag): add golden retrieval and citation non-regression suite

test(storage): add legacy database migration fixtures

test(models): add tokenizer and Core ML descriptor fixtures

chore(repo): remove generated PR artifacts
```

Commit bodies must reference all source PRs and state whether each was retained, reimplemented, superseded, or rejected.

# Full post-implementation validation

Run the complete matrix again:

* Debug build
* Release build
* simulator builds
* physical-device build
* macOS build where supported
* package build
* pure tests
* service tests
* database migration tests
* tokenizer fixtures
* Core ML model fixtures
* RAG golden benchmarks
* citation validation
* App Intent invocation
* iCloud and file-import tests
* entitlement-missing fallback
* PCC consent
* offline mode
* memory warning
* cancellation
* repeated ingestion
* repeated retrieval
* performance suite
* energy suite
* static analysis
* privacy scan
* secret scan
* artifact scan

Compare results against the frozen baseline.

Do not report “no regression” without attached evidence.

# Documentation and Notion closure

After approved implementation is complete:

1. Review the final diff.
2. Update `WHATS_NEW.md` only for real user-visible changes.
3. Update `CHANGELOG.md` with the required architecture tags.
4. Update architecture documentation only where verified behavior changed.
5. Do not overwrite the canonical source of truth without the required evidence-tagged Atlas process.
6. Synchronize the Notion roadmap only if the configured connector is available.
7. Never fabricate a Notion update.
8. Do not mark rejected PR work as shipped.
9. Do not quantify performance improvements without native measurements.

# Draft consolidation PR

After all validation passes, request authorization to create one draft consolidation PR.

Its description must contain:

1. Complete 68-PR ledger.
2. Starting and ending SHAs.
3. Apple API compatibility matrix.
4. Protected-file authorization record.
5. All duplicates.
6. All contradictions.
7. All contaminated PRs.
8. All misleading PRs.
9. All retained changes.
10. All reimplemented changes.
11. All rejected changes.
12. RAG before-and-after metrics.
13. Citation before-and-after metrics.
14. Performance before-and-after metrics.
15. Storage migration evidence.
16. Tokenizer/model evidence.
17. Physical-device evidence.
18. Simulator limitations.
19. Entitlement limitations.
20. Remaining risks.
21. Rollback commits.
22. Confirmation that no original PR was directly merged.

Do not merge the consolidation PR.

Do not close original PRs until:

* the consolidation is approved and merged
* the source PR’s intent is represented or explicitly rejected
* the owner authorizes the closure

# Required final report

```text
OPENINTELLIGENCE ZERO-REGRESSION AUDIT

Starting main SHA:
Ending integration SHA:
Xcode version:
Swift version:
iOS SDK:
macOS SDK:
Physical devices:
Simulators:
Consolidation PR:

PR #1
Historical state:
Actual patch:
Current-main presence:
Adjacent components:
Apple APIs:
Risk:
Audit decision:
Implementation commit:
Tests:
Evidence:

...

PR #68
Historical state:
Actual patch:
Current-main presence:
Adjacent components:
Apple APIs:
Risk:
Audit decision:
Implementation commit:
Tests:
Evidence:

APPLE API RESULTS:
Documented:
SDK present:
Compile verified:
Simulator verified:
Physical-device verified:
Entitlement blocked:
Speculative or rejected:
Deprecated APIs removed:
Fallbacks verified:

RAG QUALITY:
Golden cases:
Previously passing cases lost:
Recall@K:
MRR:
nDCG:
Citation precision:
Citation recall:
Faithfulness:
False abstention:
Unsupported claims:
Latency:
Peak memory:

STORAGE:
Legacy databases tested:
Migration result:
Cross-container isolation:
Orphan rows:
Vector format compatibility:
Chat compatibility:
Evidence Thread compatibility:
iCloud sync result:

MODEL AND TOKENIZER:
Core AI:
Core ML fallback:
Embedding dimension:
Normalization:
Tokenizer fixtures:
Byte fallback:
KV-cache masks:
Generation parity:

PERFORMANCE:
Ingestion:
Vector search:
Hybrid search:
Context assembly:
Generation:
Memory:
Energy:
Thermal:

SECURITY AND PRIVACY:
Secrets found:
Query persistence:
Logging exposure:
Entitlement behavior:
PCC consent:
App Intent privacy:

ADJACENT REGRESSIONS:
Unexpected files changed:
Unexpected symbols changed:
UI regressions:
Billing regressions:
Sync regressions:
Routing regressions:
App Intent regressions:

GENERATED ARTIFACTS REMOVED:
PROTECTED FILES MODIFIED:
AUTHORIZATION EVIDENCE:
REMAINING RISKS:
OWNER ACTIONS REQUIRED:
```

# Completion condition

The task is not complete merely because:

* all 43 open PRs were given dispositions
* the project compiles
* tests pass
* an AI reviewer approved the diff
* a benchmark improved
* a consolidation PR exists

The task is complete only when:

* all 68 PRs are accounted for
* all 43 open PRs have terminal dispositions
* every Apple API claim is evidence-classified
* all accepted APIs compile under the installed SDK
* required APIs run on appropriate physical hardware
* protected files were modified only with explicit authorization
* no critical RAG benchmark regressed
* no previously passing exact-needle case was lost
* citations remain correctly aligned
* persisted data remains compatible
* vector and tokenizer contracts remain compatible
* model fallbacks remain safe
* PCC cannot crash without an entitlement
* App Intents cannot deadlock on consent
* no query-history privacy regression was introduced
* no generated artifacts remain
* no unrelated file entered the diff
* full post-change validation matches or improves the frozen baseline
* the owner has reviewed the draft consolidation PR
* no merge or PR closure occurred without explicit authorization
