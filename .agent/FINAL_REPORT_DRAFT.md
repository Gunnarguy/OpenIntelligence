# OPENINTELLIGENCE ZERO-REGRESSION AUDIT — PHASE A FINAL REPORT
**Date:** 2026-07-13 · **Status:** Phase A COMPLETE (read-only audit). No production source, test, project-configuration, entitlement, package, persisted-format, or GitHub-PR state was modified by the audit sessions of 2026-07-13.

## 0. Environment and Baseline
*   Starting/current `origin/main` SHA: `7eeee45c7aa2d9e6b8c545355c7f2239c7101b76` (HEAD == origin/main; re-verified live via authenticated `gh` on 2026-07-13, zero head-SHA drift on all 67 PR refs — TE-13)
*   Xcode 27.0 (27A5194q) · Swift 6.4 · iPhoneSimulator 27.0 SDK · macOS 27.0 SDK
*   Baseline builds: iOS Simulator Debug (TE-01), iOS Simulator Release (TE-03), macOS Debug (TE-04) — all SUCCEEDED, 0 first-party compile warnings
*   Physical devices: NONE used — all device-dependent claims are recorded as unresolved (OWNER_ACTION_REQUIRED)
*   Working tree: DIRTY with uncommitted prior-agent Phase B work performed under superseded AUTH-03/AUTH-04 (see §8 and RISK-15). Preserved untouched; all baseline claims used Git-object isolation.

## 1. Complete 68-PR Ledger
Formal `audit_disposition` values only; `strategy` = `implementation_strategy`. Full per-PR evidence in `pr_manifest.json`.

### Merged (3)
| PR | Disposition | Notes |
| :-- | :-- | :-- |
| #1 | KEEP | Merge `a2e261f` in main; post-integration behavioral spot-checks queued for Phase B regression suite |
| #3 | KEEP | Merge `241fc37`; removed the test target — root cause of the dead-test backlog (RISK-03) |
| #6 | KEEP | Merged per GitHub API; area since reworked (its commits no longer patch-equivalent) |

### Closed-unmerged (22)
All `CLOSE`. Presence in current main (TE-12): **present/adopted:** #5 (ancestor of main), #15 (equivalent Dictionary-map lookup in main), #18 (service removal happened), #19, #20, #21 (patch-equivalent commits). **Not present:** #2 (partial — issue templates/ci.yml adopted; copilot files not), #7–#14, #16, #17, #22 (empty net diff), #23–#25. #4 does not exist on GitHub. Committed contaminants: #15 `commit_msg.txt`, #17 `pr_description.md`. Test-only intents (#8–#10, #13, #14, #16, #23–#25) fold into the restored-test-target plan, not into resurrection of old patches.

