# Current State

Updated: 2026-08-18
Branch/worktree: main (20 commits ahead of `origin/main`, nothing pushed)
Last verified commit: 9ebe759

## Objective

**Get v5.0 shippable.** Two things block it and neither is a code defect; see Blockers 1 and 2.
Everything else on the board is optional for this release.

The embedding arc that ran all week is **complete in code and unverified in behaviour**. The fix
with the measured payoff — mean pooling, `vector r@1` 0.000 → 0.571, p = 0.0005 — shipped today in
`3ea5cd9`, after its two prerequisites.

## Status

Twenty commits today, tree clean, **nothing pushed**. `origin/main` is still at `0990a69`.

Four device captures drove most of it. Two fixes are confirmed on hardware; the rest are
suite-verified only, and this suite covers none of retrieval, routing, sync or the agentic path.

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
| `OpenIntelligence/Services/Embedding/EmbeddingFingerprint.swift` | New. What is hashed, and what is deliberately not. |

## Verification

Run today, output read:

- `xcodebuild test`, iOS 27.0 iPhone 17 Pro simulator → **238 tests, 2 skipped, 0 failures**. The two
  skips are `EmbeddingProviderAgreementTests`, which cannot run without hardware.
- Deep Think pilot, 3 cases → **93s, 31s/case, 3/3 PASS**, real retrieval (3-5 chunks, conf 0.85-0.95).
- Device capture: sync writes 48 → 0, with `already current; skipping rewrite` ×143.
- Device capture: rebuild banner fired on a genuinely empty vector store; manual rebuild succeeded,
  196 chunks in 6.8s.
- `strings` on the new `main.mlirb` → `input_ids`, `attention_mask`, `embeddings`. The previous
  committed artifact had only the first and third.
- `python3 scripts/secret_scan.py` → clean. `scripts/check_icloud_conflicts.sh` → clean.

**Not run:** any 25-case benchmark, any device test of today's code, `build_simulator_smoke.sh`.

## Blockers / Unknowns

1. **The App Store build pins Xcode 26.5**, so no iOS 27 API can ship. Decides what 5.0 can contain.
   [Notion](https://app.notion.com/3bf49a74d54f818cb1bde1b11a0a7557)
2. **PCC entitlement unproven through Archive and TestFlight.** It is advertised, so it has to work
   through the signing path. [Notion](https://app.notion.com/39e49a74d54f81388056f384c4663876)
3. **The re-exported vectors are unverified.** Graph shape is proven; the numbers are not. Closes
   with `EmbeddingProviderAgreementTests` on device, or a benchmark where Core AI `vector r@1`
   **matches** `BenchmarkRuns/coreml-provider` rather than merely beating CLS.
4. **The session cap is unmeasured.** Pilot fixtures retrieve 3-5 chunks, making 1-2 windows; the
   bug needed 6+. Measuring it needs `--pool-limit 40`, roughly two hours, paired at `e16a2d3` and
   `e16a2d3~1` and compared with `compare_benchmark_runs.py`.
5. **The truncation fix has never executed.** Three device runs all took the reasoning-chain branch
   because retrieval was excellent. `executeDirectSynthesis` is reached only at moderate or low
   confidence, so exercising it needs a query the library covers *poorly*.
6. **Retrieval is ~21% reproducible.** Caps confidence in any single benchmark run, and is why
   paired comparison plus the sign test is the only trustworthy readout.
7. **Launch is slower than at the start of the day**: 2.94s → 3.75s → 4.31s → 4.06s across captures.
   `5e81abd` should improve it and has not been measured.

## Exact Next Action

**Install the current tree on device and launch it.** One session answers three open questions and
needs no benchmark:

1. Does the rebuild banner appear for existing libraries? That is the fingerprint firing after the
   re-export — expected and correct, not a fault.
2. Does the launch hang drop below 4.06s, and is `Loaded EmbeddingModel.mlmodelc` absent until
   something first embeds? That closes blocker 7.
3. Then run the device-only embedding test, which closes blocker 3:

```bash
xcodebuild test -scheme OpenIntelligence \
  -destination 'platform=iOS,id=<device-udid>' \
  -only-testing:OpenIntelligenceTests/EmbeddingProviderAgreementTests
```

`xcrun devicectl list devices` gives the UDID. A wireless attempt on 2026-08-18 failed with
`Failed to allocate RSD device` during `enablePersonalizedDDI`; use a USB cable and unlock the phone
first.

After that, the 40-document paired benchmark is the overnight job for blocker 4.
