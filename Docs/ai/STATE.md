# Current State

Updated: 2026-08-13
Branch/worktree: main, primary checkout
Last verified commit: e29fee0. **Everything is committed and pushed. Tree clean. Only `main` exists.**

## Read this first

The engine now has a real quality measurement for the first time. That is the headline, and
everything below follows from it.

**`Docs/EVALS.md` is the single entry point for anything about measurement.** It opens with a
"Start here" section: the numbers, what each is worth, which file owns which part, and the two
comparisons that will mislead you. Do not re-derive any of this from run artifacts.

### The four numbers that matter

| | |
| :--- | :--- |
| Accuracy | **44% exact match, 46% gold recall**, 72 answerable external questions |
| Dense retrieval | `vector` MRR@10 **0.28** |
| Lexical retrieval | `lexical` MRR@10 **0.65** |
| Where it loses | right document reaches final ranking on **75% of missed cases** |

Read that last row carefully. **The failure is not "cannot find the paper". It is "finds the paper,
picks the wrong paragraph".** Every lever below follows from it.

### The finding worth acting on

**RRF fusion scores worse than the lexical arm alone**, 26 wins to 6 over 72 paired cases, exact
two-sided sign test **p = 0.0005**. The mechanism is in the code, not the theory:
`QueryProfile.adjustedHybridWeights` clamps both arms to `max(0.35, min(0.65, ...))`, guaranteeing
the weak dense arm at least 35% of the fusion. That is a sound default for two comparable arms,
which is what the RRF literature assumes; these arms are not comparable.

**A run testing a 0.3/0.7 rebalance is paused at 36/83 and is resumable.** See Blockers 1.

## Status


The tree carries the fixture work described below. Everything that can be verified without
`xcodebuild` has been verified and its output read.

**`xcodebuild` deadlocks on this repository's own path, and the workaround is a copy.** Anything
that opens the project hangs forever at the "Command line invocation" header with no
`XCBBuildService` and no DerivedData, while `-version` and `-list` still work. `sample` of the hung
process shows the blocked thread in `-[DVTFilePath performCoordinatedReadRecursively:]`, parked in
`semaphore_wait_trap`: an **NSFileCoordinator** coordinated read against iCloud-synced `~/Documents`
that never returns. Plain `ls -R` on the same path is instant and no file is dataless, so this does
not look like an iCloud problem until you sample it.

Build from `rsync`'d copy at `/private/tmp/oi-src` instead. Verified by A/B on the identical
command: hangs in `~/Documents`, `exit=0` instantly from the copy. Full recipe in `RUNBOOK.md`
item 1b. **This is not a signing, sandbox, or permission-classifier problem**, and the RUNBOOK's
previous claim that an agent could not run the build has been corrected in place.

**No Swift source was touched.** The changes are Python, docs, and new fixture data only.

## Completed this session (2026-08-12)

- **`Benchmarks/ResearchFixtures/qasper_external_v1/`**, 83 cases over 40 papers from QASPER
  (Dasigi et al., NAACL 2021, CC BY 4.0), built by `scripts/build_external_fixtures.py`. Questions
  were written by readers shown only a title and abstract, and answered by separate annotators
  against full text. A case survives only where two or more annotators agreed; `annotator_agreement`
  records the count. Six abstention controls come from genuinely unanswerable questions, replacing
  two the project invented for itself. `fixtures.lock.json` pins the dataset revision, the selected
  papers and questions, and a corpus SHA-256. **Two independent rebuilds produced a byte-identical
  tree**, and `--check` verifies it offline.
- **The shared distractor pool**, which is the change that actually matters. A manifest may now
  declare a top-level `pool`, and `run_quality_matrix.py` ingests it for every case, so each
  question is asked against 39 papers that are not the answer.
- **`minimum_detectable_effect` now computes its own claim.** It previously interpolated `n` into a
  sentence whose threshold was hardcoded. See Blockers 3.
