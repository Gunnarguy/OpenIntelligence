# Decisions

Decisions whose rationale cannot be reconstructed by reading the code. Append; do not rewrite. When
a decision is replaced, leave it and add a superseded-by line.

Note on dating: the public repository's git history is squashed into snapshots, so a first-touch
commit date is not a creation date. Dates below cite the artifact that carries them.

---

## 2026-07-01 — Route every task through a RepoOS governance layer

**Context.** Roughly 270 Swift components across 30 subsystems, several of which break silently
rather than loudly: model routing, entitlements, sync, index formats. Agents were making
defensible-on-their-merits edits in places where a compile-clean change can still cost users data or
money.

**Decision.** `Docs/RepoOS/` plus `Docs/AuditArtifacts/RepoOS/change_impact_matrix.csv` define a
route per task type, each binding a set of read-first docs, allowed and forbidden edit paths,
required tests, and required doc updates. A deterministic preflight script reports the matched route.
Fifteen named files are hard-boundary and need the user to name the file in their approval. No source
edit happens before an explicit `PROCEED: IMPLEMENT`.

**Alternatives.** Trust agent judgment per task; a single global "be careful" instruction. Both were
in effect and both failed, most recently when an agent edited `FoundationModelRoutePolicy.swift` to
add a log line without authorization on 2026-08-07.

**Consequences.** Every task pays a routing cost. The gate is the point: the changes that need it
look small on their merits, which is exactly why judgment alone does not catch them.

`[evidence_source: Docs/RepoOS/00_REPO_COMMAND_CENTER.md header "Generated 2026-07-01", .agents/rules/00-repoos-routing.md]`

---

## 2026-07-28 — Keep the git object store out of iCloud with a `.git.nosync` pointer

**Context.** The repository lives in iCloud-synced `~/Documents`. iCloud corrupted the object store:
four conflict copies of `.git/index` and a duplicate branch ref, found 2026-07-28. Finder metadata
inside `.git/refs` also made `git fsck` fail.

**Decision.** `.git` is a file containing `gitdir: .git.nosync`. The `.nosync` suffix excludes the
directory from iCloud sync. Git works normally through the pointer.

**Alternatives.** Move the repository out of `~/Documents`, which is the real fix and remains open.
Disable iCloud Desktop & Documents sync, which affects the whole machine.

**Consequences.** Anything that recreates a plain `.git` directory re-exposes the repository to
corruption. Do not "fix" `.git` being a file. The broader iCloud problem is still live: conflict
copies named `Foo 2.swift` are compiled for real by Xcode's synchronized file groups, and iCloud
extended attributes break `codesign`.

**Superseded by:** nothing yet. Moving the repository out of `~/Documents` would supersede this.

`[evidence_source: scripts/check_icloud_conflicts.sh header, AGENTS.md, .agent/RISK_REGISTER.md RISK-20]`

---

## 2026-07-28 — Build with DerivedData outside iCloud sync, then codesign in `/tmp`

**Context.** Build inputs from the working tree carry `com.apple.FinderInfo` and
`com.apple.fileprovider.fpfs#P` extended attributes. `codesign` rejects them with "resource fork,
Finder information, or similar detritus not allowed", pointing at the swift-tokenizers and
swift-transformers bundles.

**Decision.** `scripts/build_simulator_smoke.sh` writes DerivedData to `.simulator-smoke.nosync/`,
then copies the built `.app` to `/tmp`, runs `xattr -cr`, ad-hoc signs it there, and copies it back.
Direct `xcodebuild test` invocations pass `-derivedDataPath` under `/private/tmp`.

**Consequences.** The smoke script is the reliable path and runs the iCloud conflict check first. A
hand-rolled `xcodebuild` that skips either step will fail in a way that looks like a code problem.

`[evidence_source: scripts/build_simulator_smoke.sh]`

---

## 2026-07-30 — iOS and macOS share one version number, derived from CHANGELOG.md

**Context.** The two platforms tracked separately, macOS at 2.5/3.0 while iOS was at 4.7. Release
documentation and roadmap rows carried split labels like `v4.7 (iOS) / v3.0 (macOS)`, which made
every version reference ambiguous.

