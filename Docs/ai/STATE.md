# Current State

Updated: 2026-08-25
Branch/worktree: main, pushed to `origin/main`.
Cross-tool handoff (if Claude access runs out): `HANDOFF.md` at repo root (kept current less often than this file).
Last verified commit: 771461c

## Objective

**Get v5.0 shippable.** It is a correctness release, not a feature drop. **Notion is authoritative
for the row list** — use the `notion-roadmap` skill, do not re-derive it here.

## Status

**v5.0 is 43 Completed against 5 open**, and every open row now has either code waiting for a
device check or a staged test. Five more fixes landed on 2026-08-25 — the answer-replacement hole,
the Self-RAG contradiction check, the background-task correction, and the sync churn — at **317
tests, 0 failures** (from 287 two days ago). **None of today's work is device-verified.**

## Completed this session (2026-08-24)

- **App Store Connect fixed and the 5.0 listing rewritten.** `APP_STORE_CONNECT_API_KEY_PATH`
  pointed at a file that was never an ASC key (12-char id where Apple issues 10). `~/.zshrc` now
  uses `AuthKey_Q3VSSU8ZGD.p8`. `scripts/asc_healthcheck.rb` answers it in ~2s. Release notes were
  still 4.9's text; rewritten to 3,995/4,000 chars, pushed, read back byte-for-byte.
- **`ece4bae` — the app no longer deletes a just-imported document's vectors.** Device-verified: the
  guard refuses at both points where the old build deleted silently, 0 occurrences of the failure
  signature against 87 before.
- **`0a79b1c` — page text is no longer transposed.** Device-verified on all 8 pages. The cause was a
  non-transitive comparator using a 0.02 threshold against ~0.015 line spacing, so neighbouring
  lines ordered by left edge. Four earlier diagnoses were wrong and are recorded on the row.
- **`dbff15a` — the source-only stage no longer destroys the answer it verifies.** Not yet executed
  on device; see Blocker 1.
- **`3b857ab`** — the ingestion overlay no longer breaks "Processing uploads" mid-word.
- **`0efb2d0` — the app stopped reading research papers as parts catalogues.** `detectSpecificationQuery`
  substring-matched two keyword lists, so bare `"min"` made every dopa**min**e query a specification
  lookup and `"ft"`/`"oz"`/`"amp"` matched inside "often", "dozen", "example". `.caseInsensitive`
  defeated the PartNumber pattern, turning reference markers (`behavior.42`, `min.43`) into part
  numbers. Added `computeBibliographyPenalty` beside the two existing penalties at **both** sites,
  because 2 of 20 cited sources in a shipped answer were bibliography entries.
- **`11b8d9f` — the extractive evidence re-sort had no defined result.**
  `abs(aPriority - bPriority) >= 2` inside a comparator is non-transitive; `sorted(by:)` is
  documented as unspecified for such a predicate. **Third instance of that shape found today.** The
  LEDGER now records that its 27.0%/15.2% rank-1 figure was measured against this undefined sort and
  must be re-taken. `extractivePriorityScore` also credited substring keyword hits at 5 points each;
  now whole-word.
- **Source-only gate instrumented.** Three device runs failed to reach that stage and each looked
  identical to a stage that ran and found nothing. Every guard now names itself, and
  `classifyAnswerIntent` logs the intent it computed for every query.
- **Scope pass.** 5 rows left v5.0: PCC entitlement, the Xcode toolchain row and physical-device
  testing to `Future Backlog` (no `v5.1` option exists in the schema); iWork **Completed** because
  the advertising it contradicted has been withdrawn; the context-window row was **kept open** after
  its apparent pass turned out to be vacuous.
- **PCC settled by research, not by testing.** Re-verified against `developer.apple.com/news/releases`
  on 2026-08-24: **Xcode 27 beta 6 shipped today and there is still no Release Candidate.** Apple
  opens App Store submissions at the RC, so PCC cannot ship in v5.0 at any price. The entitlement was
  never the question — it survives distribution signing, verified 2026-08-20 against a local Xcode 27
  archive carrying 18 `PrivateCloudComputeLanguageModel` symbol references. The release notes already
  say shipped builds do not contain PCC, so the decision was made in copy before the rows caught up.

## Active Constraints

- **Build from a copy outside iCloud.** `rsync -a --exclude 'BenchmarkRuns/' --exclude
  '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' ./ /private/tmp/oi-src/`, then run the
  script from there. **This includes `scripts/build_simulator_smoke.sh`** — in place it deadlocks in
  `-[NSFileCoordinator _blockOnAccessClaim:withAccessArbiter:]`, confirmed with `sample`.
- **The smoke script builds only; it does not run tests.** Full suite:
  `xcodebuild test -scheme OpenIntelligence -destination "platform=iOS Simulator,id=8FA2B3CE-5EB0-4339-8629-F40684EDCE2D" -derivedDataPath /private/tmp/oi-build`
  Warm: ~2-4 min. Cold: ~10-15. Current baseline **302 tests, 3 skipped, 0 failures**.
