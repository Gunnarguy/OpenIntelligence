# Decisions

**Read this file by section, never whole** (about 50 KB): `grep -n '^## ' Docs/ai/DECISIONS.md`
lists the decisions; read any that touch what you are about to change.

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

## 2026-08-12 - Keep the benchmark on macOS until Apple Intelligence can generate in the Simulator

**Context.** Every mitigation in `scripts/run_quality_matrix.py` exists to stop benchmark runs
polluting the owner's real document library, because the macOS app resolves
`applicationSupportRoot()` to his actual container. A simulator has its own filesystem container, so
moving the benchmark there would delete that entire class of problem at once: no cleanup script, no
reset between cases, no risk of repeating the 2026-08-12 incident that ingested 40 papers into his
live library. It would also measure iPhone and iPad, which is what the product primarily ships for,
instead of the least representative target. The reasoning is sound and the conclusion was still
wrong, which is why it is recorded rather than discarded.

**Decision.** Stay on macOS. Re-open the moment Apple Intelligence generates in the Simulator on this
machine.

**Measurement that decided it.** One case at `--pool-limit 10` on iPhone 17 Pro / iOS 27.0 exceeded
ten minutes and then failed, against 170s on macOS. Ingestion and retrieval were fine; generation was
not. `[ReasoningChain] All 8 sessions failed to produce an insight`, then
`[Agentic] Failed: The on-device model did not return a usable response across 8 reasoning sessions`.
The agentic path retries eight reasoning sessions before giving up, and that retry loop is the ten
minutes. At 83 cases that is 14+ hours in which every case fails, against roughly 4 hours of real
answers on macOS.

**Why generation fails.** The framework loads and reports `availability: available`; generation dies
in Apple's `ModelManagerError 1026`. Verified with a bare `FoundationModels` probe with no app code
involved: the same probe on the host Mac reports available **and generates real text**, so the machine
is capable and provisioned. Ruled out: locale (`en_US` both sides), a wedged model catalog (erasing
the simulator removed those errors entirely), and the app's own guards (the failure reproduces with
them removed). Apple's forums document this error pair; the remedy is toggling Apple Intelligence off,
restarting the Mac, and turning it back on. **The owner declined**, reasonably, because this is
developer convenience and nothing the shipping app depends on. Do not spend a session on it.

**The trap.** With a single document and a simple query the pipeline falls back to extractive quickly
and looks fine. The escalation only appears at a realistic pool size, so a one-document smoke test
will tell you the Simulator works.

**Consequence for the three simulator guards.**
`LLMService.AppleFoundationLLMService.isAvailable` and `RAGService.checkDeviceCapabilities` hardcode
unavailability under `#if targetEnvironment(simulator)`, with reasons like "Foundation Models not
available in Simulator". Availability is actually reported *available*, so the stated reason is wrong
while the behaviour it produces is right: without the guards the app attempts generation, fails, and
is slower and noisier for it. They were removed and reverted twice on 2026-08-12. Leave them until
AFM generates in the Simulator, then remove all three together. This is also the whole answer to "why
does the chat header say `Hybrid - Unavailable`": that pill reads `supportsFoundationModels` from
`checkDeviceCapabilities`, so on a simulator it reports a compile-time constant rather than anything
about the machine.

**Revisit when** any Xcode or macOS update lands. Re-run the bare probe; if it generates, moving the
benchmark to the Simulator becomes correct and worth doing immediately. The change is contained to
`run_one` in `scripts/run_quality_matrix.py`, which drives the macOS binary directly and would instead
need `xcrun simctl launch --console-pty <udid> <bundle-id> --args ...` with the same stdout parsing.

`[evidence_level: measured, confidence: exact, evidence_source: bare FoundationModels probe on host vs
iOS 27 simulator; one full case at --pool-limit 10 on each target]`

---

## 2026-08-16: Handle both Foundation Models error taxonomies rather than migrating off the old one

**Context.** iOS 27 deprecates every case of `LanguageModelSession.GenerationError` and splits it
across four replacement types: `LanguageModelError`, `GeneratedContent.ParsingError`,
`LanguageModelSession.Error` and `SystemLanguageModel.Error`. The app caught only the old type, at
three sites, so on iOS 27 every Foundation Models error fell past its handler into a generic catch
that could print `localizedDescription` and nothing else. Two consequences were paid for weeks. The
"empty response" failure resisted five separate hypotheses because the type carrying the evidence
was never caught: a device capture on 2026-08-16 was **17 of 17 `GeneratedContent.ParsingError`**,
each reported as "Session ended without producing a response". And recovery logic that switched on
`GenerationError` cases became unreachable, so `ContentTaggingService` stopped shortening text on
context overflow and silently degraded to keyword tagging.

**Decision.** Add handling for the new types alongside the old, not instead of it.
`FoundationModelErrorMapper.mapModernError` returns `nil` for anything that is not one of the new
types, so each call site falls through to its existing behaviour unchanged. A separate
`recoveryHint(for:)` collapses both taxonomies into the distinction that recovering callers actually
need, which is context overflow versus filtered content.

**Alternatives.** Replace the old handling outright. Rejected because both taxonomies exist in the
iOS 27 SDK, the old cases are deprecated rather than removed, and nothing documents which API throws
which. Deleting the old path would have been an unverifiable bet against paths that currently work.
Also rejected: typed `catch` clauses per type, which the iOS 26 deployment target forbids since all
four replacements are iOS 27, so one availability-guarded downcast covers every site instead.

**Consequences.** Rate limiting can use the real `resetDate` instead of the hardcoded `[2, 5, 12]`
second backoff, and context overflow reports Apple's actual `tokenCount` and `contextSize` instead of
the app's own estimate. Most importantly `GeneratedContent.ParsingError.rawContent` is now logged,
which is the model output that failed to parse and the one piece of evidence this failure has never
yielded. This is expected to be diagnosis rather than cure: if the raw content shows the model
emitting something unparseable, fixing that is separate work.

---

## 2026-08-17: Size the synthesis evidence budget with FoundationModelTokenBudget, not the embedding tokenizer

**Context.** `AgenticOrchestrator` truncated retrieved evidence with a hardcoded
`String(searchResults.prefix(3000))` before synthesis. `Docs/ai/STATE.md` specified the replacement
should count tokens with `DocumentProcessor.countTokens`, on the grounds that it became trustworthy
once the padding defect was fixed in `2753d15`.

**Decision.** Use `FoundationModelTokenBudget` instead, with `isAppleFMOnDevice: true`.

**Alternatives.** `DocumentProcessor.countTokens` as specified. Rejected on two grounds. It is
`private`, so using it would have meant widening access on a file outside the change. More
substantially it is the wrong tokenizer for the question being asked: it encodes with the MiniLM
WordPiece tokenizer used for embedding, while the budget being enforced is an Apple Foundation
Models prompt window. The two disagree, and a count that is accurate for the wrong model is the kind
of plausible-looking number that caused the padding defect to survive 3,910 ingestions.

Also considered: deriving the chars-per-token ratio from the query's actual destination, so a
PCC-bound query would get the cloud ratio. Rejected because it inverts the safety property. The
budget would be most generous exactly when the device is the destination and least able to hold the
result, which is the same failure shape `.claude/rules/orchestration-and-routing.md` already records
for `estimateTokens(..., isAppleFMOnDevice:)`.

**Consequences.** The budget is an estimate, not an exact count, and is deliberately conservative: a
256-token safety reserve absorbs tokenizer disagreement and chat-template overhead. If a future
change needs exactness rather than a bound, `FoundationModelTokenBudget.snapshot` already wraps
Apple's `tokenCount(for:)` on iOS 26.4+ and reports `.sdkExact` versus `.conservativeFallback` as its
source; that path is async and was not needed here.

A related decision inside the same change: parent document expansion is now gated on this budget,
but the gate admits every primary retrieval match unconditionally and only withholds siblings.
Gating primaries would have replaced a silent loss at synthesis with a silent loss at retrieval,
which is the same defect one stage earlier.

---

## 2026-08-25 — PCC stays behind `#if compiler(>=6.4)`, and a runtime gate is not an alternative

**Context.** The owner runs local Xcode 27 builds and sees Private Cloud Compute working, while
App Store users do not. The natural hypothesis — that a runtime check like
`if #available(iOS 27.0, *)` could unlock it on an iOS 27 device from an App Store binary, and that
it would therefore "just work" once iOS 27 ships publicly — was investigated across five independent
lines and settled empirically rather than by argument. This is recorded because the hypothesis is
reasonable, recurs, and acting on it would produce either a build failure or a review rejection.

**What was established.**

1. **`#if compiler(...)` is a build-time condition, and its false branch is not merely uncompiled —
   it is not even parsed.** Swift's language reference states an explicit exception for `swift()`
   and `compiler()` conditions: those branches are scanned only far enough to find the matching
   `#endif`. Verified locally: code inside `#if compiler(>=99.0)` calling a nonexistent function
   compiles cleanly, and its string literals are absent from the built binary under `strings`, raw
   byte `grep` and `nm -u`. The same test under `-Onone` behaves identically, so this is conditional
   compilation rather than the optimiser.

2. **`if #available` is the opposite.** A probe gated on `#available(macOS 99.0, *)` — a version
   that can never be satisfied — still emits **both** branches, and both string literals appear in
   the binary. Availability chooses between paths that were both compiled; conditional compilation
   decides whether the code exists at all. A runtime check cannot reach a symbol a false
   compile-time gate excluded, because the compiler never emitted it.

3. **The symbol does not exist in the older SDK, so a runtime gate does not even compile.** Against
   `MacOSX26.5.sdk`, `if #available(macOS 27.0, *) { PrivateCloudComputeLanguageModel() }` fails
   with `error: cannot find 'PrivateCloudComputeLanguageModel' in scope`. Changing **only** the
   `-sdk` flag to `MacOSX27.0.sdk` makes the identical source typecheck. `grep -c` over the 26.5
   FoundationModels `.swiftinterface` returns **0** for the type against **29** for
   `SystemLanguageModel`, so the absence is real rather than a broken grep.

4. **Xcode 26.6 ships Swift 6.3**, verbatim from Apple: *"Xcode 26.6 includes Swift 6.3 and SDKs for
   iOS 26.5…"*. `6.3 < 6.4`, so every Xcode Cloud "Latest Release" build compiled all ten gates out.
   Xcode 27 was still **beta** at the time of this check, which is why "Latest Release" resolves
   to 26.6.

5. **One tempting nuance, checked and closed.** The 26.5 SDK's FoundationModels linker stub *does*
   export `PrivateCloudComputeLanguageModel` mangled symbols as non-public ABI — 20+ of them. That
   is why "surely the code is on the device" feels right. But the exported shape is an earlier,
   incompatible iteration of the type, and reaching it would mean hand-declaring mangled symbols,
   which is private-API use and a review rejection. There is no supported path.

**Decision.** Leave the gate as `#if compiler(>=6.4)`. It is correct as written. PCC enables when
the **build toolchain** moves to Xcode 27, not when the user's OS does.

**Alternatives rejected.** Replacing the compile-time gate with a runtime one (does not compile
against the shipping SDK); weak-linking and hand-declaring the symbols (private API, rejection risk);
waiting for iOS 27's public release and expecting existing binaries to light up (they cannot — the
code is not in them).

**Consequences.** No App Store or TestFlight build has ever contained executable PCC code, and the
owner is the only person who has run it. **The app itself never misled anyone:**
`FoundationModelCapabilityProvider` returns `supportsPCC: false` on the 26.x toolchain and the UI
reads that snapshot, so nobody was offered PCC and then failed. The defect was confined to outward
copy, corrected for marketing on 2026-08-21 and for in-app copy in `8f76398`.
`[evidence_level: proven, confidence: exact, evidence_source: local compile probes against MacOSX26.5.sdk vs MacOSX27.0.sdk; swift-book Statements.md; Apple Xcode 26.6 and Xcode 27 beta 6 release notes; 21-agent verification pass]`

## 2026-08-28 — `Status` tracks the work, `Shipped On` tracks reach

**Context.** The platforms diverged on 2026-08-26 and have not re-converged: macOS reached 5.0.2
while iOS is on 5.0, so macOS carries fixes iOS has never received. `CLAUDE.md` said a row moves to
`Completed` only when its behaviour is verified where the defect appeared. Under that rule a fix
verified and live on the Mac had **no honest state**: `Completed` lies to an iPhone user, `In
Progress` lies to a Mac user. `Target Release` was also a single value whose options jumped from
`v5.0` to `v5.1`, so a macOS point-release fix had to be filed against `v5.0` or `Future Backlog`,
neither true. Two rows drifted for exactly this reason and were found by a claims audit.

**Decision.** `Status` tracks whether the work is done. A new `Shipped On` multi-select (`iOS`,
`macOS`) tracks where users can actually install it. A verified fix live on one platform is
`Completed` with `Shipped On` naming that platform, not held open because the other platform has not
had a release. `v5.0.1` and `v5.0.2` were added as `Target Release` options. Empty `Shipped On` means
*not recorded*, never *not shipped*.

**Alternatives rejected.** Keeping `Status` open until every platform ships — rows sit open on a
technicality, which is what caused the drift. Encoding the platform in `Target Release` — it is a
single-value select, so it cannot express "shipped on one, pending on the other". A per-platform
status property — two `Status` columns invites them disagreeing about the same work.

