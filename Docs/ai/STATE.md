# Current State

Updated: 2026-08-11
Branch/worktree: main, primary checkout
Last verified commit: 8b30ae5

## Objective

**Make the app explain its own vocabulary in place, to a non-technical user.** People saw "38 TOPS",
"32/batch", "768 search", "16-core ANE", "Chunks" and "Vectors" on the onboarding completion card and
had no idea what any of it meant, which risks them uninstalling rather than engaging. The owner wants
the app "digestible to all crowds, the technical and nontechnical, almost a blend", and explicitly
wanted this **not** buried in Settings.

`PROCEED: IMPLEMENT` was granted for this on 2026-08-11 with the instruction "Remember I want to have
the technical and non-technical explanations of the vocabulary. Go nuts."

The implementation is **complete, building and test-verified**. See Verification.

## Status

**Committed as `8b30ae5`**, 16 files, 1757 insertions. **Not pushed.** `origin/main` is still at
`e60fa7f`, so this work exists only in this local checkout.

The owner asked on 2026-08-11 that commits stop carrying a `Co-Authored-By: Claude` trailer, because on
a public repository it reads as the work being entirely generated. `includeCoAuthoredBy: false` is now
set in `~/.claude/settings.json`, and `8b30ae5` is the amended, trailer-free version of the original
commit. **Do not add that trailer by hand.** 152 already-pushed commits still carry it; see Blockers.

Suite is **219 tests, 0 failures** on iOS 27.0, up from a 205-test baseline. The 14 added cases are all
`GlossaryTests`.

## Completed

- **`OpenIntelligence/UI/Components/Glossary.swift`, new.** 24 terms, each with a `plain` register
  (no code identifier, model name or framework name) and a `technical` register (free to name
  `MiniLM-L6-v2`, `vDSP_mmul`, `ms-marco-TinyBERT-L2-v2`, Apple TN3193). Definitions are returned
  from **one exhaustive `switch` over `GlossaryTermID`** rather than a string-keyed dictionary, so a
  call site cannot name a term that does not exist, lookup returns no optional, and adding a case is
  a compile error until both registers are written. Sections: 11 pipeline, 7 hardware, 6 answering.
- **`OpenIntelligence/UI/Components/GlossaryViews.swift`, new.** `GlossaryTermDetail`,
  `GlossaryTermSheet`, `GlossaryInfoButton`, the `.definedTerm(_:)` modifier that makes any view open
  a definition, and `.definitionUnderline(_:)`. The technical register sits behind a
  `DisclosureGroup` bound to `AppStorage` key `glossary.showsTechnicalDetail`, so opening it once
  opens it for every definition in the app.
- **`OpenIntelligence/Features/Settings/GlossaryView.swift`, new.** The searchable index, three
  sections, with the register toggle at the top. Search covers term, both registers and synonyms, so
  typing `bm25` or `vdsp` reaches the right entry even though the plain register avoids those words.
- **Wired at the point of confusion, not in a screen of its own.** In
  `OnboardingChecklistView.swift`: the four pipeline capsules (tappable while the stage they name is
  running), all four counters in the metric strip, all six device chips, the Private Cloud Compute
  line, and a new `hardwareTranslation` block with a link to the full index. In `HowItWorksView.swift`:
  an info button on each of the four stages plus a new `vocabularyCard`. In `SettingsView.swift`: a new
  `SettingsEntryID.glossary` row titled "Plain English", ten Hardware Envelope rows, two Silicon RAG
  batch pills, and the Neural Engine TOPS line.
- **`OpenIntelligenceTests/Features/Settings/GlossaryTests.swift`, new.** 14 cases. A plain
  definition fails the suite if it contains any of 24 code identifiers, model names or framework
  names, uses a backtick, exceeds 360 characters, or duplicates its technical counterpart. Also pins:
  no em-dashes, no self-reference or duplicate in `seeAlso`, no term orphaned from the cross-reference
  graph, every synonym returns its own term, and `bm25`/`vdsp`/`minilm`/`tinybert`/`fts5` each reach
  the right entry. **Two cases guard specific hedges rather than structure** and must not be deleted:
  `testTopsDefinitionDoesNotClaimAMeasurement` and
  `testNeuralEngineDefinitionKeepsTheSchedulingHedge`.
