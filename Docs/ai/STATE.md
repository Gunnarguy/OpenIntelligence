# Current State

Updated: 2026-08-24
Branch/worktree: main, **not pushed** — check `git status` against `origin/main` before assuming this is current.
Cross-tool handoff (if Claude access runs out): `HANDOFF.md` at repo root (kept current less often than this file).
Last verified commit: 0837f29

## Objective

**Get v5.0 shippable.** PCC has never shipped (Xcode Cloud builds with Xcode 26.6; no Xcode 27 RC
exists yet), so v5.0 is a correctness release, not a feature drop. Scope was frozen 2026-08-21 to 11
Notion rows passing one of three tests (loses/corrupts data, breaks an advertised capability, or
blocks shipping). **Notion is authoritative for the row list** — use the `notion-roadmap` skill, do
not re-derive it here.

## Status

**The vector-deletion fix is device-verified and both its rows are closed.** A second capture on a
build carrying `ece4bae` shows the guard refusing at both of the exact points where the previous
build deleted silently, zero occurrences of the failure signature against 87 before, and the vectors
surviving a relaunch with no rebuild needed. **The source-only fix is still unexercised** — that path
is gated on extractive-first intent and the question asked was narrative, so it never ran.

## Completed this session (2026-08-24)

- **App Store Connect metadata push fixed, after two prior sessions diagnosed it wrongly.**
  `APP_STORE_CONNECT_API_KEY_PATH` pointed at `ApiKey_5UNPFIPXPPRC.p8` — a 12-character id where
  Apple issues 10, 240 bytes where every genuine `AuthKey_*.p8` here is 257, and dated 2026-06-02,
  fourteen months before the rotation that supposedly produced it. **It was never an App Store
  Connect key.** `JT97AQ3U4U` was separately revoked and is absent from Users and Access. So the
  rotation swapped a dead key for a non-key, and Apple returns a byte-identical bare 401 for both.
  A working Admin key, `Q3VSSU8ZGD`, was sitting unused in `~/Downloads` the whole time; the issuer
  UUID was correct throughout. **`~/.zshrc` now points at
  `~/.appstoreconnect/private_keys/AuthKey_Q3VSSU8ZGD.p8`.** Backup at `~/.zshrc.bak-asc-20260824`.
- **`scripts/asc_healthcheck.rb`** — one command, ~2s, prints the configured key, validates id
  length/filename/mode, authenticates against `GET /v1/apps` and confirms the app is reachable.
  Prints no key material, no issuer UUID, no token. It catches this specific defect *before* the
  network call, on id length alone. Both paths were run.
- **`Docs/ai/RUNBOOK.md` Release section corrected.** It said credentials come from `.env.appstore`.
  That file defines `ASC_KEY_ID`/`ASC_ISSUER_ID`/`ASC_KEY_BASE64`, which **no lane reads**, and loads
  only under `fastlane --env appstore`; the Fastfile reads `APP_STORE_CONNECT_*` from the shell. The
  doc pointing at the wrong one of two credential sources is the discoverability half of why this
  stayed broken for days. Also records the UTF-8 locale `deliver` needs.
- **5.0 release notes rewritten and pushed.** `fastlane/metadata/en-US/release_notes.txt` still held
  the 4.9 text. New text is 3,995 characters against Apple's 4,000 limit after the `96e73a1` trade, pushed with `deliver`
  (metadata only, screenshots explicitly skipped) and **read back from
  `appStoreVersionLocalizations` and confirmed byte-for-byte**.
- **The embedding arc was missing from every user-facing file.** `2753d15` (tokenizer padding),
  `3ea5cd9` (mean-pooling re-export) and `3b48c88` (fingerprint) are the release's largest measured
  retrieval change and appeared only in `CHANGELOG.md`. A `Search` section now covers them in all
  three user-facing files, including the part that reads badly and is true: **a library built before
  this release keeps its old index and will never be prompted to rebuild**, because
  `embeddingFingerprint` was nil on every existing container and took the silent-adopt branch.
- **Two user-facing claims were stronger than their own Notion rows, corrected via `oi-claim-audit`.**
  "Four separate ways ... found and closed" claimed four closures where two are device-proven and the
  two queue-vetoed rebuild paths have never been exercised. Reworded in all three files to say what
  is verified and name the rest as fixed-not-verified. Nothing was deleted.
- **`OpenIntelligence/Resources/VersionHistory.md` had drifted from `Docs/USER_CHANGELOG.md` by one
  bullet** (the dark app icon, added by `defc7e6` to only one of the two). `VersionHistoryTests`
  asserts byte-equality on these; they are identical again at 42,425 bytes.