**Decision.** The `MARKETING_VERSION[sdk=macosx*]` override was removed from `project.pbxproj`.
`ci_scripts/ci_post_clone.sh` derives `MARKETING_VERSION` for both platforms from the first
`## <number>` heading in `CHANGELOG.md`. The `## [Unreleased]` heading is invisible to that grep
because `[` is not a digit.

**Consequences.** `CHANGELOG.md` is now a build input, not just documentation. Editing its first
numbered heading changes what ships. Historical split-label options survive in the Notion `Target
Release` schema; new rows use `v4.9` or `v5.0`.

`[evidence_source: ci_scripts/ci_post_clone.sh, CHANGELOG.md [Unreleased] comment]`

---

## on or before 2026-08-05 — The Notion database is the roadmap source of truth

**Context.** `Docs/ROADMAP.md` and the Notion database disagreed, and the expensive failure was a
Notion row not knowing that work had already shipped, which reordered the plan.

**Decision.** Database `37f49a74-d54f-81b7-9424-dae1288c0043` is authoritative. Sync at task start
and at verified completion. Never locate it by workspace search: other databases in the workspace
have similar-looking rows, distinguishable because theirs use emoji statuses and this one does not.
The exact tool recipe is `.agents/workflows/sync-notion.md`.

**Consequences.** Roadmap questions cannot be answered from memory or from `Docs/ROADMAP.md`. Row
titles are published on the public roadmap page, so a title carrying an unmeasured figure ships that
figure to everyone.

`[evidence_source: .agents/rules/01-docs-and-notion-sync.md, schema read off the live data source 2026-08-05]`

---

## 2026-08-06 — Withdraw a claim by correcting it in place, and verify before removing it

**Context.** A sweep removed unverifiable claims from user-facing copy. One removal was wrong:
"TinyBERT" was deleted because `ReRankerModel.mlpackage/Manifest.json` declares no model family. A
Core ML manifest is a packaging descriptor and never carries the source architecture, so its silence
proved nothing, and `THIRD_PARTY_NOTICES.md` had bound the model by exact path the whole time.

**Decision.** Historical entries are corrected in place with a dated note rather than deleted, so the
record shows what was claimed and when it was withdrawn. Before removing any specific technical name,
figure, or capability, run the `oi-claim-audit` skill.

**Alternatives.** Delete withdrawn claims outright, which loses the fact that they were ever made.
Leave unverified claims in place, which is what created the problem.

**Consequences.** Absence of evidence in one artifact is not evidence of absence. The fix for a claim
you cannot verify is to look harder before deleting it. Attribution recorded to satisfy a license is
the strongest provenance in the repository, because getting it wrong is a licensing exposure.

`[evidence_source: commit 84bcf15, CHANGELOG.md [Unreleased], .claude/skills/oi-claim-audit/SKILL.md]`

---

## 2026-08-07 — Retrieval stage capture lives in `Services/RAG`, not `Services/Evaluation`

**Context.** Per-stage retrieval metrics need the rank-ordered output of each stage. The obvious home
is beside the metrics in `Services/Evaluation`.

**Decision.** `RetrievalTraceCollector` and `RetrievalStageTrace` live in
`Services/RAG/Retrieval/RetrievalTraceCollector.swift`. `OpenIntelligenceEngine` is a separate target
whose synchronized root groups include `Services/RAG` but not `Services/Evaluation`, and
`HybridSearchService` compiles into that target, so anything it references must live in a folder the
Engine target also builds.

Capture is threaded as an optional defaulted parameter rather than by widening the return type,
because `search` has many call sites and the collector only runs during evaluation. It is not a
task-local or a singleton: retrieval runs concurrent child tasks, and a process-wide sink would
interleave stages from overlapping queries with no way to separate them afterwards.

**Consequences.** The constraint happens to match the right layering. Retrieval reports what it did;
it does not know how that report is graded. Check target membership before placing any new file.

`[evidence_source: OpenIntelligence/Services/RAG/Retrieval/RetrievalTraceCollector.swift header]`

---

## 2026-08-07 — `CLAUDE.md` distills `AGENTS.md` rather than importing it

**Context.** Claude Code reads `CLAUDE.md` and does not read `AGENTS.md`. This repository's directive
list had been in `AGENTS.md` only, so none of it reached a Claude Code session. The documented fix is
`@AGENTS.md`, which imports the file into every session's startup context.