- **Two bugs found in this session's own work.** Related-term rows were dead buttons on the Settings
  route: they used an `onSelectRelated` closure that only `GlossaryTermSheet` could supply, so
  `GlossaryView`'s `navigationDestination` passed the default no-op. They are
  `NavigationLink(value:)` now. And `onDevicePanel` carried
  `.accessibilityElement(children: .combine)`, correct for static text but it would have left all six
  chips tappable by touch and invisible to VoiceOver. That panel and `HowItWorksView.stage` use
  `.contain` now.
- **Two em-dashes removed from Swift string literals.** The 2026-08-10 sweep covered documents, not
  interpolated strings in views. `"Import failed \u{2014} tap Retry"` and the ticker's stage separator
  are fixed; the `\u{2014}` zero-time placeholder is now `0s`.
- **Docs moved in the same turn.** `CHANGELOG.md` under `## 5.0` (2 Added, 2 Fixed, all `**[UI]**`),
  `Docs/USER_CHANGELOG.md` plus its mandatory mirror `OpenIntelligence/Resources/VersionHistory.md`,
  `WHATS_NEW.md`, `README.md` (feature table and codebase map), Atlas section 5, and
  `Docs/RELEASE_NOTES.md`.
- **`Docs/RELEASE_NOTES.md` entry count corrected.** Its v5.0 header claimed "46 entries, 15
  `[General]`, 13 `[UI]`". Counted from `CHANGELOG.md`, the real figure is **74 entries, 32 `[UI]`, 16
  `[General]`, 15 `[Ingestion]`, 5 `[Retrieval]`, 5 `[Orchestration]`, 1 `[Chunking]`**. It had gone
  stale across the interface pass.
- **Notion row created**, Completed, UI, High, v5.0, dated 2026-08-11: "Onboarding showed TOPS, batch
  sizes, chunks and vectors with no way to find out what they meant",
  <https://app.notion.com/p/3b949a74d54f81da9a00edca5c230d8a>.

The design rationale, including the three alternatives that were rejected and why extending
`InfoButtonView` was not the right shape, is recorded in `Docs/ai/DECISIONS.md` under
**2026-08-11 - Explain the vocabulary in two registers rather than simplifying the screens**. Read that
before changing the structure of `Glossary.swift`.

## Active Constraints

- **No em-dashes. Anywhere.** `USER_CHANGELOG.md` renders inside the app, so this is a product rule.
  It now also applies to Swift string literals, which the last sweep missed.
- **A plain definition may never acquire a code identifier.** That is the whole point of two
  registers and `GlossaryTests.testPlainRegisterStaysPlain` enforces it. Put mechanism in `technical`.
- **Two hedges in `Glossary.swift` are load-bearing.** TOPS must keep saying the figure is a per-chip
  lookup rather than a measurement: `DeviceCapabilityService.npuTops` reads a table keyed by device
  identifier, several entries are explicitly projections, and Apple exposes no live Neural Engine
  occupancy API. Neural Engine must keep crediting Core ML with the final scheduling decision.
- **`Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` must stay byte
  identical** or `VersionHistoryTests` fails. Edit one, then `cp` it over the other.
- **`[Unreleased]` in `CHANGELOG.md` must stay empty.** New entries go under `## 5.0` until 5.0 ships,
  or Xcode Cloud refuses to build. The router reporting v5.0 as `shipped` is about changelog
  structure, not the App Store.
- **Zero call sites is not dead code.** Run `oi-claim-audit` before any removal.
- Hard-boundary files still need the user to name them in an approval. None were touched: new files
  are picked up by `PBXFileSystemSynchronizedRootGroup`, so `project.pbxproj` was not edited.

## Working Set

All of these are committed in `8b30ae5`, which is not pushed.

- `OpenIntelligence/UI/Components/Glossary.swift`, the single source of every definition. Change copy
  here and nowhere else.
- `OpenIntelligence/UI/Components/GlossaryViews.swift`, the affordances. `.definedTerm(_:)` is the
  primitive for adding a definition to any new surface.
- `OpenIntelligence/Features/Settings/GlossaryView.swift`, the index screen.
- `OpenIntelligenceTests/Features/Settings/GlossaryTests.swift`, the drift guard.
- `OpenIntelligence/Features/Onboarding/OnboardingChecklistView.swift`, modified. `dashCounter`,
  `deviceChip` and `pipelineCapsule` each take a `term:` now; `hardwareTranslation` is new.
