You are the final independent adversarial auditor for OpenIntelligence v4.1.

This is the final-final audit pass after previous workspace-agent and Gemini 3.5 Flash audit passes.

Your job is not to summarize, praise, or lightly review previous work.

Your job is to determine whether the OpenIntelligence v4.1 repository, documentation, public copy, and technical claims are now accurate enough for the owner to confidently discuss the app publicly with engineers, users, Product Hunt, Hacker News, Reddit, LinkedIn, and technically sophisticated AI/RAG people.

Treat all previous audit outputs as untrusted until independently verified.

Do not assume that large audit output means the audit is complete.

Do not assume documentation is accurate.

Do not assume comments in code are accurate.

Do not assume a file existing means the feature ships.

Do not assume a function existing means it is reachable.

Do not assume a model resource exists unless you verify it.

Do not assume a model resource ships unless you verify target membership and bundle inclusion.

Do not assume Core ML means Core AI.

Do not assume Core ML computeUnits = .all proves ANE execution.

Do not assume “abstention path” affects user-facing behavior unless the runtime path proves it.

Do not assume “contradiction sweep” is strong unless the implementation proves it.

Do not edit production code.

You may create or update audit/report files under Docs/AUDIT/ only.

If a requested command cannot run in this environment, document that limitation explicitly and explain what evidence is missing because of it.

The owner is relying on this final audit to understand what is literally in OpenIntelligence v4.1 and what can be safely said publicly.

Accuracy matters more than sounding impressive.

────────────────────────────────────────

FINAL AUDIT GOAL

Determine whether OpenIntelligence v4.1 is now fully documented, accurately described, and safe to discuss publicly.

You must answer:

1. Did the previous audit truly walk the entire codebase?
2. Did it inventory every git-tracked file?
3. Did it classify every component correctly?
4. Did it verify target membership and shipped reality?
5. Did it separate shipped user-facing behavior from internal behavior, resource-dependent behavior, fallback behavior, debug-only tools, scaffolding, placeholders, and future plans?
6. Did it verify all public claims against actual code and build artifacts?
7. Did it correct stale or inflated documentation?
8. Did it verify the exact status of reranking, cross-encoder reranking, Core ML, Core AI, abstention, contradiction sweeps, semantic grounding, numeric sanity, verification gates, PCC routing, Foundation Models routing, billing, Spotlight/AppIntents, and Core AI scaffolding?
9. Did it produce owner-facing explanations that are technically accurate and digestible?
10. Did it produce public copy that does not overclaim?
11. Did it run build/test/validation checks or clearly document why they could not be run?
12. What gaps remain before the repo/docs can be treated as source of truth?

────────────────────────────────────────

FIRST REQUIRED ACTION: PRODUCE COUNTS BEFORE INTERPRETATION

Before writing any analysis, produce these numbers:

* Current branch
* Current commit SHA
* Git dirty/clean status
* Git-tracked file count
* Inventory CSV row count
* Missing tracked files count
* Extra inventory rows count
* Blank status row count
* UNKNOWN_REQUIRES_REVIEW row count
* Rows without evidence count
* Audit files expected count
* Audit files found count
* Audit files missing count
* Build validation files found count
* Public docs checked count
* Public copy files checked count

If you cannot produce these counts, stop and state:

“The previous audit is not verifiable yet because the required counts could not be produced.”

Do not proceed to interpretation until these numbers are produced.

────────────────────────────────────────

REQUIRED FINAL OUTPUT FILE

Create:

Docs/AUDIT/99_FINAL_ABSOLUTE_AUDIT_4.1.md

This is the final decision document.

It must include every section below.

────────────────────────────────────────

SECTION 1 - FINAL EXECUTIVE VERDICT

Choose exactly one:

* APPROVED_AS_SOURCE_OF_TRUTH
* APPROVED_WITH_MINOR_GAPS
* MOSTLY_COMPLETE_BUT_REQUIRES_REPAIR
* PARTIAL_NOT_SAFE_TO_TRUST_YET
* FAILED_AUDIT

Use this table:

Verdict	Meaning
APPROVED_AS_SOURCE_OF_TRUTH	Every tracked file, major component, claim, doc, resource, and validation step is accounted for. Remaining gaps are trivial.
APPROVED_WITH_MINOR_GAPS	Mostly trustworthy. Minor unresolved items do not affect public claims.
MOSTLY_COMPLETE_BUT_REQUIRES_REPAIR	Useful audit, but important gaps remain before public/docs source-of-truth status.
PARTIAL_NOT_SAFE_TO_TRUST_YET	Major audit areas are missing, unverified, or unreliable.
FAILED_AUDIT	The audit cannot be trusted.

Do not choose APPROVED_AS_SOURCE_OF_TRUTH unless the inventory, target membership, resource bundling, component map, feature claim register, docs, public copy, and validation checks are complete.

Explain the verdict in 5 to 10 bullets.

────────────────────────────────────────

SECTION 2 - AUDIT FILE EXISTENCE AND ADEQUACY CHECK

Inspect whether these exist:

* Docs/AUDIT/00_REPO_STATE_4.1.md
* Docs/AUDIT/01_AUDIT_CONTROL_LEDGER_4.1.md
* Docs/AUDIT/02_FILE_INVENTORY_4.1.md
* Docs/AUDIT/file_inventory_4.1.csv
* Docs/AUDIT/03_TARGET_MEMBERSHIP_4.1.md
* Docs/AUDIT/04_ENTRY_POINTS_AND_RUNTIME_MAP_4.1.md
* Docs/AUDIT/05_COMPONENT_REALITY_MAP_4.1.md
* Docs/AUDIT/06_FEATURE_CLAIM_REGISTER_4.1.md
* Docs/AUDIT/07_DOCUMENTATION_ACCURACY_MATRIX_4.1.md
* Docs/AUDIT/08_UNUSED_CODE_CANDIDATES_4.1.md
* Docs/AUDIT/09_REORGANIZATION_PLAN_4.1.md
* Docs/AUDIT/10_BUILD_AND_VALIDATION_4.1.md
* Docs/AUDIT/11_FINAL_AUDIT_SUMMARY_4.1.md
* Docs/AUDIT/12_AUDIT_OF_AUDIT_COMPLETION_REPORT_4.1.md
* Docs/AUDIT/13_VIK_COMMENT_TECHNICAL_ALIGNMENT_4.1.md
* Docs/AUDIT/14_RAG_RELIABILITY_DEEP_DIVE_4.1.md
* Docs/AUDIT/15_RERANKING_AND_CROSS_ENCODER_REALITY_4.1.md
* Docs/AUDIT/16_OWNER_EXPLAINER_RAG_RELIABILITY_AND_RERANKING_4.1.md
* Docs/AUDIT/17_POST_VIK_ALIGNMENT_VALIDATION_4.1.md
* Docs/AUDIT/18_GEMINI_PRO_FINAL_AUDIT_REVIEW_4.1.md, if created
* Docs/APP_REALITY_4.1.md
* Docs/BILLING_AND_LIMITS.md
* Docs/KNOWN_LIMITATIONS_4.1.md
* Docs/DEVELOPER_MAP.md
* Docs/PUBLIC_COPY_4.1.md, if created
* README.md
* WHATS_NEW.md
* CHANGELOG.md
* fastlane metadata files, if present

Use:

File	Exists?	Line Count	Adequate?	Missing Information	Action Required

If the file exists but is shallow, mark it inadequate.

If a file is missing, say whether that blocks source-of-truth approval.

────────────────────────────────────────

SECTION 3 - INVENTORY INTEGRITY CHECK

Verify the file inventory.

Run or equivalent:

* git ls-files
* count tracked files
* compare to file_inventory_4.1.csv
* identify missing tracked files
* identify extra inventory entries
* identify rows with blank status
* identify UNKNOWN_REQUIRES_REVIEW
* identify rows with no evidence
* identify suspiciously generic evidence
* identify files classified as shipped without target membership evidence

Produce:

Metric	Count
Git-tracked files
Inventory rows
Missing tracked files
Extra inventory rows
Blank status rows
UNKNOWN_REQUIRES_REVIEW rows
Rows without evidence
Rows with questionable classification
Rows requiring human review