- **Non-commercial datasets can no longer be pulled into the tree by accident.**
  `prepare_rag_research_fixtures.py` refuses `financebench` and `docvqa` unless
  `--accept-non-commercial` is passed for a local-only run.
- **`build_eval_dataset.py` renders every known pack**, so `Benchmarks/rag_eval_qasper_v1.jsonl`
  reaches the in-app `RAGEvalCase` framework the same way the synthetic set does. The only change to
  the pre-existing `rag_eval_v1.jsonl` is two header comment lines; every case line is byte-identical.

Notion: the fixtures row is `In Progress` with a dated note, the harness row has a dated note, and
two new Completed rows cover the power-calculation defect and the licensing gate.

## Why the ceiling was never about sample size

This is the finding that reframed the row, and it is worth not rediscovering.

`run_quality_matrix.py` created a fresh store per (case, mode) and ingested only that case's
`input_files`. **Every case was therefore scored against an index containing nothing but its own
expected documents.** The 2026-08-11 reports show the vector stage seeing two to five candidate
chunks per case, all of them from the expected file. `R@5` asks whether the right document is in the
top five when there are at most five candidates and every one is relevant, so `MRR@10 1.000` and
`R@5 1.000` were arithmetic, not pipeline quality. Real external data at n=300 would not have moved
them. The corpus was the defect; externality and `n` were real but secondary.

`[evidence_level: run_artifact_verified, confidence: exact, evidence_source: BenchmarkRuns/20260811-150328-matrix/reports/*.txt STAGE METRICS results column; run_quality_matrix.py:391, :720]`

## Completed 2026-08-11

Newest first. The last two in this list are the previous objective; everything above them was found
while verifying it. Doc-only commits are omitted.

- `bca92c0` The owner's own one-character HUD capitalisation edit, committed on its own rather than
  folded into an unrelated change.
- `ba05818` **The two destructive library actions were indistinguishable, and one menu entry led to a
  screen that could never hold anything.** "Wipe Library" and "Delete Library" sat adjacent, both
  destructive, on `trash` and `trash.slash`. They are now "Remove All Documents from X" and "Delete
  the X Library", different icon families, divider between them. Cached Documents is gated on the
  cache holding something: `DocumentationCacheService.cache(...)` has zero call sites, but it is
  scaffolding for the open roadmap row "Web Clipper / Share Extension", not dead code.

- `5cf54b4` Three documentation-status banners asserted verification state that was wrong:
  `RELEASE_NOTES.md` claimed 202 tests against 230, and `USER_CHANGELOG.md` and `WHATS_NEW.md` both
  still said v4.9. The RUNBOOK gained the more dangerous omission, that stage figures either side of
  2026-08-11 are not comparable because the eval ground truth changed rather than the pipeline.
- `fd5af3a`, `561dcd3` Closed three gaps a final audit found: `RELEASE_NOTES.md` had no coverage of
  the correctness pass and its entry count read 74 against an actual 87, the Atlas did not record
  `LibraryDeletion`, and Notion was missing a row for it. The count had gone stale twice in one day,
  46 to 74 to 87, so the recount command is now recorded beside it instead of the number being
  retyped again.
- `b464378` **One delete-library implementation.** `DocumentLibraryView` and `ContainerSettingsSheet`
  had near-identical copies that had diverged: on an iCloud library whose shared copy fails to
  delete, the first aborted and reported, the second logged and deleted locally anyway, so the next
  sync restored the library and the user believed it was gone. Both now call
  `LibraryDeletion.delete`, which aborts. `ContainerSettingsSheet` had to stop calling `dismiss()`
  before the work started, and `resolvedLocalDeletionContainerIDs` was deleted as unreachable.
- `8d00bf5` `default.profraw` gitignored.
- `6693a39` Two CHANGELOG citations had rotted the same day they were written, because the commit
  that described a line also inserted lines above it. Fragile ones replaced with symbol names.