### Open (43) — terminal Phase A dispositions
| PR | Disposition / Strategy | One-line basis (verified by merge-base git-object diff) |
| :-- | :-- | :-- |
| #26 | REWORK / consolidate w/ #46 | WorkspaceTier test suite (superset); dead until test target exists |
| #27 | REWORK / consolidate+reimplement w/ #55 | Identifier regex allowlist; `definition` still raw; protected FTS5 boundary |
| #28 | REWORK / unify w/ vector policy | 1-line magnitude reduce; FP-identical; not contaminated (DEC-25) |
| #29 | REWORK / pure helper, no widening | `citationIndex` private→internal for tests; test file collides with #38 |
| #30 | REWORK / move tests to target | RetrievalConfig tests embedded in diagnostic UI; collides with #43 |
| #31 | REWORK / keep after tests | Single-pass min/max; subtle NaN-edge differences; benchmark unrun |
| #32 | REWORK / consolidate w/ #50 | LLMModelType tests; duplicate file path |
| #33 | REWORK / split | Real empty-input NaN guard + unmeasured allocation claim |
| #34 | REWORK / keep after fixtures | isHorizontalRule rewrite; ACCEPTS TABS (behavior change, CommonMark-conformant) |
| #35 | REWORK / keep after equivalence tests | Variance via reduce; same accumulation order |
| #36 | REWORK / expand boundary coverage | RetrievalConfig recommendation tests; boundaries incomplete |
| #37 | REWORK / consolidate/upstream w/ #41 | Mask-dtype inference (float32/16 only); CONTAMINATED: `pre_commit.sh` |
| #38 | REWORK / pure helper, no widening | `minimumClaimLength` widening; collides with #29 |
| #39 | REWORK / rework then benchmark | Statement reuse w/o per-row error handling or rollback; protected boundary |
| #40 | CLOSE | Replaces bound params with interpolated multi-statement SQL — never acceptable |
| #41 | REWORK / consolidate/upstream w/ #37 | Duplicate of #37 (if/else form); clean branch |
| #42 | REWORK / verify sqlite3_changes or close | Logged-count semantics unproven under FTS5 vtab/cascades |
| #43 | REWORK / move tests to target | Widens MarkdownParser internals; tests in UI; collides with #30 |
| #44 | BLOCKED / pending fixture tests | byte_fallback change can shift token IDs → citation offsets |
| #45 | CLOSE | Two-statement unroll; no benefit |
| #46 | REWORK / consolidate w/ #26 | WorkspaceTier subset suite |
| #47 | REWORK / consolidate+reimplement w/ #49,#61 | vDSP overlay+C mix; one of 3 competing vector rewrites |
| #48 | SQUASH | Dead-code removal in Tier-2 RAGService.swift |
| #49 | REWORK / consolidate+reimplement w/ #47,#61 | Downgrades modern overlay→`vDSP_svesq` in 4 files incl. Tier-2 BNNS store |
| #50 | REWORK / consolidate w/ #32 | LLMModelType duplicate |
| #51 | REWORK / keep after tests | Parser extraction + tests; ALREADY APPLIED uncommitted in working tree (TE-15) |
| #52 | SQUASH | "UNIVERSAL FIX" comment churn (7 lines, 5 files) |
| #53 | REWORK / escape literals + classification tests | Word-boundary regex fixes substring false positives; unescaped interpolation fragile |
| #54 | BLOCKED / pending SDK proof | `SystemLanguageModel.advanced` ABSENT from SDK (TE-02, independently reproduced); cannot compile |
| #55 | REWORK / consolidate+reimplement w/ #27 | Identifier quoting; `definition` still raw |
| #56 | CLOSE / unless benchmark proves value | HyDE separator `\n`→space changes every HyDE embedding; unmeasured |
| #57 | REWORK / remove try!, justify Sendable, prove equivalence | Precompiled regex cache; title misleading (not a syntax fix) |
| #58 | SUPERSEDE / reimplement UTType refactor | Trivial useful refactor; CONTAMINATED: `fix.py`, `refactor.py` |
| #59 | REWORK / composite quality metric | Native word-count ratio unreliable under garbled text layers |
| #60 | SQUASH | Comment/rename only; verify comment accuracy when folding |
| #61 | REWORK / consolidate+reimplement w/ #47,#49 | cBLAS variant; third competing implementation |
| #62 | SUPERSEDE / labeled eval + clean branch | Hard-zero heuristic falsely rejects valid non-numeric answers; CONTAMINATED: `plan.txt` |
| #63 | SUPERSEDE / reimplement preserving sizing policy | Concurrency drops vector-confidence recall scaling; changes cancellation; CONTAMINATED: `fix.py`, `test_compile.sh` |
| #64 | REWORK / align w/ retrieval lexical policy | Query-aware compression fallback mislabeled as build fix |
| #65 | CLOSE | Entire patch = 1-line visibility widening; stated premise (compile error) false |
| #66 | CLOSE | Plaintext query-history persistence to UserDefaults mislabeled as leak fix — privacy regression (DEC-27) |
| #67 | REWORK / keep intent, reimplement cleanly | Observer capture change; NOT contaminated (DEC-25 correction); device validation needed |
| #68 | REWORK / reuse existing expansion set | Regenerates expansions without corpus vocabulary; discards HyDE/dedup context |