**Consequences.** The closure rule now lives in three places that must move together: `CLAUDE.md`,
`.claude/skills/notion-roadmap/SKILL.md`, `.agents/rules/01-docs-and-notion-sync.md`. Backfill was
taken from the changelog's own platform annotations and stops where the evidence stops: 88 rows set,
and the 68 rows targeted `v4.0`–`v4.5` left empty because the only macOS versions documented anywhere
in this repository are 2.5, 3.0, 4.8, 5.0 and 5.0.2, the earliest tied to iOS 4.6. The `v4.8 (iOS)`
rows are `iOS, macOS` despite their label: iOS 4.8 was developer-rejected and never shipped, macOS
4.8 was approved, and the iOS 4.9 binary carries every 4.8 entry.
`[evidence_level: artifact_derived, confidence: exact, evidence_source: CHANGELOG heading annotations for 4.6/4.7/4.9; the 4.9 heading comment on the iOS 4.8 rejection; Docs/SHIPPED_VERSION.json; per-option row counts before and after the schema change, 224 rows unchanged]`

---

## 2026-08-29 — Narrow Vision's OCR language set, but only when the detection is confident

**Context.** `OCRConfiguration` applied all thirteen recognition languages — four of them CJK — to
every `VNRecognizeTextRequest` in the codebase, and set `automaticallyDetectsLanguage = true`
alongside them.

**The reason to narrow is accuracy, and the first draft of this entry had it backwards.** Apple's
header says the flag makes Vision "identify the script/langauge … and use the appropiate model …
so you don't have to pick the language model in the first case" — so Vision was already selecting a
model, and "thirteen models were being loaded" was never established. What Apple does state is the
warning that follows: "as the language correction cannot always guarantee the correct detection, it
is advisable to set the languages, if you have domain knowledge of what language to expect." A wrong
auto-detection applies language correction against the wrong lexicon, which corrupts text rather
than merely slowing it down.

**Decision.** During PDF ingestion, detect the document language once from the PDFKit text layer
already being mined for custom vocabulary, and pass only the detected languages.
`narrowedRecognitionLanguages(matching:)` returns `nil` — meaning keep all thirteen — whenever
narrowing is not clearly safe: primary confidence at or below 0.8, an undetermined language, an
empty text layer, or a language the curated list does not cover. Chinese narrows to both scripts
rather than choosing between Hans and Hant.

**Why the asymmetry, which is the part that cannot be read off the code.** The two errors are not
comparable. Narrowing wrongly means Vision has no model for text that is present, so that text is
lost and no later stage can tell it ever existed — the silent-discard failure this pipeline has
produced four separate times. Keeping the full list wrongly only costs time, which is visible in a
log and recoverable on the next run. So the function is built to decline, and a future change that
makes it eager will look like an optimisation while being a regression. The tests exist mainly to
pin the declining cases for that reason.

**Alternatives.** Detect per page, which multiplies a fixed per-document cost by the page count for
a property that rarely varies within a document. Hardcode English, which is wrong for a local-first
app whose users' documents are not knowable. Drop the CJK entries from the curated list, which
would silently stop supporting those languages rather than stop loading them when absent.

**Consequences.** Call sites without a prior text layer — camera capture, `IntelligentDocumentProcessor`
— pass no languages and are unchanged, so this helps PDF ingestion and nothing else. It applies to
**both platforms**: neither `OCRConfiguration` nor the changed region of `DocumentProcessor` contains
a platform conditional. No performance figure is claimed. A speed benefit is likely — fewer
candidates for language correction, and the per-request script detection no longer runs — but Apple
does not quantify it and the log line reports which branch ran so a device trace can.

**This is one of four controls, and the only one changed.** Render scale, `minimumTextHeight` and
Vision concurrency all govern the same underlying quantity and are all set to maximum. They are
filed on the roadmap with the evidence and deliberately not started, because attributing the
observed five-hour ingest to any one of them is inference until a run is instrumented.

## 2026-09-13 - The camera stays behind `#if os(iOS) && DEBUG` until it has been watched on a device

**Decision.** `ChatScreen.visionCaptureAction` returns nil outside Debug builds, so the attachment
menu never renders "Look at Something" in a Release build and `CameraVisionOverlayView` cannot be
presented. 5.3 ships with the camera code compiled in and no way to open it. The owner's words on
2026-09-13: the camera work is experimental and "should probably wait".

**Why a compile-time gate rather than a setting.** A setting still ships the screen and leaves it one
tap from anyone who goes looking, and this screen's riskiest property is one nobody has observed:
`.onDisappear` stops the capture session, which is correct code, but a dismissal path where
`.onDisappear` does not fire leaves the camera running. On a stranger's phone that is a lit camera
indicator and a flat battery, reported through a review. One person on one phone is not evidence
that every dismissal path fires. `#if DEBUG` keeps the screen on the owner's device builds, which is
where that testing has to happen anyway.

**What "gated" means, measured.** The screen's own `Vision Capture` string is absent from a Release
binary and present in Debug, compared alongside a control string present in both. The menu label
`Look at Something` survives into Release because `AttachmentPicker` compiles unconditionally, so the
item is unreachable rather than absent. A present string is not proof a feature is reachable, and
the distinction is recorded so that nobody greps a build and concludes the gate failed.

**Consequences.** The user-facing notes written for the camera are held in
`Docs/Release/5.3/camera_user_notes_held.md`, not shipped, because `Docs/USER_CHANGELOG.md` is copied
into `Resources/VersionHistory.md` and rendered in Settings, where it would have described a button
the build does not have. The roadmap row that tracked the camera stack moved from v5.3 to Future
Backlog. The detector, the geometry and their 22 tests stay in every build. Removing the gate is what
releasing the feature means; it should come with the held notes and a device pass over every
dismissal path, not with a diff tidy.

**Alternatives.** Ship it labelled experimental: rejected, because a label does not stop a capture
session. Delete the 4,300 lines: rejected, because two days of measured repairs are in them and the
screen works in Debug. A runtime flag read from UserDefaults: rejected for the reason above and
because it is the mechanism that made every earlier "disabled" feature here reachable by accident.

## 2026-09-14 - The sample library's suggested questions are written by hand, and stay that way

**Decision.** The three sample documents get the curated question set in
`SuggestedQuestionsService.sampleWorkspaceQuestions`, not model-generated ones, on every device
family alike. Owner's words, 2026-09-14: they are "formulated to answer precisely what the questions
are set up to ask to guide users to understand more of the app, they're not intended to be
randomized or flashy." Improving their wording is welcome; replacing them with generation is not.

**Why, which the code does not say.** The sample library is the first thing a new user sees, and its
questions exist to teach the app, not to demonstrate the generator. A generated set would vary by
device, by model availability at first launch, and by run, and the samples are conceptual product
prose that the generator handles worst of all. A fixed set is the only one that can be written to
lead a reader through the app in order.

**Rejected the same day.** Using the curated set only as a bootstrap until the model has written
grounded questions for the samples. Proposed by the agent, declined by the owner: the value of the
set is that it is the same for everyone.

**Consequences.** The fix committed as `063305f` (sample identity, numbered-copy cleanup, fail-closed
templates, bank rebuild) stands; it restores this path, it does not change its nature. The refresh
button on the sample workspace still shuffles the curated list; that is the one place the set is
not deterministic, left as is at "let's put this to rest".

## 2026-09-23 - Standard checks an answer against its sources only when the verification gates flag it

**Context.** `SourceOnlyAnswerService.verifyAndRender` is a second check on extractive answers: a
structured draft of the answer's claims, then a structured review of each claim against the
evidence, two sequential model calls. Standard ran it on every extractive-first answer after the
last word had streamed, so the person watched a finished answer behind a blinking cursor and a
locked composer. Measured on the macOS 27.0 Debug build that day, four such Standard questions
whose nine verification gates had passed finished 19.4, 37.6, 58.3 and 163.8 seconds after their
last word, and the check replaced none of the four answers. In the 25-case QASPER benchmark run the
same morning it ran on 5 cases and replaced none of those answers either.

**Decision.** In Standard, the check runs only when the gates did not pass the answer (failed, or
never judged). Deep Think and Maximum keep it unconditionally. Separately, the check's draft gets
a 1,024-token generation limit, and any stage that runs after an answer's
text is complete can be ended by the person (`RAGService.finishAnswerNow()`), keeping the answer
and its sources.

**Alternatives.** Keep the check everywhere and only change the UI (the cursor goes, the composer
unlocks). Rejected as the whole fix because the wait stays and the answer stays unsaved until it
ends. Run the check after returning the answer and patch the saved message if it changes. Rejected
for now: the check's outcome also changes the structured answer, the gating record and the
confidence, which would all need a second write path. Cap the check by time. Rejected: a time
budget is arbitrary. Cap the draft at its 700-token budget reserve. Tried first and measured too
tight the same day: completed Deep Think drafts used 571 and 675 of 700 and a third failed to parse
at the limit, so the draft limit is 1,024, about 1.5 times the largest completed draft.

**Consequences.** A Standard answer the gates passed is no longer re-checked claim by claim. The
accuracy A/B for the change is `BenchmarkRuns/2026-09-23-sourceonly-{before,after}-greedy25`,
recorded in `BenchmarkRuns/LEDGER.md`. If a later benchmark shows the check correcting passed
Standard answers, the gate is one function, `RAGService.standardSkipsSourceOnlyCheck`. Each
completed draft logs its token use against the 1,024 limit, so the limit can be judged from traces.

## 2026-09-23 - Every change since the live release ships in the version App Store Connect is preparing

**Context.** 5.4 was in Prepare for Submission on build 474 when the answer work of 2026-09-23 was
planned. Reading the scope-freeze rule in `CLAUDE.md` as closing 5.4, the plan opened
`## 5.5 <!-- unreleased -->` above 5.4 in `CHANGELOG.md`, filed three roadmap rows against a new
`v5.5`, and was pushed as `faed0d6`. `ci_scripts/ci_post_clone.sh` stamps every build from the first
numbered heading, so Xcode Cloud build 475 went to TestFlight as 5.5, a version App Store Connect
does not have. The owner, the same day: 5.4 is the version that exists, there is no 5.5 in App Store
Connect, and every change made since 5.3 is 5.4.

**Decision.** Work since the last live release belongs to the version App Store Connect is
preparing, until that version is submitted. A new version heading goes into `CHANGELOG.md` only
after the previous version is submitted, or when the owner names the new version. The scope-freeze
rule decides which roadmap rows a release takes on; it never opens a version. When the two seem to
pull apart, ask the owner which version the work ships in, in those words.

**Alternatives.** Keep 5.5 open and submit 5.4 on build 474 without the answer work. That is what the
push set up, and it is not what the owner wanted: 5.4 would ship without the fixes, and every build
after it would carry a version App Store Connect does not have.

**Consequences.** `## 5.5` was folded into `## 5.4 <!-- unreleased -->` the same day, and so were the
matching sections of `Docs/USER_CHANGELOG.md`, its bundled copy, `WHATS_NEW.md` and the in-app
What's New entry. The three rows moved to `v5.4`. The build to submit for 5.4 is the first build of
`main` after the fold, in place of 474. Build 475 (5.5) stays in TestFlight unused, and the Notion
`v5.5` option has no rows.

`[evidence_source: owner's messages 2026-09-23; git show faed0d6 -- CHANGELOG.md; App Store Connect builds?filter[version]=475 -> version 5.5 on iOS and macOS]`

## 2026-09-24 - Development pauses after 5.4, and no next version is opened

**Context.** 5.4 went live on iOS at 14:32 PT and on macOS at 17:00 PT on 2026-09-24. Earlier that
afternoon the owner picked 5.5 over 5.4.1 as the next number. When he asked for the Mac release, he
added that he would probably stop building for now, and wanted 5.4 officially set and done. Since
5.2, every go-live commit has opened the next version above the shipped one (`006f6a3` opened 5.4
when 5.3 went live), so that `ci_post_clone.sh` never stamps a released version.

**Decision.** 5.4 is closed with nothing open above it. `Docs/SHIPPED_VERSION.json` keeps
`preparing` at 5.4, the first numbered heading. fascinaiting.me drops its in-development entry, so
no public page announces a version nobody is building. The next version is 5.5 when he resumes.

**Alternatives.** Open `## 5.5 <!-- unreleased -->` now, the usual go-live routine. That would have
put a 5.5 "in development" entry on fascinaiting.me, and a version heading no App Store Connect record
matches, while no work is planned.

**Consequences.** The router reports release `v5.4`, state shipped. That forces the next session to
name the version before filing work, which the 2026-09-23 rule requires anyway. An app-change push
before 5.5 is opened would build 5.4, and App Store Connect would reject the upload. Pushes of
documentation only start no build. Opening 5.5 means the `CHANGELOG.md` heading with its
`next-version` marker, `preparing` 5.5, the 5.5 records in App Store Connect, and Fascinaiting's
in-development entry back.

`[evidence_source: owner's messages 2026-09-24; App Store Connect read 17:00 PT, both 5.4 records READY_FOR_SALE; git show 006f6a3 -- CHANGELOG.md]`