- `cc49ce2` **Library Settings honesty pass.** Vectors were deleted at Save, before the rebuild
  dialog, so "Later" left documents with no vectors; the delete moved into `startReembedding`.
  Sliders offered 100...600 and 0...200 against enforced clamps of 260 and 50. The "elastic"
  strategy claimed embedding similarity that never runs. "persistent JSON storage" was stale. The
  `narrative` preset declared 280/55 against those clamps.
- `4178ff0` **Library controls stopped destroying data while promising they had not.** "Remove Local
  Copies" was never local and is now "Wipe Library"; it also leaked Spotlight entries, entity-index
  rows and the imported files. Flipping a library to Local Only deletes its iCloud copy and now
  confirms. Database scope carries a `UUID` so any library can be inspected. Toolbar overflow,
  duplicate-name disambiguation, and a dead `onSetLibraryStorage` closure in Semantic Search.
- `818ea88` **Answers ending in bold or italic lost their closing markers**, because
  `hasResponseTerminalBoundary` did not accept `*`. Also the eval set credited one of the two
  documents every multi-hop question needs, which made a working reranker read as a regression.
- `0a9af59` The benchmark answered the embedder question. See Blockers 1.
- `24f305a`, `8b30ae5` The vocabulary layer: 24 terms in a plain and a technical register, attached
  in place. `Docs/ai/DECISIONS.md` holds the rationale under **2026-08-11 - Explain the vocabulary
  in two registers rather than simplifying the screens**.

Notion has five new Completed v5.0 rows for the above, plus a dated progress note on
"Retrieval benchmark harness over rag_eval_v1.jsonl" recording what that harness still cannot
measure.

## Active Constraints

- **No em-dashes anywhere.** `USER_CHANGELOG.md` renders in the app, so it is a product rule. It
  applies to Swift string literals too, which an earlier sweep missed.
- **Do not write a value into user-facing copy. Read it from the code.** This is the pattern that
  fixed five separate defects today and the one that prevents their return. A typed number drifts;
  a read one cannot.
- **Freeze the working tree before any build or test run**, documentation included.
  `VersionHistoryTests` compares the bundled `VersionHistory.md` against `Docs/USER_CHANGELOG.md`,
  which makes that doc a build input. Three runs were discarded on 2026-08-11 for this.
- **A new file under most `Services/` folders is also compiled into the `OpenIntelligenceEngine`
  SDK framework.** That target synchronises eighteen folders including
  `Services/Infrastructure/Integration`, but not `Presentation/` and not `Features/`. A file there
  referencing either fails **only in the test build**, with a scope error that reads exactly like
  stale DerivedData and is not. Put such files under `Features/`.
- **`Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` must stay byte
  identical.** Edit one, `cp` it over the other.
- **`[Unreleased]` in `CHANGELOG.md` stays empty.** New entries go under `## 5.0`.
- **Commits must not carry a `Co-Authored-By: Claude` trailer.** `includeCoAuthoredBy: false` is set
  in `~/.claude/settings.json`; do not add one by hand.
- **Zero call sites is not dead code.** Run `oi-claim-audit` before any removal.
- Hard-boundary files still need the owner to name them. None were touched.

## Working Set

- `Docs/AuditArtifacts/Verification/LIBRARY_SURFACES_AUDIT_2026-08-11.md`, **the 44 findings not
  fixed today**, with evidence and file references. This is the backlog for the library surfaces and
  the first file to open for that work.
- `OpenIntelligence/Features/Documents/Library/LibraryDeletion.swift`, the single delete
  implementation. Its header records the two lookalikes deliberately left alone and why.
- `OpenIntelligence/UI/Components/Glossary.swift`, the single source of every user-facing
  definition. Change copy here and nowhere else. `GlossaryTests` fails if a plain definition
  acquires a code identifier.
- `OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift`, whose `ChunkingConfig` now
  owns the clamp constants that both `DocumentProcessor` and the Library Settings sliders read.
- `scripts/build_eval_dataset.py` and `scripts/run_quality_matrix.py`, both of which now read a
  plural `expected_sources`.
- `Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json`, the eval ground truth.

## Verification