- **Notion row created** (Completed, v5.0, Infrastructure):
  [The App Store metadata push pointed at a file that was never an App Store Connect key](https://app.notion.com/p/3c649a74d54f81019954f8d4eab3b1bc)
- **Device console forensics** over `Delete+IngestANDCHANGELIBRARIESMIDINGEST+Query+Rebuild.txt`
  (11,690 lines, gitignored, kept at repo root). 16 confirmed findings, 4 rejected on verification.
  Four Notion rows filed and two existing rows corrected in place — see Blockers.
- **`ece4bae` — the app no longer deletes a just-imported document's vectors.**
  `synchronizeVectorStore` refuses to delete when the chunks it just read are non-zero, and
  `removeVectorStoreArtifacts` takes a mandatory `reason` and logs what it removed. All eleven call
  sites labelled, not a subset. Hard-boundary file, edited under explicit owner approval.
- **`dbff15a` — the source-only stage no longer destroys the answer it verifies.** Drop loop bounded
  by `evidenceBudgetShare` (it previously stopped at the whole budget); `snippetLimit` sized against
  a measured probe render rather than raw snippet length; and `SourceOnlyAnswerOutcome` now carries
  `candidateCoverage`, with the caller keeping the generated answer below 0.85. The gate is the
  load-bearing part — enforcing the share alone still leaves under 600 characters for a long answer.
- **`96e73a1` — App Store notes re-pushed** with the vector-deletion fix, 3,995/4,000 characters,
  read back byte-for-byte. Two bullets traded out to make room.

## Active Constraints

- **Build from a copy outside iCloud.** `rsync -a --exclude 'BenchmarkRuns/' --exclude
  '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' ./ /private/tmp/oi-src/`, then build with
  `-derivedDataPath` under `/private/tmp`. In place it hangs in NSFileCoordinator.
  **This includes `scripts/build_simulator_smoke.sh`.** Re-confirmed 2026-08-24: run from the repo
  root it deadlocks with no output past the build-settings dump, and `sample` shows
  `-[NSFileCoordinator _blockOnAccessClaim:withAccessArbiter:]` → `semaphore_wait_trap`. Writing DerivedData to
  `.simulator-smoke.nosync/` is not sufficient, because the deadlock is on *reading the source*,
  which is still in iCloud. Rsync first, then run the script from the copy.
- **Nothing else builds, tests or runs while a benchmark measures.** Never `pkill` on the app path —
  match `Contents/MacOS/OpenIntelligence`, not `--app`.
- **Core AI does not work in the simulator** — anything touching embeddings is device-only.
- **The benchmark ingests into the real library**, protected by snapshot. Never delete a
  `BenchmarkRuns/*` run directory — gitignored, so deletion is permanent.
- **`Docs/USER_CHANGELOG.md` and `OpenIntelligence/Resources/VersionHistory.md` must stay
  byte-identical.** `VersionHistoryTests` fails otherwise. Editing one means copying it over the
  other in the same turn. `WHATS_NEW.md` is a third, condensed copy in `**Label:**` style.
- Commit to `main`; do not branch. Do not push unless asked.

## Working Set

| File | Why |
|---|---|
| `scripts/asc_healthcheck.rb` | Run before ever diagnosing an ASC failure from its error text. |
| `Docs/ai/RUNBOOK.md` → Release → App Store Connect credentials | The corrected credential source and the `deliver` locale requirement. |
| `fastlane/metadata/en-US/release_notes.txt` | What the App Store shows for 5.0. 3,995 of 4,000 characters — anything added needs something removed. |
| `Docs/USER_CHANGELOG.md` | Source of truth for user-facing history. Copy to `OpenIntelligence/Resources/VersionHistory.md` on every edit. |
| `Delete+IngestANDCHANGELIBRARIESMIDINGEST+Query+Rebuild.txt` (repo root, gitignored) | The device capture behind Blockers 1-3. Line 11513 is the relaunch divider. 1.78 MB — grep it, never read it whole. |
| `BenchmarkRuns/LEDGER.md` | Full narrative of every run. Read before trusting any figure. |
| `OpenIntelligence/App/DebugRAGValidationHarness.swift` | `RERANK CHUNK TEXT` lives here; extend for a rerank-stage `passage_present` scoring pass. |

## Verification

Command → result, this session only:

- `ruby scripts/asc_healthcheck.rb` → **READY**, 8 apps visible, OpenIntelligence reachable
  (id 6756559175). Same script with the old broken values → **NOT READY**, exit 1, correct
  explanation, before any network call.
- `LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 fastlane push_metadata` (metadata only, screenshots skipped,
  version 5.0, platform ios) → **exit 0**, `fastlane.tools finished successfully`.
- ASC read-back of `appStoreVersionLocalizations` for the 5.0 iOS version → description 3,482,
  whatsNew 3,996, promotionalText 161 characters, each matching the local file exactly after
  trailing-whitespace stripping.
- `diff Docs/USER_CHANGELOG.md OpenIntelligence/Resources/VersionHistory.md` → **identical**, which
  is precisely what `VersionHistoryTests.testBundledHistoryMatchesTheWrittenChangelog` asserts.
- ASC `builds` API → iOS 4.9 shipped as **build 265, uploaded 2026-08-03T17:28:20-07:00**. `git log`
  puts `acfbfbd` (17:17:16) as HEAD at that moment, so the five orchestration fixes dated 08-03
  shipped in **4.9**, not 5.0, and are correctly absent from the 5.0 notes.

- Device console capture, 11,690 lines, physical iPhone, build 150: import + mid-import library
  switch + query + relaunch. `[BNNS] Persisted 196 chunks` at 6675 and `Persisted 197` at 6866, then
  `no vector store yet` from 6951 — the store was written twice and removed twice. Analysed by 26
  agents across 6 dimensions; 16 findings confirmed against the source, 4 rejected on verification.

- `xcodebuild test` on iOS 27 (UDID 8FA2B3CE-5EB0-4339-8629-F40684EDCE2D), after each of `ece4bae`
  and `dbff15a` → **277 tests, 3 skipped, 0 failures, TEST SUCCEEDED** both times. Note the suite
  references `WorkspaceSync` nowhere and covers no orchestration path, so this bounds regressions
  rather than proving either fix.

**Not run:** device verification of `ece4bae` or `dbff15a`; the simulator test suite (`build_simulator_smoke.sh`
builds only, it does not run tests); anything on device since 2026-08-19; the rerank-stage
`passage_present` scoring pass (data exists, scorer does not).

## Blockers / Unknowns

1. **`dbff15a` has never executed. Two device runs have now missed it, so note the exact reason.**
   `sourceOnlyOutcomeIfNeeded` opens with `guard answerIntent.isExtractiveFirst`, and
   `QueryEnhancementService` only returns `.lookup` for queries whose prefix is in
   `["what", "which", "when", "where", "who", "how much", "how many", "wat"]`. **Bare "How do…" is
   not in that list.** *"How does dopamine affect social behavior?"* (2026-08-24 evening) and
   *"How do dopamine and serotonin signals affect movement?"* (later the same night) both classified
   conceptual/balanced and skipped the stage; both answered healthily at 526 and 554 words. The
   question must start with one of those words. Use the original: **"What role do dopamine receptors
   play in movement?"** — that one reached the stage in the first capture and produced the 9-word
   stub. This also scopes the defect: it can only ever have bitten lookup-style questions.
   (Original text below.) The 2026-08-24 evening capture ran on a build containing it and
   `SourceOnly` appears **0 times in 8,603 lines**, because `sourceOnlyOutcomeIfNeeded` opens with
   `guard answerIntent.isExtractiveFirst else { return nil }` and *"How does dopamine affect social
   behavior?"* classifies as narrative. **To exercise it, ask the original question:** *"What role do
   dopamine receptors play in movement?"* against a library holding the Yagishita paper — that one
   did reach the stage in the first capture. Pass is a full answer, or the console line
   `Declining to replace the answer: the extraction stage saw only N% of it`. A 9-word stub is a
   failure. Row: https://app.notion.com/p/3c649a74d54f81eaa73dfa4d627d8a5e
2. **The same failure shape reached the answer through a second path, unfixed.** In that capture the
   agentic layer rejected a replacement twice in one query:
   `Rejected replacement: would trade 12 citations for none (3953 chars -> 190 chars)`. It held, so
   the answer survived at 526 words — but something upstream is repeatedly proposing to replace a
   grounded 3,953-character answer with a ~180-character stub. Worth understanding before assuming
   the source-only guard covers the class.
3. **~~Two-column PDFs~~ — closed 2026-08-24, device-verified.** It was never a column defect: a
   non-transitive comparator in `buildReadingOrderText` used a 0.02 threshold against ~0.015 line
   spacing, so neighbouring lines ordered by left edge instead of position down the page. All eight
   pages now match Vision's transcript order. Four earlier locations were wrong and are recorded on
   the row so they are not re-tried. The non-English-detection "interleaving signal" is withdrawn —
   it was reading bibliographies.
4. **`final` r@1 stays below `rerank` r@1 at n=83 (0.442 vs 0.610 on `shipcfg-50`).** The ledger
   **rejects** `filterBySimilarity` — do not re-open that. Best account:
   `EvidenceScoringPolicyService.extractivePriorityScore` re-sorts extractive-intent queries by a
   keyword heuristic that overwrites the cross-encoder. **Cheap test, not run:** make it a tie-break.

## Exact Next Action

**Owner: ask *"What role do dopamine receptors play in movement?"* on the current build**, against a
library containing the Yagishita paper. That is the only outstanding check on `dbff15a`, it takes one
query, and it is the last v5.0 row that is fixed-but-unproven.

The same device session can settle Blocker 3 at no extra cost: re-import the Yagishita paper and
check whether a chunk containing the locomotion passage reads as continuous prose. Pre-fix text for
comparison is in that row.

Agent-side, unclaimed and in rough value order: the repeated-non-English interleaving detector
(118 of 552 chunks, free signal, nothing reads it); the second answer-replacement path in Blocker 2;
and Blocker 4's tie-break test. All need `PROCEED: IMPLEMENT`.