- **Nothing else builds, tests or runs while a benchmark measures.** Never `pkill` on the app path.
- **Core AI does not work in the simulator** — anything touching embeddings is device-only.
- **Never delete a `BenchmarkRuns/*` run directory** — gitignored, so deletion is permanent.
- **`Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` must stay
  byte-identical.** `VersionHistoryTests` asserts it. `WHATS_NEW.md` is a third, condensed copy.
- **A pre-commit hook rejects any `.swift` change without a doc update** in `WHATS_NEW.md`,
  `CHANGELOG.md` or `Docs/`.
- Commit to `main`. Do not branch.

## Working Set

| File | Why |
|---|---|
| `scripts/asc_healthcheck.rb` | Run before ever diagnosing an ASC failure from its error text. |
| `fastlane/metadata/en-US/release_notes.txt` | 3,995 of Apple's 4,000 chars. Anything added needs something removed. |
| `Docs/USER_CHANGELOG.md` | Source of truth for user-facing history; copy to `VersionHistory.md` on every edit. |
| `OpenIntelligence/Services/RAG/Orchestration/RAGEngine.swift` | `computeTOCPenalty` / `computeQuestionBankPenalty` at two sites — where the bibliography penalty belongs. |
| `OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift` | `:585-598` substring spec match, `:519` unanchored standards regex. |
| `BenchmarkRuns/LEDGER.md` | Full narrative of every run. Read before trusting any figure. |

## Verification

- `xcodebuild test` on iOS 27 → **287 tests, 3 skipped, 0 failures**, run after each of `ece4bae`,
  `dbff15a`, `952d85f`, `0a79b1c` and the probe removal.
- Device: vector-deletion fix and reading-order fix both **proven on hardware** (captures
  `SameProcessButPostChanges.txt`, `PostPostFixAgain.txt`).
- ASC read-back of `appStoreVersionLocalizations` matches all three local metadata files exactly.

**Not verified:** `dbff15a` has never executed; the three To Do rows are unstarted.

## Blockers / Unknowns

**Everything open is now a device check. No unstarted code work remains in v5.0.**

1. **Sync churn — the highest-value check, and the one with real downside if wrong.**
   `771461c` skips the two full store reads when a signature of both roots, the document set,
   `documentAliases` and `strategy` matches a pass that concluded nothing needed writing.
   Baseline to beat: **128 opens / 43,164 chunk records / 0 writes** in one session, 64 opens
   before first paint. **The check that matters is the second one:** a genuine change must still
   sync. Edit or import on one device and confirm it reaches another. The failure this could
   introduce is a *skipped* sync, not a slow one. No unit coverage — sync has none.
   https://app.notion.com/p/3c649a74d54f81219022c292bc4aba31
2. **Self-RAG contradiction check.** `7851b92` retries an answer that asserts its sources are
   silent while citing them. Look for `Answer asserts its sources do not cover the question while
   citing N of them`. An honest abstention citing nothing is explicitly unaffected and has a test.
   https://app.notion.com/p/3bf49a74d54f81b8a47ef00d9037f08e
3. **A library with no vectors cannot repair itself.** Needs a staged stuck-queue item.
   Discriminator: `Self-healing rebuild completed successfully` with no preceding
   `[Reembed] STARTING FULL REBUILD`. https://app.notion.com/p/3c049a74d54f81fd9255edc739959d36
4. **Existing libraries keep truncated vectors.** Original closing test was consumed by nil-adopt
   and cannot fire twice; needs a fingerprint change induced on a library that already carries one.
   https://app.notion.com/p/3bf49a74d54f812597ffd48a165a139f
5. **Background grant — recommend moving out of v5.0.** The row's premise is false and now
   corrected: the task **is** submitted, and `whatQuery.txt` shows `Submitted continued query task`
   once with zero failures. What is unknown is whether a long answer survives backgrounding, which
   nothing in the repo can settle. Its lifecycle logs now reach a shareable trace.
   https://app.notion.com/p/3c149a74d54f8171adfcce5dcb345777

**Not in the release, filed:** the recursive-research loop still proposes uncited fragments — six
occurrences across three captures. Every displacement site is now guarded, so the harm is contained,
but the loop *prefers* the fragment because an uncited answer has its grounding forced to 0.5 and
skips the retry check. Changing that risks a loop and needs its own measurement.
https://app.notion.com/p/3c749a74d54f816b808cee4e0284948c

## Exact Next Action

**Owner, one session on the phone settles four rows.** Import a document (checks sync churn and the
truncated-vector flag), let it finish, ask a question that would previously have drawn an absence
claim (checks the Self-RAG contradiction check), and background the app mid-answer (checks the
continued-query task). Share the trace.

**Agent-side, and it costs nothing on device:** re-run the greedy A/A pair on a build containing
`11b8d9f`. `final` sits downstream of the extractive re-sort, whose result was undefined until that
commit. If the jitter narrows, the "two runs return different evidence" row has its answer and the
`final` r@1 figure can be re-taken — which it needs regardless, because the 27.0%/15.2% attribution
was measured against the undefined sort.