- **`xcodebuild test` -> 236 tests, 0 failures**, iPhone 17 Pro / iOS 27.0, run 2026-08-12 from the
  non-iCloud copy at `/private/tmp/oi-src`. The app is healthy.
- The app library was restored and verified: 4 real documents, 0 stray registrations, empty
  ingestion queue, original container `0D979768`.
- The **iCloud container was checked and is clean**: 7 files, all the owner's, no benchmark content
  from today or from the July-30-onward leakage, newest mtime May 23. Nothing this session did
  reached iCloud or the phone.

Run on 2026-08-12 and the output read:

- `python3 scripts/build_external_fixtures.py --check` -> OK, 83 cases, 40 papers,
  `allenai/qasper @ fdc9d8214fba`.
- Two full rebuilds of the pack from separate downloads produced the **same
  `fixtures_sha256`**, `4a470066...`, which is the determinism claim actually tested rather than
  asserted.
- `python3 scripts/build_eval_dataset.py --check` -> OK, 20 cases and 83 cases.
- `python3 scripts/secret_scan.py` -> clean. `scripts/check_icloud_conflicts.sh` -> clean.
- `python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py` -> 24 tests, OK.
- `minimum_detectable_effect` re-derived numerically against the exact binomial sign test before the
  claim was changed, and the old figure checked against three readings (paired 33 pts, Wilson 21 pts,
  unpaired 47 pts) to confirm 25 matched none of them.

**Not run this session, and not runnable here:** `xcodebuild test`, the simulator smoke build, and
the retrieval benchmark. See Status for why. The last known figures are 236 / 0 and the 2026-08-11
matrix run, both against Swift that this session did not touch.

Carried forward from 2026-08-11 and still true: **nothing verifies what the UI does.** Zero test
files touch `DocumentLibraryView`, `ContainerPicker`, `DatabaseDashboardView`,
`ContainerSettingsSheet`, `LibraryDeletion` or `clearAllDocuments`. Every on-device behaviour and
every Mac path is also unverified.

## Blockers / Unknowns

**1. A benchmark run is paused at 36/83 and resumes with one command.** Testing whether rebalancing
the fusion weights to 0.3 dense / 0.7 lexical improves anything. Interim on the 33 scored was 48%
against the 44% baseline, which at n=27 means nothing yet. **A run costs ~4.7 hours and pins the
machine**, so ask before starting one.

```bash
caffeinate -is env SWIFT_DETERMINISTIC_HASHING=1 python3 scripts/run_quality_matrix.py --app /private/tmp/oi-mac-nosbx/Build/Products/Debug/OpenIntelligence.app --manifest Benchmarks/ResearchFixtures/qasper_external_v1/manifest.json --modes standard --pcc deny --pool-limit 10 --reset-shared-library --vector-weight 0.3 --resume BenchmarkRuns/qasper-vw30
```

Then **always** `python3 scripts/save_benchmark_summary.py <run-dir>` and commit it. `BenchmarkRuns/`
is gitignored; an unsummarised run did not happen.

**Before any run:** `python3 /private/tmp/clean_benchmark_library.py --apply`. The app writes
ingested documents into the real library regardless of `--rag-validation-storage`, and accumulation
makes later cases time out. Backup at `/private/tmp/oi-library-backup-20260812`.

**2. There is no shortcut to a faster run, and two attempts failed.** Index reuse would cut a run to
~15 minutes and **does not work**: retrieval succeeds but every source resolves to `Unknown` and
scores 0.0000, because `WorkspaceSyncService` writes document records to the real library while
vectors go to the storage dir, so their IDs never line up. Both `documentIdsByName` (commit
`99fcdaf`, whose changelog claim of "four hours against fifteen minutes" is **withdrawn**) and
co-locating storage with the real library were tried and failed. Do not re-attempt without a new
idea. The real fix is the `WorkspaceSyncService` root path, which is a **hard-boundary file needing
the owner to name it**.