Then list:

Missing Tracked Files

Extra Inventory Rows

Blank / Unknown / No-Evidence Rows

Questionable Classifications

If tracked files are missing from inventory, the audit is not complete.

────────────────────────────────────────

SECTION 4 - TARGET MEMBERSHIP AND SHIPPED REALITY

Verify that previous agents did not confuse repo existence with shipped app behavior.

Inspect:

* Xcode project
* app target sources
* resource build phases
* target membership
* Swift package references
* asset catalogs
* StoreKit configuration
* model resources
* vocab resources
* entitlements
* Info settings
* build settings
* debug/release conditionals
* scripts and generated resources

Use:

Component/File	Previous Classification	Actual Classification	Evidence	Correction Needed

Classifications allowed:

* SHIPPED_USER_FACING
* SHIPPED_INTERNAL
* RESOURCE_DEPENDENT
* FALLBACK_ONLY
* DEV_ONLY
* DEBUG_ONLY
* TEST_ONLY
* SCRIPT_ONLY
* RESOURCE_ONLY
* SCAFFOLDED
* PLACEHOLDER
* DEPRECATED
* HISTORICAL_DOC
* UNUSED_CANDIDATE
* NOT_TARGET_MEMBER
* UNKNOWN_REQUIRES_REVIEW

Pay special attention to:

* RAGEngine
* ReRankerModel
* reranker_vocab
* FoundationModelRoutePolicy
* FoundationModelSessionFactory
* FoundationModelStructuredGenerator
* FoundationModelToolRegistry
* VerificationGateService
* CoreAIExecutionBackend
* CoreAIEmbeddingBackend
* CoreAIModelRegistry
* StoreKitBillingService
* EntitlementStore
* QuotaPolicy
* SpotlightIndexService
* AppEntity/AppIntent files
* Liquid Glass / Theme files
* Unified Metrics Bar
* DebugRAGValidationHarness
* Evaluation files
* Fastlane metadata
* App Store metadata source files
* README/WHATS_NEW/CHANGELOG/Docs

────────────────────────────────────────

SECTION 5 - BUILD AND VALIDATION CHECK

Determine whether the app was actually built or tested after audit/doc changes.

Report:

Validation	Command / Method	Result	Blocking?	Notes

Validation items:

* git status after audit
* xcodebuild clean/build, if possible
* app target build
* package build, if applicable
* tests, if present
* markdown link check, if possible
* stale phrase grep
* unsafe claim grep
* resource existence check
* bundle inclusion check for models/vocabs
* target membership check
* docs consistency check

If build cannot run, clearly state:

* why it could not run
* what confidence is lost
* what the owner must run locally

Search for unsafe phrases:

* guarantee
* guaranteed
* no hallucinations
* hallucination-free
* fully verified
* fully grounded
* Core AI reranking
* fully integrated Core AI
* native Core AI engine
* runs on ANE
* Neural Engine reranking
* 4x
* 20%
* battery drain
* reduced battery
* zero retention
* unlimited Pro
* 432 DPI
* production-ready, unless justified
* Apple Intelligence-native evidence system
* secure enclaves, unless carefully sourced
* solved hallucinations
* perfect citations
* always local
* always private

For each occurrence, decide:

* acceptable
* needs rewrite
* historical doc only
* unsafe public claim
* needs human review

────────────────────────────────────────

SECTION 6 - FEATURE CLAIM FINAL REVIEW

Review every major claim that may appear in README, docs, App Store text, Product Hunt copy, LinkedIn, HN, Reddit, or owner explanations.

Use:

Claim	Final Status	Evidence	Safe Wording	Unsafe Wording	Public Risk

Final statuses:

* VERIFIED_SHIPPED_USER_FACING
* VERIFIED_SHIPPED_INTERNAL
* VERIFIED_RESOURCE_DEPENDENT
* VERIFIED_FALLBACK_ONLY
* VERIFIED_DEV_ONLY
* SCAFFOLDED
* PLACEHOLDER
* PARTIALLY_TRUE
* OUTDATED
* UNSUPPORTED
* NEEDS_BENCHMARK
* NEEDS_HUMAN_REVIEW

