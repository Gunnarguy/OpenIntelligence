# OPENINTELLIGENCE INDEPENDENT VERIFICATION REPORT

Date: 2026-07-11
Auditor: Independent verification session (Claude, read-only)
Method: Every prior claim treated as unverified until corroborated by current code, git history, reproducible compiler output, installed SDK interfaces, or GitHub API state. No prior agent report was accepted on its own authority.

Repository path: `/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence`
Current branch: `audit/openintelligence-zero-regression-2026-07-10`
Current HEAD: `7eeee45c7aa2d9e6b8c545355c7f2239c7101b76`
origin/main: `7eeee45c7aa2d9e6b8c545355c7f2239c7101b76` (identical — 0 ahead / 0 behind; no implementation commits exist)
Working tree: clean except untracked `.agent/` and `macosconsole.txt` (13,889-line runtime console log, benign). `.simulator-smoke/` build output is gitignored.
Directive reviewed: `.agent/OPENINTELLIGENCE_AUDIT_DIRECTIVE.md` (2,307 lines, complete)
PR range reviewed: #1–#68 (67 real PRs; **#4 does not exist on GitHub** — confirmed via GitHub API, matches the prior agent's placeholder note)
Environment (independently confirmed): Xcode 27.0 (27A5194q), Swift 6.4, iPhoneSimulator 27.0 SDK, macOS 27 host

---

## EXECUTIVE VERDICT

**Overall status: SUBSTANTIALLY_INCOMPLETE**

The prior agent (self-identified "Antigravity AI Agent", per `.agent/AUTHORIZATION_LEDGER.md`) performed a **shallow but honest slice of Phase A only**. Phase B (implementation) was never started, and the read-only rules were respected. Every *concrete technical claim* the agent recorded checked out under independent reproduction. However, the top-line claim in `FINAL_REPORT_DRAFT.md` — "Audit Status: COMPLETE / covering all 68 Pull Requests" — is **CONTRADICTED by the agent's own manifest**, which leaves all 43 open PRs `UNREVIEWED` at `grep_verified` evidence level with every `overlaps_with`, `contradicts`, and `generated_artifacts` field empty.

Nothing was broken. Nothing was implemented. The audit is roughly 20–25% of Phase A.

---

## DIRECTIVE COMPLIANCE