- `OpenIntelligence/Features/Settings/HowItWorksView.swift`, modified. `stage(...)` takes a `term:`;
  `vocabularyCard` is new. This screen's prose is the tone the glossary matches and is deliberately
  not duplicated by it.
- `OpenIntelligence/Features/Settings/SettingsView.swift`, modified. `hardwareLimitRow` and
  `siliconInfoPill` take an optional `term:`.
- `/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/5731000b-392c-4bb9-a76a-49189863cce7/scratchpad/build_review.py`
  regenerates the owner-facing copy-review page by parsing `Glossary.swift`. Published at
  <https://claude.ai/code/artifact/9173a230-2eae-4b12-bff7-615af65df9c8>. Re-run it after any copy
  change and republish the same file path to keep that URL.

## Verification

Every line below was run this session and its output read.

- `xcodebuild test` on iPhone 17 Pro / iOS 27.0 -> **`** TEST SUCCEEDED **`, 219 tests, 0 failures**
  in 25.1s, from a 205-test baseline. All 14 `GlossaryTests` cases ran and passed. The run's log
  contains lines matching `error:`; every one is simulator noise from `BiomeStorage` and
  `com.apple.modelcatalog`, which is expected because Foundation Models do not run in the simulator.
  There were no compile errors.
- `bash scripts/build_simulator_smoke.sh` -> **BUILD SUCCEEDED**. Covers the app target including all
  three new files and all three wiring sites. Does **not** build the test target, which is why the
  suite above was the real gate.
- `python3 scripts/secret_scan.py` -> clean.
- `scripts/check_icloud_conflicts.sh` -> no iCloud damage, `.git` pointer intact.
- Ad hoc Python check over the 24 parsed `plain` strings -> no jargon from the 24-item list, no
  backticks, none over 360 characters, no em-dashes, none equal to its `technical` counterpart.
- `grep` cross-checks that put each technical claim against code before it was written: 384 dimensions
  and MiniLM-L6-v2 (`BNNSVectorDatabase.swift:90`, `AdaptiveEmbeddingOptimizer.swift:753`), BM25 with
  SQLite FTS5, `ms-marco-TinyBERT-L2-v2` bound by path in `THIRD_PARTY_NOTICES.md`, 4,096 tokens cited
  to TN3193 (`LLMModel.swift:159,329-333`), `CloudEvidenceMinimizer`'s bounded payload
  (`Docs/PRIVACY_AND_ROUTING.md:84`), adjacent-sentence cosine similarity in `SemanticChunker.swift`,
  PDFKit `page.string` for text-layer PDFs, and per-library index scoping
  (`vector_database_<containerId>.json` in `WorkspaceSyncService.swift:2542`, plus a `containerId`
  column in `SQLiteFullTextService.swift:362`).
- Notion: queried the roadmap data source, confirmed no emoji statuses so it is the right database,
  and confirmed **no pre-existing row tracked this work** before creating one.

**Not verified.** Every on-device behaviour, since Foundation Models do not run in the simulator, and
every Mac path. Specifically for this work: no definition sheet has been opened on real hardware, so
the popover presentation, its `.medium` detent, and the dashed underline on 8pt labels are all
unverified visually. Nothing about the vocabulary layer needs Foundation Models, so the simulator is a
fair check of everything except appearance and VoiceOver.

## Blockers / Unknowns

**1. `8b30ae5` is not pushed**, and `origin/main` is at `e60fa7f`. The work exists in one local
checkout inside iCloud-synced `~/Documents`, which is the least durable place it could be.

**1b. 152 pushed commits carry a `Co-Authored-By: Claude` trailer the owner wants gone.** Removing it
from history means `git filter-branch` or `git filter-repo` over the whole range plus a force-push to
`origin/main`, which rewrites published history and changes every SHA from the root. **Do not do this
without him asking for it explicitly**, and if he does, note that every SHA referenced in
`CHANGELOG.md`, `Docs/RELEASE_NOTES.md` and past handoffs becomes wrong. Leaving history alone and only
preventing new trailers is the low-cost option and is what is in force.