Claims to verify:

* OpenIntelligence v4.1 is live
* Apple Silicon RAG engine
* private-first
* standard queries run locally when they fit
* PCC routing
* Deep Think
* Maximum
* context-heavy queries route to PCC when enabled
* larger PCC context window
* reasoning-capable PCC model support
* Foundation Models support
* WWDC26 Foundation Models support
* Metal GPU vector search
* SIMD4 batch execution
* high-volume cosine similarity acceleration
* moving retrieval work off CPU
* citation-backed answers
* structured generation
* citation normalization
* verification gates
* numeric sanity checks
* contradiction sweeps
* abstention paths
* semantic grounding
* evidence coverage
* quote faithfulness
* domain isolation
* suggested questions from real library content
* suggested question caching
* suggested question deduplication
* OCR/layout artifact filtering
* Liquid Glass UI
* Unified Metrics Bar
* model route telemetry
* token speed telemetry
* context usage telemetry
* retrieval quality telemetry
* source count telemetry
* Deep Think / Maximum confidence progress
* smart ingestion
* page-complexity pre-scan
* native text preservation for clean PDFs
* Vision OCR escalation for scans/images
* structured recovery for tables/figures/low-confidence pages
* Siri and Search integration
* App Entities
* Core Spotlight
* passage-level indexing
* Core AI scaffolding
* future native embedding
* future reranking
* future local model execution
* Core ML cross-encoder reranking
* Core AI reranking
* on-device reranking
* heuristic fallback reranking
* candidate-pool cutoff
* device-aware concurrency
* StoreKit products
* Free tier limits
* Pro tier limits
* Lifetime tier limits
* document pack add-ons
* Maximum free daily uses
* legacy paid protection
* iCloud/sync behavior
* RAG evaluation suite
* benchmark metrics
* speed/battery/performance claims
* hallucination-prevention claims

Public risk levels:

* LOW
* MEDIUM
* HIGH
* BLOCKER

Any HIGH or BLOCKER public risk must be repaired before public launch copy is trusted.

────────────────────────────────────────

SECTION 7 - RAG RELIABILITY FINAL REVIEW

Verify these systems directly from code and runtime path:

* verification gates
* evidence coverage
* numeric sanity
* contradiction sweep
* semantic grounding
* quote faithfulness
* generation quality
* answer completeness
* domain isolation
* shouldAbstain
* abstainReason
* final user-visible behavior
* warnings/confidence UI
* structured claims
* citation normalization
* source evidence display

Use:

Reliability System	Exists?	Runtime-Reachable?	User-Visible?	Evidence	Caveat

Then answer directly:

1. Are abstention paths real?
2. Are they internal only or user-facing?
3. Which gates can trigger abstention?
4. Do contradiction sweeps trigger abstention, or only reduce confidence / fail a gate?
5. Does semantic grounding trigger abstention?
6. Does numeric sanity trigger abstention?
7. Does retrieval confidence trigger abstention?
8. Does domain isolation trigger abstention?
9. Are verification gates always run, conditionally run, or only available?
10. Does the final answer path respect verification results?
11. Is “first-class” a fair description?
12. What is the honest limitation?

Produce:

Safe RAG Reliability Explanation

Plain English, no hype.

Unsafe RAG Reliability Claims

List exact phrases to avoid.

────────────────────────────────────────

SECTION 8 - CONTRADICTION SWEEP FINAL REVIEW

Verify contradiction sweep specifically.

Answer:

1. Where is contradiction detection implemented?
2. What does the detection method actually detect?
3. Is it lexical, numeric, semantic, heuristic, or formal logic?
4. Does it compare claims across chunks?
5. Does it compare source values?
6. Does it fail a gate?
7. Does it reduce confidence?
8. Does it force abstention?
9. Is it surfaced to users?
10. Is “contradiction sweep” fair wording?
11. What is the strongest safe public wording?
12. What would overstate it?

Use:

Aspect	Actual Behavior	Evidence	Limitation

Important:
If contradiction sweep is heuristic, say heuristic.
If it does not fully resolve contradictions, say that.
If it flags potential contradictions rather than proving contradictions, say that.

