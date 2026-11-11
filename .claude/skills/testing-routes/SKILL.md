---
name: testing-routes
description: Where each OpenIntelligence test, benchmark or answer-quality run can actually run (the Mac's iOS Simulator, a native Mac test, Xcode Cloud simulators and Macs, the owner's iPhone over devicectl or TestFlight), which of them have Apple's language model, what each costs the owner (his Mac's CPU, his phone, Xcode Cloud compute hours), and the commands. Use before starting any test or benchmark run longer than a few minutes, before saying a test "can't run" somewhere or "needs the phone", before spending Xcode Cloud hours, and when the owner asks "can you run this in the cloud", "can you do it without my phone", "do my Xcode Cloud hours count", "why is my CPU at 100%", or "how can we put this to rest".
---

# Testing routes

The owner's question, 2026-11-11: run the benchmarks without tying up his Mac (he games on it) or his iPhone,
using the 100 Xcode Cloud compute hours he pays for. This file is the settled answer. Re-check a row when Xcode,
macOS or iOS changes, and re-date it.

## The table

| Route | Apple's model | Costs him | Use for |
|---|---|---|---|
| iOS 27 Simulator on his Mac | **Yes**, after about a minute of `modelNotReady` [measured 2026-10, iOS 27.0]. The app turns its own model off there (`AppleFoundationLLMService.swift:110`, `LLMService.swift:380` and the `RAGService*` guards); tests that bring their own model (Evaluations, `ModelEnvironmentProbeTests`) are not affected | His Mac's CPU and about 3 GB of memory for the whole run | Answer-quality runs (all modes), UI robots, the demo copy |
| Native macOS tests on his Mac | Yes | His CPU, **and his real library**: the hosted suite imports and deletes in it (auto memory `mac-unit-tests-run-in-his-real-library`) | Single library-free classes only |
| Xcode Cloud, iOS simulators | **No.** The framework reports `available`, then every `respond()` fails at once with `ModelManagerError 1019`, and the runner's `intelligencetasksd` daemon crashed (SIGTRAP) during the run [measured, run 496, commit ef305172, 2026-11-11: `[ModelProbe] place=xcode-cloud model=iPhone16,1 availability=available waited=0s respond=error`; run 495 failed the same way] | Compute hours only; his Mac is untouched | The whole unit suite (about 1,706 tests a device) on three devices; anything that needs no model |
| Xcode Cloud, cloud Mac | **No.** The runners are virtual machines and Apple DTS: Apple Intelligence "isn't available on macOS running on a VM" [documented, developer forums, read 2026-11-11] | Compute hours | Mac unit tests that need no model and no real library |
| His iPhone, `devicectl` launch | Yes, and Private Cloud Compute | The phone must stay unlocked with the app in front for the run | One-off device truth (speed, memory, thermal) |
| His iPhone, TestFlight build | Yes, and PCC; Apple's named route for testing PCC | The phone, while it runs | Release candidates |

**Recommended route for the answer benchmark** (Standard, Deep Think, Maximum): the iOS 27 Simulator on his Mac,
started only when he says he is not gaming (overnight is best). Xcode Cloud cannot generate (run 496), so it carries
the unit suite and every model-free check, which is most of the 1,706 tests.

## Xcode Cloud: what the hours buy

- Plan: 100 compute hours a month ($49.99) on top of the 25 the Developer Program includes [documented,
  developer.apple.com/xcode-cloud, read 2026-11-11].
- Hours are the **sum of every parallel action**, not wall time [documented, "Reviewing Xcode Cloud usage data"].
  Each test destination runs in parallel after one build-for-testing, so three simulators cost about three times
  the test time [inferred from the two statements].
- Measured: runs 489 to 495 of `Tests (manual)` took 26 to 30 minutes of wall time for the iOS action (three
  simulators) [measured 2026-11-11 from `/v1/ciBuildRuns/{id}/actions` dates], so a full run is roughly 1.5 compute
  hours, about 60 full runs a month. A run that dies in the first minute (493, 494) costs almost nothing.
