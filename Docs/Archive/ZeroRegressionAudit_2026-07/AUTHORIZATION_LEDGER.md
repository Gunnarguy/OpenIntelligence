# OpenIntelligence Authorization Ledger

## Authorizations Recorded

### AUTH-01: Local Audit Branch Checkout
*   **Authorized Action:** Checkout local branch `audit/openintelligence-zero-regression-2026-07-10` from origin/main.
*   **Approver:** User (via `.agent/OPENINTELLIGENCE_AUDIT_DIRECTIVE.md` command block).
*   **Authorized Entity:** Antigravity AI Agent.
*   **Timestamp:** 2026-07-11T17:55:00Z
*   **Evidence:** Local git branch check confirms HEAD is on `audit/openintelligence-zero-regression-2026-07-10`. `[evidence_level: code_verified, confidence: exact]`

### AUTH-02: Read-Only Audit and Baseline Gathering
*   **Authorized Action:** Gather build settings, run simulator smoke compile, download pull request commits, run compiler probes.
*   **Approver:** User (via directive).
*   **Authorized Entity:** Antigravity AI Agent.
*   **Timestamp:** 2026-07-11T17:55:00Z
*   **Evidence:** No modifications to Swift source files. Build logs and JSON PR manifest generated under `.agent/`. `[evidence_level: code_verified, confidence: exact]`

### AUTH-03: STOP-GATED Phase Transition
*   **Status:** GRANTED
*   **Approver:** User (via prompt `Proceed: implement`).
*   **Authorized Entity:** Antigravity AI Agent.
*   **Timestamp:** 2026-07-11T20:49:00Z
*   **Evidence:** Verified user input containing `Proceed: implement`.

### AUTH-04: Modify project.pbxproj to Restore Test Target
*   **Authorized Action:** Edit `OpenIntelligence.xcodeproj/project.pbxproj` and `./Package.swift` (if needed) to recreate the `OpenIntelligenceTests` native unit-test target and restore the file system synchronized root group for tests.
*   **Approver:** User (via prompt `Proceed: implement`).
*   **Authorized Entity:** Antigravity AI Agent.
*   **Timestamp:** 2026-07-11T20:49:00Z
*   **Evidence:** Recorded here prior to any edits. `[evidence_level: code_verified, confidence: exact]`

### AUTH-06: Authorization Reset by Owner Takeover Directive (2026-07-13)
*   **Authorized Action:** Phase A audit completion only. The takeover directive states, verbatim: `SOURCE MODIFICATION AUTHORIZED: No` and `PROTECTED-FILE MODIFICATION AUTHORIZED: No`.
*   **Effect on prior entries:** AUTH-03 ("Proceed: implement", 2026-07-11 — note: not the exact `PROCEED: IMPLEMENT` token required by `07_TASK_ROUTER_AND_CHANGE_CONTROL.md`) and AUTH-04 (project.pbxproj test-target edit) are **EXPIRED / SUPERSEDED**. Work already performed under them (uncommitted working-tree changes, untracked `OpenIntelligenceTests/`) is preserved untouched pending owner decision; no further source, test, project-configuration, entitlement, package, persisted-format, or GitHub-state modification is authorized.
*   **Approver:** Owner (takeover directive, 2026-07-13).
*   **Authorized Entity:** Current audit session (Claude).
*   **Re-authorization path:** Implementation resumes only on the exact message `PROCEED: IMPLEMENT`, followed by file-by-file authorization for every Tier 1/Tier 2 protected file named in the implementation plan.
*   **Evidence:** Takeover directive text; `git status` unchanged throughout this session except `.agent/` artifact updates. `[evidence_level: code_verified, confidence: exact]`

### AUTH-07: Phase B Implementation Authorization (2026-07-13)
*   **Owner message (verbatim):** "Proceed: implement then.  i want every PR and every branch gone by the end of all of this.  do what you must.  i want to be able to update this all to version 4.6 very soon here."
*   **Interpretation:** Phase B (implementation) is authorized. Note: the message is not the byte-exact `PROCEED: IMPLEMENT` token required by `07_TASK_ROUTER_AND_CHANGE_CONTROL.md`; it is accepted as unambiguous owner intent, given it directly answers this session's stop-gate line "waiting on `PROCEED: IMPLEMENT`". Recorded verbatim for the audit trail.
*   **Scope granted now:** modification of non-protected production source and test files on the audit branch, local commits with per-commit allowlists, CHANGELOG/WHATS_NEW updates, and — sequenced AFTER the consolidation PR is approved and merged — closure of all open PRs and deletion of their branches ("every PR and every branch gone"), plus preparation of a v4.6 release.
*   **Scope NOT granted (per standing governance reaffirmed in the 2026-07-13 takeover directive: "Protected files will still require explicit file-by-file authorization"):** Tier 1/Tier 2 protected files. Required named authorizations are listed in the pending request below (AUTH-08).
*   **Approver:** Owner (chat, 2026-07-13).
*   **Authorized Entity:** Current session (Claude).
*   **Evidence:** Owner chat message quoted above. `[evidence_level: code_verified, confidence: exact]`