**3. Six of 83 cases produce no result and it is unexplained.** Four timed out at 600s, two returned
no report: `qasper_1905.00472_04914917`, `qasper_1805.04833_f2dba5bf`, `qasper_1805.07882_67cb001f`,
`qasper_1806.04387_9f1d81b2`, `qasper_1611.06322_3319d565`, `qasper_1909.12079_3f717e6e`. Lead: one
case took 4173s against a 168s median, and the Simulator showed the same shape as
`All 8 sessions failed to produce an insight`, which is the agentic retry loop. Read the per-case
reports under `BenchmarkRuns/qasper-overnight/reports/`.

**4. Apple Intelligence cannot generate in the iOS Simulator on this machine.** The framework loads
and reports `available`; generation dies in `ModelManagerError 1026`. A bare probe on the host Mac
generates real text, so the machine is capable. Ruled out: locale, model catalog, the app's own
guards. The documented remedy is toggling Apple Intelligence off, restarting the Mac, and back on;
**the owner has declined**, reasonably, since this is developer convenience. Do not spend a session
on it. The three simulator guards in `LLMService` and `RAGService` are stale in wording and correct
in outcome; leave them until AFM generates there.

**5. `xcodebuild` deadlocks on this repository's path.** Anything that opens the project hangs
forever with no DerivedData while `-version` and `-list` work. `sample` shows
`-[DVTFilePath performCoordinatedReadRecursively:]` parked in `semaphore_wait_trap`: an
NSFileCoordinator read against iCloud-synced `~/Documents` that never returns. **Build from a copy:**

```bash
rsync -a --exclude 'BenchmarkRuns/' --exclude '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' ./ /private/tmp/oi-src/
```

Then build from `/private/tmp/oi-src`. Full recipe in `RUNBOOK.md` item 1b. Diagnose by sampling,
never by guessing; clearing `com.apple.DeveloperTools` is actively misleading because it makes
`-list` succeed while the next build still hangs.

**6. Five device checks still gate confidence in the 2026-08-11 library work.** They need the
owner's physical device. Not session work.

**7. 44 verified findings remain on the library surfaces**, in
`Docs/AuditArtifacts/Verification/LIBRARY_SURFACES_AUDIT_2026-08-11.md`: 3 high, 18 medium, 13 low.
The three high ones are worth reading first, and none needs a build or a device.

## v5.0 roadmap, reconciled against code 2026-08-11

All 27 open v5.0 rows were checked against the code, each verdict challenged by a second pass told to
refute it. **19 open, 7 partial, 1 needs hardware. Nothing was found already shipped and unmarked**,
so the roadmap was not stale in the direction of overstating what is left; it was stale in
understating what has landed inside seven rows. Every partial now carries a dated note in Notion
saying which half is real, so tomorrow does not rebuild it.

**Three rows were retitled** because all three began "Validate: PCC" and read as *PCC does not work*.
It does: the entitlement is `true` in `OpenIntelligence.entitlements` (read via plistlib) and
`PrivateCloudComputeLanguageModel` is wired at `FoundationModelCapabilityProvider.swift:54`,
`FoundationModelSessionFactory.swift:92` and `FoundationModelRoutePolicy.swift:127`. Row titles
publish to the public roadmap page, so the old wording told every reader the same wrong thing.

**PCC cannot be exercised from an agent shell.** Tested directly: `fm available` prints `System model
available` on stdout and `Private Cloud Compute is not available in this context. Please use the
Terminal app.` on stderr. Local builds carry no entitlements at all because the smoke and benchmark
builds pass `CODE_SIGNING_ALLOWED=NO`. No run in `BenchmarkRuns/` records a PCC route. Those rows need
the owner's device, and that is a hard limit rather than an unattempted check.

**Two defects surfaced that were not on the roadmap. Both are now fixed in `0e7458a`.**

1. **The planner attempted PCC on a quota state its own route gate scores as unauthorized.** Three
   places already asserted fail-closed on `.unknown`: `RouteEvalMetrics.RouteInvariant.quotaFailClosed`,
   `Docs/PRIVACY_AND_ROUTING.md` in prose, and `ModelExecutionReceipt.nonAuthorizingQuotaStates`. Only
   `canUsePCC` disagreed, testing `!= .limitReached` alone, and it is the one that decides. The rule
   now lives once as `PCCQuotaState.authorizesCloudExecution`, exhaustive over the enum, and both
   sides derive from it. That doc sentence had been false for as long as it was written and is now
   annotated as corrected. `PCCQuotaAuthorizationTests`, 6 cases.