────────────────────────────────────────

SECTION 9 - RERANKING FINAL REVIEW

This is critical.

Verify:

1. Does the current code contain a cross-encoder reranking path?
2. Is it implemented in Core ML, Core AI, or another system?
3. What file contains it?
4. What model resource name is expected?
5. Is the model resource present?
6. Is the model resource target-membered?
7. Is the model resource copied into the app bundle?
8. What tokenizer resource is expected?
9. Is the tokenizer resource present?
10. Is the tokenizer target-membered/copied?
11. What happens if model/tokenizer are missing?
12. What fallback reranking exists?
13. Is fallback heuristic, lexical, semantic, metadata-based, or hybrid?
14. Is reranking runtime-reachable from the query path?
15. Are rerank scores propagated downstream?
16. Does the system normalize cross-encoder scores?
17. Are TOC/question-bank penalties applied after cross-encoder scoring?
18. Does the implementation prove ANE execution?
19. Does the implementation only request Core ML computeUnits = .all?
20. Is “on-device Core ML cross-encoder path” safe?
21. Is “Core AI reranking” safe?
22. Is “future Core AI scaffolding” safe?

Use:

Question	Answer	Evidence	Public Claim Allowed?

Required distinction:

* Core ML cross-encoder reranking path
* on-device Core ML reranking
* Core AI reranking
* Core AI scaffolding
* ANE execution
* Core ML computeUnits = .all
* resource-dependent shipped path
* fallback-only path

If the model function exists but the resource is absent or not bundled, status must be RESOURCE_DEPENDENT or NOT_SHIPPED, not fully shipped.

If the resource is present and bundled, status can be VERIFIED_RESOURCE_DEPENDENT or VERIFIED_SHIPPED_INTERNAL depending on runtime reachability.

────────────────────────────────────────

SECTION 10 - CANDIDATE-POOL FORMULA FINAL REVIEW

Find the actual formula used to decide how many candidates are sent into reranking.

Do not trust comments. Calculate from code.

Use:

Chunk Count	topK	Candidate Pool	Comment Matches Code?	Notes

Calculate:

* 5 chunks, topK 5
* 25 chunks, topK 5
* 50 chunks, topK 10
* 100 chunks, topK 10
* 150 chunks, topK 10
* 199 chunks, topK 10
* 200 chunks, topK 10
* 500 chunks, topK 10
* 500 chunks, topK 20
* 5,000 chunks, topK 10
* 5,000 chunks, topK 50

Then answer:

* Is the behavior adaptive?
* Is there a minimum candidate pool?
* Is there a maximum candidate pool?
* Does it actually use all chunks for small corpora?
* Do code comments match implementation?
* Is the formula reasonable?
* What should Gunnar ask Vik about candidate-pool sizing?
* What should the docs say?

────────────────────────────────────────

SECTION 11 - CORE ML VS CORE AI FINAL REVIEW

This is a likely public-claim trap.

Verify:

System	Actual Status	Evidence	Safe Claim	Unsafe Claim

Systems:

* Core ML reranker
* Core ML model loading
* Core ML computeUnits = .all
* ReRankerModel
* reranker_vocab
* CoreAIExecutionBackend
* CoreAIEmbeddingBackend
* CoreAIModelRegistry
* Future Core AI local execution
* Future Core AI embedding
* Future Core AI reranking

Rules:

* If CoreAIExecutionBackend returns placeholder output, call it PLACEHOLDER.
* If CoreAIEmbeddingBackend returns an empty embedding, call it PLACEHOLDER.
* If CoreAIModelRegistry only registers metadata, label it appropriately.
* Do not let docs imply production Core AI inference unless code proves it.
* Prefer “Core AI scaffolding” if future-facing.
* Prefer “Core ML cross-encoder reranking path” if current reranking uses MLModel.

────────────────────────────────────────

SECTION 12 - APP STORE / PUBLIC COPY FINAL REVIEW

Review current public-facing copy sources.

Check for mismatch between:

* App Store metadata
* Fastlane metadata
* README
* WHATS_NEW
* CHANGELOG
* Docs/PUBLIC_COPY_4.1.md
* LinkedIn/Product Hunt/HN/Reddit draft copy
* actual code

