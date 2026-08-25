# Current State

Updated: 2026-08-25
Branch/worktree: main, pushed and clean as of writing.
Cross-tool handoff (if Claude access runs out): `HANDOFF.md` at repo root (kept current less often than this file).
Last verified commit: a1508d6

## Objective

**Get v5.0 shippable.** It is a correctness release, not a feature drop: PCC does not ship in it and
the notes say so. **Notion is authoritative for the row list** — use the `notion-roadmap` skill, do
not re-derive it here.

## Status

**v5.0 is 43 Completed against 5 open, and every open row is a device check rather than unstarted
work.** Nine code fixes landed 2026-08-24 into 08-25 at **317 tests, 3 skipped, 0 failures** (from
287). **None of the nine is device-verified.** One attempt to measure them on the Mac failed
outright — see Blocker 6.

## Completed this session (2026-08-25)

- **`0efb2d0`** Research papers were read as parts catalogues. `"min"` inside dopa**min**e made every
  dopamine query a specification lookup; `"ft"` matched "often", `"amp"` matched "example";
  `.caseInsensitive` on an uppercase PartNumber pattern turned `behavior.42` into a part number.
  Word-boundary matching, an anchored standards regex, and a bibliography penalty at both existing
  demotion sites.
- **`11b8d9f`** **The largest finding of the pass.** The extractive evidence re-sort used
  `abs(lhs - rhs) > 0.05` inside its comparator, which is not a strict weak ordering, so
  `sorted(by:)` returned an **unspecified** result. The evidence order behind every extractive
  answer was undefined. It sits exactly where `final` r@1 falls below `rerank`.
- **`19e93d0`** One answer-replacement site had no citation guard (length test only), and it is the
  pass most likely to strip citations because it is told to remove unsupported claims. Separately
  `citationCount` matched `[S1]` but not `(S1)`, so an answer citing in parentheses counted as zero
  and the guard **waved through exactly what it exists to block**.
- **`7851b92`** Self-RAG now retries an answer asserting its sources are silent while citing them.
  Requires a corpus reference **and** an absence phrase in one sentence, so a reported null result is
  not confused with a claim about the corpus. Honest abstention with nothing cited is unaffected.
- **`a78260a`** The background-grant row's premise is **false** — the task is submitted, proven from
  `whatQuery.txt`. Its lifecycle logs moved to a trace-visible category instead of a fix being
  written for a non-bug.
- **`771461c`** Sync churn. 128 store opens / 43,164 chunk records / **0 writes** in one session,
  half before first paint. A signature of both roots plus document set, aliases and strategy now
  skips the reads when nothing has moved. Hard-boundary file, edited under explicit approval.
- **`91ea045`** A library with **no** embedding fingerprint is flagged for rebuild instead of
  silently adopting the live one. `3b48c88`'s nil-adopt was right in August and wrong for release:
  v5.0 is the first build carrying the field, so nil **plus documents** means indexed by the
  pre-5.0 pipeline — 55% of content unembedded (`2753d15`) and CLS pooling (`3ea5cd9`). **Release
  consequence: every user updating from 4.9 with documents sees a one-time rebuild offer.**
- **`a1508d6`** The App Store listing said *"nothing will prompt you to change it"*, which `91ea045`
  made false. Corrected and re-pushed, 3,966 chars, read back from the API and confirmed.

## Active Constraints

- **Build from a copy outside iCloud.** `rsync -a --delete --exclude 'BenchmarkRuns/' --exclude
  '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' --exclude '.git.nosync/' ./ /private/tmp/oi-src/`
  then build there. In place it deadlocks in `NSFileCoordinator`, including
  `scripts/build_simulator_smoke.sh`.
- **Nothing else builds, tests or runs while a benchmark measures.**
- **Never delete a `BenchmarkRuns/*` directory.** Gitignored, so deletion is permanent. Tidy the
  ledger, never the runs.
- **Core AI does not work in the Simulator** — embeddings are Mac or device only.
- **`Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` must stay
  byte-identical**; `VersionHistoryTests` asserts it. `WHATS_NEW.md` is a third, condensed copy whose
  bullets are worded differently, so a text match that works on the first two often misses it.
- **`fastlane/metadata/en-US/release_notes.txt` is at 3,966 of 4,000 characters.** Anything added
  needs something removed, and it must not contradict shipped behaviour.
- Commit to `main`; do not branch.

## Working Set