**Superseded in part by 2026-09-28.** The no-version-open state ended when the extractor-fix branch merged and 5.5
opened; the pause itself still holds for anything beyond that fix.

## 2026-09-28 - A codemap for agents, whose links are VERIFIED only where the Swift syntax states them

**Context.** A fresh agent session starts from the owner's words and 299 app Swift files.
`Docs/ai/ARCHITECTURE.md` maps areas to folders and a dozen of his phrases to key symbols, and the
Repo Map shows which documents still match the code, but nothing listed a feature's entry points, the
files it owns and what they call or render. The `codemap` skill (`~/.claude/skills/codemap/`, built
the same day for OpenResponses) defines a format and a checker; its installer puts the checker in
`scripts/`, and here a push touching `scripts/` starts an Xcode Cloud build.

**Decision.** `Docs/ai/codemap/` holds one slice per feature, 46 in all, whose primary files cover
every app Swift file once. The checker is `.claude/codemap/codemap.py`, inside Xcode Cloud's skip
filter. Links are written by `~/.agents/codemap/build.py`, shared with MissionToAutonomy. A link is
VERIFIED only when the Swift syntax on the cited line states it on its own (the line constructs the
type by name, or calls the member through its type), which this repository's evidence protocol calls
`code_verified`; a link found by a matching name is INFERRED, `grep_verified`. Names, aliases and
boundaries were drafted by Gemini on the owner's Google plan and corrected by hand, and entry points
start from the symbols ARCHITECTURE names. A `UserPromptSubmit` hook prints the slice a prompt names;
it is registered in the root `.claude/settings.json` because sessions here start at the root.

**Alternatives.** The skill's own Swift `derive`, which marks every link INFERRED, so a reader cannot
tell a stated link from a guess. An agent-written graph with hand-tagged verified links. The checker
in `scripts/` with `[ci skip]` on every commit that touches it.