**Totals (open):** 30 REWORK · 3 SQUASH (#48 #52 #60) · 3 SUPERSEDE (#58 #62 #63) · 5 CLOSE (#40 #45 #56 #65 #66) · 2 BLOCKED (#44 #54).

## 2. Recommended Actions by Category
*   **Closures (owner authorization required to close on GitHub):** #40, #45, #56, #65, #66 + all 22 historical closed PRs stay closed. No PR state was or will be changed without explicit authorization.
*   **Consolidations:** {#26+#46}, {#32+#50}, {#27+#55}, {#37+#41}, {#47+#49+#61}, {#48+#52+#60 squash set}.
*   **Clean reimplementations (never cherry-pick):** #58, #62, #63 (contaminated); #67 (validation-driven); all stale-base intents land re-derived on current main.
*   **Blocked:** #54 (SDK symbol absent), #44 (tokenizer fixtures required).
*   **Conflicts identified:** #29↔#38 (same test file path, different contents/imports), #30↔#43 (same UI insertion region), the three-way vector competition, the two-way schema-fix competition.
*   **Misleading titles/descriptions:** #51, #54, #57, #64, #65, #66, #67 (DEC-30).

## 3. Apple API Verification Status
*   `SystemLanguageModel.advanced`: **UNAVAILABLE_IN_INSTALLED_SDK / SPECULATIVE** (compile probe, independently reproduced).
*   `SystemLanguageModel`, `LanguageModelSession`, `GenerationOptions`, `Transcript`, `Instructions`, `Tool`, `PrivateCloudComputeLanguageModel`, Vision `RecognizeDocumentsRequest`: SDK_PRESENT / COMPILE_VERIFIED.
*   PCC entitlement `com.apple.developer.private-cloud-compute`: deliberately absent from entitlements; ENTITLEMENT_REQUIRED; unentitled device behavior UNVERIFIED → MAIN-2 / RISK-14.
*   Current-main defects found (not from any PR): **MAIN-1** route-telemetry misreport; **MAIN-2** `EntitlementChecker.hasEntitlement` fails open. Both need named Tier-2 authorization to fix.
*   PR-introduced API surface: CoreML `MLTensor`/`MLMultiArrayDataType` (#37/#41 — fixture-gated), Accelerate vDSP/CBLAS (#47/#49/#61 — benchmark-gated). No deprecated API introduced by any accepted intent.

## 4. Risk Summary (register: RISK-01…RISK-19)
*   **Retrieval quality:** no measured baseline exists; #53/#56/#59/#62/#63/#64/#68 all shift retrieval or scoring semantics — none may land before the golden benchmark (RAG_QUALITY_BASELINE).
*   **Citations:** #44 can shift byte-level citation offsets (RISK-18); citation-index tests (#29 intent) dead until test target restored.
*   **Storage/migration:** protected FTS5 boundary touched by 6 PRs with zero fixture coverage (RISK-19); #40 de-parameterization rejected.
*   **Tokenizer/embedding:** 384-dim contract unchanged by any accepted intent; #56 changes embedding inputs (closed unless benchmarked); BNNS persisted norms must survive any vector-math consolidation (#49).
*   **Privacy:** #66 closed; no query persistence introduced. PR #6 scope (no private material in public repo) — no new exposure found in audit artifacts.
*   **Process:** uncommitted prior-agent implementation work in tree (RISK-15); stale-base PRs (RISK-16); false contamination claims corrected (DEC-25).

## 5. Protected Files Requiring Named Authorization in Phase B
| File | Tier | Needed for |
| :-- | :-- | :-- |
| `OpenIntelligence.xcodeproj/project.pbxproj` (+ 2 schemes) | 1 | Test-target restoration (working tree already holds an uncommitted version) |
| `Package.swift` | 1 | Only if test target requires it |
| `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift` | 2 | #27/#55 supersession; optional #39/#42 |
| `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift` | 2 | Vector-math consolidation if the winner touches norms |
| `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift` | 2 | MAIN-1 fix |
| `OpenIntelligence/Core/Support/EngineSDKCompatibility.swift` | 2 | MAIN-2 fix |
| `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift` | 2 | #48/#60 squashes, #68 rework, needle-rescue region |

## 6. Proposed Implementation Clusters and Commit Sequence (Phase B, after `PROCEED: IMPLEMENT`)
1.  `test(openintelligence): restore layered regression coverage` — test target (Tier-1 auth); land consolidated #26/#46, #32/#50, #51 (+#36 expanded; #29/#38 intents via pure helpers). Gate: `xcodebuild test` exits 0.
2.  `fix(storage): harden fixed SQLite schema migrations` — closed migration-descriptor enum superseding #27/#55 (Tier-2 auth); fixture DB from current main committed with tests. Gate: storage battery green.
3.  `perf(vector): consolidate measured Accelerate implementation` — benchmark scalar vs overlay vs vDSP vs cBLAS (#47/#49/#61/#28); adopt winner only if rank-stable ≤1e-6 and faster on this Mac; device re-run OWNER_ACTION_REQUIRED.
4.  `fix/test: safe small fixes` — #31, #33 guard, #34, #35, #36, #53, #57, #67 reimplementation, #58 reimplementation; one commit per logical group with tests.
5.  `fix(apple-models): report actual model route and fail closed on unproven PCC entitlement` — MAIN-1 + MAIN-2 (Tier-2 auth, both files together). Gate: full build matrix clean; device validation OWNER_ACTION_REQUIRED.
6.  `fix(retrieval)/fix(compression)` — RAG reworks (#59, #62-intent, #63-intent, #64, #68; #56 only if benchmark proves value) — ONLY after the golden retrieval benchmark exists and baseline numbers are captured; otherwise remain unimplemented with OWNER_ACTION_REQUIRED.
7.  `chore(repo): remove generated PR artifacts` — ensured via clean reimplementation (never cherry-picking #37/#58/#62/#63).
8.  Deferred blocked: #44 and #37/#41 until real tokenizer/model fixtures exist. Do not fake fixtures.
Every commit: declared file allowlist in DECISION_LOG first; `git diff --name-only` must match exactly; unexpected file = stop condition.

## 7. Required Validation Inventory
*   **Tests:** layered suites (Layer 1 pure units incl. tokenizer/SQL/citation/launch-args; Layer 2 service fakes; Layer 3 simulator integration incl. migrations; Layer 4 device; Layer 5 performance).
*   **Benchmarks (unresolved):** RAG golden corpus + variance bounds; vector-math matrix incl. edge-case numerics; ingestion throughput (#39); query-classification latency (#53).
*   **Physical device (unresolved, OWNER_ACTION_REQUIRED):** Foundation Models routes + availability states; PCC unentitled behavior (MAIN-2); memory-warning eviction (#67); Metal/BNNS performance and energy/thermal.
*   **Entitlement (unresolved):** PCC entitlement absent by design; distribution-build fail-closed proof required.
*   **Storage battery (unresolved):** full matrix in STORAGE_MIGRATION_MATRIX.
*   **Strict-concurrency build:** not yet run; required before accepting any `nonisolated`/`@unchecked Sendable` from reworks (#57, #66-class patterns).

## 8. Working-Tree Reconciliation (owner decisions required)
Uncommitted prior-agent work performed under superseded AUTH-03/AUTH-04 (DEC-24, TE-15, RISK-15):
1.  `project.pbxproj` + schemes: OpenIntelligenceTests target — **adopt, re-derive, or discard?** (Tier-1; overlaps Phase B commit 1.)
2.  `LaunchArguments.swift`: byte-identical to PR #51 — adopt with #51's tests or revert to main pending Phase B?
3.  `SemanticChunker.swift`: 39-line NER-fallback behavior change with NO PR provenance — needs explicit owner accept/reject; currently unreviewed production drift.
4.  Untracked `OpenIntelligenceTests/` (9 suites): overlaps #26/#46, #32/#50, #51, plus 5 unrequested suites — fold into Phase B commit 1 or discard.
5.  `.gitignore` + `build_simulator_smoke.sh` (`.nosync` handling, DEC-07): benign tooling; recommend adopting in Phase B chore commit.
6.  `macosconsole.txt`, `GEMINI_REMEDIATION_DIRECTIVE.md`, `INDEPENDENT_VERIFICATION_REPORT.md` (untracked, repo root): archive or delete after Phase B — owner call; do not commit to production history.

## 9. Rollback Strategy
*   Phase A itself: nothing to roll back (no tracked file modified; `.agent/` is untracked).
*   Phase B: one logical cluster per commit on the audit branch; each commit lists its source PRs and file allowlist; rollback = revert the single cluster commit. Storage cluster additionally gated by the pre-change fixture DB so migration reversibility is testable. No force-pushes; `main` never pushed.

## 10. Remaining Owner Decisions
1.  Issue (or withhold) `PROCEED: IMPLEMENT` for Phase B.
2.  Per-file authorization for the Tier-1/Tier-2 list in §5.
3.  Working-tree items in §8 (esp. the un-provenanced SemanticChunker change).
4.  Authorize GitHub closures for #40, #45, #56, #65, #66 (and eventual supersession closures) — no PR state will be touched before that.
5.  Physical-device validation runs (Layer 4/5) — cannot be executed by the agent.
6.  Editorial correction of "local 20B" claims in Docs/What's-New (tied to MAIN-1).
7.  Whether a query-history feature (from #66's intent) should ever be designed, with retention/deletion/disclosure.

---
No test was executed beyond those recorded in TEST_EVIDENCE.md; no benchmark, device run, or entitlement probe is claimed that did not occur. Unverified items are labeled unresolved rather than rounded up.