**Decision.** `CLAUDE.md` restates the operative subset and names `AGENTS.md` as authoritative,
instead of importing it.

**Alternatives.** `@AGENTS.md` import, or a symlink. Both were rejected because `AGENTS.md` is a
dense 52 lines carrying Gemini/Antigravity-specific rules and historical Phase 1A directives that no
longer apply, and all of it would be paid for on every session including trivial ones.

**Consequences.** The two files can drift, and a distillation that drifts is worse than an import.
`.claude/rules/repo-governance.md` states the coupling, and the `project-context-audit` skill checks
it. If `AGENTS.md` and `CLAUDE.md` disagree, `AGENTS.md` wins and `CLAUDE.md` is the bug.

`[evidence_source: https://code.claude.com/docs/en/memory "Claude Code reads CLAUDE.md, not AGENTS.md", fetched 2026-08-07]`

---

## 2026-08-07 — The active release is derived from `CHANGELOG.md` and reported as three facts

**Context.** `repoos_router.py` scanned a list of candidate documents for a version, `Docs/ROADMAP.md`
first, with a loose `^##\s+(\d+\.\d+)` pattern. That document numbers its sections, so the router
matched `## 0.5 Instrumentation & Benchmarking` and reported `v0.5` with `confidence: exact`. Every
preflight handed out a wrong changelog target, release-notes target, and Notion `Target Release`.

**Decision.** `CHANGELOG.md` is the only source. It is the only version marker the build reads:
`ci_scripts/ci_post_clone.sh` stamps `MARKETING_VERSION` for both platforms from its first
`## <number>` heading. No document that numbers its sections is consulted.

The release is reported as three fields rather than one: `version` (what new work targets), `state`
(`shipped` or `in_development`), and `last_shipped`. When `[Unreleased]` holds entries, `version`
comes from a `<!-- next-version: X -->` marker beside that heading; with no marker the router
reports `unreleased` at `confidence: unknown` rather than guessing.

**Alternatives.** Report the first numbered heading and stop. Rejected: `ci_post_clone.sh:38`
already records why. When `[Unreleased]` has entries that heading names a version already cut, and
CI stamping it got a build rejected by App Store Connect on 2026-07-28. A router that repeats the
mistake in a different place is not a fix. Also rejected: infer the next version by incrementing.
The repository moved 4.9 to 5.0, not 4.10, so the increment is a product decision, not arithmetic.

**Consequences.** The marker is a new convention someone has to maintain. It sits beside the
`[Unreleased]` heading, is invisible to the CI grep (which needs a digit right after `## `), and its
purpose is documented inline. When `[Unreleased]` is promoted to a numbered heading, the marker moves
to the release after.

The three tests that covered this asserted the literal `v4.6` against the live working tree, so they
failed the moment 4.7 shipped and stayed red through 4.8 and 4.9, hiding the defect beneath them.
They are rebuilt against throwaway fixtures. A test that asserts a moving value against the working
tree is a calendar, not a test.

`[evidence_source: repoos_router.py, ci_scripts/ci_post_clone.sh:23-71, suite 19/19 after the change]`

---

## 2026-08-07 — Supabase and Docusign are denied for this repository

**Context.** Several MCP connectors are installed at user scope and reach every session in every
repository. Two of them are write-capable and have nothing to do with an on-device iOS RAG app:
Supabase (`execute_sql`, `apply_migration`) and Docusign (`createEnvelope`).

**Decision.** Both denied at the server level in the tracked `.claude/settings.json`. Notion stays,
because the roadmap depends on it.