2. **macOS had no foreground check at all**, so a backgrounded Shortcut reported itself
   foreground-interactive and could reach PCC unattended. It reads `NSApplication.shared.isActive`
   now, and a platform with neither UIKit nor AppKit falls closed. **The Notion row stays open**: it
   also asks for the backgrounded Shortcuts path to be exercised, which needs the owner's device.

**Also found:** `RAGEvalRunner` has zero call sites repo-wide, so the in-app half of evaluation cannot
be invoked at all; every measurement goes through `scripts/run_quality_matrix.py` plus
`DebugRAGValidationHarness`. And `Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` row 7 and risks
R06/R07 cite the wrong files for the consent guard.

## Do not move the benchmark to the iOS Simulator yet. Measured 2026-08-12.

**The reasoning below was sound and the conclusion was wrong.** Keep the reasoning, because it
becomes correct the moment one thing changes, and re-deriving it wastes a session.

**What was measured.** One case at `--pool-limit 10` on iPhone 17 Pro / iOS 27.0 **exceeded ten
minutes and then failed**, against 170s on macOS. Ingestion and retrieval were fine. Generation was
not:

```
[ReasoningChain] All 8 sessions failed to produce an insight
[Agentic] Failed: The on-device model did not return a usable response across 8 reasoning sessions
[RAGValidation] Validation failed
```

Apple Intelligence cannot generate in the Simulator on this machine, and the agentic path retries
eight reasoning sessions before giving up. That retry loop is the ten minutes. At 83 cases that is
**14+ hours in which every case fails**, against 4 hours of real answers on macOS.

Note the trap: with a single document and a simple query it falls back to extractive quickly and
looks fine. The escalation only appears at a realistic pool size, so a one-document smoke test will
mislead you here.

**Why generation fails.** The framework loads and reports `availability: available`; generation dies
in Apple's `ModelManagerError 1026`. Verified with a bare probe with no app code involved: the same
probe on the host Mac reports available **and generates real text**, so the machine is capable and
provisioned. Ruled out: locale (`en_US` on both sides), a wedged model catalog (erasing the
simulator removed those errors entirely), and the app's own guards (failure reproduces with them
removed). Apple's forums document this exact error pair and the remedy is to toggle Apple
Intelligence off, restart the Mac, and turn it back on. **The owner has declined to do that**, which
is reasonable: this is developer convenience, not something the shipping app depends on.

`[evidence_level: measured, confidence: exact, evidence_source: bare FoundationModels probe on host vs iOS 27 simulator; one full case at --pool-limit 10 on each target]`

**The three simulator guards are therefore correct in outcome and stale in wording.**
`LLMService.AppleFoundationLLMService.isAvailable` and `RAGService.checkDeviceCapabilities` both
hardcode unavailability under `#if targetEnvironment(simulator)`, with reasons like "Foundation
Models not available in Simulator". Availability is actually reported *available*, so the reason is
wrong, but the behaviour they produce is right: without them the app attempts generation, fails,
and is slower and noisier for it. They were removed and reverted twice on 2026-08-12. **Leave them
until AFM generates in the Simulator**, then remove all three together.

This is also the whole answer to "why does the chat header say `Hybrid - Unavailable`". That pill
reads `supportsFoundationModels` from `checkDeviceCapabilities`, so on a simulator it is reporting a
compile-time constant rather than anything about the machine. On a real device it should read
available.

**Re-check trigger:** any Xcode or macOS update. Re-run the probe; if it generates, the move below
becomes correct and worth doing immediately.

## Why the Simulator is still the right destination once generation works

The owner's suggestion on 2026-08-12, and the reasoning holds.