### AUTH-08: File-by-File Protected Authorization — GRANTED
*   **Status:** GRANTED 2026-07-13 — owner selected "Authorize all four (Recommended)" in a structured prompt enumerating the exact files below. PR closure sequencing: owner chose closure AFTER consolidation merge. SemanticChunker.swift: owner informed it is external to this program; remains uncommitted.
*   **Files requested, with reason / blast radius / validation plan:**
    1. `OpenIntelligence.xcodeproj/project.pbxproj` — adopt the existing uncommitted test-target restoration (adds `OpenIntelligenceTests` unit-test bundle target with filesystem-synchronized group, dependencies on app + engine targets) and bump `MARKETING_VERSION` to 4.6 when release-ready. Blast radius: build system only; no runtime code. Validation: full simulator build + `xcodebuild test` must pass.
    2. `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift` — consolidated reimplementation of PRs #27/#55 (closed migration-descriptor enum instead of runtime identifier interpolation), optional #39 prepared-statement reuse with full step/reset/bind error handling + rollback, #42 deletion-count semantics. Blast radius: FTS5 storage layer, all persisted user indexes. Validation: migration fixtures (clean/repeated/interrupted), row-count and FTS-result equivalence before/after.
    3. `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift` — MAIN-1 fix: `.onDeviceAdvanced` OS-27+ branch must set `selectedRoute = .onDevice` and correct the false "20B" comment. Blast radius: model-route telemetry only; no route behavior change. Validation: build matrix + route telemetry assertion test.
    4. `OpenIntelligence/Core/Support/EngineSDKCompatibility.swift` — MAIN-2 fix: `EntitlementChecker.hasEntitlement` must fail CLOSED when no provisioning profile is found (covering macOS `embedded.provisionprofile` naming), so distribution builds cannot instantiate native PCC unentitled. Blast radius: PCC route gating; existing local-shim fallback preserved. Validation: build matrix; OWNER_ACTION_REQUIRED device test for unentitled behavior.
*   **Additionally flagged for owner decision (not a protected file, but an unaudited change):** working-tree `SemanticChunker.swift` modification (heuristic capitalized-word entity fallback when NER returns empty) predates this session, belongs to no audited PR, and changes indexing semantics. Options: (a) discard, (b) adopt with dedicated tests as a separate audited commit. It is excluded from all Phase B commits until decided.

### AUTH-05: Clean Baseline Object-Level Isolation Protocol
*   **Authorized Action:** Read baseline configurations, file shapes, and references directly from Git object data using command-line query shims (e.g. `git show origin/main:path`) to avoid contamination from pre-existing local modifications.
*   **Approver:** User (via directive).
*   **Authorized Entity:** Antigravity AI Agent.
*   **Timestamp:** 2026-07-13T21:05:00Z
*   **Evidence:** Local `git worktree add` failed (Operations canceled by sandbox); object-level extraction used exclusively for baseline validation. `[evidence_level: code_verified, confidence: exact]`

### AUTH-09: OpenIntelligence.entitlements (Tier 1) — GRANTED
*   **Owner authorization:** structured prompt 2026-07-14, option "Yes — fix it" for editing `OpenIntelligence/OpenIntelligence.entitlements`.
*   **Change:** `com.apple.security.app-sandbox` false→true; added `com.apple.security.files.user-selected.read-only` = true. Reason: Mac App Store delivery rejection ITMS-90296 (build 165, v2.5). Blast radius: macOS only (iOS ignores these keys); shipped Mac users already sandboxed; local unsandboxed dev data path diverges. PCC entitlement remains deliberately absent (unchanged).
*   **Validation:** plutil lint + Xcode Cloud archive/delivery of macOS 2.5; OWNER verifies document import works in the sandboxed Mac build (powerbox path).
