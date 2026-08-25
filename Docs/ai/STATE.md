# Current State

Updated: 2026-08-25
Branch/worktree: main, pushed to `origin/main`.
Cross-tool handoff (if Claude access runs out): `HANDOFF.md` at repo root (kept current less often than this file).
Last verified commit: ef5ede0

## Objective

**Get v5.0 shippable.** It is a correctness release, not a feature drop. **Notion is authoritative
for the row list** — use the `notion-roadmap` skill, do not re-derive it here.

## Status

**v5.0 is 43 Completed against 4 open.** The overnight retrieval pass was device-verified on
2026-08-25 in `whatQuery.txt` and closed three rows at once. Four fixes confirmed on hardware: the
source-only gate declined a 23%-coverage replacement and kept the answer, `Draft generation failed`
is gone with the stage demonstrably running, spec-query boosts went 6 to 0, and no bibliography
entry reached the citation map. What remains is two staged device checks and two unstarted tasks.

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

**Two staged device checks. Neither is a normal query — both need a deliberately constructed state.**

1. **A library with no vectors cannot repair itself, and the repair reports success.** Detection and
   repair are device-proven; the **blocked-rebuild** path never has been. Needs a library with a
   stuck non-terminal ingestion queue item, which vetoes its own document's repair. Discriminator on
   the row: `Self-healing rebuild completed successfully` with no preceding
   `[Reembed] STARTING FULL REBUILD`. https://app.notion.com/p/3c049a74d54f81fd9255edc739959d36
2. **Existing libraries keep truncated vectors.** `EmbeddingFingerprint` shipped in `3b48c88`, but
   every existing container had `embeddingFingerprint == nil` and took the silent-adopt branch, so
   the event that would have proven the flag was absorbed and **cannot fire twice**. Replacement
   condition on the row: induce a fingerprint change on a library that already carries one — a
   chunker-recipe change or a `modelRevision` bump — then confirm flag, banner and rebuild on device.
   The owner's own library is in this state; delete-and-re-import is the cheap workaround.
   https://app.notion.com/p/3bf49a74d54f812597ffd48a165a139f

**Two unstarted tasks.**

3. **Self-RAG accepted an answer that contradicts itself and its own sources at 88% confidence.**
   https://app.notion.com/p/3bf49a74d54f81b8a47ef00d9037f08e
4. **A long answer outlives its 30-second background grant**; the task that would save it is
   registered but never submitted. Loses the answer, so it passes test 1.
   https://app.notion.com/p/3c149a74d54f8171adfcce5dcb345777

**Not in the release, but live and now filed.** The recursive-research loop keeps proposing to
replace long cited answers with uncited fragments — six occurrences across three captures, most
recently `3080 chars -> 352 chars` twice in one query. `shouldAcceptReplacement` has caught every
one. The loop *prefers* the fragment because an answer with no citations has its grounding forced to
0.5 and skips the retry check, so uncited always verifies cleaner than cited. The guard is a net
under a bug; nobody has enumerated the replacement sites to confirm it covers all of them, and that
enumeration is a code read rather than a device run.
https://app.notion.com/p/3c749a74d54f816b808cee4e0284948c

## Exact Next Action

**Agent-side, and it costs nothing on device: re-run the greedy A/A pair on a build containing
`11b8d9f`.** The 2026-08-23 pair was bit-identical on vector, lexical and fusion but jittered at
`boosted` and between `rerank` and `final`. `final` sits downstream of the extractive re-sort, whose
result was undefined until that commit. If the jitter narrows, the "two runs return different
evidence" row has its answer and the `final` r@1 figure can be re-taken in the same run — and that
figure needs re-taking regardless, because the 27.0%/15.2% attribution was measured against the
undefined sort.

Then Blocker 4 (background grant, passes test 1) and Blocker 3 (Self-RAG contradictions), each
needing `PROCEED: IMPLEMENT`. The two staged device checks are the owner's whenever convenient.
