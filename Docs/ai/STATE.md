# Current State

Updated: 2026-08-24
Branch/worktree: main, clean, **not pushed** — check `git status` against `origin/main` before assuming this is current.
Cross-tool handoff (if Claude access runs out): `HANDOFF.md` at repo root (kept current less often than this file).
Last verified commit: 5f30a37

## Objective

**Get v5.0 shippable.** PCC has never shipped (Xcode Cloud builds with Xcode 26.6; no Xcode 27 RC
exists yet), so v5.0 is a correctness release, not a feature drop. Scope was frozen 2026-08-21 to 11
Notion rows passing one of three tests (loses/corrupts data, breaks an advertised capability, or
blocks shipping): 3 data-corruption fixes (committed, **none verified on device**), 2 broken
importers (iWork, two-column PDFs), 3 infra rows, 3 orchestration judgment calls. **Notion is
authoritative for the row list** — use the `notion-roadmap` skill, do not re-derive it here.

## Status

**Tonight's finding closes a measurement-trust problem that has undermined every retrieval A/B in
this project for weeks — this is the headline.** Every other open item below is unchanged by it.

## Completed this session (2026-08-23 into 08-24)

- **`058a27b`** — `DebugRAGValidationHarness` now emits `RERANK CHUNK TEXT` (rerank-stage chunk
  text, same format as the existing final-stage block). Debug-only, smoke-verified before the long
  runs: 90 chunks captured at rerank vs. 7 at final on the smoke case.
- **`5f30a37`** — overnight run, ~8h14m unattended (`caffeinate` + detached `nohup`), written up in
  full in `BenchmarkRuns/LEDGER.md` (read that for the complete analysis; this is the summary):
  - **`greedy-25-a`/`greedy-25-b`**, a *deliberately designed* A/A pair (every prior reproducibility
    finding here was found by accident, not built): vector/lexical/fusion stages came back
    **bit-identical**, and accuracy matched exactly, **9/24 both times** — against a previously
    measured ±1-case noise floor under `topk` sampling. Two small non-sampler jitter sources remain
    (at `boosted` and between `rerank`/`final`) but neither moved accuracy. **Conclusion: `greedy`
    sampling makes this benchmark's accuracy trustworthy for A/B comparison; `topk` measurably was
    not.** One pair, not proof against every future case, but the cleanest evidence produced here.
  - **`greedy-83-1` vs. `shipcfg-50`** (same commit modulo this session's own additive-only harness
    diff — verified with `git diff --stat`, so this is a clean single-variable comparison): **39/83
    (47.0%) vs. 32/83 (38.6%)**, paired sign test on `score.correct`, 8 wrong→right vs. 1 right→wrong,
    **p = 0.039**. Unplanned finding, flagged as such in the ledger — this was a reproducibility run,
    not a sampler-selection run, and does **not** mean the shipping default should change without its
    own deliberate measurement (greedy has failure modes, e.g. repetition, that extractive QASPER
    questions may not surface).
  - Every report from all four runs now carries `RERANK CHUNK TEXT`, which unblocks but does not yet
    answer "never retrieved vs. retrieved-then-cut-by-budget" for the cases where the gold span never
    reaches the model — no scoring pass against that block exists yet (`score.passage_present` is
    still final-stage only in `results.jsonl`).
- **ASC metadata push retried with a rotated API key — still fails, same error.** See Blocker 1.

## Active Constraints

- **Build from a copy outside iCloud.** `rsync -a --exclude 'BenchmarkRuns/' --exclude
  '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' ./ /private/tmp/oi-src/`, then build with
  `-derivedDataPath` under `/private/tmp`. In place it hangs in NSFileCoordinator.
