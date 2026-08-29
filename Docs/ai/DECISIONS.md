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
