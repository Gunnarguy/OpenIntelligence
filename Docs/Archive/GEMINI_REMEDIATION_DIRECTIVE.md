# OPENINTELLIGENCE REMEDIATION AND INTEGRATION DIRECTIVE (FOR GEMINI)

You are the implementation engineer for the repository `Gunnarguy/OpenIntelligence` at
`/Users/gunnarhostetler/Documents/GitHub/OpenIntelligence`.

Your job is to FINISH the audit that was started under `.agent/OPENINTELLIGENCE_AUDIT_DIRECTIVE.md`, then implement the approved work — exactly as written here. An independent verification pass (see `INDEPENDENT_VERIFICATION_REPORT.md` in the repo root) has already validated some facts and invalidated others. **Do not re-litigate settled facts. Do not skip stop gates. Do not improvise.**

---

## 0. HARD RULES — READ FIRST, APPLY ALWAYS

1. Work only on branch `audit/openintelligence-zero-regression-2026-07-10`. Never push to `main`. Never force-push.
2. NEVER run: `git reset --hard`, `git clean`, `rm -rf`, `git checkout -- .`, `git restore .`.
3. NEVER merge, close, reopen, comment on, or re-label any GitHub PR. Local work only.
4. NEVER edit these protected files without a line in `.agent/AUTHORIZATION_LEDGER.md` naming the file and quoting the owner's authorization message:
   - `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift`
   - `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelRoutePolicy.swift`
   - `OpenIntelligence/Core/Support/EngineSDKCompatibility.swift`
   - `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift`
   - `OpenIntelligence/OpenIntelligence.entitlements`
   - `OpenIntelligence.xcodeproj/project.pbxproj`, any `Package.swift`
5. NEVER claim a test ran unless you paste its exact command, exit code, and the last 20 lines of raw output into `.agent/TEST_EVIDENCE.md`.
6. NEVER mark anything `physical_device_verified`. You cannot run devices. Write `OWNER_ACTION_REQUIRED` instead and list the exact steps the owner must perform.
7. Every commit: run `git diff --name-only` first; if ANY file outside the commit's declared allowlist appears, STOP, unstage nothing, and report.
8. If a step fails or an instruction is ambiguous: STOP that work item, record the failure verbatim in `.agent/DECISION_LOG.md`, and move to the next independent item. Do not guess.

## 1. SETTLED FACTS — DO NOT REDERIVE, DO NOT CONTRADICT

These were verified independently on 2026-07-11 against Xcode 27.0 (27A5194q) / Swift 6.4 / iOS 27.0 SDK:

