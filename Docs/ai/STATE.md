# Current State

Updated: 2026-08-11
Branch/worktree: main, primary checkout
Last verified commit: 9ee0fa9

## Objective

**None active.** The vocabulary objective from the previous handoff is finished, verified and
pushed. What followed was an unplanned correctness pass across the library surfaces, also finished
and pushed. Nothing is half-done in the working tree.

Pick the next objective from Blockers below, from the Notion roadmap, or from the owner.

## Status

`origin/main` and local `main` are both at `bca92c0`. 17 commits since `e60fa7f`, all pushed.
Suite is **230 tests, 0 failures** on iPhone 17 Pro / iOS 27.0, up from 205 at the start of the day.

**The working tree is clean.** Nothing is uncommitted and nothing is unpushed.

## Completed

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

Every line was run this session and its output read.

- `xcodebuild test` on iPhone 17 Pro / iOS 27.0 -> **230 tests, 0 failures**. The log contains
  `error:` lines from `BiomeStorage` and `com.apple.modelcatalog`; those are simulator noise,
  expected because Foundation Models do not run there.
- `bash scripts/build_simulator_smoke.sh` -> **BUILD SUCCEEDED**.
- Retrieval benchmark, macOS Debug, `SWIFT_DETERMINISTIC_HASHING=1`, `--modes standard --pcc deny`,
  run twice. Final run `BenchmarkRuns/20260811-150328-matrix` (gitignored, local only): every stage
  at **MRR@10 1.000 and R@5 1.000**, accuracy 18/20, 0 hallucinated, abstentions 100% correct.
- `python3 scripts/build_eval_dataset.py --check` -> up to date, 20 cases.
- `python3 scripts/secret_scan.py` -> clean. `scripts/check_icloud_conflicts.sh` -> clean.
- All ten `file:line` citations added to `CHANGELOG.md` today re-checked to resolve to what they
  claim.

**Not verified: anything the UI does.** Zero test files touch `DocumentLibraryView`,
`ContainerPicker`, `DatabaseDashboardView`, `ContainerSettingsSheet`, `LibraryDeletion` or
`clearAllDocuments`. Green means the tested code still passes, not that today's screens work. Also
unverified: every on-device behaviour, and every Mac path.

## Blockers / Unknowns

**1. Five device checks gate confidence in everything shipped today.** Four carried from
2026-08-10: type in Settings search; run a query with the HUD visible and watch the Neural Engine
bar; rotate with the HUD on; update from a pre-v5.0 build to see the sample refresh banner. New and
most important: **open Library Settings, change the embedding model, and press "Later"** on the
rebuild prompt. That is the data-loss path reordered in `cc49ce2`, and nothing automated covers it.
Also worth a look: wipe a library, delete one document, flip a library off iCloud, and tap a device
chip on the onboarding completion card with VoiceOver on.

