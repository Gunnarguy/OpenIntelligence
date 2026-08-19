# Current State

Updated: 2026-08-19
Branch/worktree: main, clean, fully pushed.
Last verified commit: 9aed4cf

## Objective

**Get v5.0 shippable.** Two things block it and neither is a code defect; see Blockers 1 and 2.
Everything else on the board is optional for this release.

The embedding arc that ran all week is **complete and verified on hardware**. Mean pooling
(`vector r@1` 0.000 → 0.571, p = 0.0005) shipped in `3ea5cd9` after its two prerequisites, and
`EmbeddingProviderAgreementTests` passed on an iPhone 16 Pro Max. That Notion row is Completed.

## Status

Twenty-plus commits today. `0990a69..50e4f0e` is pushed; the rest are local.

Five device captures and, for the first time, **real device tests and Instruments traces**. Six
fixes are now confirmed on hardware rather than argued from source.

**Existing libraries will prompt for a rebuild on next launch.** That is the fingerprint detecting
the re-export, working as designed, and the button works.

## Completed today

Confirmed on device:

- **Sync loop.** 48 vector-store rewrites per boot → 0, in two separate captures. ~200 MB of
  pointless writes and iCloud uploads per launch, gone. (`72b5c8b`, instrumented in `a840786`)
- **Self-heal.** A library with no vectors now detects it, shows a banner, and rebuilds
  successfully. Previously silent; deleting the library was the only escape. (`116978a`)

Code-verified, not device-verified:

- **Vectors written to the wrong library** (`0350083`). `addDocument` captured its container once
  but resolved the vector store live, so switching libraries during a long import split the
  document from its index. This is the root cause beneath the self-heal symptom.
- **Embedding fingerprint** (`3b48c88`) and **mean-pooling re-export** (`3ea5cd9`). The ordering was
  mandatory: without the fingerprint the re-export corrupts every existing library undetectably.
- **Reasoning chain re-read windows 1-3 as sessions 6-8** (`e16a2d3`). ~105s of 279s, byte-identical.
- **Launch: the 43 MiB model loads on first use** (`5e81abd`), not in `ContentView.init`.
- **SourceOnly prompt budget** (`68713fd`); six UI and flow fixes (`70a15a0`, `c9be781`, `dc097cc`,
  `b87123d`, `078292d`).
- **Release scope frozen** (`9caf575`): new findings default to `Future Backlog` unless they lose
  data, break an advertised capability, or block shipping.

## Active Constraints

- **Build from a copy outside iCloud.** `rsync -a --exclude 'BenchmarkRuns/' --exclude
  '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' ./ /private/tmp/oi-src/`, then build there
  with `-derivedDataPath /private/tmp/oi-dd`. In place it hangs in NSFileCoordinator.
- **Never build, test or run anything while a benchmark measures.** Cost 20 minutes twice.
- **Core AI does not work in the simulator.** It resolves no model resource and sets
  `isModelLoadingFailed` before attempting a load, so anything touching Core AI is device-only.
- Hard-boundary file edited today under explicit approval: `WorkspaceSyncService.swift`.
- Commit to `main`; do not branch. Do not push unless asked.

## Working Set

| File | Why |
|---|---|
| `Docs/Engineering/EMBEDDING_MEAN_POOLING_REEXPORT.md` | The re-export, its four verification steps, and which remain outstanding. Read before touching embeddings. |
| `OpenIntelligenceTests/Services/Embedding/EmbeddingProviderAgreementTests.swift` | The check that closes the re-export. Device-only; skips in CI by design. |
| `Docs/Engineering/V50_PERF_AUDIT.md`, `V50_FLOW_AUDIT.md`, `V50_STAGE1_DIAGNOSIS.md` | Three read-only audits, adversarially verified, refutations recorded. |
| `scripts/run_deepthink_pilot.sh` | Executed: 31s/case, 3/3 pass. Fixtures too small to exercise the session cap. |
| `scripts/run_device_tests.sh` | Runs the suite on a wired iPhone. Works around blocker 3. Read its header before touching signing. |
| `OpenIntelligence/Services/Embedding/EmbeddingFingerprint.swift` | New. What is hashed, and what is deliberately not. |