- Workflow `Tests (manual)` (id in `BenchmarkRuns/2026-11-07-xcode-cloud/tests_workflow_id`, local): Test - iOS on
  iPhone 15 Pro, iPhone 17 Pro Max and iPad mini (A17 Pro), iOS 27.0, scheme settings; manual or API start only, so
  release archives (`Default`) are untouched. Ask before changing it.

Commands, all through `zsh -ic` because the App Store Connect key's variables come from `~/.zshrc` (never print
them), run from `BenchmarkRuns/2026-11-07-xcode-cloud/` (gitignored, local):

```bash
zsh -ic 'python3 start.py'        # start a run on main; writes run_id
```

```bash
zsh -ic 'python3 watch.py'        # waits (polls every 3 min), then prints per-device pass/fail and failures
```

```bash
zsh -ic 'python3 dl.py run_id "Test - iOS" /private/tmp/oi-xc/logs.zip'   # the log bundle, for printed lines
```

Cloud traps:

- Only pushed commits run. Every commit here carries `[ci skip]`; that keeps `Default` from building and does not
  stop an API start of `Tests (manual)`.
- Custom environment variables can be set only in the workflow's Environment section (Xcode or the App Store
  Connect website) or in a committed test plan configuration; the API's workflow schema has no field for them
  [documented, read 2026-11-11]. They reach tests with the `TEST_RUNNER_` prefix, which `xcodebuild` strips.
- Tests run as `test-without-building`, with **no source checkout** [documented]. A test that reads fixtures
  through `#filePath` (`AnswerQualityEvaluationTests`, the golden harnesses) cannot find them in the cloud; its
  fixtures have to be in the test bundle's resources first.
- No physical devices: destinations are `SIMULATOR` and `MAC` only.
- Failures in run 496 (ef305172), on all three devices unless noted: `SourceLookupTests.testATablePassageIsFoundByItsCells`,
  `SourceLookupImportTests.testEveryKindOfFileFindsItsOwnPassages`, `StructuredKeywordOrderTests.testTheFirstTwentyCodesAreKeptInTheOrderTheyAppear`
  (returns `[]`), `TourTipTests.testEveryTipHasTextAndASymbol` (an X-Ray tip is 286 characters, limit 220), and
  `WatchedFolderPathTests.testAFileThatCannotImportIsReportedOnceAndNotRetried` on the iPad only. Not yet diagnosed;
  a local "Simulator 240 run" covers only the classes it names, not these. Compare a new red run with 496 before
  calling anything a regression.
- A run's `.xcresult` is about 60 MB; the log bundle (about 0.5 MB) holds every printed line, so download that one.

## His iPhone without tapping

`xcrun devicectl device process launch --terminate-existing --environment-variables '{"OI_...":"..."}' --console
--device <id> Gunndamental.OpenIntelligence` starts the app with settings and streams its output; `device copy from
--domain-type appDataContainer --domain-identifier <bundle id>` copies results out [measured, `devicectl --help`,
Xcode 27.0, 2026-11-11]. The phone must be unlocked. A test or benchmark launched this way runs in **his real app
container and library**, so a benchmark there needs a separate bundle-id copy ("Bench"), which needs a signing
change in hard-boundary files: ask first. `xcodebuild test` over Wi-Fi is unverified.

## Traps on his Mac

- He games on it. Before any local `xcodebuild`, Simulator boot or benchmark, check he is not playing; a run that
  pushes the CPU to 100% while he plays is the failure this skill exists to prevent (2026-11-11). Timers run about
  14 times slow with a game in front (`MACHINE-MAP.md`).
- One `xcodebuild` at a time; shut the simulator down when done; give each run its own simulator.
- A freshly erased simulator reports `modelNotReady` for about a minute: wait with a real `respond()`, not the
  availability flag (auto memory `fm-availability-flag-lies`).

## Settling a "can it run there" question

Write a one-test probe that always passes and prints what it found, push it, run it where you are unsure, and read
the printed line. `OpenIntelligenceTests/Services/AIPlatform/ModelEnvironmentProbeTests.swift` does this for the
model: it prints `[ModelProbe] place=... availability=... waited=...s respond=...`.