**2. Four device checks close every open verification item, carried from 2026-08-10.** On a physical
device: type in Settings search; run a query with the HUD visible and watch the Neural Engine bar;
rotate with the HUD on; update from a pre-v5.0 build to see the sample refresh banner. Add a fifth
now: tap a device chip on the onboarding completion card with VoiceOver on and confirm each chip is
its own element, which is the `.combine` to `.contain` fix and cannot be checked in the simulator.

**3. `README.md` claims iWork support and the app cannot read iWork files.** README line ~55 says the
app reads "Office and iWork files". `Docs/USER_CHANGELOG.md` v5.0 says Pages, Numbers and Keynote
"were never actually readable". The Notion roadmap already tracks this as a To Do v5.0 row,
"iWork import is advertised but cannot read any file iWork produces",
<https://app.notion.com/p/3b749a74d54f81569b7eda2df6a887bc>. Handle the README line and that row
together, and use `oi-claim-audit` first because it is a claim removal.

**4. `VisualizationsView.swift:408` tells users embeddings are "512-number vectors".** The model
outputs 384. `AdaptiveEmbeddingOptimizer.swift:753` says so explicitly. Not fixed here because
correcting a specific figure in user-facing copy requires `oi-claim-audit`.

**5. `OnboardingChecklistView.swift:881` logs "Generating BM25 dictionary + HNSW vectors".**
`BNNSVectorDatabase` is a flat store searched by batched `vDSP_mmul`, not an HNSW graph. The glossary
deliberately does not repeat "HNSW". Verify by reading `BNNSVectorDatabase.swift` for any graph
construction; if there is none, that log line names an algorithm the app does not use.

**6. Blocker 6 of the previous handoff was wrong and is retired.** It said the Notion roadmap had not
been touched and that "Liquid Glass UI Refresh" needed closing. That row was updated 2026-08-10 with a
dated progress note, is correctly `In Progress`, and lists what remains: sheet presentations,
navigation bars, remaining feature screens, and migration off the pre-iOS-18 `.tabItem` API. Do not
mark it Completed.

**7. The retrieval eval set is saturated and cannot score a model change.** R@5 = 1.00 at every stage
but `lexical` 0.94. `RetrievalStageMetrics.swift:45` states recall@5 "gives no information beyond 'did
a chunk from the right file appear'". **Read MRR@10 and nDCG before any embedder or reranker
decision.** If MRR is also at ceiling, retrieval is not the bottleneck; if MRR is poor while R@5 is
1.00, it is a reranker problem, which is the cheap Apache-licensed swap rather than a re-embed.

**8. Licensing shapes the embedder decision.** The shipped stack (MiniLM-L6-v2,
`ms-marco-TinyBERT-L2-v2`) is Apache 2.0. **EmbeddingGemma is not**; it ships under the Gemma Terms of
Use, whose §3.1 requires the use restrictions to be enforceable against *your* users. Jina's v2
reranker weights are reported CC-BY-NC; verify before relying on that. Not legal advice.

**9. The What's New sheet is a changelog, not a splash.** The `"5.0"` entry has 8 items and no deep
links, and `WhatsNewView` has one button, "Done". Cutting to 3-4 and making rows navigate is the
improvement.

**10. Carried from 2026-08-09.** The malformed `[Needs Verification]` block still reaches users
(`SourceOnlyAnswerService.swift:349`). The verification gate still hedges correct answers.

## Exact Next Action

**Commit the 16 paths.** The work is verified at 219 tests, 0 failures, and exists nowhere but this
working tree. One commit, `feat(UI):` scope, the vocabulary layer. Do not `git add .`; add the 16
paths by name.

```bash
git status --porcelain   # expect exactly 16: 12 modified, 4 untracked
```

**Then wait on the owner before touching any `plain` string.** He had not reacted to the copy when the
session ended. It is published for review at
<https://claude.ai/code/artifact/9173a230-2eae-4b12-bff7-615af65df9c8>, generated from
`Glossary.swift` by the scratchpad script named in Working Set. He has said previous attempts at this
kind of writing "came out cringe", so **expect revisions to the `plain` register**, and regenerate that
page and republish the same file path after any change so the URL holds.

If he asks for a different direction on the hardware figures specifically, the decision already taken
is recorded in `Docs/ai/DECISIONS.md`: the figures stay and each explains itself, rather than being
removed or softened. Reopening that is his call, not a default.
