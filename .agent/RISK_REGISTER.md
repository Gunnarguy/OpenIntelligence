# OpenIntelligence Risk Register

## Risks Identified

### RISK-01: SDK Incompatibility of Claimed Apple Intelligence APIs
*   **Description:** PRs claiming to use new WWDC 2026 APIs (specifically `SystemLanguageModel.advanced` in PR #54) do not compile because the actual SDK interface has no such symbol.
*   **Impact:** Critical (breaks compilation of main/release targets).
*   **Mitigation:** Block PR #54; enforce strict compiler typecheck gates for any WWDC 2026 API claims. `[evidence_level: compile_verified, confidence: exact]`

### RISK-02: Missing Private Cloud Compute Entitlement and Local Simulation
*   **Description:** The active `.entitlements` file intentionally omits `com.apple.developer.private-cloud-compute` to prevent CI/CD signing errors. The app runs PCC routes by simulating them locally on `SystemLanguageModel.default` via a compatibility shim.
*   **Impact:** Medium (app does not execute on remote secure enclaves; behaves as standard on-device execution).
*   **Mitigation:** Ensure the fallback logic remains intact and does not crash when the entitlement is absent. `[evidence_level: code_verified, confidence: exact]`

### RISK-03: Lack of Unit Testing Framework
*   **Description:** PR #3 deleted the Xcode unit testing targets and all associated tests. Currently, there are no compiled unit tests running.
*   **Impact:** High (risk of regression is high for subsequent changes).
*   **Mitigation:** Implement a replacement testing strategy layers 1-5 (deterministic unit, fakes, simulator integrations, physical device verification). `[evidence_level: code_verified, confidence: exact]`

### RISK-04: Background Git Pruning of PR References
*   **Description:** Background IDE sync daemons run `git fetch --prune` which silently prunes PR tracking branches.
*   **Impact:** Low (causes manifest generator scripts to fail to resolve branches).
*   **Mitigation:** Fetch all refs to the local `refs/pull/` namespace which is ignored by prune actions. `[evidence_level: code_verified, confidence: exact]`

### RISK-05: Baseline Contamination from Pre-Existing Dirty Working Tree
*   **Description:** Pre-existing changes to Tier 1 and Tier 2 files contaminate local build baselines and compile diagnostics if testing runs directly against the checkout.
*   **Impact:** High (may report baseline metrics/behaviors that diverge from actual clean main branch state).
*   **Mitigation:** Programmatically query clean files using Git object extraction (`git show`, `git cat-file`) to bypass local modifications during baseline validation. `[evidence_level: code_verified, confidence: exact]`

### RISK-06: Sandbox Restrictions on Local Worktree Generation
*   **Description:** macOS/IDE sandbox limitations prevent `git worktree add` from memory-mapping files in sibling or temp directories, blocking clean baseline directory checkouts.
*   **Impact:** Medium (prevents multi-file baseline builds directly on the filesystem outside of Git object databases).
*   **Mitigation:** Limit baseline validations to file-level queries, isolated compiler probes, and diffs extracted directly from Git refs. `[evidence_level: code_verified, confidence: exact]`

### RISK-07: Concurrency Sizing Policy Recall Regression (PR #63)
*   **Description:** Removing `vectorCount` scaling in `lexicalRecallLimit` prevents the retrieval engine from scaling up lexical candidates when vector results are weak, risking significant search recall failures.
*   **Impact:** High (could result in complete failure to recall keyword needles in sparse indices).
*   **Mitigation:** Reject the patch and require a concurrent design that preserves fallback scaling (e.g. by querying an initial vector count or executing a high lexical limit under fallback scenarios). `[evidence_level: code_verified, confidence: exact]`

### RISK-08: Branch Contamination Integration Risk (PR #63)
*   **Description:** PR #63 includes uncommitted helper scripts (`fix.py`, `test_compile.sh`) in the branch, which could contaminate production files if merged blindly.
*   **Impact:** Low (clutters the workspace, potential build script pollution).
*   **Mitigation:** Set the disposition to `SUPERSEDE` to force a clean pull request branch excluding these scripts. `[evidence_level: code_verified, confidence: exact]`

### RISK-09: Regex Engine Overheads during Query Processing (PR #53)
*   **Description:** Evaluation of regular expressions with word boundaries over multiple patterns in a loop (`embeddedLookupPatterns` and `specLookupPatterns`) runs for every query during intent classification, which increases CPU cycle overhead.
*   **Impact:** Low (queries are typically short, so latency impact is negligible, but it represents a minor CPU processing increase).
*   **Mitigation:** Verify via unit benchmarks that query classification latency is within acceptable parameters (< 1ms). `[evidence_level: code_verified, confidence: exact]`

### RISK-10: Tokenizer Segment Alignment Mismatch (PR #56)
*   **Description:** Altering the text separator between the query and hypothetical document from newline to space modifies the input structure processed by the model tokenizer, which can affect the token IDs and generated embeddings.
*   **Impact:** Low (generally positive, as it matches standard training datasets, but it does shift semantic retrieval boundaries).
*   **Mitigation:** Verify that retrieval precision and recall metrics on test datasets are stable or improved post-integration. `[evidence_level: code_verified, confidence: exact]`

### RISK-11: NSRange Conversion Index Crash Risk (PR #57)
*   **Description:** Converting between Objective-C `NSRange` (based on UTF-16 code units) and Swift `Range<String.Index>` (based on Extended Grapheme Clusters) can lead to indexing crashes or misalignments if string length mappings do not explicitly specify the target view (`utf16.count`).
*   **Impact:** Low (the code correctly specifies `sentence.utf16.count` for NSRange generation and uses `Range(match.range, in: sentence)` for safe conversion, eliminating index crash risks).
*   **Mitigation:** Confirm via unit tests that strings containing multi-byte characters and emojis do not trigger range conversion issues or index out-of-bounds exceptions. `[evidence_level: code_verified, confidence: exact]`

### RISK-13: Current-Main Defect MAIN-1 — `.onDeviceAdvanced` Telemetry Misreport
*   **Description:** On current `origin/main` (not from any PR), `FoundationModelSessionFactory.swift` (~lines 56–68) runs `SystemLanguageModel.default` for the `.onDeviceAdvanced` case on OS 27+ but never downgrades `selectedRoute`, so telemetry reports an "advanced" (claimed 20B) model that does not exist in the installed SDK. Repository docs and commits `7eeee45`/`abd1e3b` overstate "local 20B" support.
*   **Impact:** Medium (misleading telemetry and documentation; no crash).
*   **Mitigation:** Phase B fix under named Tier-2 authorization: set `selectedRoute = .onDevice` in the 27+ branch and correct the comment; owner editorial pass on Docs/What's-New claims. Source: Independent Verification Report 2026-07-11, corroborated against the master directive PR #54 section. `[evidence_level: code_verified, confidence: exact]`

### RISK-14: Current-Main Defect MAIN-2 — `EntitlementChecker.hasEntitlement` Fails Open
*   **Description:** `EngineSDKCompatibility.swift` (~lines 204–214) returns `true` when no embedded provisioning profile is found (App Store builds; all macOS builds where the profile is `embedded.provisionprofile`). With the PCC entitlement deliberately removed, distribution builds on OS 27+ can instantiate native `PrivateCloudComputeLanguageModel()` unentitled; the only safety net is `nativeModel.isAvailable`, whose unentitled device behavior has never been observed.
*   **Impact:** Critical for distribution builds (potential crash class documented in `03_FORBIDDEN_EDIT_BOUNDARIES.md`).
*   **Mitigation:** Phase B fix under named Tier-2 authorization: fail closed when the profile cannot be proven, or additionally check `embedded.provisionprofile`; PCC route must keep throwing `LLMError.modelUnavailable`. Physical-device validation required (OWNER_ACTION_REQUIRED). `[evidence_level: code_verified, confidence: exact]` (runtime behavior: `unknown`)

### RISK-15: Uncommitted Prior-Agent Implementation Work in the Working Tree
*   **Description:** The checkout carries uncommitted modifications (Tier-1 `project.pbxproj` + schemes adding an `OpenIntelligenceTests` target; PR #51-identical `LaunchArguments.swift`; a 39-line un-provenanced `SemanticChunker.swift` entity-extraction fallback) and 9 untracked test suites, performed under the now-superseded AUTH-03/AUTH-04. This work overlaps open PRs #26/#46, #32/#50, #51 and closed PRs #8/#9/#13.
*   **Impact:** High (baseline contamination for any in-place build; provenance ambiguity; risk of accidental commit mixing audit and implementation).
*   **Mitigation:** Preserved untouched per takeover directive; all baseline claims use Git-object isolation. Owner must decide in Phase B whether to adopt, re-derive, or discard each piece (see FINAL_REPORT_DRAFT owner decisions). `[evidence_level: code_verified, confidence: exact]`

### RISK-16: Stale-Base Open PRs (#26–#45)
*   **Description:** Twenty open PRs are based on old main `ac1d82947fda`; files they touch (e.g. `SQLiteFullTextService.swift`, `StructuredAnswer.swift`, `MarkdownRenderer.swift`) have since drifted on main. Direct merges would resurrect stale context even where the hunks still apply.
*   **Impact:** Medium.
*   **Mitigation:** All accepted intents are scheduled for reimplementation on current main (see manifest `implementation_strategy` fields); no direct merges. `[evidence_level: code_verified, confidence: exact]`

### RISK-17: Same-Path Test-File Collisions (#29 vs #38; #30 vs #43; #26 vs #46; #32 vs #50)
*   **Description:** #29 and #38 both create `OpenIntelligenceTests/Core/Models/StructuredAnswerTests.swift` with different contents and different `@testable import` targets (`OpenIntelligence` vs `OpenIntelligenceEngine`); #30 and #43 insert conflicting "Test 9" blocks at the same `CoreValidationView.swift` location; the WorkspaceTier and LLMModelType pairs duplicate whole files.
*   **Impact:** Medium (merge conflicts and duplicate/dead suites if handled independently).
*   **Mitigation:** Consolidation strategies recorded per PR; a single canonical suite per subject lands with the restored test target. `[evidence_level: code_verified, confidence: exact]`

### RISK-18: Tokenizer Unknown-Token Change Can Shift Citation Offsets (PR #44)
*   **Description:** Honoring `byte_fallback=false` changes token sequences for unknown tokens, which can invalidate byte-level citation offsets and alter model behavior for affected configs.
*   **Impact:** High (citation alignment is a canonical invariant).
*   **Mitigation:** BLOCKED_PENDING_FIXTURE_TESTS; exact-ID and round-trip fixtures against upstream reference required before any decision. `[evidence_level: code_verified, confidence: exact]`

### RISK-19: Storage-Boundary PRs Lack the Mandatory Test Battery (#27, #39, #40, #42, #45, #55)
*   **Description:** All storage-cluster changes touch `SQLiteFullTextService.swift` (protected data-integrity boundary) with no legacy-fixture, interrupted-migration, locked/busy, disk-full, or WAL-recovery tests in existence. #39 additionally omits per-row step/reset error handling and rollback; #40 de-parameterizes SQL (CLOSE).
*   **Impact:** High.
*   **Mitigation:** No storage change enters the integration branch before the battery exists (master directive hard rule); #27+#55 to be superseded by a closed migration-descriptor enum design. `[evidence_level: code_verified, confidence: exact]`

### RISK-12: PDFKit Word Count Skew under Corrupted Text Layers (PR #59)
*   **Description:** PDFKit native text extraction can report inaccurate word counts if the PDF's text layer is garbled, contains hidden duplicated text (often added by bad OCR programs), or contains unresolved ligatures/substituted fonts.
*   **Impact:** Medium (can result in extremely low or inflated quality scores, causing the system to either bypass OCR when needed or trigger redundant OCR runs).
*   **Mitigation:** Reject raw word-count ratios as single metrics. Rework to use a composite quality score incorporating layout observations, character ranges, and dictionary coverage. `[evidence_level: code_verified, confidence: exact]`





### RISK-13/RISK-14 STATUS UPDATE (2026-07-13): MAIN-1 and MAIN-2 are FIXED on the audit branch (commit d9eeddc, AUTH-08). RISK-14 residual: unentitled-device fallback behavior still requires physical-device verification (OWNER_ACTION_REQUIRED).

### RISK-20: iCloud Eviction of Git Object Store
*   **Description:** The repository lives in iCloud-synced `~/Documents` with Optimize Mac Storage; macOS evicted a 15MB git pack file to a dataless stub mid-session, causing indefinite hangs in `git rev-parse`/`git show` on PR objects.
*   **Impact:** Medium (blocks audit/implementation work unpredictably; a future eviction during a commit could corrupt perception of repo state).
*   **Mitigation applied:** force-materialized the pack by reading it. **Owner recommendation:** exclude the repo (or at least `.git/`) from iCloud optimization, or relocate the repo outside `~/Documents`. `[evidence_level: code_verified, confidence: exact]`