**2. The v5.0 embedding arc is blocked on the eval set, not the model.** The benchmark now reports
every stage at ceiling, so it can detect a regression and cannot demonstrate an improvement. The
corpus is also self-authored (`manifest.json` says "Generated locally by OpenIntelligence fixture
script", tags read `synthetic_financebench_style`), ground truth is document-level while retrieval
returns chunks, and n=18, where the harness itself warns that differences below roughly 25 points
are not resolvable. **Nothing measured supports starting the re-embed.** The prerequisite is the
Notion row "Build quality fixtures with external ground truth", which now gates "Benchmark three
embedders and replace MiniLM-L6-v2 if warranted" for a measured reason.

**3. 44 verified findings remain on the library surfaces**, in the audit file named in Working Set:
3 high, 18 medium, 13 low, 10 the verifier could not reproduce. The three high ones are worth
reading first.

**4. `OpenIntelligenceEngine.deleteLibrary` leaks everything.** It calls
`containerService.deleteContainer` alone, leaving documents, chunks, vectors and Spotlight entries
behind. It is `public` and synchronous, so routing it through `LibraryDeletion.delete` would break
the SDK signature. Deliberately untouched; decide the API question before fixing it.

**5. `README.md` claims iWork support the app does not have.** Tracked in Notion as
"iWork import is advertised but cannot read any file iWork produces" (To Do, v5.0). It is a claim
removal, so use `oi-claim-audit` first.

**6. `OnboardingChecklistView` logs "Generating BM25 dictionary + HNSW vectors".** `BNNSVectorDatabase`
is a flat store searched by batched `vDSP_mmul`, not an HNSW graph. Verify by reading that file for
any graph construction; if there is none, the log names an algorithm the app does not use.

**7. Licensing shapes the embedder decision.** The shipped stack (MiniLM-L6-v2,
`ms-marco-TinyBERT-L2-v2`) is Apache 2.0. **EmbeddingGemma is not**; it ships under the Gemma Terms
of Use, whose §3.1 requires the use restrictions to be enforceable against *your* users. Jina's v2
reranker weights are reported CC-BY-NC; verify before relying on that. Not legal advice.

**8. The What's New sheet is a changelog, not a splash.** The `"5.0"` entry has 8 items and no deep
links, and `WhatsNewView` has one button, "Done". Cutting to 3-4 and making rows navigate is the
improvement.

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

**Two defects surfaced that were not on the roadmap and deserve their own rows:**

1. **The planner and the route gate disagree about `pccQuota == .unknown`.** `canUsePCC` in
   `ModelExecutionPlan.swift` tests `pccQuota != .limitReached`, so `.unknown` permits a cloud
   attempt, while `RouteEvalMetrics` treats `.unknown` as non-authorizing. The planner is fail-open on
   exactly the state the scorer flags as a violation, so the first real gate run would correctly
   report an unauthorized cloud attempt.
2. **The macOS App Intent path has no foreground check.** The guard is inside `#if canImport(UIKit)`
   and the non-UIKit branch hardcodes `isForegroundInteractive = true`. Implementable now, no device
   needed.

**Also found:** `RAGEvalRunner` has zero call sites repo-wide, so the in-app half of evaluation cannot
be invoked at all; every measurement goes through `scripts/run_quality_matrix.py` plus
`DebugRAGValidationHarness`. And `Docs/RepoOS/04_RELEASE_READINESS_DASHBOARD.md` row 7 and risks
R06/R07 cite the wrong files for the consent guard.

## Exact Next Action

**Build the eval fixture set with external ground truth.** Notion row "Build quality fixtures with
external ground truth", v5.0, High. It is the measured prerequisite for the owner's stated top v5.0
goal and now blocks three other rows: the embedder benchmark, the `EPIC v5.0` parent, and the
three-mode quality matrix.

Why it is the right first move rather than a preference: every retrieval stage now reads MRR@10 1.000
and R@5 1.000, so the fixture can detect a regression and cannot demonstrate an improvement. Until
that changes, no embedder decision is defensible, and running one would produce a number that cannot
mean anything.

Concretely: replace or supplement `Benchmarks/ResearchFixtures/tiny_research_suite/manifest.json`
with cases drawn from real published datasets rather than the current self-authored corpus, which
`manifest.json` itself labels "Generated locally by OpenIntelligence fixture script" and tags
`synthetic_financebench_style`. Keep the plural `expected_sources` shape added on 2026-08-11. Aim for
enough cases that a 10-point difference is resolvable, since `run_quality_matrix.py` warns that at
n=18 nothing below roughly 25 points is. Then re-run and see whether any stage comes off the ceiling.

Ask the owner before starting if he wants something else; two alternatives are the three
high-severity findings in `Docs/AuditArtifacts/Verification/LIBRARY_SURFACES_AUDIT_2026-08-11.md`, and
the two newly found defects listed in the reconciliation section above, of which the macOS foreground
check needs no hardware.

Do not treat Blocker 1 as session work: those five checks need the owner's physical device.