**Alternatives.** Leave them and rely on judgment, which is what "least privilege" exists to avoid.
Put the rules in `.claude/settings.local.json`, rejected because the intent ("these are out of scope
for this project") is a project fact worth sharing, not a machine preference.

**Consequences.** The deny rules name connector ids, not names, because connector tools carry no
readable server name. Those ids are per-install and will rot if a connector is removed and re-added,
and a stale rule fails silently: it matches nothing, produces no startup warning because the id
contains `_`, and the connector is simply live again. The mapping and the re-derivation step are
recorded in `Docs/ai/RUNBOOK.md` so the rot is at least detectable.

---

## 2026-08-07 — The doc-sync obligations are restated in `.claude/rules/`, not referenced

**Context.** `.agents/rules/01-docs-and-notion-sync.md` holds the canonical path-to-doc table. Four
of the six `.claude/rules/` files restate the rows that apply to their paths, which is duplication,
and `.claude/rules/repo-governance.md` itself says a fact in two places will drift.

**Decision.** Restate anyway, scoped per path.

**Rationale.** Claude Code never loads `.agents/rules/`. It is Antigravity's always-on directory. A
pointer to a file that the reading agent will not open is not a rule, it is a wish. The duplication
buys the obligation actually reaching the agent editing the file.

**Consequences.** The canonical table and the four restatements can diverge. `.agents/rules/01` wins.
The `project-context-audit` skill checks contradiction across rules, and any change to the canonical
table has to be mirrored in the same edit.

---

## 2026-08-07 — No `PreToolUse` hook enforcing the hard-boundary files

**Context.** Hooks are the only mechanism Claude Code enforces regardless of what the model decides.
The fifteen forbidden-edit files are the highest-value thing to enforce, and a `PreToolUse` hook on
`Edit|Write` could match them by path.

**Decision.** No such hook. The boundary stays a documented rule plus a path-scoped
`.claude/rules/hard-boundaries.md` that fires when one of the files is read.

**Rationale.** The rule is not "never edit these", it is "never edit these *unless the user names
the file in their approval*". A hook cannot see whether that approval was given. `deny` would block
legitimate approved work on files that are actively maintained, `project.pbxproj` most of all.
`ask` would double-prompt on every edit and train the user to click through, which is worse than no
gate.

**Alternatives.** A hook reading an approval token from a scratch file. Rejected: the token becomes
the thing to forge, and an agent that would skip the rule would write the token.

**Consequences.** The boundary remains advisory in the enforcement sense, which is exactly how it
failed on 2026-08-07. The mitigation is reach, not enforcement: the list is now in `CLAUDE.md`,
which loads every session, and in a rule that fires on opening any of the files. Worth revisiting if
a mechanism appears that can express "approved for this file, this session".

Note the genuinely machine-checkable rule, "never run destructive git commands", is also unenforced
and is a better candidate for a `PreToolUse` hook than the boundary list is.

---

## 2026-08-07 — Agent Teams not adopted

**Decision.** Not used. Recorded so a future session can tell "considered and declined" from
"never looked".

**Rationale.** The work in this repository is one writer against one checkout with a human approval
gate in the middle. Teams solve peer coordination between independently useful tasks, which is not
the shape here, and the gate makes independent agents a liability rather than throughput. Isolated
Explore subagents already cover the actual need, which is keeping repository sweeps out of the main
context.

**Revisit when** a task genuinely decomposes into parallel write streams, at which point worktrees
are the prerequisite anyway.

---

## 2026-08-07 — The agent knowledge plane is `Docs/ai/`, capitalised

**Context.** The Context OS specification asks for `docs/ai/`. This repository already has `Docs/`.

**Decision.** `Docs/ai/`, matching the existing directory.

**Rationale.** The filesystem is case-insensitive, so `docs/ai/` resolves into the existing `Docs/`
anyway, but git would then track the path with a lowercase prefix and produce two spellings of one
directory in the index. One spelling avoids that.

`[evidence_source: `ls -la docs` returns the contents of `Docs`, verified 2026-08-07]`

---

## 2026-08-09 — Ingestion fixtures are synthesised in Swift, not committed as binaries

**Context.** The ingestion fixture set needs a text-layer PDF, an image-only PDF, a figures-only
PDF, a degraded scan, a PNG of a table, CSV, `.docx` and `.xlsx`. The obvious approach is to commit
eight small files.

**Decision.** Committed as *code* that draws them at test time, in
`OpenIntelligenceTests/Services/Document/Processing/IngestionFixtureFactory.swift` and
`IngestionOfficeFixtures.swift`. No binary fixture is checked in. `.docx` and `.xlsx` are built by a
store-only ZIP writer in the test target, which works because `DocumentProcessor`'s ZIP reader
accepts `compressionMethod == 0`.

**Alternatives.** (a) Commit binaries and load them as bundle resources — needs the files added to
the test target's resources build phase, and `project.pbxproj` is a hard-boundary file. (b) Commit
binaries and locate them via `#filePath` — avoids the pbxproj question but still puts binaries in
the repository. (c) Generate them with `soffice`, which is installed on this machine — makes the
suite depend on LibreOffice being present wherever it runs.

**Rationale.** Three things fall out at once. The expectations and the bytes derive from the same
`TableSpec`, so there is no hand-transcribed ground truth to drift out of sync with the fixture. No
binary enters a repository that lives in iCloud, which duplicates and re-stamps binary files and has
broken builds here before. And nothing about the test target's file membership changes, so the
hard-boundary `project.pbxproj` stays untouched.

**Consequences, stated plainly.** A rasterised page rendered from vector text is cleaner than
anything a real scanner produces. These fixtures therefore catch *structural* regressions — rows
collapsing to one line, recovered prose being dropped, figures being discarded, chunk inventory
changing shape — and they do **not** catch OCR accuracy loss on genuinely noisy input. That is an
acceptable trade because all five defects fixed on 2026-08-08 were structural, but it means a real
scanned corpus is still worth acquiring later and this set does not replace it.

**Revisit when** OCR accuracy on noisy input becomes the thing under test, at which point real
scans are required and the pbxproj question has to be faced.

---

## 2026-08-11 - Explain the vocabulary in two registers rather than simplifying the screens

**Context.** A tester said the app "feels vibecoded". The interface pass that followed closed most of
it, but the onboarding completion card stayed a problem of a different kind. It shows a chip name, a
TOPS rating, an embedding batch size, a vector search batch size, a Neural Engine core count, and
counters labelled Words, Chunks, Vectors and Time, all read live from `DeviceCapabilityService`,
roughly ninety seconds after install. Those figures are the strongest thing the product can say: "this
ran on your A19 Pro at 32 passages per batch" is checkable in a way "your data stays private" is not.
They are also a wall to a reader who has met none of the words, so the one screen built to earn trust
was the most likely in the app to lose it.

**Decision.** Keep every figure and make each one answer for itself where it already sits. One
registry, `UI/Components/Glossary.swift`, defines 24 terms twice: a `plain` register that uses no code
identifier, model name or framework name, and a `technical` register that names them freely. The
technical register is collapsed behind a disclosure bound to a single `AppStorage` key, so opening it
once opens it for every definition in the app. Definitions are returned from one exhaustive `switch`
over a `GlossaryTermID` enum, not from a dictionary keyed by string.

**Alternatives.**

- *Remove or soften the figures.* Rejected. They are true, measured where claimed, and are the
  differentiator. This repository's expensive mistake has been withdrawing true claims, not making
  false ones, and "38 TOPS" being unfamiliar is not the same defect as it being wrong.
- *One middle register, pitched between the two audiences.* Rejected. A single register that avoids
  jargon while gesturing at mechanism serves neither reader: too vague to be useful to an engineer,
  still opaque to everyone else. The shared toggle is what makes two registers cheaper than one
  compromise, because each reader configures the whole app once.
- *A glossary screen in Settings only.* Rejected, and the owner ruled it out explicitly. The moment a
  user needs a definition is the moment the unexplained figure is in front of them; a definition
  behind two taps in Settings is one nobody reads.
- *Extend `InfoButtonView`, which already existed.* Rejected as the primary shape. It takes
  `(title, explanation)` as free strings, typed separately at each of its three call sites, which is
  the exact mechanism by which one word acquires two definitions. The enum-plus-`switch` design makes
  a missing definition a compile error and an unknown term unrepresentable.

**Consequences.** Adding a term costs an enum case and both registers, enforced by the compiler.
Adding a definition to a new surface costs `.definedTerm(_:)` and nothing else. `GlossaryTests` fails
the suite if a plain definition acquires a code identifier or a backtick, which is the real long-term
risk: nothing renders differently as a plain definition drifts into a second technical one, so without
a test the regression is invisible. Two definitions have their hedges pinned by named tests because
those hedges are load-bearing and would otherwise read as measurements: `tops` must keep saying the
figure is a per-chip lookup, since `npuTops` reads a table keyed by device identifier with projections
for unreleased silicon and Apple exposes no live Neural Engine occupancy API; `neuralEngine` must keep
crediting Core ML with the final scheduling decision.

**Revisit when** a second language ships. The registry is Swift string literals with no
`LocalizedStringKey`, so localisation is the change that forces this design to be reopened.