### Verified
- **Read-only compliance: VERIFIED.** No tracked file was modified (`git status --porcelain` shows only untracked `.agent/`, `macosconsole.txt`). No commits exist on the audit branch (HEAD == origin/main). No destructive git commands are evidenced.
- **`PROCEED: IMPLEMENT` gate: VERIFIED respected.** No source edits occurred; `AUTHORIZATION_LEDGER.md` AUTH-03 correctly shows "WAITING FOR APPROVAL"; git history corroborates.
- **Protected files: VERIFIED untouched.** `FoundationModelSessionFactory.swift`, `FoundationModelRoutePolicy.swift`, `EngineSDKCompatibility.swift`, `SQLiteFullTextService.swift`, entitlements, `project.pbxproj`, StoreKit config — all unmodified vs origin/main.
- **GitHub state: VERIFIED unchanged.** 43 PRs still open (#26–#68), merged set {1,3,6}, closed set {2,5,7–25} — exactly matches the directive's topology. No merges, closures, or force-pushes since the manifest was generated (all 67 manifest `head_sha` values match live GitHub `headRefOid`s).
- **Audit branch: VERIFIED** — created from origin/main today 10:47 (reflog), zero divergence.
- **All 13 required `.agent` artifacts: VERIFIED present.**
- **PR refs: VERIFIED** — 67 refs under `refs/pull/*` as claimed in `DECISION_LOG.md` DEC-01.

### Partially verified
- **PR manifest**: all 68 entries exist with correct states/SHAs, but the directive-required analysis fields are unpopulated (see PR COVERAGE below).
- **Baseline build matrix**: only **one** build ran (Debug, iphonesimulator, ad-hoc signing). Release, macOS, oldest-simulator, device, package-test, and archive-equivalent builds from Phase A2 were never attempted.
- **Session-start protocol**: environment capture done; PR-state refresh done; but no review-comment processing, no warning inventory beyond one build.

### Violated (as claims, not as actions)
- `FINAL_REPORT_DRAFT.md` "Audit Status: COMPLETE" — **INCORRECT** (self-contradicted by manifest).
- Phase A completion outputs missing: no terminal dispositions for 43 open PRs, no measured RAG baseline, no measured performance baseline, no review-comment classification, no proposed implementation commits, no protected-file authorization list, no rollback strategy, and the required final line (`AUDIT COMPLETE… AWAITING: PROCEED: IMPLEMENT`) was never emitted.

### Unauthorized
- **None found.** No unauthorized source, GitHub, or release-metadata changes.

---

## PR COVERAGE

- **Fully verified by prior agent: 0 of 43 open PRs.** Manifest dispositions: 43 × `UNREVIEWED`, 22 × `CLOSE` (historical closed PRs), 3 × `KEEP` (historical merged). All 68 entries carry `evidence_level: grep_verified` only.
- **Incorrect manifest entries:**
  - Every `overlaps_with` and `contradicts` array is empty, despite independently confirmed duplicate/competing sets: **#26/#46** (both add `WorkspaceTierTests.swift`), **#32/#50** (both add `LLMModelTypeTests.swift`), **#37/#41** (same mask-type inference in `swift-transformers/Sources/Models/LanguageModel.swift`), **#47/#49/#61** (three competing rewrites of cosine similarity in `VectorDatabase.swift`), **#27/#55** (two competing edits to the same `ensureColumnExists` function).
  - Every `generated_artifacts` array is empty, despite contamination being visible in the agent's own diffstat summaries and confirmed by me (below).
  - **PR #66 `risk: low` is wrong** — it persists user queries in plaintext (privacy issue, see below).
  - Manifest (#54 `UNREVIEWED`) contradicts `FINAL_REPORT_DRAFT.md` (#54 "REJECTED") and `DECISION_LOG.md` DEC-02 ("REJECTED") — internal inconsistency; the decision log is right, the manifest was never updated.
- **Missing dispositions:** all 43 open PRs.
- **Duplicate/conflicting work: CONFIRMED** (sets listed above; independently diffed).
- **Contaminated PRs: CONFIRMED by actual patch inspection** (`git diff merge-base..refs/pull/N --name-only`):
  - **#37**: `pre_commit.sh`
  - **#58**: `fix.py`, `refactor.py`
  - **#62**: `plan.txt`
  - **#63**: `fix.py`, `test_compile.sh`
- **Empty or misleading PRs: CONFIRMED:**
  - **#65**: patch is exactly one line — `private struct ConsolidatedMetrics` → `struct ConsolidatedMetrics` in `ChatScreen.swift`. Its title claims it resolves a Swift compile error; the baseline build of main succeeds cleanly, so the premise is false. Classification: **CONTRADICTED** (title vs patch vs build reality). Disposition should be CLOSE.
  - **#66**: title says "Fix memory leak in query history"; the patch **introduces** query-history persistence to `UserDefaults` (key `OpenIntelligence.QueryHistory`, 300 entries × 200 chars) inside `expandQuery`, via an unstructured `Task { @MainActor … }`, making query expansion impure and write-reordering possible. User queries (potentially medical/legal/proprietary) stored in plaintext with no retention policy, deletion control, or disclosure. Classification: **CONTRADICTED description / privacy regression**. Disposition per directive: CLOSE.

---

## APPLE API VERIFICATION (independently reproduced)

- **Documented + SDK present:** `SystemLanguageModel`, `LanguageModelSession`, `GenerationOptions`, `Transcript`, `Instructions`, `Tool` — confirmed in `FoundationModels.swiftmodule/arm64-apple-ios-simulator.swiftinterface` (iPhoneSimulator27.0.sdk).
- **`PrivateCloudComputeLanguageModel`: VERIFIED SDK_PRESENT** — `final public class PrivateCloudComputeLanguageModel : Sendable` at swiftinterface line 45 (31 references).
- **`RecognizeDocumentsRequest`: VERIFIED SDK_PRESENT** in `Vision.swiftmodule` (13 references).
- **`SystemLanguageModel.advanced`: VERIFIED ABSENT.** I wrote and ran my own probe (`xcrun swiftc -typecheck`, target `arm64-apple-ios27.0-simulator`): `error: type 'SystemLanguageModel' has no member 'advanced'`, exit 1. Swiftinterface grep confirms no such member. The prior agent's identical probe result is **VERIFIED**, and its probe file exists at the claimed path. **PR #54 cannot compile under the installed SDK. Classification: SPECULATIVE / UNAVAILABLE_IN_INSTALLED_SDK. The rejection is correct.**
- **Entitlement blocked:** `OpenIntelligence/OpenIntelligence.entitlements` **contains no `com.apple.developer.private-cloud-compute` key** (verified by reading the file) — matches RISK-02.
- **Physical-device verified: NONE.** No device evidence was produced for any API. (`macosconsole.txt` incidentally shows the app running on a macOS device with Foundation Models available and no crash, but it is not directive-grade evidence.)
- **Incorrect availability gates / NEW FINDINGS ON CURRENT MAIN (not in the prior agent's report):**
  1. **`FoundationModelSessionFactory.swift:56–68` — `.onDeviceAdvanced` route misreports telemetry.** On iOS/macOS 27+, the code comment claims "native AFM 3 Core Advanced (20B)" but the code runs `SystemLanguageModel.default`, and `selectedRoute` is **not** downgraded (the iOS 26 fallback branch sets `selectedRoute = .onDevice`; the 27+ branch does not). Telemetry therefore reports an "advanced" route that does not exist. Repository docs and recent commits (`7eeee45` "local 20B RAM gating", `abd1e3b` "local 20B RAM gate fallback") **overstate actual support** — no 20B on-device model exists in the installed SDK.
  2. **`EngineSDKCompatibility.swift:204–214` — `EntitlementChecker.hasEntitlement` fails open.** When `embedded.mobileprovision` is absent it returns `true` ("App Store builds… assume it is present"). But the PCC entitlement was deliberately removed from the entitlements file, so an App Store/TestFlight build on iOS 27+ (and any macOS build, where the profile is named `embedded.provisionprofile` and the `mobileprovision` lookup always misses) will pass the guard at `FoundationModelSessionFactory.swift:86` and instantiate the **native** `FoundationModels.PrivateCloudComputeLanguageModel()` without the entitlement. The directive's requirement "the missing-entitlement path must not crash" is **UNVERIFIED for distribution builds** — the only runtime safety net is the subsequent `nativeModel.isAvailable` check, whose unentitled behavior has never been observed on a device.
  3. `#if compiler(>=6.4)` is used as an API-availability proxy in the PCC path (`FoundationModelSessionFactory.swift:84`) — the exact pattern the directive says to scrutinize. It happens to work under Xcode 27 but is fragile.
- **PCC local shim claim: VERIFIED.** `EngineSDKCompatibility.swift:156` defines a local `PrivateCloudComputeLanguageModel` struct with `isAvailable` hardcoded `true`, and `LanguageModelSession` convenience inits (lines 191–195) that route it to `SystemLanguageModel.default`. The prior agent's description of this shim is accurate.

---

## RAG QUALITY

- Baseline valid: **NO** — no benchmark was executed. `RAG_QUALITY_BASELINE.md` honestly states "No active evaluations run in this read-only phase"; its table is **target thresholds copied from `Docs/EVALS.md`**, not measured results. Directive Phase A1 item 8 ("Record the current RAG benchmark result set") was not fulfilled.
- Benchmark comparable: **NOT_APPLICABLE** (no baseline run, no post-change run, no changes).
- Critical regressions / citation regressions / retrieval regressions: **NONE POSSIBLE** — no retrieval code changed (HEAD == origin/main).
- Unsupported claims: the "zero-regression" framing anywhere in `.agent` is vacuously true (nothing changed) and must not be cited as evidence for future integration work.
- Remaining gaps: the entire RAG cluster (#53, #56, #57, #59, #60, #62, #63, #64, #68) is unevaluated; no golden corpus, no variance bounds, no noninferiority margins exist.

## STORAGE

- Migration safety: **UNVERIFIED** — no legacy fixtures were located or tested. `STORAGE_MIGRATION_MATRIX.md` is a code-derived inventory (accurate as far as it goes), not test evidence.
- Legacy fixture coverage: **NONE.**
- FTS compatibility / vector compatibility / Evidence Thread compatibility / iCloud compatibility / entitlement compatibility: **UNVERIFIED** (nothing changed, so nothing regressed; but the mandatory storage test battery from the directive does not exist).
- Note: both open SQL-injection PRs (#27, #55) modify the same function with different strategies, and **both leave the `definition` parameter interpolated raw** — the directive's observation that identifier escaping alone doesn't make arbitrary column definitions safe is confirmed in the actual patches.

## MODEL AND TOKENIZER

- Fixture quality: **NONE EXIST** — no tokenizer or Core ML fixtures were created; PRs #37/#41/#44 remain unevaluated beyond diffstats.
- Tokenizer equivalence / Core ML descriptor correctness / generation parity: **UNVERIFIED.**
- Embedding compatibility: 384-dim contract documented (`MODEL_TOKENIZER_COMPATIBILITY_MATRIX.md` matches code-level constants); no PR currently changes it.
- Reindex requirement: none triggered (no changes merged).

## CONCURRENCY

- Strict-concurrency result: **NOT RUN** — no strict-concurrency build was performed against HEAD.
- Unsafe annotations: not audited by prior agent. PR #66 (confirmed) adds `nonisolated` to `classifyIntent`/`expandQuery` plus an unstructured `Task` — exactly the pattern the directive flags; unevaluated beyond my patch reading.
- Cancellation / stale-task / actor-isolation issues: **UNVERIFIED** (PR #63's concurrency changes to `HybridSearchService` unevaluated).

## PROTECTED BOUNDARIES

- Authorized changes: none requested, none made.
- Unauthorized changes: **NONE** (verified via git).
- Insufficient validation: not applicable this session; note that the eventual integration will require named authorization for `FoundationModelSessionFactory.swift`, `FoundationModelRoutePolicy.swift`, `EngineSDKCompatibility.swift`, `SQLiteFullTextService.swift`, and `project.pbxproj`/`Package.swift` (test-target restoration).

## TEST CREDIBILITY

- Verified runs: **1 of 1 claimed.** TE-01 (simulator smoke build) is genuine: `.simulator-smoke/xcodebuild.log` (498 KB, mtime 10:58 today) ends `** BUILD SUCCEEDED **`; zero ` warning:` diagnostics (I counted); the build script `scripts/build_simulator_smoke.sh` is a pre-existing tracked file. Caveats: Debug-only, simulator-only, ad-hoc signing, SwiftPM dependencies compiled with `-suppress-warnings` (Xcode default), so "0 warnings" strictly covers first-party code in one configuration.
- TE-02 (PR #54 probe): **verified — independently reproduced with identical result.**
- Stale runs: none (all evidence generated today against current HEAD).
- Unexecuted tests: all test-addition PRs (#26, #32, #46, #50, #29, #30, #36, #38, #43, #51) add XCTest files, but the project has **no test target** (removed by merged PR #3, per RISK-03 — consistent with repo state). Any merged test file would be dead code until the target is restored.
- Mock-only tests: not applicable yet.
- Device evidence missing: **all of it** — Foundation Models runtime, PCC entitlement behavior, Metal/BNNS performance, Vision document recognition.

## GENERATED ARTIFACTS
- Tracked tree: **CLEAN** — `git ls-files` scan found no `*.orig`, `*.rej`, `*.patch`, `plan.txt`, `commit_message.txt`, `fix.py`, `refactor.py`, `test_compile.sh`, `pre_commit.sh`, or submission scripts.
- PR branches: contamination confirmed in #37, #58, #62, #63 (listed above under PR COVERAGE).

## UNEXPECTED FILES
- `macosconsole.txt` (untracked, repo root): 13,889-line runtime console capture from a physical macOS run of v4.5.1 build 150. Benign, useful as informal runtime evidence, but unexplained by any `.agent` artifact and should not be committed.
- `.agent/` (untracked): expected per directive; never committed to the audit branch (permitted but not required).

## FALSE OR OVERSTATED CLAIMS
1. `FINAL_REPORT_DRAFT.md`: "Audit Status: COMPLETE" — **false**; 43/43 open PRs unreviewed in the agent's own manifest.
2. `FINAL_REPORT_DRAFT.md`: "covering all 68 Pull Requests… performance limits" — enumeration ≠ audit; no performance measurement occurred.
3. `PERFORMANCE_BASELINE.md`: "App Launch Time: Within nominal platform limits (~500ms)" — no measurement evidence; `doc_claim_only` presented in a "Baseline Measurements" section.
4. Several `[evidence_level: code_verified]` tags on doc-derived statements (e.g., RAG target thresholds sourced from `Docs/EVALS.md`) — mislabeled; should be `doc_claim_only` / `artifact_derived`.
5. Current main documentation/commits claiming "local 20B" model support (`7eeee45`, `abd1e3b`, Atlas/What's-New docs) — overstated relative to the installed SDK, which exposes no advanced/20B on-device model.

## STOP-SHIP FINDINGS (for any future integration)
1. **PR #54 must never merge as-is** — uses a nonexistent SDK symbol; breaks compilation. (CONFIRMED)
2. **PR #66 must not merge** — plaintext query-history persistence without product requirement, retention policy, deletion path, or disclosure; misleading title. (CONFIRMED)
3. **`EntitlementChecker.hasEntitlement` fail-open** (`EngineSDKCompatibility.swift:204`) combined with the removed PCC entitlement means distribution builds on OS 27+ may instantiate native PCC unentitled — must be proven safe on a device or fixed before any App Store release built with Xcode 27. (NEW, CONFIRMED in code; runtime behavior UNVERIFIED)
4. **`.onDeviceAdvanced` telemetry misreport** (`FoundationModelSessionFactory.swift:56–68`) — route telemetry claims a model tier that doesn't exist; docs overstate. (NEW, CONFIRMED)
5. Contaminated branches #37, #58, #62, #63 must be reimplemented cleanly, never cherry-picked. (CONFIRMED)

## REQUIRED CORRECTIVE ACTIONS
See companion document `GEMINI_REMEDIATION_DIRECTIVE.md` (repo root), which converts these findings into an ordered, evidence-gated work plan: complete the 43 terminal dispositions, run the missing baseline matrix, execute the storage/tokenizer/RAG evidence work, fix the two current-main findings (telemetry misreport; entitlement fail-open) after named authorization, and only then integrate approved clusters one commit at a time.

## OWNER DECISION
**BLOCK** — the directive's Phase A is substantially incomplete and Phase B never began; no integration, merge, or release action should proceed from the current `.agent` evidence. The prior agent's concrete technical findings (PR #54 rejection, PCC shim behavior, environment records, baseline build) are sound and may be **retained as verified inputs** to the remediation pass.

---

OPENINTELLIGENCE INDEPENDENT VERIFICATION COMPLETE.
NO SOURCE CODE OR GITHUB STATE WAS MODIFIED.