| File | Why |
|---|---|
| `Docs/ai/RUNBOOK.md` → Retrieval benchmark | Items 1, 1b and 7. Item 7 is the one that was skipped and cost fifty minutes. |
| `BenchmarkRuns/LEDGER.md` | Top two entries are the undefined-sort correction and the failed run. Read before trusting any `final`-stage figure. |
| `scripts/run_quality_matrix.py` | `--limit`, `--sampling`, `--manifest`, `--resume`. |
| `OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift` | Hard boundary. Holds the new signature cache; needs the owner to name it in any future approval. |
| `OpenIntelligence/Services/RAG/Orchestration/RAGService.swift` | The nil-fingerprint branch changed by `91ea045`. |
| `fastlane/metadata/en-US/release_notes.txt` | Live App Store text, 34 characters of headroom. |

## Verification

Command → result, this session only:

- `xcodebuild test`, iOS 27 Simulator, from `/private/tmp/oi-src` → **317 tests, 3 skipped, 0
  failures**, run after each of `19e93d0`, `7851b92`, `771461c` and `91ea045`.
- `scripts/build_simulator_smoke.sh` from `/private/tmp/oi-src` → **BUILD SUCCEEDED** each time.
- macOS Debug unsandboxed build → **BUILD SUCCEEDED**; `codesign -d --entitlements -` printed none,
  which is the runbook's precondition for benchmarking.
- `fastlane push_metadata` after `a1508d6` → exit 0; ASC read-back `whatsNew` **3,966 chars**,
  matching the local file exactly.
- `python3 scripts/secret_scan.py` → no sensitive tokens.

**Not run:** any device verification of the nine fixes; any successful benchmark.

## Blockers / Unknowns

**Rows 1-5 are device checks. Row 6 is agent work and is the only one that does not need the phone.**

1. **Sync churn (`771461c`).** Baseline to beat: **128 opens / 43,164 chunk records / 0 writes**.
   **The half that matters is the second: a genuine change must still sync.** Edit or import on one
   device and confirm it reaches another. The failure this could introduce is a *skipped* sync, not
   a slow one. No unit coverage — sync has none.
   https://app.notion.com/p/3c649a74d54f81219022c292bc4aba31
2. **Fingerprint rebuild offer (`91ea045`).** A library with documents and no fingerprint should now
   surface the rebuild banner. **The owner's own libraries were already stamped by a dev build
   carrying `3b48c88` and will not flag** — testing this needs a library that has never run such a
   build, or delete-and-re-import.
   https://app.notion.com/p/3bf49a74d54f812597ffd48a165a139f
3. **Self-RAG contradiction check (`7851b92`).** Look for `Answer asserts its sources do not cover
   the question while citing N of them`. https://app.notion.com/p/3bf49a74d54f81b8a47ef00d9037f08e
4. **Library with no vectors cannot repair itself.** Needs a staged stuck-queue item. Discriminator:
   `Self-healing rebuild completed successfully` with no preceding `[Reembed] STARTING FULL REBUILD`.
   https://app.notion.com/p/3c049a74d54f81fd9255edc739959d36
5. **Background grant — recommend moving out of v5.0.** Premise corrected: the task **is** submitted.
   What is unknown is whether a long answer survives backgrounding, which no code change addresses.
   https://app.notion.com/p/3c149a74d54f8171adfcce5dcb345777
6. **`final` vs `rerank` r@1 has never been measured against a defined sort, and the run that would
   fix that failed.** `20260825-postfix-greedy-83`: cases 1-5 each `ERROR: timeout after 600s`,
   killed during case 6, **no `reports/` written so nothing attributes the hang**. Sandbox cause
   ruled out (zero `have permission to save`, empty entitlements). Whether Foundation Models
   generation completed is **not established** — the 600s shape matches the runbook's eight-retry
   description, but that passage concerns the Simulator and says the host Mac generates fine.

## Exact Next Action

**Diagnose the benchmark with a two-case run before spending another five hours.** From
`/private/tmp/oi-src`, with the macOS app already built at
`/private/tmp/oi-mac-nosbx/Build/Products/Debug/OpenIntelligence.app`:

```bash
python3 scripts/run_quality_matrix.py --app /private/tmp/oi-mac-nosbx/Build/Products/Debug/OpenIntelligence.app --manifest Benchmarks/ResearchFixtures/qasper_external_v1/manifest.json --modes standard --pcc deny --sampling greedy --limit 2 --output-dir BenchmarkRuns/20260825-diagnose-2
```

If both cases time out again, read the per-case report under `reports/` for where it stalls —
absence of Foundation Models output would confirm the FM hypothesis the failed run could not.
If they pass, the 83-case run is sound and can be relaunched with the same flags minus `--limit`.

**Owner, in parallel:** one phone session settles rows 1, 3 and 5 — import a document, ask a question
that would previously have drawn an absence claim, background the app mid-answer, share the trace.