- `SystemLanguageModel.advanced` DOES NOT EXIST in the installed SDK. Compile probe fails. **PR #54 can never merge as-is.**
- `PrivateCloudComputeLanguageModel` and Vision's `RecognizeDocumentsRequest` DO exist in the SDK.
- The entitlements file contains NO `com.apple.developer.private-cloud-compute` key.
- `origin/main` (`7eeee45c…`) builds clean: Debug, iphonesimulator, 0 warnings, 0 errors.
- PR branch contamination (confirmed in the actual patches): #37 has `pre_commit.sh`; #58 has `fix.py`, `refactor.py`; #62 has `plan.txt`; #63 has `fix.py`, `test_compile.sh`.
- Duplicate/competing sets (confirmed): {#26, #46}, {#32, #50}, {#37, #41}, {#47, #49, #61}, {#27, #55}.
- PR #65's entire patch is `private struct ConsolidatedMetrics` → `struct ConsolidatedMetrics` in `ChatScreen.swift`; its stated premise (compile error) is false.
- PR #66 adds plaintext query-history persistence to `UserDefaults` inside `expandQuery` — a privacy regression mislabeled as a memory-leak fix.
- Two defects exist on CURRENT MAIN (not from any PR):
  - **MAIN-1:** `FoundationModelSessionFactory.swift` lines ~56–68: the `.onDeviceAdvanced` case on OS 27+ runs `SystemLanguageModel.default` but does not set `selectedRoute = .onDevice`, so telemetry reports a nonexistent "advanced" model. The comment claiming a "20B" model is false.
  - **MAIN-2:** `EngineSDKCompatibility.swift` lines ~204–214: `EntitlementChecker.hasEntitlement` returns `true` when no embedded provisioning profile is found (App Store builds, and all macOS builds where the profile is `embedded.provisionprofile`). Because the PCC entitlement was removed, distribution builds on OS 27+ can instantiate native `PrivateCloudComputeLanguageModel()` unentitled.

## 2. PHASE 1 — FINISH THE AUDIT (NO SOURCE EDITS)

### 2.1 Session start (every session)
```bash
git status --short --branch && git fetch --all --prune && git rev-parse HEAD origin/main
gh pr list --state open --json number,headRefOid --limit 60
```
If any open PR's `headRefOid` differs from `.agent/pr_manifest.json`, update that manifest entry and note it in `.agent/DECISION_LOG.md` before anything else.

### 2.2 Complete `.agent/pr_manifest.json`
For every open PR, set `audit_disposition` from the table in §3, and populate `overlaps_with`, `contradicts`, and `generated_artifacts` using the settled facts in §1. You may inspect patches with:
```bash
git diff $(git merge-base main refs/pull/N)..refs/pull/N
```
Updating `.agent/*` files is authorized. Modifying anything else is not (yet).

### 2.3 Complete the baseline build matrix
Run and record (command, exit code, duration, warnings) in `.agent/TEST_EVIDENCE.md`:
1. iOS Simulator **Release** build.
2. **macOS** (Catalyst or native, whichever the project supports) Debug build.
3. If either fails: record the failure verbatim; do NOT fix anything; continue.

### 2.4 Review comments
For PRs #26–#68: `gh pr view N --comments`. Classify each substantive comment as ACTIONABLE / OUTDATED / INCORRECT / STYLE_ONLY / SUMMARY_ONLY in a new file `.agent/REVIEW_COMMENT_LEDGER.md`. Generated reviewers (Sourcery, Copilot, Jules) never outrank code evidence.

### 2.5 STOP GATE
Update `.agent/FINAL_REPORT_DRAFT.md` with honest status (it currently overstates completion — fix that), then output exactly:
```
AUDIT COMPLETE. SOURCE CODE HAS NOT BEEN MODIFIED.
AWAITING: PROCEED: IMPLEMENT
```
Do not proceed to §4 until the owner replies exactly `PROCEED: IMPLEMENT`.

## 3. TERMINAL DISPOSITIONS (PRE-APPROVED — copy into the manifest)

| PR | Disposition | Rule |
|----|-------------|------|
| #26 + #46 | CONSOLIDATE | Merge into ONE `WorkspaceTierTests.swift`. Tests are dead until the test target exists (§4.1). |
| #27 + #55 | CONSOLIDATE_AND_REIMPLEMENT | Write one clean fix: identifier allowlist regex AND quoting, plus treat `definition` as a closed enum of known column definitions — never raw interpolation. Do not cherry-pick either branch. |
| #28 | REWORK | Unify with the vector policy chosen in §4.3. |
| #29, #38 | REWORK | No visibility widening just for tests; extract a pure helper instead. |
| #30, #43 | REWORK | Move validation logic out of diagnostic UI into the restored test target. |
| #31 | KEEP_AFTER_TESTS | Must prove: empty input, NaN/∞, prefix-limit semantics, identical UI output. |
| #32 + #50 | CONSOLIDATE | One `LLMModelTypeTests.swift`. |
| #33 | SPLIT | Keep division-by-zero guard if reproducible; drop allocation "optimization" unless natively benchmarked. |
| #34 | REWORK | Horizontal-rule parsing: prove equivalence for tabs, mixed markers, >3 markers, embedded text. |
| #35 | REWORK | Prove variance semantics, overflow, empty input. |
| #36 | REWORK | Test every threshold boundary. |
| #37 + #41 | CONSOLIDATE_REIMPLEMENT | Contaminated (`pre_commit.sh`). Reimplement mask-dtype inference cleanly; must handle ALL `MLMultiArrayDataType` cases from real model descriptors, not just float32/float16. |
| #39 | REWORK_THEN_BENCHMARK | Prepared-statement reuse only with full `sqlite3_step`/reset/bind error handling + rollback on row failure. |
| #40 | CLOSE | Replaces bound parameters with interpolated SQL. Never acceptable. |
| #42 | VERIFY_OR_CLOSE | Keep only if `sqlite3_changes()` semantics match the intended count under triggers/cascades. |
| #44 | BLOCKED_PENDING_FIXTURES | Tokenizer byte-fallback change needs real fixture round-trip tests (ASCII, emoji, CJK, combining marks) before any decision. |
| #45 | CLOSE | Unrolling two statements: no measurable benefit. |
| #47 + #49 + #61 | CONSOLIDATE_AND_REIMPLEMENT | See §4.3. Do NOT stack; do NOT pick one blindly. |
| #48, #52, #60 | SQUASH | Comment/naming churn: fold into related logical commits only if still accurate. |
| #51 | KEEP_AFTER_TESTS | Launch-arg parsing: test the full edge matrix (dup flags, `--key=value`, missing value, `--`). |
| #53 | REWORK | Regex must escape literals; test multiword/hyphen/Unicode/plural cases. |
| #54 | CLOSE | Settled: symbol absent from SDK. Related main fix is MAIN-1 (§4.5). |
| #56 | CLOSE_UNLESS_BENCHMARKED | Separator change needs paired retrieval benchmark evidence; without it, close. |
| #57 | REWORK | Regex caching: no `try!`, no unjustified `@unchecked Sendable`, prove extraction equivalence. |
| #58 | SUPERSEDE | Contaminated. Reimplement the small UTType refactor by hand if still useful. |
| #59 | REWORK | qualityScore needs a defined composite metric, not raw word-count ratio. |
| #62 | SUPERSEDE | Contaminated + hard-zero heuristic falsely rejects prose/material/color spec answers. Requires labeled eval set first. |
| #63 | SUPERSEDE | Contaminated + removes vector-confidence-based recall sizing and changes failure/cancellation semantics. Reimplement only with benchmark proof. |
| #64 | REWORK | Compression fallback must use the same normalized lexical policy as retrieval; test stopwords/stemming/CJK/negation. |
| #65 | CLOSE | Settled: unrelated one-line patch, false premise. |
| #66 | CLOSE | Settled: privacy regression. A query-history FEATURE may only be designed later with explicit owner approval, retention policy, and deletion UI. |
| #67 | KEEP_INTENT_REIMPLEMENT | Reimplement observer-capture fix by hand; verify token removal, no retain cycle, deinit safety. |
| #68 | REWORK | Reuse the existing expansion set (corpus vocabulary, HyDE decisions, dedup, order); never regenerate from the raw query; measure added embedding calls. |

## 4. PHASE 2 — IMPLEMENTATION (only after `PROCEED: IMPLEMENT`)

Implement in THIS order. One cluster = one commit. Before each commit: declare the file allowlist in `.agent/DECISION_LOG.md`, then verify `git diff --name-only` matches it exactly.

### 4.1 Restore the test target (FIRST — everything else depends on it)
Request named authorization for `project.pbxproj` / `Package.swift`. Add a unit-test target. Land the consolidated #26/#46 and #32/#50 suites plus #51's parser tests in it. Commit: `test(openintelligence): restore layered regression coverage`.
Gate: `xcodebuild test` (simulator destination) exits 0; paste output.

### 4.2 Storage cluster (#27/#55 reimplementation; optionally #39, #42)
Request authorization for `SQLiteFullTextService.swift`. Implement the consolidated migration-safety fix from §3. Add migration tests using a fixture database generated from current main BEFORE your change (create the fixture first, commit it with the tests). Commit: `fix(storage): harden fixed SQLite schema migrations`.
Gate: repeated + interrupted migration tests pass; row counts identical; FTS query results identical.

### 4.3 Vector cluster (#47/#49/#61 + #28)
Write a benchmark (in the test target, not the app) comparing scalar vs Accelerate-overlay vs vDSP vs cBLAS for 384-dim cosine similarity, including: empty, zero, NaN, ±∞, mismatched dims, ranking + tie equivalence vs the current scalar implementation. Pick the winner ONLY if it is numerically equivalent (tolerance ≤ 1e-6 rank-stable) and faster in YOUR measured run on this Mac; otherwise keep scalar. Simulator/Mac numbers are provisional: record `OWNER_ACTION_REQUIRED: re-run benchmark on physical iPhone before release`. Commit: `perf(vector): consolidate measured Accelerate implementation`.

### 4.4 Safe small fixes (#31, #33-guard, #34, #35, #36, #51, #53, #57, #67 reimplementation)
Each with its tests, each within its allowlist. One commit per logical group.

### 4.5 MAIN-1 and MAIN-2 (protected; request named authorization for both files together)
- MAIN-1 (`FoundationModelSessionFactory.swift`): in the `.onDeviceAdvanced` OS-27+ branch, set `selectedRoute = .onDevice` and correct the comment (no 20B model exists). Do not change any other behavior.
- MAIN-2 (`EngineSDKCompatibility.swift`): make `hasEntitlement` fail CLOSED when no profile is found, OR check for macOS `embedded.provisionprofile` as well — and gate on a compile-time flag the owner approves. The PCC route must throw `LLMError.modelUnavailable` (existing behavior) whenever entitlement presence cannot be proven.
- Also flag for the owner: `Docs` and What's-New claims about "local 20B" support are overstated and need editorial correction (owner decision, not yours).
Commit: `fix(apple-models): report actual model route and fail closed on unproven PCC entitlement`.
Gate: full build matrix from §2.3 still clean; paste output.

### 4.6 RAG cluster (#53 done above; #56, #59, #62, #63, #64, #68 reworks)
Do NOT implement any RAG semantic change unless you first build and run a golden retrieval benchmark (fixed corpus + query set committed under `Benchmarks/`), capture baseline numbers on current code, and show your rework is non-inferior. If you cannot run the benchmark end-to-end, record `OWNER_ACTION_REQUIRED` and leave the rework unimplemented. Aggregate metrics alone are insufficient — list every individual case that changed.

### 4.7 Deferred
#37/#41 (mask dtype) and #44 (byte fallback) stay BLOCKED until real model/tokenizer fixtures exist. Do not fake fixtures.

## 5. FINAL VALIDATION AND REPORT

After all commits: rerun §2.3 builds + full test suite, update every `.agent` artifact, and produce the final report in the exact format of `.agent/OPENINTELLIGENCE_AUDIT_DIRECTIVE.md` § "Required final report". Every claim must carry `evidence_level` and cite a command or file. Anything you could not verify gets `UNVERIFIED` — never round up.

Then STOP and await owner review. Do not create the consolidation PR without explicit authorization.

## 6. WHAT SUCCESS LOOKS LIKE

- All 43 open PRs have terminal dispositions recorded in the manifest with populated overlap/contamination fields.
- Test target restored and green.
- Storage, vector, and small-fix clusters landed as clean commits with tests and allowlists.
- MAIN-1 and MAIN-2 fixed under authorization.
- No contaminated branch was cherry-picked. No generated artifact (`fix.py`, `plan.txt`, `pre_commit.sh`, `test_compile.sh`, `refactor.py`, `commit_message.txt`) exists anywhere in the tree.
- Every unproven claim is labeled `UNVERIFIED` or `OWNER_ACTION_REQUIRED`.
- `main` was never pushed to; no PR was merged, closed, or commented on.