**Consequences.** Slices go stale as code moves: `codemap.py check` re-finds every cited line and the
session brief prints how many moved or broke; after a Swift change, `affected` names the slices to
rebuild. The builder and the hook live on the owner's Mac, so a clone elsewhere can read and check the
map but not rebuild it, and its hooks exit quietly. A slice is a map, not a proof (`AGENTS.md` rule
19). An independent reader refuted 2 of 20 sampled VERIFIED links (real links, wrong type) and 7 of
20 INFERRED links (names in comments, standard-library methods, calls on self); each cause became a
builder rule. A second sample of 40 on the fixed build held 20 of 20 VERIFIED and 18 of 20 INFERRED,
and its two failures (a private member of another file, SwiftUI's `dismiss()`) became rules too.

`[evidence_source: codemap.py check 0 errors at 0e9728e; review samples and verdicts, and the A/B, in ~/.agents/featuremap/ab/2026-09-28-OpenIntelligence/ on the owner's Mac; build.py and its README]`

## 2026-09-28 - The cloud extractor-fix branch merges into main, and 5.5 is the open release

**Context.** A cloud session left `claude/determined-ritchie-7y60am` five commits ahead of `main`
(2026-09-26): 6,198 added lines, about 5,500 of them the RAG architecture audit under
`Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/`. The app change is 42 lines in
`SpecificationExtractor.swift` plus four regression tests, and the branch opened
`## 5.5 <!-- unreleased -->`. Its own handoff left the Xcode test run on the Mac and the owner's merge
call open. On 2026-09-28 the owner asked to close the loop, and said App Store Connect already had
5.5; he had created both records on 2026-09-25.

**Decision.** Merge the whole branch, audit included, and make 5.5 the open release: `preparing` 5.5.
Resolve the two conflicts, which were both documentation, and file the three 2026-09-28 doc and tooling
entries under `## 5.5` as well. Push only after the full suite passes in Xcode on the merged tree, then
delete both cloud branches (`claude/feature-knowledge-graph-fhu4mc` was already fully in `main`).

**Alternatives.** Keep the branch parked until 5.5 work resumes. That leaves a branch against the
owner's rule of 2026-09-14 ("everything on their mains with no branches"). Merging the audit without
the code would split one piece of work across two places.

**Consequences.** This supersedes the "no next version is open" part of the 2026-09-24 decision. The
push starts an Xcode Cloud build that stamps 5.5 and uploads to the 5.5 records for TestFlight.
Nothing is submitted. The row "Deep Think answered a lease-notice question with '1 lb'" stays In
Progress: on 2026-09-26 the fix removed the lock, but Deep Think still answered "at least 30 days"
where the lease says 60, and marked it Verified. Fascinaiting's in-development entry stays off
until more 5.5 work is planned.

`[evidence_source: git merge-tree origin/main origin/claude/determined-ritchie-7y60am (two conflicts, both documentation); App Store Connect read 2026-09-28, iOS and macOS 5.5 PREPARE_FOR_SUBMISSION, created 2026-09-25; memory extractor-fix-device-check]`

## 2026-09-29 - DEC-35 was reversed in code without being amended; the reversal stands until the owner says otherwise

**Context.** The July PR audit's decision log (now `Docs/Archive/ZeroRegressionAudit_2026-07/DECISION_LOG.md`)
records DEC-35 (2026-07-14): a capitalized-word entity fallback in `SemanticChunker` was rejected as a
regression, because sentence-initial words such as "However" and "Should" become entities that feed the
entity index and two-hop graph expansion, and the log said any such fallback must be display-time only,
never persisted at ingest. The fallback came back the next day in `9d819a5` ("add fallback entity
extraction") and became unconditional in `f962e03` (2026-07-28), whose code comment gives the reason:
Natural Language tagging on iOS 27 did not classify "Apple" consistently. Nobody amended DEC-35.

**Decision.** Record the reversal here so it is not lost when the log is archived. The shipped behaviour
stands: `SemanticChunker.swift:1634` runs the deterministic supplement on every chunk, and the
single-word pattern at `:1673` with its stoplist at `:1681` still lets "However" and "Should" through.

**Alternatives.** Leave DEC-35 only in the archived log, where a later session would read a rejected
design as the current one; or revert the supplement, which is an app change and not this cleanup's call.

**Consequences.** Whether sentence-initial capitals create false cross-document links is an open
retrieval-quality question for the owner. It is filed as Future Backlog, not 5.5 work:
https://app.notion.com/p/3ea49a74d54f81059b20e8bda0663798 (To Do, Chunking, Low, 2026-09-29).

`[evidence_level: code_verified, confidence: exact, evidence_source: OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift:1634, :1673, :1681; git log -S 'ALWAYS runs' and -S 'singleWordPattern' on that file -> f962e03, 9d819a5; DEC-35 at Docs/Archive/ZeroRegressionAudit_2026-07/DECISION_LOG.md]`

## 2026-09-29 - The engine SDK stays; its private snapshot lives only in history

**Decision.** `OpenIntelligence/SDK/OpenIntelligenceEngine.swift` and its library product stay until the
owner says the SDK plan is over. The private engine snapshot taken before the public handoff, with the
SDK file, the `SourceSDKHost` demo app and `MISSIONFORTODAY.md`, is at `54b0a50` (2026-05-12, "Preserve
private engine snapshot before public handoff"); `git show 54b0a50` recovers it.

`[evidence_level: code_verified, confidence: exact, evidence_source: git show --stat 54b0a50]`

## 2026-09-29 - The repository cleanup archives only what nothing live needs, and leaves the app alone

**Context.** A read-only pass judged 460 files against the code, put every "can go" call to a dependency
skeptic and a value skeptic (38 of 76 survived), and a final check refuted one more step. The owner
said to carry out the recommendations as long as nothing fundamental breaks.

**Decision.** Archive only files no live tool, route, site or rule needs, repointing every live
reference in the same change and fixing relative links inside moved files: the July `.agent/` bundle
except `RISK_REGISTER.md`, `Docs/ARCHITECTURE.md` (as `ARCHITECTURE_v4.1.md`), the root
`HOW_IT_WORKS.md`, two superseded engineering references, the 4.8 release-notes draft, playbook 06, three
playbook aliases and RepoOS 02. Delete 14 scripts nothing runs and one unreferenced screenshot, all kept in git history. Move `Docs/Release/CONVERSION_AND_REVIEWS_2026-09.md` out of the repository into the owner's private workspace (`~/ASC/`), after copying it there and comparing the copy byte for byte; the plan named this move and the owner approved the plan. Correct wrong claims in place under `oi-claim-audit`. Leave alone:
anything compiled into the app (5.5 build 481 is staged), the four June audits (2026-08-17 decision
re-examined and kept: they carry [Archived] banners and moving them breaks 71 links),
`Docs/AppleIntelligenceTransitionPlan.md` (app code comments cite it by line), the CI scripts, the
Fastfile, the secret scanner and the store listing.

**Consequences.** `Docs/Archive/README.md` maps every old path to its new one, so citations inside
archived documents resolve without editing history. gunnarguy.me drops two pages on its next sync
(`ARCHITECTURE.md` and `RELEASE_NOTES_4.8_DRAFT.md`). Dead Swift, bundle strays and the eval types wait
for a release the owner opens for them.

`[evidence_source: the cleanup workflow's classifications and verdicts, 2026-09-29; owner's message 2026-09-29]`

## 2026-09-29 - Only a Lifetime purchase earns permanent protection; everyone who already has it keeps it

**Context.** Through 5.4, `EntitlementStore` promoted every verified paid purchase to `.historicalPaidPurchase` at launch, on purchase and from StoreKit history, and that state resolves to Lifetime whatever StoreKit says (`EntitlementStore.swift:205`, `:267`). A Pro subscription, including an annual free trial, therefore became Lifetime for good; the design dates from `6dc093c` (2026-05-12), whose comment called it grandfathering, and `Docs/BILLING_AND_LIMITS.md` described it. The owner learned of it on 2026-09-29 and asked for it fixed.

**Decision.** From 5.5 only `lifetime_cohort` earns the protection, plus any subscription whose original purchase date is before 2026-09-30 00:00 UTC, and a refunded transaction earns nothing (`EntitlementStore.protectionEarned`). Protection already stored on a device is never lowered. The owner's reasoning, paraphrased: the mistake was the app's, the people who got it should keep it, and taking it away would invite angry reviews.

**Alternatives.** Take it back at launch wherever StoreKit shows a subscription and no Lifetime purchase, leaving it alone when StoreKit cannot answer; proposed first, and set aside at the owner's word. Leave the bug in place; rejected, because every new trial kept adding permanent Lifetime users.

**Consequences.** Anyone who starts a subscription or trial on 5.4 still gets the stored protection until they update, so the leak closes when 5.5 is live and installed. A lapsed subscription now drops the person to Free for the first time: iCloud library sync switches off and the libraries stay on the device, since both workspace modes work from the local folder (`WorkspaceSyncService.swift:411-434`, `:883-905`). A refund still does not clear stored protection (`handleRevocation`). Whether a lapsed subscription that is bought again keeps its first original purchase date is not verified.

`[evidence_level: code_verified, confidence: exact, evidence_source: EntitlementStore.swift:205, 235-258, 267, 384-425, 441-464, 575-590; EntitlementProtectionTests; owner's messages 2026-09-29]`

## 2026-09-29 - Lifetime's standing price is $49.99 from 2026-09-30

**Context.** Lifetime was $59.99 until the launch sale, $39.99 from 2026-09-15 through 2026-09-29, and was scheduled to revert to $59.99. Daily sales reports (`~/ASC/data/asc.sqlite3`, through 2026-09-27) show 9 paid Lifetime purchases at full price from 2026-02-23 to 2026-08-09, about 1.6 a month, and 2 during the sale in 13 days. Two is too few to separate the price from the iOS 27 launch and the posting that ran at the same time. Pro Annual is $29.99, and from 5.5 a Pro subscription stops at its end date instead of becoming Lifetime (the entry above).

**Decision.** The owner chose $49.99, set through the API on 2026-09-29 to start 2026-09-30, so the price goes from $39.99 straight to $49.99. Other storefronts follow Apple's equalization of the US price point.

**Alternatives.** Revert to $59.99: two years of Pro Annual, and the price that sold about 1.6 a month. Keep $39.99: about 16 months of Pro Annual, which would pull buyers off the annual plan now that Pro really lapses.

**Consequences.** US proceeds per Lifetime sale are $42.49 instead of $50.99, so Lifetime needs about 20% more sales to earn the same; at about two a month, telling whether it does will take months of daily reports. `Docs/BILLING_AND_LIMITS.md` section 5 has the prices and the undo snapshot. The next sale needs `schedule_sale.py`'s `REGULAR_PRICE` and `LaunchSale.regularLifetimePrices` updated first.

`[evidence_level: measured, confidence: exact, evidence_source: GET manualPrices after the write, 2026-09-29 12:25 PT; sales table in ~/ASC/data/asc.sqlite3 read 2026-09-29; owner's messages 2026-09-29]`

## 2026-09-29 - Pro Annual $24.99 and Pro Monthly $4.99 from 2026-10-01; the annual win-back is $14.99

**Context.** With Lifetime at $49.99 (entry above), Annual at $29.99 made Lifetime only 1.67 times Annual. Research read the same day put the app already below market: RevenueCat's 2026 report gives median prices of $8 a month and $34.80 a year (North America $9.99 and $39.99); productivity apps keep monthly subscribers worst of any category and cite cost most in cancellations. Sales are too few to test anything: about one subscription purchase a week, 3 active monthly subscribers and about 1 annual. The research recommended keeping Monthly at $5.99 and making one move, Annual to $24.99, timed with 5.5.

**Decision.** The owner chose Annual $24.99, Monthly $4.99 and an annual win-back of $14.99, all from 2026-10-01, the earliest start App Store Connect allowed. Lifetime is now 2.0 times Annual, and Annual stays 5.0 times Monthly, a 58% saving against twelve months.

**Alternatives.** Keep Monthly at $5.99 (the research's recommendation); hold Annual at $29.99 until 5.5 has run 60 to 90 days; Annual at $19.99, rejected in the research as the lowest category median and the old win-back price.

**Consequences.** Existing subscribers renew at the lower prices, and Apple offers no way to keep them higher. Raising a price later needs Apple's notice (60 days for annual, 27 for monthly) and, above certain thresholds or within 12 months of a previous increase, each subscriber's consent. The $19.99 win-back offer stays live until 2027-09-24 because a live offer's dates cannot be changed through the API; App Store Connect shows the better offer where they overlap. The paywall's "Save 58% vs monthly" is hardcoded and should be computed from each storefront's prices in the next build. Judge the change on proceeds per download over months, not on conversion counts. `Docs/BILLING_AND_LIMITS.md` section 5 has the verified prices.

`[evidence_level: measured, confidence: exact, evidence_source: subscription prices and win-back offers read back from the App Store Connect API 2026-09-29; RevenueCat State of Subscription Apps 2026 and Adapty 2026 benchmarks, read 2026-09-29; owner's messages 2026-09-29]`

## 2026-09-29 - 5.5 comes back out of App Review to carry the plans screen's comparisons; win-backs stay off that screen

**Context.** 5.5 (build 482) and the product-description submission were waiting for review, not in it, when the owner
asked for the plans screen to show what each plan saves against the others. The prices change on 2026-09-30 and
2026-10-01, and the paywall's only saving was a hardcoded "Save 58% vs monthly" bullet. Proposed first as 5.6, after
5.5 released.

**Decision.** The owner rejected the 5.6 route: "Just reject it for now and make ALLLL the proper changes, then get it
back into review." All three submissions were cancelled through the API the same afternoon and 5.5 carries the change:
comparisons computed per storefront from live prices and placed under the billed price (`Docs/BILLING_AND_LIMITS.md`
section 2), every card's label shown, "Lifetime Cohort" renamed "Lifetime" in the app and in App Store Connect, the
fallback prices and the sale's regular-price table moved to the new prices. Win-back offers on the plans screen were
offered and declined ("Skip it"): showing and charging them there needs `StoreKitBillingService.swift`, which the billing
route forbids without the owner naming it, and StoreKit already merchandises the three offers itself.

**Alternatives.** Ship 5.5 as submitted and the comparisons in 5.6 (declined); edit `StoreKitBillingService.swift` to
apply `.winBackOffer` from the plans screen (declined, purchase path untouched before an expedited review).

**Consequences.** 5.5 lost its place in the review queue, which the owner means to recover with an expedited-review
request. Subscribers who lapse see the win-back offer through StoreKit's sheet on iPhone and iPad, the App Store and
Subscription settings, not on the plans screen; a lapsed subscriber who buys from the plans screen pays the regular
price. Revisit in-app win-backs if lapsed subscribers become a meaningful number.

`[evidence_level: measured, confidence: exact, evidence_source: PATCH /v1/reviewSubmissions {canceled: true} for 409aead4 (iOS), 6d81ae2c (macOS) and 00242f20 (products), 2026-09-29, read back COMPLETE with both 5.5 records DEVELOPER_REJECTED; owner's messages 2026-09-29]`

## 2026-10-09 - Deep Think and Maximum sessions are not prewarmed, and their prompt order stays

**Context.** A 5.7 roadmap row asked for the model's cache to be kept warm between the steps of a Deep Think
answer. Each step builds a new session with its own instructions, and its passages, which change every step
and fill most of the window, come after the question and the prior findings. Apple's article on key-value
caching says a session reuses what it has already processed and that `prewarm(promptPrefix:)` precomputes a
prefix before the first request. The plan was to give every step the same instructions, put the passages
first, and prewarm the next step's session while the current one generated.

**Decision.** Not built. On this Mac (M3 Pro, macOS 27.0, `contextSize` 8192, about 6,100 input tokens a run)
no form of prewarm put a token in the cache or shortened the time to the first word: 7.6 to 9.3 s cold; 8.2 s
and 8.5 s after `prewarm(promptPrefix:)` with the whole passage window and a 12 s and 25 s wait; 8.3 s with
the passages in the instructions and a bare `prewarm()`; 8.4 s with the passages in a rebuilt transcript and
`prewarm()`. `usage.input.cachedTokenCount` read 0 in every one. A second turn in the same session did reuse
the cache (3.0 s, 6,304 cached tokens), and a prewarm started while another session was generating delayed
that session's first word from 7.6 s to 12.6 s. A step's passages fill the window, so two steps cannot share
a session, which is the only thing that was faster.

**Alternatives.** Reorder the prompts anyway for a later system that does cache a prefix (rejected: it changes
what every Deep Think step is sent, with nothing to measure the answers against); keep one session and trim
its transcript between steps (rejected: Apple's article says a change deep in the transcript drops the cache
from that point, and the passages are that point).

**Consequences.** Deep Think's time is the sum of its sessions, each paying for its own prompt. The launch
warm-up in `LLMService.warmUpModel` still calls `prewarm` with a prefix; whether that shortens the first
answer after a cold start was not measured, because the model was already loaded for every run. Re-run the
probe on an iPhone and after a system update before trying this again.

`[evidence_level: measured, confidence: medium (one machine, one run per case, differences under about 1 s are not differences), evidence_source: BenchmarkRuns/2026-10-09-session-cache-probe/results.txt and cacheprobe.swift, run 2026-10-09 (local: BenchmarkRuns is not committed); developer.apple.com/documentation/foundationmodels/optimizing-key-value-caching-in-language-model-sessions, read 2026-10-08]`

The same probe read `transcriptErrorHandlingPolicy`: left at its default (`nil`), a prompt too large for the
window threw and the transcript kept its 3 entries, as it did with `.revertTranscript`; `.preserveTranscript`
kept the failed prompt (4 entries). So the app sets no policy: the default already rolls a failed turn back.

## 2026-10-10 - New libraries on iPhone and iPad embed with the Core ML copy of the model; the Mac keeps Core AI

**Context.** From 5.0 a library made on iOS 27 or macOS 27 used `CoreAISentenceEmbeddingProvider`, and a saved
Core ML default was moved to it. No measurement on a phone stood behind that. The owner's 88.50 MB import ran at
46 falling to 32 passages a second on an iPhone 16 Pro Max, stopped whenever the app left the front, and heated
the phone to "Serious".

**Decision.** `EmbeddingProviderDefaults.preferredSentenceProviderId` (`EmbeddingService.swift`) answers Core ML
on iOS and iPadOS and Core AI on macOS 27. `SettingsStore`, `ContainerService.defaultContainer` and
`AdaptiveEmbeddingOptimizer` ask it. An existing library keeps its provider, and
`RAGService.evaluateEmbeddingShift` no longer counts the other copy of the same model as a change of provider.

**Rationale.** Measured on that iPhone on 2026-10-10 with `DebugEmbeddingBench` (model alone, 420 real tokens of
512, thermal state nominal, passages a second): Core AI 88.5 default, 85.5 preferring the GPU, 78.5 preferring
the Neural Engine, 5.4 on the CPU, and two or four calls in flight no faster; Core ML 115.8 on CPU and Neural
Engine, 99.0 on all units, 84.0 on the CPU alone (104.0 with two in flight). On the Mac the same day the Core AI
model printed a Neural Engine validation failure at its attention-mask step when loaded, and its vectors
matched CPU-only output to nine decimal places under every option, so no half-precision unit ran it. Its rate
says which unit did: on the M3 Pro Mac on 2026-10-12 it took 4.71 ms a passage by default and 4.70 ms
preferring the GPU against 112.26 ms CPU-only, and on the iPhone 88.5 passages a second against 5.4, so it
runs on the GPU on both. The Core ML
provider already drops to the CPU for a background import; the Core AI provider has no such mode and its CPU
path is unusable.

**Alternatives.** Prefer a compute unit or run several calls at once in the Core AI provider (the owner had
approved both; measured as no gain on the phone, so neither was built). Export the Core AI model again so the
Neural Engine accepts it (needs `coreai-torch`, `torch` and `transformers` downloaded; not done). Move existing
libraries (rejected: a provider change clears a library and embeds it again, 144,247 passages for the owner's).

**Consequences.** The two providers are treated as one model by auto-tuning, though their vectors differ in
precision and scaling and a library must stay on one of them. Not measured: the two providers end to end in an
import, and how closely their vectors agree (`DebugEmbeddingBench.runProviders` exists for that and has not
finished a run). If a re-exported Core AI model beats Core ML on the Neural Engine, this decision is re-opened.
`[evidence_level: measured for the rates and the Mac finding; test_verified for the default and the copies rule, confidence: medium, evidence_source: scratchpad phone2/embedding_bench_models_1201.json as recorded in Docs/ai/STATE.md 2026-10-10; LargeLibraryCostTests]`

## 2026-10-10 - A large library is read through samples, with fixed limits

**Context.** A library of 144,247 passages on the owner's iPhone made the app slow at launch, on opening Chat
and the Atlas, and on the first question. Each cost was a step that walked every passage, and several ran on the
main actor.

**Decision.** Above a fixed size these steps work from an even sample taken in the library's order
(`RAGService.evenSampleIndices`): the Atlas and the other maps 6,000 passages; the query-expansion vocabulary
and the suggested-question sampler 4,000 (the sampler also keeps every document summary); the extractive spec
scan 20,000; the Atlas's term and phrase statistics about 2,000,000 characters in eight slices per long
document. Below those sizes nothing changes. Where a screen shows a sample it says so and shows the library's
real count.

**Rationale.** These are statistics of a library, and an even sample in the library's order is spread over
every document and repeatable. The alternative that keeps exactness, moving each step off the main actor and
letting it run over everything, leaves minutes of work and gigabytes of memory on a phone.

**Consequences.** A vocabulary built from a sample can miss a term that appears in few passages, and the spec
scan can miss the one passage that holds a value (the keyword and vector searches still look in full). The
limits are constants beside the code that uses them; none was tuned against retrieval quality.
`[evidence_level: test_verified for each rule (LibraryMapSampleTests, LargeLibraryCostTests, SystemToolsAndScanTests); not timed on a device, confidence: medium]`

## 2026-10-10 - The Knowledge Atlas takes its clusters from the embeddings and its names from the passages' own words

**Context.** The Atlas named clusters by matching keywords against a built-in list of subjects, and named an
axis with one word from a passage at its extreme. On the owner's library three clusters were all "API
Reference", names and sizes changed between launches, and the axes read "Return", "Document" and "Text". He
asked for a fix "genuinely universal" to any content.

**Decision.** `AtlasLabeling` holds the whole rule as pure functions. Membership is a k-means over the sampled
embeddings with fixed starting centres (1 cluster below 12 passages, otherwise 2 to 6). A cluster's name is the
one or two words most over-represented in it against the sample; a word in more than 40% of passages names
nothing; no two clusters share a name; a library that is all one group is named by its commonest words; with
nothing to go on a cluster is "Group N". An axis is labelled at both ends from its lowest and highest tenth of
passages, or "Component N". Words are split with `NLTokenizer`. The subject list and the code around it, about
1,770 lines, are deleted.

**Alternatives.** Keep the list and extend it (rejected: it is the thing that is specific to some content).
Ask the on-device model to name clusters (rejected for now: a model call per cluster on every Atlas open, and
names that would change between runs).

**Consequences.** Names are words from the library, so they are only as good as its words: a library of codes
or numbers gets "Group N". The map views and `LibraryVisualizationEngine` each cluster their own sample, so
the chips under the map and the labels in it may show different counts; not checked on a device.
`[evidence_level: test_verified (AtlasLabelingTests), confidence: medium; not seen on a device]`

## 2026-10-10 - iCloud sync leaves a library's vector store alone during an import, and remembers across launches that two copies matched

**Context.** `WorkspaceSyncService.synchronizeVectorStore` decodes both copies of a library's store, keeps the
passages whose document has a record, and writes back what differs. An import saves its document record last.
A device trace held 135 full decodes of one store during one import, and in a library with another document the
pass would have written the store back without the import's passages. Separately, the record that two copies
matched lived in memory, so every launch decoded and compared every synced library.

**Decision.** A pass skips the vector store of any library with an unfinished import on this device, read from
the import queue before the documents and again before the vector step. The record that two copies matched is
kept across launches as a digest of the same signature (sizes, dates, documents, aliases, strategy).

**Rationale.** The file's own rule is that a stale index is recoverable and a deleted one is not. Skipping
costs nothing: the store syncs on the first pass after the import ends. The digest is trusted under exactly the
conditions the in-memory record was.

**Consequences.** An import that both starts and finishes inside one pass is not covered. The first pass after
an import still decodes both copies and writes a whole second copy for iCloud (381 MB for the owner's library).
`[evidence_level: test_verified for the rules (WorkspaceSyncImportGuardTests, LargeLibraryCostTests); measured for the 135 decodes; code_verified for the loss it prevents, confidence: medium]`

## 2026-10-10 - The vector store keeps its file format; the plan is to index the passage file, not to move it (planned, not built)

*Built on 2026-10-12. The record of that date, "The vector store indexes its passage file", says what was built, what was measured and what was left.*

**Context.** `BNNSVectorDatabase` decodes `_meta.json`, every passage's text, into memory on load: 159 MB and
3.0 to 3.2 s for 144,247 passages. That one decode per launch, the memory it holds, and every save rewriting
the whole store are what still grow with a library after the sampling above.

**Decision.** Planned for 5.7 and not started: keep the three files and their layout; memory-map `_meta.json`;
hold a small per-passage index in memory (id, document, number, page, level, byte range of the passage's JSON
object) rebuilt when the file changes; decode a passage when it is asked for; move callers from `allChunks()`
to count, by-index, by-document and sample methods. The caller inventory is in
`BenchmarkRuns/2026-10-10-large-library/W3-store-callers.md` (local; not yet read or checked).

**Alternatives.** Passages as SQLite or SwiftData rows with only vectors in the store (rejected for now: a
format change to a protected file, a migration for every existing library, and the keyword index, the only
other copy of the text, is a local cache that iCloud does not carry).

**Consequences.** No migration and no change to what syncs. Saves stay whole-file rewrites until an
append-only save is designed, which needs the loader to trim a partly written vector.
`[evidence_level: design, not built; the measurements are from the device trace of 2026-10-10]`

## 2026-10-10 - Background GPU Access is requested; work written by delegated agents lands only as a reviewed patch

**Background GPU Access.** `OpenIntelligence.entitlements` carries
`com.apple.developer.background-tasks.continued-processing.gpu`, added at the owner's instruction. The task's
status file on his iPhone read `backgroundGPUSupported = false` while background imports stopped within
seconds; `BackgroundTaskService` already asks for the GPU when the system offers it. The inference entitlement
(`...continued-processing.inference`, iOS 27) is not requested: Xcode 27.0's capability list has no entry for
it, and the model does not run on the Neural Engine today. Unverified: that a background import continues with
the key, and that App Store signing in Xcode Cloud accepts it.

**Delegated agents.** On 2026-10-10 the owner asked for delegated agents (Antigravity) to save this tool's
usage. The rule that came out of it: an agent that writes works in a detached worktree outside `~/Documents`,
runs no git and no build, and touches no protected file; its change reaches `main` only as a patch that was
read, corrected, built for a device and the Mac, and run through the suite here. Of four such jobs that day,
three needed corrections: inverted logic that followed an error in the brief, a dozen redundant accessors,
mislabelled call sites, and tests that assumed a tie-break. A read-only survey on a weaker model reported Core
AI as absent from the SDK. The procedure is in `Docs/ai/RUNBOOK.md`, "Delegated agents".
`[evidence_level: build_verified for the entitlement (codesign shows the key); the agent record is from the session of 2026-10-10]`

## 2026-10-12 - Thirteen 5.7 decisions are recorded after the fact

**Context.** An audit of the documentation on 2026-10-12 found that thirteen design decisions made for 5.7 on
2026-10-09 and 2026-10-10 had a changelog entry and no record here.

**Decision.** The thirteen records that follow were drafted that day by a delegated read-only agent from
`CHANGELOG.md`, the ingestion, privacy and Atlas docs and the code, under the rule that a reason nobody wrote down
is written as "Not recorded." and not guessed. Twenty-three of their cited symbols, tests and figures were checked
by search before they were added, and one sentence about the JSON size limits was corrected. Each record carries
the date of its decision, so these thirteen are out of date order in this file.

**Consequences.** "Not recorded." in a record below means the reason was never written anywhere that was read. It
does not mean there was none.
`[evidence_level: artifact_derived, with the spot checks code_verified, confidence: medium, evidence_source: CHANGELOG.md 5.7; the records' own evidence lines]`

## 2026-10-09 - JSON and JSON Lines files import as records, read by the app's own order-keeping reader

**Context.** Through 5.6 a `.json`, `.jsonl` or `.ndjson` file came in as its text as written, cut wherever the
chunker's word window fell.

**Decision.** `JSONRecordExtractor` writes each record (a line of JSON Lines, an element of a top-level array, an
object or list member of a top-level object) as a `Record N of T` header and `path: value` lines. It parses with
its own reader, `JSONValue.parse`. A file that does not parse and a `.json` file over 16 MB take the text lane.
A JSON Lines file read in one go has a limit of the same kind at 64 MB, which a `.jsonl` or `.ndjson` file no
longer reaches, because over 8 MB it is imported in pieces, each piece as records (the next record). `.jsonl`
and `.ndjson` are stored as `DocumentType.json`.

**Rationale.** `JSONSerialization` loses member order, a number's own digits and members with the same name. A new
type case would not decode on an older build reading the same library.

**Alternatives.** Not recorded.

**Consequences.** The 16 MB figure is a guess at what a phone can hold as one parsed tree and has not been
measured. No `.jsonl` has been picked in the iOS document picker.
`[evidence_level: test_verified for the extractor, inferred for the stored type, confidence: high, evidence_source: CHANGELOG.md 5.7 Added, Docs/INGESTION_PIPELINE.md JSON section, Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md, JSONRecordExtractor.swift, JSONRecordExtractorTests]`

## 2026-10-09 - A text, Markdown or JSON Lines file over 8 MB is imported in pieces with a checkpoint after each

**Context.** Read whole, the owner's 88.50 MB JSON Lines file reached a footprint of 2,830.73 MB during cleanup
and the import never finished.

**Decision.** A text, Markdown, `.jsonl` or `.ndjson` file over 8 MB (`DocumentProcessor.piecewiseTextBytes`) is cut
into pieces of about 2 MB, with a checkpoint after each piece. The document's text is stored once at the end. A
piece the app stopped while storing is imported again if neither store has it and counted if both do. If only
the vector store has it, its index rows are rebuilt (`Recovery.finishIndex`, since 2026-10-10).

**Rationale.** The search index's append rewrites the whole stored text each time. Any other mismatch starts the
document over, because neither store can give up one piece's chunks.

**Alternatives.** The first rule started over in the vector-store-only state, and on 2026-10-10 sent a 17-part
import back to part 1.

**Consequences.** The vector store still rewrites its files whole once a piece. CSV, HTML, RTF and Office files
keep the one-go path.
`[evidence_level: test_verified for the cutting, the recovery decision and the saved state, build_verified for the import loop, measured for the footprint, confidence: medium, evidence_source: CHANGELOG.md 5.7 Fixed, Docs/INGESTION_PIPELINE.md section 5, RAGService+TextStreaming.swift, TextPieceReader.swift, TextPieceImportTests]`

## 2026-10-09 - The tenth and last App Shortcut slot goes to "Find Passages"

**Context.** Apple allows an app ten App Shortcuts, and through 5.6 the app registered nine. An eleventh makes the
whole set stop registering with no error.

**Decision.** `SearchPassagesIntent`, titled "Find Passages", takes the tenth slot. It returns the passages
`searchDocumentsRaw` finds in the active library and writes no answer. `AppShortcutsProviderTests` fails the suite
at eleven.

**Rationale.** The intent's comment says "Search Library" (now "Ask a Library") generated an answer and showed a
card, with nothing returned to the shortcut. This action returns the passages so a following step, or another
app's model, can read them. Why this action and not another took the last slot is not recorded.

**Alternatives.** Not recorded.

**Consequences.** No App Shortcut slot is left. The action has not been run from Shortcuts or Siri.
`[evidence_level: test_verified for the count, build_verified for the action, confidence: high, evidence_source: CHANGELOG.md 5.7 Added and Fixed, Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md section 12, SearchPassagesIntent.swift, AppShortcutsProviderTests]`

## 2026-10-09 - Shortcuts ask actions build an engine per question and the other actions use the app's engine

**Context.** Every action in `RAGAppIntents.swift` built its own `RAGService()`, and each new engine pointed the
weak `activePresentedInstance` at itself. After one action ran, the actions that reach for the app's engine got a
second engine instead.

**Decision.** The engine's initializer registers itself only when no engine is registered, and `ContentView`
registers the app's engine. Actions that change or list what the app shows call `IntentSupport.engine()`, which
returns the app's engine when there is one and a new one otherwise. The ask actions build an engine of their own
for each question.

**Rationale.** A second question on the app's engine would cancel an answer the chat is generating, because
`executeAgenticQuery` cancels the active generation.

**Alternatives.** Not recorded.

**Consequences.** An engine built while the app is closed has no entitlement store. `createNewThread` then reads
the plan from UserDefaults, and the document limit at import falls back to the free limit. Not run with the app
open or closed.
`[evidence_level: code_verified, confidence: high, evidence_source: CHANGELOG.md 5.7 Fixed, Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md section 12, IntentSupport.swift, RAGService.swift, ContentView.swift, RAGAppIntents.swift AskActionRunner]`

## 2026-10-09 - A question can be limited to named documents through RAGQueryScope

**Context.** "Ask About a Document" put the file name into the question, and `query` has no document filter, so
an answer could come from any document in the library.

**Decision.** `RAGQueryScope.documentIds` is a task-local set that `AskActionRunner` sets around one `query` call.
`HybridSearchService.search` then scores only the named documents' passages. Standard narrows its result and
candidate lists, skips the query cache, and throws `RAGQueryScopeEmptyError` when no passage is left. Deep Think,
Maximum and `searchDocumentsRaw` narrow their candidate lists. `AskActionRunner` refuses an answer whose passages
are not all from the named documents.

**Rationale.** The library-wide vector index and FTS5 ignore the candidate list, and a small document in a large
library would be crowded out.

**Alternatives.** A first version narrowed only the Standard result after a library-wide search. It leaked through
three later searches and did nothing in Deep Think or Maximum.

**Consequences.** No scoped question has been run. The runner's last check stands behind the limit until one has.
`[evidence_level: test_verified for the scope's filter and inheritance (RAGQueryScopeTests), code_verified for the four places, confidence: medium, evidence_source: CHANGELOG.md 5.7 Fixed, Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md, RAGQueryScope.swift, HybridSearchService.swift searchInsideScope, RAGService.swift]`

## 2026-10-10 - MetricKit reports are kept on the device only

**Context.** MetricKit's iOS 27 Swift API (`MetricManager`) delivers the reports the system gives an app about
itself: hangs, crashes, CPU and disk exceptions, and launch and memory figures.

**Decision.** `MetricDiagnostics` subscribes to the diagnostic and metric report sequences. Each report becomes
"[MetricKit]" lines in the pipeline log and one JSON line in `metric_reports.jsonl` in the local cache folder,
newest 200 kept. It starts at launch, not under tests, and does nothing before iOS 27.

**Rationale.** Not recorded.

**Alternatives.** Not recorded.

**Consequences.** The file has no upload code and makes no request, so the reports go nowhere. Whether a person
shares analytics with Apple is the system's own setting and is neither read nor changed. No report has been
received on a device yet. The file was written by a delegated agent and reviewed.
`[evidence_level: build_verified, test_verified for the formatting and trimming helpers (MetricDiagnosticsTests), confidence: low until a report arrives, evidence_source: CHANGELOG.md 5.7 Added, Docs/PRIVACY_AND_ROUTING.md, Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md section 9, MetricDiagnostics.swift]`

## 2026-10-10 - The two system model tools are registered and off by default, with no Settings control

**Context.** iOS 27 and macOS 27 provide two tools for FoundationModels sessions: `OCRTool`, which reads text from
an image, and `SpotlightSearchTool`.

**Decision.** `SystemModelTools` in `FoundationModelToolRegistry.swift` adds each to what `createTools` returns only
when its `UserDefaults` switch is set (`systemTools.ocr.enabled`, `systemTools.spotlightSearch.enabled`). Both are
off when unset. `SpotlightSearchTool` searches the app's own Core Spotlight index only, with at most 8 results, and
never the files source. There is no Settings control.

**Rationale.** A tool's description takes room in the model's window on every request, and neither tool has been
tried on a device with this app's questions. Why there is no Settings control is not recorded.

**Alternatives.** Not recorded.

**Consequences.** With both off, `createTools` returns what it returned before. Whether either tool is offered to
a session routed to Private Cloud Compute has not been observed.
`[evidence_level: build_verified, test_verified for the switches (SystemToolsAndScanTests), confidence: low for behaviour, evidence_source: CHANGELOG.md 5.7 Added, Docs/PRIVACY_AND_ROUTING.md, FoundationModelToolRegistry.swift]`

## 2026-10-09 - The Documents screen uses its own Paste control, not the system PasteButton

**Context.** The first development build of 5.7 used the system's `PasteButton` on the Documents screen.

**Decision.** On 2026-10-09 it was replaced by `LibraryPasteButton`, a plain button whose label is the screen's
own action chip. It reads `UIPasteboard.general.itemProviders`, or `NSPasteboard.general` on the Mac, through
`PastedContentStaging.clipboardProviders`.

**Rationale.** `PasteButton` draws itself and cannot take the chip's look, so it did not match the controls
beside it.

**Alternatives.** The system `PasteButton`, which reads the clipboard without asking.

**Consequences.** iOS asks "Allow Paste" when the copied content came from another app, unless the person has set
Paste from Other Apps to Allow. On iPhone and iPad a declined prompt ends in the same "Nothing to Paste" alert as
an empty clipboard. Command-V with no button pressed is not handled. Nothing has been pasted into a running app.
`[evidence_level: test_verified for how pasted content is told apart, build_verified for the control, confidence: medium, evidence_source: CHANGELOG.md 5.7 Added, Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md, PastedContentStaging.swift LibraryPasteButton, PastedContentStagingTests]`

## 2026-10-09 - Completion notifications are off by default and carry fixed text

**Context.** The app posted no notifications through 5.6.

**Decision.** `CompletionNotificationService` posts one when an import batch finishes, or when a question that ran
20 seconds or longer finishes, and only while the app is not in front. It is off until the switch on the Settings
Notifications page is turned on, which is when the system's permission prompt appears. The text is one of four
fixed sentences. The rule that writes it is handed only whether something finished and how long it took.

**Rationale.** A notification can be read on a locked screen, so it never carries the question, an answer or a
file name. An answer faster than 20 seconds was not worth leaving the app for. Why it is off by default is not
recorded.

**Alternatives.** Not recorded.

**Consequences.** A question asked from Shortcuts is not announced. If the system has notifications off for the
app, the switch goes back off. No notification has been posted on a device.
`[evidence_level: test_verified for the rule, build_verified for the service and the Settings page, confidence: high, evidence_source: CHANGELOG.md 5.7 Added, Docs/PRIVACY_AND_ROUTING.md, CompletionNotificationService.swift, CompletionNotificationPolicyTests]`

## 2026-10-09 - A document that would need more than 50,000 passages is refused, not truncated

**Context.** The chunker stops at 50,000 chunks (`SemanticChunker.maxChunks`). Through 5.6 it logged nothing and
the import went on as if the text were whole.

**Decision.** The chunker records the stop (`stoppedAtChunkLimit`) only when words are left after the furthest
chunk. On the import path the import fails with `DocumentProcessingError.tooManyPassages` and the stored text is
removed. The message says the file needs more than 50,000 passages and asks for smaller files.
`SemanticChunker.exceedsChunkLimit` refuses from the word count first, and a text over about 31 MB is counted
before cleanup.

**Rationale.** The silent stop left the rest of the text unindexed. Why refusing was chosen over a higher limit is
not recorded.

**Alternatives.** Not recorded.

**Consequences.** A text or JSON Lines file over 8 MB is imported in pieces, where the limit applies to a piece and
not to the document. The refusal still applies to a text the fallback chunker takes whole.
`[evidence_level: test_verified for the limit, the early check and the message, build_verified for the processor's handling, confidence: medium, evidence_source: CHANGELOG.md 5.7 Fixed, Docs/INGESTION_PIPELINE.md section 3, SemanticChunker.swift, SemanticChunkerLargeTextTests]`

## 2026-10-10 - Text files are decoded in a fixed encoding order, and embedding input is cut at the model's window

**Context.** `readTextFileWithFallbackEncodings` tried UTF-8 and then Latin-1, which never fails, so a Shift-JIS,
EUC-JP, GB 18030, Windows-1251 or UTF-16 file was imported as garbage with no error. Both large-file paths cut any
passage over 500 tokens to its first 1,500 characters before embedding.

**Decision.** `DocumentProcessor.decodeTextFile` reads UTF-16 by its byte-order mark, UTF-16 with no mark by its
zero bytes, UTF-8, Foundation's lossless detection, then Windows-1252 and Latin-1. `RAGService.embeddingText` sends
a passage whole when it fits `maxSafeTokens` and cuts one that does not at the last character that fits.

**Rationale.** Latin-1 gives every byte a character. 1,500 characters is about 350 tokens for a model that reads
512, so a passage lost about a third of what its vector could cover.

**Alternatives.** Not recorded.

**Consequences.** Mac Roman is not handled. How many passages the old cut shortened was not measured.
`[evidence_level: measured on macOS 27 with a copy of the decoder (13 cases), test_verified (IngestionAccuracyTests), confidence: medium, evidence_source: CHANGELOG.md 5.7 Fixed, Docs/INGESTION_PIPELINE.md, DocumentProcessor.swift, RAGService+TextStreaming.swift, RAGService+Streaming.swift]`

## 2026-10-09 - A first suite on Apple's Evaluations framework grades the claim check

**Context.** The repository had no use of Apple's Evaluations framework (Xcode 27). `AppleEvaluationsBridge.swift`
was an older placeholder that imports no Evaluations.

**Decision.** `ClaimCheckEvaluationTests`, a Swift Testing suite in the test target, runs seventeen labelled
sentences through `VerificationGateService` and scores whether each reads Supported. The thirteen the check claims
to judge are asserted at 100%. The overall figure, which counts four known failures, is printed and not asserted.
The test target finds the framework with no project change. `AppleEvaluationsBridge.swift` is left as it was.

**Rationale.** No model runs, so the suite works in the simulator. The overall figure is printed so the gap stays
visible in the evaluation report.

**Alternatives.** Not recorded.

**Consequences.** It does not grade an answer written by the model, which the simulator cannot produce. Its first
run gave thirteen of thirteen where the check claims to work and thirteen of seventeen overall.
`[evidence_level: test_verified, confidence: high for what it measures, evidence_source: CHANGELOG.md 5.7 Added, ClaimCheckEvaluationTests.swift, the Evaluations interface in the Xcode 27.0 SDK]`

## 2026-10-09 - Every link the app shares carries one campaign tag, In_App_Share

**Context.** Share the App, a shared answer and a Markdown export hand an App Store link to other people.

**Decision.** `OpenIntelligenceLinks.sharedAppStoreURL` is the App Store link with the provider token the
repository README already publishes and the campaign tag `In_App_Share`. All three use it. About's "open in the
App Store" keeps the plain link.

**Rationale.** App Store Connect shows a campaign only after first-time downloads from five people, so splitting
the tag would hide the number.

**Alternatives.** A separate tag for each place, which the code comment says would hide the number.

**Consequences.** Downloads from the three places are reported under one campaign. Apple's limit for a campaign
token is 30 characters.
`[evidence_level: test_verified (OpenIntelligenceLinksTests), confidence: exact, evidence_source: CHANGELOG.md 5.7 Added, AboutView.swift OpenIntelligenceLinks, SettingsView.swift shareApp]`

## 2026-10-12 - The vector store indexes its passage file and decodes a passage when asked; the steps that read every passage's text stay as they are

**Context.** The plan of 2026-10-10 (the record "The vector store keeps its file format") was approved by the
owner on 2026-10-12 ("ok now do the storage change"). `BNNSVectorDatabase` decoded `_meta.json` whole at every load
and held every passage's text: 159 MB of JSON and 3.0 to 3.2 s for the owner's 144,247 passages, and every save
encoded all of it again.

**Decision.** Keep the three files and their format. Map `_meta.json`, walk it once for a 72-byte record per passage
(`PassageFileIndex`), decode a passage from its own bytes when it is asked for, and write a save by copying the
bytes of passages already in the file. Give the store protocol methods for records, positions, one document and
ids, and move the callers that used a few passages onto them. Leave `allChunks()` in place: its first call decodes
every passage on several threads and the store keeps them, as it kept them from load before.

**Rationale.** A load that only indexes is what a launch, a library switch, a count and a sync check need. The
walk is trusted only where it is certain: anything not shaped as the encoder writes it goes to `JSONDecoder`, a
decoded passage must carry the id its record names, and the walk in several stretches is accepted only when
every stretch ends exactly on the next one's start.

**Alternatives.** (1) A second file holding the records, so a launch reads 10 MB and walks nothing. Rejected:
it is a second source of truth that can go stale when sync replaces the metadata file, checking it against the
file's content costs about what the walk costs (0.02 s optimised on the Mac), and it would only help
unoptimised builds. (2) Appending new passages to the file in place. Rejected for now: a write that is cut off
leaves a file that is not a JSON array, which an older build on the same iCloud library cannot read. Saves stay
whole-file and atomic. (3) Moving the question path off the full array. Not done: the summary, enumeration,
parent-expansion, cross-reference, extractive-scan and multi-hop steps read every passage's text for each
question, so serving them from the file means a decode for each question, or asking the keyword index instead
of scanning memory, which is a change to retrieval and has no end-to-end test to hold it. (4) Sampling the
library analysis (`refreshIntelligence`). Not done: it measures vocabulary richness and total words over all the
text and those feed the embedding plan, a sample shifts both, and a shifted plan can start a rebuild of the
library.

**Consequences.** On the Mac with 144,247 synthetic passages (unoptimised build): load 1.97 s to about 0.62 s,
memory after a load 276 MB to 11 MB, the saves of building the library 60.8 s to 13.8 s, a delete 2.31 s to
under 1 s. Memory is unchanged once every passage has been asked for, which the library analysis does at launch
and the question path does for each question: 329 MB against 330 MB for a plain decode. The store drops its
decoded passages under memory pressure and reads them back. Eleven callers still read every passage's text,
listed in the changelog entry. *(The figures in this paragraph are the first version's. The record that
follows this one says what the review changed, and the changelog entry carries the figures of the code as
committed.)* Run over copies of the nine metadata files on the owner's iPhone (145,500 passages, written by
builds from 2026-09-14 on), the walk and the decoder agreed on every passage, and the 159 MB file walked in
0.015 s optimised and 0.17 s unoptimised on the Mac. The figures on the owner's iPhone are not known: the walk in an unoptimised build is the
part most likely to differ, and the first launch of a build with this change prints it as `[VectorLoad]`.
`[evidence_level: test_verified for the format, the alignment of vectors and passages, and the moved callers (VectorStorePassageIndexTests); measured on the Mac for the figures (VectorStoreScaleBenchmarkTests, 2026-10-12); not run on a device, confidence: high for what was built, medium for what a phone will show, evidence_source: BNNSVectorDatabase.swift, PassageFileIndex.swift, VectorDatabase.swift; CHANGELOG.md 5.7 Changed]`

## 2026-10-12 - After review of the storage change: a load never writes, a delete saves what is unsaved first, and a passage that cannot be read is left out

**Context.** The storage change of the record above was committed locally and handed to a second agent told to
refute it, before anything was pushed. It found seven things, listed in `CHANGELOG.md` (5.7, Changed, the second
Indexing entry). The two that could have damaged a library: a delete ended part-way while passages were unsaved
could leave a vectors file the loader reads as a cut-off save, with every passage on a neighbour's vector, and
`allChunks()` handed back a shorter array when one passage failed to decode, which sync pairs with the vectors
by position.

**Decision.**
1. A load reads and never writes. Vectors the metadata does not list are ignored in memory and the next save
   writes the file at its right length. Fewer vectors than passages loads the store empty and leaves the files.
2. A delete and an update write out anything unsaved before they take a vector out of the middle of the file.
   That keeps one rule true for the loader: a cut-off save leaves more vectors than the metadata lists, all after
   the listed ones, and a cut-off delete leaves fewer.
3. A passage whose bytes no longer decode is counted and left out: of searches, of reads of a document or by
   id, and of `readableChunks()`, which every reader of text in the app now calls. `allChunks()` throws instead,
   and sync is its one caller.
4. Each file is written under a unique name in the system's replacement directory for the store's volume,
   synchronised to disk, and renamed over the destination.
5. A caller that picks passages from the store's records reads them by id. `chunks(atIndices:)` is gone.
6. The scoped search gets its similarities from vectors asked for by id, inside `HybridSearchService`.

**Alternatives.** (a) Leave the unreadable passage out of `allChunks()` too. Rejected: `WorkspaceSyncService`
pairs that array with `getEmbeddings(forIndices:)` and would write both copies of the library with every later
passage on its neighbour's vector. That file is a hard boundary and was not edited. (b) Have every reader
throw. Rejected: through 5.6 one passage that did not decode emptied the library at load, and throwing would
have made that a library in which every question fails. (c) Remove the unreadable passage from the files when it
is found. Rejected: it is a write made from a read, sync's store could make it while the app's store is saving,
and if the fault were ever in the store's records and not in the file it would delete good passages. Nothing is
lost by leaving the bytes, and deleting the document removes them. (d) A method on the store that scores
passages against a vector where the vectors are, with none copied out. It was written and taken out again: it
is the faster way to rank a very large document, and it is an addition to `BNNSVectorDatabase.swift` for
retrieval, which the owner's go-ahead for the storage change does not cover. It waits for his word.
(e) `FileManager.replaceItemAt`. Not used: `rename` replaces in one step whether or not the destination exists.

**Consequences.** A library with a passage that cannot be read answers questions without it, and does not sync
until the document is deleted or imported again; the pipeline log names the cause. Saves cost a synchronise
each: the 49 saves of building the 144,247-passage store took 15.5 and 16.3 s in two builds, against 13.8 s
without it and 60.8 s in the 5.6 code. The cut-off cases are held by tests through a hook that exists only in
debug builds (`interruptMetadataWrites`). Two stores open on one library's files at once is still not tested.
`[evidence_level: test_verified (BNNSVectorDatabasePersistenceTests, VectorStorePassageIndexTests, HybridSearchServiceTests; the full suite on 2026-10-13, 864 tests with 0 failures and 4 skipped), measured on the Mac for the save figures, confidence: high for the cases the tests reproduce, evidence_source: BNNSVectorDatabase.swift, PassageFileIndex.swift, VectorDatabase.swift, HybridSearchService.swift; CHANGELOG.md 5.7]`

## 2026-10-13 - A large library is analysed from a sample, the analysis is kept until the library changes, and a sample never changes the embedding model

**Context.** The owner answered the list of what the storage change left open with a go-ahead for all of it.
The first thing measured was the library analysis (`LibraryIntelligenceCenter.analyzeLibrary`), which `RAGService` ran over every
passage whenever the app loaded its documents, after every import and after every delete. On the 144,247-passage
benchmark store it took 199 s and 1,054 MB over what the process held (Mac, unoptimised build), against 0.7 s
for the store's own load. Its output feeds two things: three screens (the Database card, the Pipeline Audit,
Library Settings), and the chunking settings of a library that tunes itself. A third is written and switched
off: a queued rebuild that embeds the whole library again when the plan changes
(`IngestionContext.allowsSelfTuningScheduling` is false for every kind of import).

**Decision.** Past 4,000 passages, analyse at most that many, read by id: up to a quarter the documents' first
passages, the rest an even sample. Keep the library's real counts in the report and mark it an estimate. Never
take another embedding model from an estimate, except for a library with no documents yet; let the chunking
settings follow an estimate as they follow any report. Keep the report, and the vocabulary the first question
builds, in the app's local cache folder under a name that carries a hash of the library's documents and the
store's passage count, and use a file only under the name the library has now. Keep a vocabulary only when it
was built from every passage in the store and each belongs to a listed document. Remove what no longer matches
at once: for one library on every refresh, after every write and on its deletion, and for all of them each time
the documents are loaded, and never before they have been loaded once. End an import in pieces with the same
refresh as any other import. Build the vocabulary, pick the sample and read and write the kept files off the
main actor; write them in place. Hold a vocabulary in memory for later questions only when it is of the whole
library as the library is when the build ends.

**Alternatives.** (1) Compute the size-dependent measures exactly by streaming every passage. Rejected: the cost
is the tokenising itself, so it would still be minutes on a large library. (2) Stop analysing at launch and do
it only when a screen asks. Rejected: the settings a self-tuning library gives its next import are decided from
the report at launch, and a kept report gives the same decision without the work. (3) Let a sample change
every setting, or none. Both were tried in this session. Letting it change everything was rejected after the
first review: whether code or math is found in a sample depends on which passages were drawn, and the draw
moves whenever the passage count does. Letting it change nothing was built next, on the first review's ground
that an import seeing a changed plan queues a re-embedding of the library, and rejected after the second: that
queue is behind `IngestionContext.allowsSelfTuningScheduling`, which is false for every kind of import, so no
report can start a rebuild today; and each import rewrites the chunking settings from the file it reads, so a
large library would have kept the last file's settings with nothing to move them back. What is left is the
rule above: the half that would cost a rebuild is closed to an estimate, and the half that costs nothing is
not. (4) Keep the files in the system's Caches folder. Tried and rejected after review: every other path in
the app goes through `OpenIntelligenceRuntimePaths`, whose overrides exist because a path that ignored them
once put benchmark fixtures in the owner's real library. (5) Put the signature inside the file. Rejected for
the name: staleness can then be told from a folder listing, which is what makes checking every library on
every load of the documents cheap. (6) Remove a kept file only when a forced refresh comes. Tried and rejected
after review: a document removed by sync arrives through a refresh that is not forced, a library removed by
sync through none, and opening the audit screen forces one with nothing changed. (7) Write the kept files atomically. Tried, and changed after the third review: an atomic write keeps a
temporary file beside its destination under a name the removal does not know (seen on macOS 27 by listing the
folder during a write), the removal clears unknown names so that a file from an older naming scheme cannot
linger, and once the writes moved off the main actor the two could overlap. A file written in place and cut
short does not decode, which is the same as nothing kept. (8) Speed up the analysis
itself. Not done: it would change results in corner cases for every library, and what is left is about 6 s on the Mac,
once per change of a large library.

**Consequences.** A launch with an unchanged library reads no passages for the analysis. A library past 4,000
passages has its chunking settings follow a sample, and its embedding model stays what it is until someone
changes it by hand; its screens say how many passages were measured. A document the sample did not reach is
shown without a preview. The first question after a change to a library no longer holds the main actor while
its vocabulary is built, and a question limited to named documents no longer leaves a vocabulary of those
documents behind as the library's. Two more files per library exist on the device, with text from its documents in them, and they go
when that text's documents go. A report held in memory no longer outlives a change to the library's documents.
`[evidence_level: test_verified (LibraryAnalysisSampleTests) and measured on the Mac (LibraryAnalysisScaleBenchmarkTests, 2026-10-13); everything inside `RAGService` (the calls that remove kept files, the refresh after an import in pieces, which actor each piece runs on, the switch that keeps a rebuild from being queued) is code_verified, not driven by a test; not run on a device, confidence: high for the mechanism, medium for a sample standing in for the whole on real libraries, evidence_source: AdaptiveEmbeddingOptimizer.swift, RAGService.swift, QueryEnhancementService.swift, ContainerService.swift, ContentView.swift]`

## 2026-10-13 - A question inside a very large document compares words for its candidates only, and the store scores vectors where they are

**Context.** `searchInsideScope` read every passage of the named documents and searched each for the question's
words. Its own comment said a document is a few thousand passages at most; the owner's library is one document
of 144,247. The review of the storage change had also shown its similarities were all 0, fixed in `c73b3b9` by
asking for vectors by id because `BNNSVectorDatabase.swift` could not be given a method then.

**Decision.** The owner's go-ahead of 2026-10-13 came in answer to a report that said the faster form waited
on his word for that file. He did not name the file himself. The agent read the answer as his word for it,
said so in its reply, and limited the change in that file to methods that read: `similarities(to:forChunkIDs:)`,
which scores in place, and the release of decoded passages. The file's format is untouched. If that reading
was wrong, both come out of the file without touching anything stored. Up to 6,000 passages in scope, nothing else changes: every passage is read and
scored both ways. Past 6,000, every vector is scored, and words are compared only for the 2,000 closest
passages and the keyword index's best 400 hits inside the scope. The rule is the same whether passages are
handed in or read by id. With no vector to score at all, every passage is read, and a question whose own
embedding failed counts as that. The closest passages are picked off the main actor, ties in store order.

**Alternatives.** (1) A keyword query restricted to the document. Not available: `SQLiteFullTextService` has no
such query, and it is a hard-boundary file that was not edited. Its library-wide hits are narrowed to the scope
instead. That search matches every word first and any word only when nothing matches all of them, so a passage
outside the scope that holds every word leaves the scope with no keyword candidates, and a large library can
crowd a document's hits out of the 400. Both need a scope past 6,000 passages that is not the whole library;
below that every passage is read. (2) Keep reading every passage.
Rejected for that size: it decodes 330 MB and lowercases all of it for each question.

**Consequences.** A scoped question on the 144,247-passage document reads the text of at most 2,400 passages. A passage far
from the question whose only match is on words the index does not rank in its best 400 can be missed there.
`[evidence_level: test_verified (HybridSearchServiceTests), not run on a device, confidence: high for the mechanism, evidence_source: HybridSearchService.swift searchInsideScope; BNNSVectorDatabase.swift similarities]`

## 2026-10-14 - Spotlight entries last as long as their document, and each way a document leaves removes them

**Context.** Through 5.6 a document's Spotlight entry and its passages' entries expired 30 days after they were
written and nothing wrote them again, so a document imported a month earlier could not be found from Spotlight,
and a deleted document's passages stayed searchable for up to 30 days. 5.7 makes documents and libraries
Spotlight's app items (`IndexedEntity`), which Siri and Apple Intelligence use, so an entry that vanishes after a
month breaks those too. A refuting review on 2026-10-14 found what permanent entries cost: a document deleted on
another device, an import that failed after its entry was written, and the Settings switch turned off each left
entries with no end. Core Spotlight cannot list what an app has indexed, and its header does not say whether an
update (`isUpdate`) moves an entry's expiry (CSSearchableItem.h, read 2026-10-14).

**Decision.** Entries are written with no expiry. Every way a document can leave removes its entries: a delete on
this device (`deindexDocument`, recursive through the passage domain), a delete on another device (`documentsLoaded`
compares each read of the document records with a list of the documents this device knows, kept in
`localCacheDir()/spotlight_documents.json`, identifiers only, and leaves an import in progress alone), an import
that fails or is cancelled (its catch), a passage write a delete overtook (removed once written), and the switch
turned off (`deleteAllSearchableItems`, with the saved activities and the Open Library donations). A read of the
records that fails changes nothing, because an empty list would remove every entry. Entries made by 5.6 are
written again whole on the first launch of 5.7, with the document's first 500 characters read again from the
full-text store, rather than refreshed as updates.

**Alternatives.** (1) Keep a 30-day expiry and refresh entries from the background task. Rejected: a refresh can
re-add documents and libraries from their records but not passages, whose text is in the libraries, and the
background task runs when the system allows. (2) Rebuild the whole index at each launch. Rejected: it rereads every
document's text and rewrites every entry for nothing on most launches. (3) Remove entries only from the records'
in-memory list. Rejected: a delete made on another device while this device's app was closed would never be seen.

**Consequences.** The device keeps one small file of identifiers. A library deleted on another device keeps its own
library entry, as it did before 5.7; its documents' entries go. Passage entries made by 5.6 still expire on their
own schedule, and a document from another device is listed without passages.
`[evidence_level: test_verified (SpotlightItemsTests: the list's arithmetic and the preview text), build_verified, not run on a device; confidence: high for the mechanism; evidence_source: SpotlightIndexService.swift documentsLoaded, indexingSwitched, indexDocumentChunks, refreshEntriesMadeBefore57; RAGService.swift applyLoadedDocuments, loadDocumentsSnapshotFromDisk, addDocument]`

## 2026-10-14 - Enhanced Security waits for the capability on the App ID; when it goes in, pointer authentication stays off

**Context.** The owner approved Apple's Enhanced Security capability for 5.7 on 2026-10-14 (the row "Turn on
Apple's enhanced security for file parsing"). Apple's guide ("Enabling enhanced security for your app",
developer.apple.com, read that day) and Xcode 27's own reference for it (`audit-xcode-security-settings-ref-*`
in `IDEIntelligenceChat.framework`) describe it as a build setting, `ENABLE_ENHANCED_SECURITY = YES`, which turns
on pointer authentication (an `arm64e` slice), zero-initialised stack variables, security warnings, typed
allocators and C++ library hardening, plus entitlements for the runtime protections:
`com.apple.security.hardened-process` (true), `...enhanced-security-version-string` ("2", which also turns on
guard objects), `...hardened-heap`, `...dyld-ro` and `...platform-restrictions-string` ("2").
`[evidence_level: code_verified for the documents, confidence: high]`

**What was found.** (1) The Rust tokenizer the app links (`swift-tokenizers`, `TokenizersRust.artifactbundle`)
ships only `arm64` for iPhone and `arm64`/`x86_64` for the Mac, no `arm64e` (`lipo -info`, 2026-10-14), so pointer
authentication cannot be built for the app target; Xcode's reference says to set
`ENABLE_POINTER_AUTHENTICATION = NO` on a target in that position. (2) With the five entitlements and the two
build settings in place, the iPhone build failed: `Provisioning profile "iOS Team Provisioning Profile:
Gunndamental.OpenIntelligence" doesn't include the Enhanced Security capability`, and with
`-allowProvisioningUpdates` it failed with `No Accounts` (no Apple account in Xcode on this Mac).
`[evidence_level: measured, confidence: exact, evidence_source: the device build logs of 2026-10-14]`

**Decision.** The change was taken out the same day, so the tree builds and an Xcode Cloud archive is not put at
risk, and is ready to go back in as it was: the two build settings on the app target's Debug and Release
configurations (`ENABLE_ENHANCED_SECURITY = YES`, `ENABLE_POINTER_AUTHENTICATION = NO`) and the five entitlements
above in `OpenIntelligence.entitlements`. It goes back in once the App ID has the Enhanced Security capability: in
Xcode with the owner's account signed in (Signing & Capabilities, add Enhanced Security, which registers it), or
through the App Store Connect key if he says to use it for that.

**Alternatives.** (1) Leave the entitlements in and let Xcode Cloud register the capability. Rejected: whether its
managed signing adds a capability the App ID lacks was not established, and a failed archive blocks the release.
(2) Version "1" to avoid guard objects' memory cost. Not chosen: the values Xcode sets are "2", and the memory cost
on a large library is to be measured on a device instead.

**Consequences.** Until then the row stays open. When it goes in: measure an import of the 88 MB JSON Lines file on
the iPhone before and after (memory and passages per second), because guard objects and the hardened heap can raise
memory use, and the app's largest imports already run near the phone's limit; then decide on hardware memory
tagging (A19 and M5 or later only), which Apple recommends turning on in soft mode first.

## 2026-10-14 - A question from Siri or Shortcuts asks for Private Cloud Compute consent in the app, and a choice already made needs no sheet

**Context.** Through the first 5.7 builds an action's question never asked: in the background the planner kept it
on device unless consent was remembered, and with the app in front it reached the consent step on an engine no
chat shows and waited for good. The owner approved best practice for consent on 2026-10-14.

**Decision.** The five ask actions declare `[.background, .foreground(.dynamic)]`. When the system lets one come
forward, the planner may choose Private Cloud Compute for its question, and the consent gate calls
`continueInForeground` and asks with the same sheet, which `ContentView` shows through `CloudConsentRelay`. A
stored choice is applied before anything about the foreground (Always Allow sends, Don't Allow refuses, nothing
comes forward), read again for each question and step. A sheet no window shows within 15 s is given up without
being remembered, and that question asks no more. Only an action's engine (`asksThroughRelay`) uses the relay.

**Alternatives.** (1) Bring every action question forward while consent is undetermined: rejected, it would pull
the app forward for questions that never use Private Cloud Compute. (2) Keep the foreground check before the
stored choice: rejected, it made Always Allow useless for a question from the background on iPhone while the
planner had already chosen Private Cloud Compute for it, and it brought the app forward for nothing.
(3) Choose the relay by `activePresentedInstance !== self`: built first, rejected by a refuting review the same
evening, because that weak pointer can be nil or another window's engine.

**Consequences.** On iPhone a question from Siri with Always Allow now uses Private Cloud Compute in the
background; before 5.7 it fell back to the device. Not seen on a device.

## 2026-10-14 - Crash reports come from MetricKit inside the app, not from a crash reporter extension

**Context.** The roadmap row planned CrashReportExtension (iOS 27). A new extension target needs a provisioning
profile for its own App ID, and Xcode on this Mac has no Apple account ("No Accounts").

**Decision.** `MetricDiagnostics` already receives MetricKit's crash diagnostics. `CrashReports` saves each as a
file of its own, leaving out text that can carry the person's data (an exception's message and arguments, the
memory region description), and offers it once. Sending is the person's act: a mail they send from their own app,
or the share sheet.

**Alternatives.** Wait for the extension: rejected while provisioning is blocked, and MetricKit gives the same
report. Upload automatically: rejected, nothing leaves the device unless the person sends it.

## 2026-10-14 - Conversation deletions sync as a list, the way document deletions do

**Context.** Conversations moved into the folder iCloud sync merges (5.7), and the merge copies the newest file
each way and keeps no record of deletions, so a deleted conversation came back from iCloud.

**Decision.** `deleted_threads.json` beside the threads folder, joined across devices by
`WorkspaceSyncService.mergeDeletedThreads` (the file was named for 5.7) and honored on both sides, as
`deleted_documents.json` is for documents. A conversation stays one file with the newest copy winning, as the
chat history does; turns added on two devices before they sync are kept from one of them only.

**Alternatives.** Delete the iCloud copy from the store alone: rejected, another device would copy it back.

## 2026-10-14 - The query cache is keyed to what the libraries hold, and the lookup by similarity is off

**Context.** `semantic_query_cache` (`SQLiteFullTextService.swift`, protected as a whole file) was keyed by the
question and library id and never cleared, so a repeated question ignored new documents and brought deleted ones
back (since 3.7.0). Its similarity lookup decoded every cached question's embedding on every question.

**Decision.** `RAGService` builds the key from the question and a digest of every library's documents and passage
counts, the embedding model and the app's version; a hit naming a missing document is not used; no lookup by
similarity. The protected file is unchanged, so rows written through 5.6 stay in the table unused.

**Alternatives.** Delete stale rows: needs the protected file, not named. Keep the similarity lookup and check its
rows: its results carry no library state that `RAGService` can check.

## 2026-10-14 - Deep Think and Maximum run the verification gates as a label, and do not abstain on them

**Context.** Every answer mode was listed as verifying (`RAGQualityMode.usesVerificationGates` is true for all
three, and Settings lists Verify for each), while Deep Think and Maximum returned before the gates ran, so their
answers read Not Checked unless the source-only check ran. The App Store description says the app checks its
answers. Standard abstains when its gates fail below its threshold.

**Decision.** From 5.7 a Deep Think or Maximum answer that the source-only check did not check runs the same
`VerificationGateService.verify` and confidence policy as Standard (`RAGService.verifyAgenticAnswer`), and its
status string reads `verified:NN%` or `unverified:<gates>`, so the badge shows Verified or Unverified and the
failed gates are listed as warnings. The answer stays as written: the result is not passed into the structured
answer, because a structured answer rebuilt from a failed check can turn into a refusal, and these answers take
minutes of the person's time.

**Alternatives.** Abstain on a failed check, as Standard does: rejected for these modes, where a refusal after
minutes reads as the app failing, and the badge already says the check failed. Run the source-only check on every
answer instead: it rewrites the answer, which is a larger change than labelling it.

## 2026-10-14 - The background inference entitlement waits for Xcode or the developer portal to offer it

**Context.** Apple documents `com.apple.developer.background-tasks.continued-processing.inference` (developer.apple.com,
read 2026-10-14: required for any Neural Engine access while the app is in the background, iOS and macOS 27). It
was added to `OpenIntelligence.entitlements` at the owner's word, and the iPhone build with
`-allowProvisioningUpdates` refused it: "Entitlement ... not found and could not be included in profile. This
likely is not a valid entitlement and should be removed from your entitlements file." The iOS 27.0 SDK's
BackgroundTasks headers name only the `.gpu` key, Xcode 27.0's capability list has Background GPU Access and
nothing for inference, and the App ID's capabilities read through the App Store Connect API are In-App Purchase,
Background GPU Access, Private Cloud Compute and iCloud.

**Decision.** The key is not in the entitlements. Background imports keep asking for the GPU, which the App ID
has. The key goes in when Xcode's Signing & Capabilities or the developer portal lists it, or when Apple grants it
on request.

**Alternatives.** Keep the key in the file: every build fails signing, the Xcode Cloud archive included.

## 2026-10-15 - Fifteen roadmap rows that waited on a decision, settled or handed back

**Context.** The roadmap reconciliation of 2026-10-14 found fifteen open rows that could not move without a
decision. The owner asked on 2026-10-14 that they be decided by best practice, with the reasons recorded here. A
decision that needs his money, his choice of languages or a protected file he has not named is handed back, not
taken.

**Decided.**
- *Minimum OS stays iOS and macOS 26* (row "27 SDK deprecations"). Raising it to 27 would clear five deprecated
  `BGTaskScheduler.submit` calls and drop every iPhone and Mac still on 26; the calls work on 27. Revisit when the
  App Store's own figures show most of the app's users on 27.
- *Library sync stays file-based* (row "CKSyncEngine / SwiftData"). 5.7 fixed the measured causes of conflict copies
  (only changed files are sent, one coordinated replace per file, `WorkspaceSyncService`). A move to CloudKit
  records is a new App ID service and a migration of every synced library; it is reconsidered only if conflict
  copies keep growing on devices running 5.7.
- *The 86 MB model stays a plain git file* (row "86 MB model in git"; `EmbeddingModel.bundle/main.mlirb`, 90,352,203
  bytes). Git LFS on a public repository spends the owner's LFS bandwidth on every download of the file, Xcode
  Cloud's included, and a free account includes 10 GiB (docs.github.com, Git LFS billing, read 2026-10-15);
  rewriting history to move the file breaks every commit id quoted in the docs and the roadmap. No re-export is
  planned; if one is, the model is fetched at build time instead.
- *Additive-then-swap re-embedding is required before any release that moves existing libraries to another model by
  itself* (row "Additive-then-swap migration"). Until then, the only provider change is one the person starts in
  Library Settings, which asks "Rebuild embeddings now?" first. Stays Future Backlog.
- *No trigram keyword index* (row "FTS5 weights and trigram index"). It needs `SQLiteFullTextService.swift`'s
  schema, which is protected and not named for 5.7, and the row's own measurement was 104 to 263 percent more
  database on disk. The weights half is done.
- *No voting board* (row "Voting board"). Shared votes need a server, CloudKit's public database or an outside
  service, and a local-first app sends nothing out unless the person asks. The feature-request email stays.
- *Apple Notes is covered by Shortcuts* (row "Apple Notes integration"). There is no public Notes API: a DTS
  engineer answered "No" in developer.apple.com/forums/thread/813810 (January 2026, read 2026-10-15) and pointed to
  App Intents in a shortcut; the supported route is the app's own actions in a shortcut with Notes' actions, and
  5.7's "Add to Library" takes a note's text. The row closes when such a shortcut runs on a device.
- *The custom pipeline row is covered by Library Settings* (row "Custom RAG Pipeline Configuration"). Advanced
  Controls has minimum similarity, the vector and keyword weights, MMR's λ (which acts from 5.7), minimum confident
  passages and explicit citations, with four presets. No further control is added without a measurement that it
  helps.
- *The Vision OCR demo row is a test idea, not a feature* (row "Multi-Modal Verification (Vision OCR)"). 5.7's
  pictures are described from the picture, and an image with no readable text imports with its labels and
  description (`ImageUnderstandingService`, read from code; no test imports such an image yet).
- *Deep Think keeps its local reasoning chain by default* (row "Decide: long-context PCC pass vs the local reasoning
  chain"). The local chain sends nothing out; a long-context pass on Private Cloud Compute would send the documents'
  passages for every Deep Think question. It is reconsidered with an A/B on the owner's documents, which needs a
  signed build.

**Handed back to the owner.** *Which languages to localize into* (row "Localization"): a choice of markets and of
who checks the translations. *A per-answer-mode model profile* and *passages by reference* were moved to Future
Backlog at his word on 2026-10-14. *User-built reasoning profiles* and *visual document retrieval* need protected
files he has not named (`FoundationModelRoutePolicy.swift`, `BNNSVectorDatabase.swift`) and, for the second, a
third-party image model, which is his call: on 2026-10-06 he kept the app on Apple's models for generation, and no
decision covers a third-party model for search.

**Alternatives.** Leave every row waiting: rejected, rows nobody can close accumulate (the roadmap skill's rule).

## 2026-10-15 - A deletion in the app waits a few seconds before it removes anything

**Context.** Through 5.6 a delete removed a document's passages, text, Spotlight entries, file and iCloud copy at once,
and the catalogue row "Delete with confirmation, undo" asked for an undo. Removing passages and embeddings cannot be
reversed without importing the file again, which makes new embeddings and a new id.

**Decision.** A deletion takes the documents out of the list at once and runs the removal six seconds later
(`PendingDocumentRemoval.undoWindow`), unless it is undone (`RAGService.scheduleRemoval`). Nothing is removed in those
seconds, so an undo puts the documents back exactly as they were. The removal also runs when the app goes to the
background, before a library is deleted, and at the next launch if the app ended in those seconds; the ids are kept
per run of the app in `pending_document_removals.json` for that. Six seconds is a default chosen on 2026-10-15, not a
measurement.

**Alternatives.** A Recently Deleted area that keeps everything for days, as Photos does: every sweep that removes
passages or text with no document (`removeTextOfUnfinishedImports`, the iCloud sweeps) would have to know about it,
and a shared library's other devices would keep showing the document. Restoring by importing again: slower, and the
document comes back with a new id, so conversations citing it lose the link.

**Consequences.** Another device sees the deletion only when the removal runs, since the record of a deleted document
(`registerDeletedDocuments`) is written then. A Mac app quit in those seconds removes the documents at its next launch;
a Mac window closed in them keeps its engine until the removal runs. In those seconds Spotlight still finds the
documents, while Shortcuts and Siri no longer list them. Anything that empties or rebuilds a library runs pending
removals first or skips them, because their files and passages are still there. "Delete Documents" uses the same
removal with undo only in the open app, on the app's own engine (`UndoableIntent`, `isTheAppsEngine`); run with no app
on screen, it removes at once, because nothing is there to undo it in. A refuting review on the day of the decision
found eight ways the first version could lose or keep the wrong document, and each is answered in the code.

## 2026-10-15 - Domain isolation engages only for a question that reads as lab science

**Context.** Gate I (`DomainIsolationService`) keeps an answer to a lab-science question from mixing in vitro, in vivo,
clinical and in silico evidence. It engaged when the question or two passages scored two keywords, and it matched
keywords inside words. A demo library of travel and hotel documents had ten right answers marked Unverified by this gate
alone, and one question refused (Simulator, demo copy of e9de06d, 2026-10-15).

**Decision.** Keywords count as whole words or phrases; "um", "ip", "po" and "iv" are no longer keywords; and the gate
engages only when the question itself scores two or more keywords.

**Alternatives.** Whole words alone: an everyday question over a benefits document ("participants", "human resources")
ranked first could still be refused as clinical evidence. Engaging on the passages too, as before: a general question
over a scientific library ("what did the study find?") keeps the protection, at the cost of refusing everyday answers in
any library whose documents use those words.

**Consequences.** A general question over a scientific library is no longer kept to one study domain; the other gates
still check every claim against its passages. The decision is reopened if a scientific library's general questions are
seen mixing domains in answers.