- **Nothing else builds, tests or runs while a benchmark measures.** Never `pkill` on the app path —
  match `Contents/MacOS/OpenIntelligence`, not `--app` (matches the harness's own command line too).
- **Core AI does not work in the simulator** — anything touching embeddings is device-only.
- **The benchmark ingests into the real library**, protected by snapshot. Never delete a
  `BenchmarkRuns/*` run directory — it's gitignored, so deletion is permanent and unrecoverable.
- Commit to `main`; do not branch. Do not push unless asked.

## Working Set

| File | Why |
|---|---|
| `BenchmarkRuns/LEDGER.md` | Full narrative of every run, including this session's. Read before trusting any figure. |
| `BenchmarkRuns/PROGRESSION.md` | Table index; `shipcfg-50` and this session's 3 runs are the newest 4 rows. |
| `OpenIntelligence/App/DebugRAGValidationHarness.swift` | `RERANK CHUNK TEXT` lives here; the file to extend for a rerank-stage `passage_present` scoring pass. |
| `~/.zshrc` (outside repo) | ASC credentials, lines ~85-87. Rotated key `5UNPFIPXPPRC` wired in but still failing — see Blocker 1. |

## Verification

Command → result, this session only:

- Smoke test, 1 case: `RERANK CHUNK TEXT` present, 90 chunks captured vs. 7 at final. **PASS** case.
- `greedy-25-a`: 25/25 complete, exit 0. `greedy-25-b`: 25/25 complete, exit 0.
  `scripts/compare_benchmark_runs.py BenchmarkRuns/greedy-25-a BenchmarkRuns/greedy-25-b` → control
  (lexical) identical case-for-case, runs comparable; vector 0 better/0 worse/24 unchanged.
- `greedy-83-1`: 83/83 complete, exit 0, 321 min wall.
- `LC_ALL=en_US.UTF-8 LANG=en_US.UTF-8 bundle exec fastlane push_metadata version:5.0` (rotated key)
  → **exit code 1**, `Authentication credentials are missing or invalid` — identical error text to
  the pre-rotation attempt.

**Not run:** the rerank-stage `passage_present` scoring pass (data exists, scorer doesn't yet); the
device verification pass; anything on device since 2026-08-19.

## Blockers / Unknowns

1. **App Store Connect metadata push still fails after key rotation — new diagnostic information.**
   Original key `JT97AQ3U4U` failed with `Authentication credentials are missing or invalid`,
   hypothesized revoked/deleted. A new key (`5UNPFIPXPPRC`) was created, moved to
   `~/.appstoreconnect/private_keys/`, wired into `~/.zshrc`, and the exact same `push_metadata`
   lane was retried — **identical error, same text.** Clock skew was already ruled out
   (`sntp -sS time.apple.com`, ~13ms). Two keys failing identically points away from "this specific
   key is revoked" and toward something systemic: the new key's **role/permissions in App Store
   Connect** (metadata push likely needs App Manager, not a narrower role), the Issuer ID being
   stale, or a `deliver`/fastlane-side issue unrelated to the key itself. Verify by checking the new
   key's assigned role in App Store Connect → Users and Access → Integrations → App Store Connect
   API, before generating a third key. This blocks closing the iWork-de-advertising Notion row,
   whose stated closing condition is exactly this push succeeding.
2. **Three vector-store loss fixes, the detector-repair fix and the ingestion deadlock fix have
   never run on the device.** Owner action: build `main` to the iPhone, run delete → ingest → query
   → relaunch, confirm no library shows documents with 0 chunks. Closes or reopens the three
   data-corruption rows — the ones that made the app lose a document.
3. **Two-column PDF fix needs symptom attribution on device**, not benchmark evidence — carried
   open on purpose per the row's own instruction. Hypothesis on record, not established: drifted
   bounds smeared X clusters, column detection failed, Y-only branch interleaved.
4. **`final` r@1 stays below `rerank` r@1 at n=83 (0.442 vs. 0.610 on `shipcfg-50`).** Ledger's
   `shipcfg-50` writeup explicitly **rejects** `filterBySimilarity` as the cause (lost cases had
   *fewer* filtered chunks, not more) — do not re-open that hypothesis. Current best account:
   `EvidenceScoringPolicyService.extractivePriorityScore` re-sorts extractive-intent queries by a
   keyword heuristic that overwrites the cross-encoder's order; rank-1 loss is 27.0% where that
   re-sort fires vs. 15.2% where it doesn't. Association, not proven sufficient cause — proposed
   cheap test (make it a tie-break/bounded boost rather than a full re-sort) not yet run.

## Exact Next Action

**Owner: build `main` to the iPhone and run delete → ingest → query → relaunch on a real library.**
This is the longest-outstanding item blocking the highest-stakes rows (data corruption, not
cosmetic). Blocker 1 (ASC push) is next in priority but needs an App Store Connect UI check first,
not another CLI retry.