## Verification

Run today, output read:

- `xcodebuild test`, iOS 27.0 iPhone 17 Pro simulator → **238 tests, 2 skipped, 0 failures**. The two
  skips are `EmbeddingProviderAgreementTests`, which cannot run in the simulator. They **passed on
  device** — see below.
- Deep Think pilot, 3 cases → **93s, 31s/case, 3/3 PASS**, real retrieval (3-5 chunks, conf 0.85-0.95).
- Device capture: sync writes 48 → 0, with `already current; skipping rewrite` ×143.
- Device capture: rebuild banner fired on a genuinely empty vector store; manual rebuild succeeded,
  196 chunks in 6.8s.
- `strings` on the new `main.mlirb` → `input_ids`, `attention_mask`, `embeddings`. The previous
  committed artifact had only the first and third.
- `python3 scripts/secret_scan.py` → clean. `scripts/check_icloud_conflicts.sh` → clean.

- **On device**, iPhone 16 Pro Max, wired: `EmbeddingProviderAgreementTests` → 2 passed. First
  device test run in this project's history; see blocker 3 for why.
- App Launch Instruments trace on device → first frame **0.69s**.
- Foundation Models Instruments trace on the Mac build → generation is **90%** of a Deep Think
  query (48.7s of 54.2s across 8 generations).

**Not run:** the 25-case benchmark, `build_simulator_smoke.sh`.

## Blockers / Unknowns