Use:

Public Surface	Claim Problem	Severity	Exact Fix

Severity:

* BLOCKER
* HIGH
* MEDIUM
* LOW

Specifically check:

* Pro document limits
* Lifetime document limits
* local/private claims
* PCC claims
* Core AI claims
* reranking claims
* hallucination/grounding claims
* speed/battery claims
* Siri/Search/AppEntity claims
* benchmark claims
* supported file types
* subscription/purchase wording

If public copy says Pro is unlimited but code says Pro has a finite limit, mark BLOCKER.

If public copy says Core AI is fully implemented but code shows placeholders, mark BLOCKER.

If public copy says hallucinations are guaranteed prevented, mark BLOCKER.

────────────────────────────────────────

SECTION 13 - DOCUMENTATION FINAL REVIEW

Determine whether documentation is now source-of-truth quality.

Use:

Document	Final Status	Problems Remaining	Fix Needed

Final statuses:

* SOURCE_OF_TRUTH_READY
* READY_WITH_MINOR_NOTES
* NEEDS_REPAIR
* HISTORICAL_ONLY
* UNSAFE
* MISSING

Review:

* README.md
* WHATS_NEW.md
* CHANGELOG.md
* Docs/APP_REALITY_4.1.md
* Docs/BILLING_AND_LIMITS.md
* Docs/KNOWN_LIMITATIONS_4.1.md
* Docs/DEVELOPER_MAP.md
* Docs/PUBLIC_COPY_4.1.md
* Docs/ARCHITECTURE.md
* Docs/RETRIEVAL_PIPELINE.md
* Docs/INGESTION_PIPELINE.md, if present
* Docs/PRIVACY_AND_ROUTING.md, if present
* Docs/EVALS.md
* Docs/AI_AGENT_MAP.md
* Docs/Engineering/*
* fastlane metadata

Every current doc must have a status.

Historical docs must be labeled historical.

Future/scaffold docs must be labeled future/scaffold.

No stale doc should appear to be the current source of truth.

────────────────────────────────────────

SECTION 14 - UNUSED / DEAD / SCAFFOLDED CODE FINAL REVIEW

Review unused-code findings.

Use:

File/Symbol	Previous Status	Final Status	Evidence	Recommendation

Final statuses:

* KEEP_SHIPPED
* KEEP_INTERNAL
* KEEP_RESOURCE
* KEEP_DEV_ONLY
* KEEP_DEBUG_ONLY
* KEEP_SCAFFOLD
* REVIEW_UNUSED_CANDIDATE
* REVIEW_DEPRECATED
* SAFE_TO_ARCHIVE_AFTER_BUILD_TEST
* DO_NOT_DELETE

Do not recommend deletion unless:

* not target-membered,
* no references,
* no resource use,
* no dynamic use,
* no scripts depend on it,
* build passes without it,
* owner approves.

If uncertain, mark REVIEW_UNUSED_CANDIDATE.

────────────────────────────────────────

SECTION 15 - REORGANIZATION PLAN FINAL REVIEW

Review the reorganization plan.

Determine whether it is safe, staged, and non-destructive.

Use:

Proposed Move	Risk	Benefit	Build Gate	Approved?

Rules:

* No mass reorganization without build gates.
* Move one subsystem at a time.
* Do not move resources until target membership and bundle inclusion are understood.
* Do not move generated or model resources casually.
* Do not mix future scaffolding with shipped implementation.
* Preserve git history where possible.
* Require owner approval before actual moves.

Final answer:

* safe to begin reorganization
* not safe yet
* safe only for docs
* safe only after build validation

────────────────────────────────────────

SECTION 16 - OWNER UNDERSTANDING SUMMARY

Write this section for Gunnar in plain English.

No hype.

No code blocks.

Explain:

1. What OpenIntelligence v4.1 actually is.
2. What happens when a user asks a question.
3. What retrieval does.
4. What reranking does.
5. What cross-encoder reranking means.
6. What “on-device” means here.
7. What Core ML means here.
8. What Core AI does and does not mean here.
9. What abstention means.
10. What contradiction sweep means.
11. What verification gates do.
12. What the app can safely claim.
13. What the app should not claim.
14. What Vik’s comment correctly noticed.
15. What Gunnar should ask Vik if the conversation continues.

Keep this section concise but complete.

────────────────────────────────────────

SECTION 17 - FINAL SAFE / UNSAFE CLAIM MAP

Create:

Safe to Say Publicly

List exact phrases Gunnar can use.

Examples may include, only if verified:

* “OpenIntelligence includes verification gates and abstention paths for weak evidence.”
* “The RAG engine includes contradiction checks that can flag conflicting retrieved evidence.”
* “The app has a Core ML cross-encoder reranking path with fallback scoring.”
* “Core AI support is currently scaffolding for future native embedding/reranking/local execution.”
* “Standard queries can run locally when they fit the on-device context budget.”
* “More complex queries can route to Apple Private Cloud Compute when enabled.”

Needs Qualification

List phrases that can be used only with careful caveats.

Unsafe to Say

List exact phrases to avoid.

Examples:

* “It guarantees no hallucinations.”
* “Core AI reranking is fully implemented.”
* “It always runs on ANE.”
* “Pro is unlimited” if code disagrees.
* “It fully solves contradiction detection.”
* “Every answer is fully verified.”
* “It is 4x faster” without benchmark evidence.
* “It reduces battery drain” without measurement.

────────────────────────────────────────

SECTION 18 - FINAL LINKEDIN / VIK RESPONSE

Create a final recommended reply to Vik.

Constraints:

* Human, not corporate.
* Technically aware.
* Does not overclaim.
* Mentions local candidate-pool sizing if appropriate.
* Uses Core ML vs Core AI correctly.
* Does not say ANE unless proven.
* Does not say Core AI reranking is shipped unless proven.
* Does not sound needy.
* Invites discussion naturally.

Produce:

Recommended Public Reply

More Technical Reply If He Responds

Optional DM After Connection Acceptance

Keep each short.

────────────────────────────────────────

SECTION 19 - FINAL BLOCKERS AND REPAIR LIST

List remaining blockers.

Use:

Priority	Blocker / Gap	Why It Matters	Exact Repair

Priority:

* P0 blocks public trust
* P1 should fix before Product Hunt/HN
* P2 should fix before reorganization
* P3 nice to fix

Likely blockers to check:

* inventory mismatch
* missing target membership proof
* missing model resource proof
* unverified build
* unsafe public claims
* App Store metadata mismatch
* Core AI overclaim
* reranking overclaim
* Pro/Lifetime limit mismatch
* stale docs still appearing current
* missing owner explainer
* missing final safe/unsafe claim map

────────────────────────────────────────

SECTION 20 - FINAL TRUST DECISION

End with:

Final Trust Decision

Choose one:

* I would trust this repo/docs as the OpenIntelligence v4.1 source of truth.
* I would mostly trust it after the listed repairs.
* I would not trust it yet.

Then include:

* 5 reasons supporting the decision
* 5 remaining risks
* the next 3 actions Gunnar should take

Do not end vaguely.

Be decisive.

────────────────────────────────────────

STRICT CONSTRAINTS

Do not be flattering.

Do not infer from docs.

Do not infer from comments.

Do not infer from file existence.

Do not infer from function existence.

Do not infer from public copy.

Verify against code, target membership, resources, runtime paths, and validation output.

If evidence is missing, say evidence is missing.

If a previous agent was wrong, say it was wrong.

If previous audit output is incomplete, say incomplete.

If you find claim/code mismatch, code wins.

If you find doc/code mismatch, code wins.

If you find comment/code mismatch, code wins.

If you find public-copy/code mismatch, code wins.

If you find model-resource/code mismatch, runtime reality wins.

This audit is complete only when the owner can answer:

* What is shipped?
* What is internal?
* What is resource-dependent?
* What is fallback-only?
* What is scaffolded?
* What is placeholder?
* What is unsafe to claim?
* What is safe to claim?
* What still needs proof?

Begin now with the required counts. Do not interpret anything until the counts are produced.
