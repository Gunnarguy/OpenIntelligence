# Current State

Updated: 2026-08-24
Branch/worktree: main, **not pushed** — check `git status` against `origin/main` before assuming this is current.
Cross-tool handoff (if Claude access runs out): `HANDOFF.md` at repo root (kept current less often than this file).
Last verified commit: 9f10a76

## Objective

**Get v5.0 shippable.** PCC has never shipped (Xcode Cloud builds with Xcode 26.6; no Xcode 27 RC
exists yet), so v5.0 is a correctness release, not a feature drop. Scope was frozen 2026-08-21 to 11
Notion rows passing one of three tests (loses/corrupts data, breaks an advertised capability, or
blocks shipping). **Notion is authoritative for the row list** — use the `notion-roadmap` skill, do
not re-derive it here.

## Status

**The device verification pass ran, and it found the cause of the 0-chunk phantom that three
sessions had misattributed.** The app deletes a just-imported document's vectors itself, in
`WorkspaceSyncService`, and the deletion is unlogged. `0350083` is exonerated. Separately, the
"garbage answer" has a definite proximate cause that is not retrieval. App Store Connect is
unblocked and the 5.0 listing now carries 5.0's own release notes; it had been carrying 4.9's.

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
  the 4.9 text. New text is 3,996 characters against Apple's 4,000 limit, pushed with `deliver`
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
| `fastlane/metadata/en-US/release_notes.txt` | What the App Store shows for 5.0. 3,996 of 4,000 characters — anything added needs something removed. |
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

**Not run:** the fix for any of Blockers 1-3; the simulator test suite (`build_simulator_smoke.sh`
builds only, it does not run tests); anything on device since 2026-08-19; the rerank-stage
`passage_present` scoring pass (data exists, scorer does not).

## Blockers / Unknowns

1. **The app deletes a just-imported document's vectors itself. Data loss, reproducible, unfixed.**
   `RAGService` persists vectors (log 6675) before it saves the document record (log 6908). In that
   window `WorkspaceSyncService.synchronizeVectorStore` builds an empty `allowedDocumentIds`,
   filters every chunk out, and falls through `guard allowedDocumentIds.isEmpty else { ... return }`
   (`WorkspaceSyncService.swift:2399`) into `removeVectorStoreArtifacts` (`:2436`, silent helper at
   `:2719`). It deleted the store twice, at 6685 and 6881. **A library switch is not required** — it
   widens the window. `0350083` worked; the vectors were addressed correctly and then destroyed.
   Fix is ~5 lines: refuse to delete when the chunks just read are non-zero.
   **`WorkspaceSyncService.swift` is hard-boundary — needs the owner to name it in an approval.**
   Row: https://app.notion.com/p/3c649a74d54f815b8f60e06555ce97bf
2. **Source-only verification destroys the answer it verifies.** A 472-word answer, accepted by
   Self-RAG at 80% confidence (log 10975), was cut to 50 of 3,415 characters by a 1,421-token prompt
   budget and delivered as a 9-word fallback (11253). No inference ran after the trim. Generation is
   allowed 1,500 tokens; the stage gating it gets 1,421 for evidence *plus* answer, so the two
   budgets are mutually unsatisfiable and this fires on every long answer. Introduced by the fix for
   the 2026-08-18 context overflow. `SourceOnlyAnswerService.swift:289`, gate at
   `RAGService.swift:16290`. Row: https://app.notion.com/p/3c649a74d54f81eaa73dfa4d627d8a5e
3. **Two-column PDFs: attribution now exists, and it is worse than "can reach".** `LayoutAwareExtractor`
   detected 2 columns on 6 of 8 pages and its output was discarded for PDFKit's `page.string`.
   Evidence chunks are left and right columns spliced line-for-line. 118 of 552 chunks in a single
   English paper were detected as non-English — a free interleaving signal nothing reads. Existing
   row updated in place: https://app.notion.com/p/3bf49a74d54f81fcb146ef3f489be576
4. **`final` r@1 stays below `rerank` r@1 at n=83 (0.442 vs 0.610 on `shipcfg-50`).** The ledger
   **rejects** `filterBySimilarity` — do not re-open that. Best account:
   `EvidenceScoringPolicyService.extractivePriorityScore` re-sorts extractive-intent queries by a
   keyword heuristic that overwrites the cross-encoder. Rank-1 loss 27.0% where it fires vs 15.2%
   where it does not. **Cheap test, not run:** make it a tie-break, not a full re-sort.

## Exact Next Action

**Fix Blocker 1.** In `WorkspaceSyncService.synchronizeVectorStore`, before the
`removeVectorStoreArtifacts` calls at `WorkspaceSyncService.swift:2436-2442`, guard on the chunks
already loaded a few lines above:

```swift
let loadedChunkCount = localChunks.count + sharedChunks.count
guard loadedChunkCount == 0 else {
    Log.error("[WorkspaceSync] Container \(container.id) has no documents in metadata but its vector store holds \(loadedChunkCount) chunk(s); refusing to delete. An import may still be writing.")
    return
}
```

Add a log line to `removeVectorStoreArtifacts` in the same change — its silence is why this took
three sessions. **Both edits are in a hard-boundary file: get the owner to name
`WorkspaceSyncService.swift` in an approval first.** Verify by re-running the owner's own protocol:
import, switch libraries mid-import, return and query. Passes if the document answers and the
console shows the refusing-to-delete line.