1. **The App Store build pins Xcode 26.5**, so no iOS 27 API can ship. Decides what 5.0 can contain.
   [Notion](https://app.notion.com/3bf49a74d54f818cb1bde1b11a0a7557)
2. **PCC entitlement unproven through Archive and TestFlight.** It is advertised, so it has to work
   through the signing path. [Notion](https://app.notion.com/39e49a74d54f81388056f384c4663876)
3. **The engine framework has a macOS install name, so no test can run on device unaided.**
   `otool -D` gives `/Library/Frameworks/OpenIntelligenceEngine.framework/...`, and the framework is
   embedded nowhere. The app does not link it so the app is fine; the test bundle does. In the
   simulator that path resolves, which is why 238 tests pass there and **zero had ever run on
   hardware**. `scripts/run_device_tests.sh` works around it with `install_name_tool`; the real fix
   is `DYLIB_INSTALL_NAME_BASE` in `project.pbxproj`, a hard-boundary file.
   [Notion](https://app.notion.com/3c149a74d54f81959f96cef9d1e28dfc)
4. **The session cap is confirmed on device and unmeasured for quality.** Device capture shows
   `Corpus exhausted after 5 distinct window(s)`, five sessions, **279.1s → 80.3s** on the same query
   and library, with a *longer* answer (512 words against 450). What is still unmeasured is whether
   answer quality moved, which needs the 40-document paired run at `e16a2d3` and `e16a2d3~1`
   compared with `compare_benchmark_runs.py`.
5. **The truncation fix has never executed.** Three device runs all took the reasoning-chain branch
   because retrieval was excellent. `executeDirectSynthesis` is reached only at moderate or low
   confidence, so exercising it needs a query the library covers *poorly*.
6. **Retrieval is ~21% reproducible.** Caps confidence in any single benchmark run, and is why
   paired comparison plus the sign test is the only trustworthy readout.
8. **Timing from any benchmark run containing a timeout is suspect.** Until `9aed4cf`, a timed-out
   case left the app resident holding the shared library, so later cases measured how long they
   waited rather than what they cost. This includes the 925s/case figure that was briefly read as a
   performance regression and withdrawn for an unrelated reason. Re-measure before trusting any
   pre-`9aed4cf` timing. [Notion](https://app.notion.com/3c149a74d54f817bb929ec79362f3c0f)
7. **The `Hang detected: N s` lines are not launch cost. Corrected 2026-08-18.**
   Measured with the App Launch Instruments template on the device: **first frame at 0.69s**, of
   which 0.547s is Initial Frame Rendering and everything before it totals 0.145s. The 2.94-4.50s
   hangs in console captures happen *after* the app is interactive, so anyone chasing them should
   look at post-launch work, not startup. `5e81abd` is confirmed working by a different signal:
   `Loaded EmbeddingModel` appears **zero times** in a session where nothing embedded.

## Device-verified on 2026-08-18, after the tests could finally run there

- **Mean-pooling re-export.** `EmbeddingProviderAgreementTests` green on an iPhone 16 Pro Max: Core
  AI and Core ML agree at cosine > 0.99, and two unrelated short texts stay below 0.95 apart, which
  is the attention mask specifically. Notion row **Completed**.
- **Session cap.** 279.1s → 80.3s, five sessions, zero repeats, longer answer.
- **Lazy model load.** `Loaded EmbeddingModel` absent from a session that never embedded.
- **Sync short-circuit.** `already current; skipping rewrite` ×70, zero writes.
- **Launch.** 0.69s to first frame, measured, not inferred.

## Exact Next Action

**Re-run the paired benchmark. The harness defect that ruined the last attempt is fixed in `9aed4cf`
and has never been exercised.**

```bash
python3 scripts/run_quality_matrix.py \
  --app /private/tmp/oi-mac-40/Build/Products/Debug/OpenIntelligence.app \
  --manifest Benchmarks/ResearchFixtures/qasper_external_v1/manifest.json \
  --pcc deny --pool-limit 10 --reset-shared-library --timeout 1800 \
  --sampling topk --seed 42 --temperature 0.7 \
  --modes deep-think,standard --limit 8 --output-dir BenchmarkRuns/paired-retry
```

Rebuild the macOS app first if the tree moved. `pool_limit 10` is not optional: it is what `tokfix`
and `coreml-provider` used, and the standard-mode baselines of 9/25 and 13/25 are only comparable at
that value.

**Success looks like the run completing.** If a case times out, the log should now say
`reaped N orphaned app process(es)` and the *next* case should still finish in ~250s. If later cases
still time out after a reap, the leak was not the cause and the ledger entry needs correcting.

Deep Think has no quality baseline at all. That is what this produces.

## Ready to close, needs only a decision

Two rows are confirmed on device and still sit `In Progress`:

- [Self-heal](https://app.notion.com/3c049a74d54f81fd9255edc739959d36) — banner fired on a genuinely
  empty vector store, manual rebuild succeeded, 196 chunks in 6.8s. The blocked-rebuild path was
  never exercised, so closing it is a judgement call about whether the visible symptom is enough.
- [Embedding fingerprint](https://app.notion.com/3bf49a74d54f812597ffd48a165a139f) — fired after the
  re-export exactly as designed, and the rebuild worked.

## Cheap and unblocked, if the benchmark is running

Three rows need no measurement and no device:

- [iWork import](https://app.notion.com/3b749a74d54f81569b7eda2df6a887bc) — support is zero, not
  limited. Internal docs are already correct; only outward claims and one error string are wrong.
  Run `oi-claim-audit` first. Note the route violation recorded on the row.
- [Eight agentic tools](https://app.notion.com/3b449a74d54f818486feee1dada5554b) — it is six, not
  eight, and the omissions are deliberate and documented. The real defect is `disableTools`, and the
  highest-value line in that row is a warning before `FoundationModelToolRegistry.swift:422`.
- [FTS5 bm25](https://app.notion.com/3b149a74d54f81248feaf48022482a63) — the weighting half was
  already done on 2026-08-06. Only trigram remains, it needs the `SQLiteFullTextService.swift`
  schema named in an approval, and it is unmeasurable at 21% reproducibility.