**It ends the isolation problem outright.** A simulator has its own filesystem container, so the
app's application-support directory lives inside the simulator rather than in the owner's real
`~/Library`. `WorkspaceSyncService` can go on resolving `applicationSupportRoot()` and it no longer
matters: there is nothing of the owner's to pollute, no cleanup script, no reset between cases, and
no risk of repeating the 2026-08-12 incident. Every mitigation in `run_quality_matrix.py` exists
only to work around a problem the simulator does not have.

**It measures the platform the app is for.** This ships primarily for iPhone and iPad; benchmarking
the Mac build measures the least representative target.

**Foundation Models load in the simulator but cannot generate there.** Corrected the same day it was
written: this section first claimed they were available, on the strength of Apple's documentation
and a capable host. Measurement disagrees, and the detail is in the section above. Availability is
reported `available`; generation fails. Treat "available" from `SystemLanguageModel` as necessary
and not sufficient.

**What it needs:** `run_quality_matrix.py` drives the app by executing the macOS binary directly. A
simulator run instead needs `xcrun simctl launch --console-pty <udid> <bundle-id> --args ...` and
the same stdout parsing. That is a contained change to one function, `run_one`.

## Exact Next Action

**Ask the owner first.** He was clear on 2026-08-13 that benchmark runs pin the machine and he needs
it. Do not start one unprompted.

### If he wants measurable progress without a run

**FTS5: weight bm25 columns and add a trigram index for identifiers.** Notion row, v5.0, Medium.
This is the recommendation because the measurement points at it: the lexical arm is carrying
retrieval at MRR 0.65 while the dense arm sits at 0.28. Strengthening the arm that already works
beats swapping the embedder, needs no model conversion, no benchmark to begin, and a trigram index
directly serves the extractive fact-lookup category that scored worst at 19/51.

Other no-run, no-device options, all open v5.0 rows:

- **`iWork import is advertised but cannot read any file iWork produces`**, a false claim in
  `README.md`. Claim removal, so run `oi-claim-audit` first.
- **`SmartReplyService fails to parse generated content on every run`**. "Every run" means
  deterministic.
- **`Chunk boundaries land mid-word and mid-phrase`**, contained in `SemanticChunker`.
- **The three high-severity findings** in the library surfaces audit, see Blockers 7.

### If he wants the benchmark finished

Resume per Blockers 1. ~4.7 hours.

### The two follow-ups this session created

1. **`count_pattern` and `search_exact_pattern` were registered in `e29fee0`** and their benefit is
   **unmeasured**. Re-run `qasper_external_v1` and compare the **`exact_value` category**
   specifically, not headline accuracy, against
   `Docs/AuditArtifacts/Benchmarks/20260812-215108-matrix.md`.
2. **The embedder swap is unblocked and has a candidate.**
   `granite-embedding-small-english-r2`: Apache 2.0, **384 dimensions matching what ships** so
   `BNNSVectorDatabase.swift` needs no change, 8192-token context against MiniLM's 256, BEIR 50.9.
   The risk is Core ML conversion, not quality, since it is a ModernBERT; the conventional-BERT
   `granite-embedding-30m-english` at the same dimension is the fallback. Neither is converted.
   Details in `Docs/Research/EMBEDDING_AND_INGESTION_UPGRADE_2026-08.md`.

### Standing rules that bit repeatedly

- **Do not point `--rag-validation-storage` at the real library.** Doing so on 2026-08-12 ingested 40
  papers into the owner's actual app and replaced his container.
- **Do not compare a `tiny_research_suite` figure to a `qasper_external_v1` figure**, or a stage
  figure from before 2026-08-11 to one after.
- **Docs move in the same turn as code.** A `.swift` change without a doc update fails the
  pre-commit hook.
- **No em-dashes anywhere.**
- **Verify before claiming.** Three claims were withdrawn on 2026-08-12 alone: that 44% beat the
  published QASPER baseline (different metrics), that 44% was a large undercount (recall says 46%),
  and that index reuse would cut runs to 15 minutes (it does not work).
