# Runbook

Every command below is labelled. **Verified** means it was run in this repository and its output
read, with the date. **Recorded** means it comes from repository evidence but has not been re-run
recently. Do not promote a recorded command to verified without running it.

## Before anything else: the iCloud check

The repository lives in iCloud-synced `~/Documents`. When a build fails in a way that makes no sense
(duplicate symbols, invalid redeclaration, a type declared twice, a codesign "resource fork, Finder
information, or similar detritus not allowed" error, or git reporting a broken ref name), run this
**before** debugging code:

```bash
scripts/check_icloud_conflicts.sh --fix
```

*Recorded.* Read the script's header for what it repairs. `--quiet` reports only on damage and is
what `build_simulator_smoke.sh` calls; plain invocation reports and exits 1 if damaged.

`.git` is a file containing `gitdir: .git.nosync`. That is deliberate. Do not convert it back.

## Setup, from a fresh clone

*Recorded, not run from a clean machine.* The steps that are not obvious:

1. **Clone outside `~/Documents`.** The existing checkout is inside it, which is the source of most
   failures on this list, and `DECISIONS.md` records that as a live problem rather than a choice.
   A new clone should not repeat it.
2. **Xcode 27.** The existing machine has it at `/Applications/Xcode-beta.app`. The iOS deployment
   target is 26.0 and the tests need an iOS 27 simulator runtime, which is a separate download in
   Xcode's Platforms pane.
3. **SwiftPM resolves on first build.** The only dependency is vendored in-tree at
   `OpenIntelligence/swift-transformers`, so there is no network fetch to fail.
4. **Fastlane needs Ruby.** `Gemfile` and `Gemfile.lock` are tracked; `bundle install` if you are
   doing release work. Credentials come from `.env.appstore`, which is not in the repository.

## Route the task

```bash
python3 .codex/skills/route-openintelligence-work/scripts/repoos_router.py preflight --task "<request>" --path <path>
```

*Verified 2026-08-07.* Prints the matched route, risk, approval mode, allowed and forbidden edit
paths, required tests, and required doc updates. All binding.

It reports the release as three facts, not one: `version` (what new work targets), `state`
(`shipped` or `in_development`), and `last_shipped`. When `[Unreleased]` holds entries the state is
`in_development` and `version` comes from the `<!-- next-version: X -->` marker beside the
`[Unreleased]` heading in `CHANGELOG.md`. Move that marker when the target changes. If it reports
`unreleased`, the next version has not been named: name it rather than guessing.

## Build

```bash
bash scripts/build_simulator_smoke.sh
```

*Recorded.* The reliable path, and what the RepoOS routes require before ending a code-modifying
turn. It runs the iCloud conflict check first, builds the `OpenIntelligence` scheme against
`platform=iOS Simulator,name=iPhone 17 Pro`, writes DerivedData to `.simulator-smoke.nosync/`, then
copies the `.app` to `/tmp`, strips extended attributes with `xattr -cr`, ad-hoc signs it there, and
copies it back. Override the destination with `OPENINTELLIGENCE_SIMULATOR_DESTINATION`.

Full log lands in `.simulator-smoke.nosync/xcodebuild.log`.

## Run the app

`build_simulator_smoke.sh` builds, strips, and codesigns, and then stops. It never installs or
launches, so it proves the tree compiles and signs and nothing about runtime behavior.

**Xcode is the supported path:** open `OpenIntelligence.xcodeproj`, pick an iOS 27 simulator, Run.

To drive it headlessly from the built product, *unverified*, after a smoke build:

```bash
xcrun simctl install booted .simulator-smoke.nosync/DerivedData/Build/Products/Debug-iphonesimulator/OpenIntelligence.app
```

Foundation Models needs a real device with Apple Intelligence, so on-device generation and Private
Cloud Compute routing cannot be exercised in the simulator at all. Anything claiming to verify
routing behavior from a simulator run is wrong.

## Test

Scheme `OpenIntelligence`, test target `OpenIntelligenceTests`, Xcode 27 at
`/Applications/Xcode-beta.app`.

```bash
xcodebuild test -scheme OpenIntelligence -destination "platform=iOS Simulator,id=<UDID>" -derivedDataPath /private/tmp/oi-build
```

*Recorded.* Two things are required and neither is the default:

1. **Target an iOS 27 simulator explicitly.** The default and first-listed simulators are iOS 18.x
   and fail destination resolution against the iOS 26.0 deployment target. A previously working
   UDID was `8FA2B3CE-5EB0-4339-8629-F40684EDCE2D` (iPhone 17 Pro, iOS 27.0). UDIDs change when
   runtimes are reinstalled, so query for a current one:

   ```bash
   DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun simctl list devices available
   ```

   Plain `xcrun simctl` uses the wrong Xcode and hides the iOS 27 runtime.

2. **Keep DerivedData outside `~/Documents`,** or `codesign` fails on the swift-tokenizers and
   swift-transformers bundles.

Single suites:

```bash
xcodebuild test -scheme OpenIntelligence -only-testing:OpenIntelligenceTests/HybridSearchServiceTests -derivedDataPath /private/tmp/oi-build -destination "platform=iOS Simulator,id=<UDID>"
```

## Retrieval benchmark

The 20-case quality matrix runs the **macOS** app headlessly, once per case, against fixtures in
`Benchmarks/ResearchFixtures/tiny_research_suite/`. Two things about it are not obvious and cost a
full session each when rediscovered.

**1. The benchmark app must be built with code signing disabled.** The normal macOS Debug build is
sandboxed — `OpenIntelligence.entitlements` has carried `com.apple.security.app-sandbox` since
`98dfa14` on 2026-07-14, with only `files.user-selected.read-only`. A sandboxed app cannot write to
the per-case storage directory the harness creates under `$TMPDIR`, so ingestion never lands, the run
falls through to `No documents loaded - using direct LLM chat mode`, and every case answers from
model priors with `Chunks: 0`. The harness reports this as
`no answer produced (agentic path did not complete headlessly)`, which points away from the cause.
The real signal is in each report: `Failed to persist ingestion queue: You don't have permission to
save the file "ingestion_queue.json"` (curly apostrophe, so grep for `have permission to save`).

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -scheme OpenIntelligence -destination "platform=macOS" -configuration Debug -derivedDataPath /private/tmp/oi-mac-nosbx -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

*Recorded 2026-08-09.* These are the same flags `scripts/build_simulator_smoke.sh` already uses, and
they do not touch the hard-boundary `.entitlements` file. Confirm the result before benchmarking:
`codesign -d --entitlements - <app>` must print no entitlements.

**Corrected 2026-08-12.** This paragraph used to say an agent could not run the command because the
permission classifier refuses anything altering code signing. That is wrong on both counts: the
command runs fine, and what actually blocks it is the repository's iCloud location, not signing. See
the next item.

**1b. `xcodebuild` deadlocks on this repository's path, and the fix is to build from a copy.**
Anything that opens the project (`build`, `test`, even `-showBuildSettings`) can hang forever at the
"Command line invocation" header, spawning no `XCBBuildService` and creating no DerivedData, while
`xcodebuild -version` and `-list` still work. Sampling the hung process shows the blocked thread in
`-[DVTFilePath performCoordinatedReadRecursively:]` under `Xcode3Project initWithFilePath:`, parked
in `semaphore_wait_trap`. That is **NSFileCoordinator**: a coordinated recursive read against
iCloud-synced `~/Documents` never returns, even though plain `ls -R` on the same path is instant and
no file is dataless.

```bash
rsync -a --exclude 'BenchmarkRuns/' --exclude '.simulator-smoke.nosync/' --exclude 'Benchmarks/run/' ./ /private/tmp/oi-src/
```

Then run the build above from `/private/tmp/oi-src`. Verified 2026-08-12 by direct A/B: the same
`-showBuildSettings` invocation hangs indefinitely in `~/Documents/GitHub/OpenIntelligence` and
returns instantly from the copy. Keep `.git.nosync` in the copy so build phases that shell out to
git resolve the right commit.

**Diagnose by sampling, not by guessing.** `sample <pid> 3 -mayDie` answered this in one shot.
Clearing `com.apple.DeveloperTools`, quitting Xcode, `DVTEnableCoreDevice=disabled`,
`-destination-timeout`, `-target` instead of `-scheme`, and restarting the CoreDevice XPC services
all failed, and clearing the cache is actively misleading because it makes `-list` succeed while the
next build still hangs.
`[evidence_level: measured, confidence: exact, evidence_source: sample(1) of the hung xcodebuild; A/B of identical invocations in ~/Documents vs /private/tmp/oi-src]`

**2. The first launch of a freshly built binary pays model warm-up, and it is minutes.** Do not lower
`--timeout` to "fail fast". A cold first case exceeded 240s and was killed; warm cases on the same
binary run 12–22s, and the harness discards all output on timeout, so a too-short timeout destroys
the evidence that would explain it. Leave the 600s default.

```bash
python3 scripts/run_quality_matrix.py --app /private/tmp/oi-mac-nosbx/Build/Products/Debug/OpenIntelligence.app --modes standard --pcc deny
```

*Verified 2026-08-09, re-run twice on 2026-08-11.* Writes `BenchmarkRuns/<timestamp>-matrix/` with
`report.md`, `results.json`, and a per-case report under `reports/`. `BenchmarkRuns/` is gitignored
in full, so no run survives a fresh clone. Running the instrumented binary from the repository root
drops a `default.profraw`, now gitignored.

**3. Stage figures from before 2026-08-11 are not comparable to anything after it.** The ground
truth changed, not the pipeline. Every `multi_hop_project_m*` case credited one of the two documents
its question requires, because `build_eval_dataset.py` read the manifest's singular `expected_source`
and `run_quality_matrix.py` passed that one filename to the harness. Ranking the *other* required
document first therefore scored as a demotion, which is where `rerank` MRR@10 0.972 and `final` 0.917
came from against a `vector` stage at 1.000. Both scripts now prefer a plural `expected_sources`.
With the correct ground truth every stage reads 1.000. **Do not read that as a pipeline improvement,
and do not diff a pre-08-11 run against a post-08-11 one at the stage level.** Accuracy, abstention
and hallucination counts are unaffected and remain comparable.

**4. The synthetic fixture cannot score a model change, and the reason is the corpus, not the
sample size.** `run_quality_matrix.py` creates a fresh store per (case, mode) and ingests only that
case's `input_files`, so each case is scored against an index holding nothing but its own expected
documents. On the 2026-08-11 run the vector stage saw two to five candidates per case, every one of
them correct. `R@5` asks whether the right document is in the top five when there are at most five
candidates and all are relevant, so the 1.000s were arithmetic. External data and a larger `n` do
not move that on their own. Treat a green run on this pack as "no regression detected", never as
evidence that a change helped.
`[evidence_level: run_artifact_verified, confidence: exact, evidence_source: BenchmarkRuns/20260811-150328-matrix/reports/*.txt STAGE METRICS; run_quality_matrix.py:391, :720]`

**5. Use the QASPER pack to measure anything.** `Benchmarks/ResearchFixtures/qasper_external_v1/`
carries 83 cases whose questions, answers and evidence come from QASPER (CC BY 4.0), and declares a
shared 40-paper `pool` that is ingested for every case, so each question is asked against 39
distractor papers.

```bash
python3 scripts/run_quality_matrix.py --app /private/tmp/oi-mac-nosbx/Build/Products/Debug/OpenIntelligence.app --manifest Benchmarks/ResearchFixtures/qasper_external_v1/manifest.json --modes standard --pcc deny
```

Ingestion is much heavier than the synthetic pack: every case ingests the whole pool, roughly
135,000 words, because the harness cannot share one index across cases without losing the
document-name mapping (see the note in `run_one`). Budget accordingly and do not lower `--timeout`.

Rebuild or verify the corpus with `scripts/build_external_fixtures.py`; `--check` is offline and
compares against `fixtures.lock.json`.

**5b. Do not run the benchmark on the iOS Simulator. Measured 2026-08-12.** It is the obviously
right destination on paper: a simulator has its own filesystem container, so it cannot pollute the
real app library, and it is the platform this app ships on. It does not work, because **Apple
Intelligence cannot generate in the Simulator on this machine**. One case at `--pool-limit 10`
exceeded ten minutes and then failed, against 170s on macOS:

```
[ReasoningChain] All 8 sessions failed to produce an insight
[Agentic] Failed: The on-device model did not return a usable response across 8 reasoning sessions
```

Ingestion and retrieval are fine; the agentic path retries eight reasoning sessions before giving
up, and that loop is the ten minutes. At 83 cases: 14+ hours in which every case fails.

**The trap:** with one document and a simple query it falls back to extractive quickly and looks
healthy. The escalation only appears at a realistic pool size, so a small smoke test will tell you
it works.

The framework itself loads and reports `availability: available`; generation dies in
`ModelManagerError 1026`. A bare probe with no app code involved reproduces it, and the same probe
on the host Mac generates real text, so the machine is capable. Locale is `en_US` on both sides and
erasing the simulator cleared the unrelated `com.apple.modelcatalog` errors. Apple's forums document
this error pair; the remedy is toggling Apple Intelligence off, restarting the Mac, and turning it
back on, which the owner has declined. **Re-check after any Xcode or macOS update**: if the probe
generates, move the benchmark to the Simulator, and remove the three `#if targetEnvironment(simulator)`
guards in `LLMService` and `RAGService` at the same time.
`[evidence_level: measured, confidence: exact, evidence_source: bare FoundationModels probe host vs simulator; one full case per target]`

**7. Watch a run for defect shapes, and run six cases before eighty three. Added 2026-08-16.**
Attach the watcher to any run and it reports per case, the moment a case lands, rather than at the
end:

```bash
scripts/watch_benchmark_defects.sh BenchmarkRuns/<run>/results.jsonl <harness-log> 6
```

It prints a line only for a case carrying a known failure signature, a heartbeat every ten clean
cases, and every terminal state including a crash or a stall. Silence means healthy. That last part
is deliberate: a filter matching only the happy path is silent through a crash, and silence then
looks exactly like progress.

### Tests on a physical device

*Verified 2026-08-18.* Nothing in this project had ever run on real hardware before that date, and
the reason was not effort:

```
Library not loaded: /Library/Frameworks/OpenIntelligenceEngine.framework/OpenIntelligenceEngine
```

`OpenIntelligenceEngine.framework` is built with an absolute macOS install name and is embedded
nowhere. The app does not link it so the app runs fine; the test bundle links it and cannot load. In
the simulator that path resolves, which is why 238 tests pass there and **zero** ran on device.

```bash
scripts/run_device_tests.sh
```

`ONLY=OpenIntelligenceTests/EmbeddingProviderAgreementTests scripts/run_device_tests.sh` for one
suite. The script embeds the framework into `OpenIntelligenceTests.xctest/Frameworks`, where the
bundle's rpath already points, rewrites both install names to `@rpath`, and re-signs. No project
change, so it needs no hard-boundary approval. The real fix is `DYLIB_INSTALL_NAME_BASE` in
`project.pbxproj` and is tracked in Notion.

Three things that will waste time otherwise:

- **USB only.** Wireless fails with `Failed to allocate RSD device` during `enablePersonalizedDDI`.
  Confirm `Transport Type: wired` in `xcrun devicectl device info details --device <uuid>`.
- **Two different identifiers for one phone.** `xcodebuild` takes the CoreDevice UUID
  (`B1483F12-…`), `xctrace` takes the hardware UDID (`00008140-…`). The wrong one gives
  "No devices found matching".
- **Never re-sign the `.app` without `--entitlements`.** It strips `application-identifier` and
  install fails with `_validateApplicationIdentifierForNewBundleSigningInfo` and the message
  "Please try again later", which describes nothing. Capture them first with
  `codesign -d --entitlements :- <app>`.

### Profiling with Instruments, headlessly

*Verified 2026-08-18.* `xctrace` drives every Instruments template from the command line, against
the Mac build or a wired phone, with no GUI. Xcode 27 ships **Core AI**, **Core ML** and
**Foundation Models** templates; `xcrun xctrace list templates` prints all 30.

```bash
xcrun xctrace record --template "Foundation Models" --output /private/tmp/x.trace \
  --time-limit 8m --no-prompt --launch -- <binary> <args>

xcrun xctrace export --input /private/tmp/x.trace \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="os-signpost"]' --output /private/tmp/x.xml
```

The XML interns repeated values: a `<row>` child carries either a literal with `id=` or a `ref=`
pointing at an earlier `id`. Resolve the refs or every field reads empty. Useful schemas are
`os-signpost` for framework intervals and `life-cycle-period` for launch phases.

Measured this way on 2026-08-18: a Deep Think query is **90% generation** (48.7s of 54.2s across 8
generations), and app launch to first frame on device is **0.69s**, of which 0.547s is initial frame
rendering. The `Hang detected: 4.5s` lines in console captures are therefore **not** launch cost.

### Deep Think has never been benchmarked

Every run in `BenchmarkRuns/` is `modes: ["standard"]`. There is no baseline and no timing
history for `deep-think` or `maximum`, which means the mode the 2026-08-18 reasoning-chain
session cap changes is the one mode nothing has measured.

Standard mode, 25 cases, measured twice: **1h52m** (`tokfix`) and **2h52m** (`coreml-provider`).
That is roughly 4.5 minutes per case for the *fast* mode, and a large part of it is ingesting the
document pool rather than answering. Deep Think does 5-8 generations per query where Standard does
one, so the full-run cost is somewhere between "modestly worse" and "5x worse" depending on whether
ingestion or generation dominates. Nobody knows which, so get a rate before committing a machine
to it:

```bash
scripts/run_deepthink_pilot.sh
```

*Recorded 2026-08-18, not yet executed.* Three cases, ten pool documents, `deep-think` only. It
prints a per-case rate and extrapolates both the 25-case and the paired 50-case figures. Override
with `LIMIT=`, `MODES=`, `POOL=`, `TIMEOUT=`.

The per-run timeout is raised to 1800s. The harness default is 600s, and a single Deep Think query
took **279s on device**, so the default risks truncating a slow case and under-reporting the very
number the pilot exists to produce.

To then measure the session cap specifically, run the pilot's full-size equivalent at `e16a2d3`
and at `e16a2d3~1` and pair them with `compare_benchmark_runs.py`. Retrieval is ~21% reproducible,
so a single run cannot separate the change from noise; the sign test over paired cases is the only
readout worth acting on.

### Comparing two runs

Never compare two runs by their own averages. Verified 2026-08-17:

```bash
python3 scripts/compare_benchmark_runs.py BenchmarkRuns/<baseline> BenchmarkRuns/<candidate>
```

It intersects on `case_id`, keeps only cases that produced stage metrics in **both** runs, names the
ones it excluded, prints per-case flips so a mean cannot hide offsetting gains and regressions, and
states explicitly whether the `lexical` control moved.

The control line is the first thing to read. `lexical` goes through FTS5 over full text, so an
embedding-provider change must leave it identical case for case. If it moved, the runs are not
comparable and nothing else in the output means anything.

It also prints an **exact two-sided sign test** over the discordant pairs, and when the result falls
short it says how many one-directional pairs would clear the threshold. Read that before claiming a
result. Only cases that changed carry information, so the count that matters is discordant pairs and
not the number of cases run: **4 better and 0 worse is p = 0.125**, which looks overwhelming and is
not significant. **Six** one-directional pairs is the first point a two-sided test clears 0.05, which
is where the `6/n` minimum-detectable-effect rule of thumb comes from.

Runs disagree about which cases finish, because timeouts and hangs differ between them, so a mean
over each run's own case set compares two different corpora. On 2026-08-17 that made the control
appear to drop 0.714 to 0.625 when it had not moved at all: two cases present in the candidate and
absent from the baseline were pulling the candidate's average down. Add `--stage`/`--metric` to
change which stage the per-case breakdown covers; it defaults to `vector r1`.

Pair it with `--limit 6`. This is measured, not a preference. On 2026-08-15 a watcher reporting only
completion left a defect visible in case 1 at minute 4 unread until three cases had burned, and the
correction cycle was a full run, about three hours, per fix. Watching shapes against a six-case run
cut that to roughly twenty five minutes and surfaced four separate defects the same afternoon: the
model echoing the prompt's own `[SEARCH: query]` placeholder, the verification loop replacing a
cited answer with an uncited one, a guard applied to only one of two call sites, and recursive
research having no wall-clock bound. Run the full set once the smoke is clean, not before.

Replay it over a finished run to sanity check a signature list before trusting it. Against
`qasper-deepthink-20260815` it flags the placeholder defect on case 1.

**6. The harness overstated its own sensitivity until 2026-08-12.**
`minimum_detectable_effect(n)` interpolated the sample size into a sentence whose threshold was a
hardcoded constant, so it printed "differences below about 25 points are not resolvable" at every
`n`. Under the exact two-sided sign test the function describes, `2 * 0.5**d < 0.05` first holds at
d=6, and the smallest difference that reaches it is `6/n`. That is **33 points at n=18, not 25**.
Every report in `BenchmarkRuns/` dated before 2026-08-12 carries the constant; read those power
statements as `6/n` instead. At n=83 the current figure is about 7 points.
`[evidence_level: computed_verified, confidence: exact, evidence_source: exact binomial sign test; scripts/run_quality_matrix.py minimum_detectable_effect]`

## Lint

There is no lint gate, and this matters mainly so you do not mistake one for existing.

`.swift-format` is tracked at the repository root. The binary resolves inside the Xcode 27
toolchain at
`/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-format`.
Nothing in `.github/workflows/` or `scripts/` invokes it.

*Verified 2026-08-07:* the tree does not currently pass. 20 of 25 sampled files under
`OpenIntelligence/` emit warnings, mostly `[Indentation]`.

```bash
/Applications/Xcode-beta.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift-format lint --configuration .swift-format <file>
```

So do not run `swift-format --in-place` across the tree as a tidy-up. It would reformat hundreds of
files, bury the actual change in the diff, and touch hard-boundary files.

## Migrations

There is no operator-invoked migration command. Migrations run inside the app at startup:
`SQLiteFullTextService` tracks `PRAGMA user_version`, adds columns through `ensureColumnExists`, and
carries `migrateFromFileStorage` and `migrateRowToContentTable` for older stores.
`[evidence_level: code_verified, confidence: high, evidence_source: SQLiteFullTextService.swift:2211, :2296, :3007, :3126]`

The operational consequence is the constraint, not a command: a change to the FTS5 schema, the
`BNNSVectorDatabase` on-disk format, or the embedding dimensionality forces every existing user to
reindex their entire library. Those files are hard-boundary for exactly this reason. Any such change
lands additively first, then swaps, never in place.

## Parallel work

*Verified 2026-08-07 against this repository's `.git.nosync` layout.*

```bash
git worktree add --detach /private/tmp/oi-wt <ref>
```

```bash
git worktree remove --force /private/tmp/oi-wt
```

`git worktree list` reports the main worktree as `.git.nosync`, which is correct and not damage.

Three things to get right:

- **Create the worktree outside `~/Documents`.** A worktree inside it inherits every iCloud failure
  mode in this runbook, which is the entire reason the git directory was moved in the first place.
- **One writer per checkout.** Two write-capable sessions in the same working tree will overwrite
  each other. Use a worktree per writer, or one writer.
- Claude Code 2.1.220 has `claude --worktree [name]` (`-w`), plus `--tmux`, which does this for you.
  Note it inherits the same location caveat.

Until `.claude/` and `CLAUDE.md` are committed, a fresh worktree will not contain them, so a session
started there gets no rules, skills, or hooks.

## Governance checks

```bash
python3 .codex/skills/route-openintelligence-work/scripts/test_repoos_router.py
```

*Verified 2026-08-07: passes, 24 of 24.* This suite was red at 3 of 14 earlier the same day, on a
version-derivation defect and on three tests that asserted a literal version against the live
working tree. Both are fixed; see [DECISIONS.md](DECISIONS.md). If it goes red again, read the
failure before assuming it is the fixture: a permanently failing test here hid a real defect for
three releases.

```bash
python3 scripts/secret_scan.py
```

*Verified 2026-08-07: passes.* Prints `secret_scan: no sensitive tokens discovered`.

The `repoos_workspace_automation` route also names
`python3 ~/.codex/skills/.system/skill-creator/scripts/quick_validate.py .codex/skills/route-openintelligence-work`.
*Unverified:* that path is outside the repository and may not exist on a given machine.

## Release

Version is derived, not set by hand. `ci_scripts/ci_post_clone.sh` stamps `MARKETING_VERSION` for
both iOS and macOS from the first `## <number>` heading in `CHANGELOG.md` during the Xcode Cloud
build. Editing that heading changes what ships.

Fastlane lanes in `fastlane/Fastfile`, all *recorded*, none run from here:

| Lane | Does |
|---|---|
| `push_metadata` | Metadata only, to a version already in App Store Connect. Editable while Waiting for Review. |
| `upload_release_metadata` | Upload release metadata for the App Store version. |
| `upload_release_build` | Build and upload to App Store Connect. |
| `submit_latest` | Push metadata and submit using the newest build ASC has already processed. Xcode Cloud is the builder. |
| `release_to_review` | Metadata, upload, and submit. `release` is an alias. |

Each takes `platform: ios` (default) or `osx`.

### Do not build a release on this Mac. It cannot be submitted.

**This machine runs a beta macOS, and that alone makes every archive it produces
unsubmittable.** Xcode stamps `BuildMachineOSBuild` into `Info.plist` from the host OS, and App
Store ingestion rejects a prerelease stamp with `ITMS-90111` **regardless of which Xcode built it**.
Builds 376 and 377 were archived here on the release Xcode 26.6 and both carry `26A5406e`, whose
trailing lowercase letter marks it prerelease.

**`altool --validate-app` does not catch this.** It returned `VERIFY SUCCEEDED with no errors` for
both. Validation is not ingestion, and treating a green validate as proof a build can ship is the
mistake this section exists to stop.

Check any archive before trusting it:

```bash
/usr/libexec/PlistBuddy -c "Print :BuildMachineOSBuild" <archive>/Products/Applications/OpenIntelligence.app/Info.plist
```

A trailing lowercase letter means prerelease. Discard the archive.

**Use Xcode Cloud instead. Do not archive releases on this machine.** Its builders run released
OS images, so the stamp comes out clean, and `ci_scripts/ci_post_clone.sh` stamps the version while
`ci_scripts/ci_post_xcodebuild.sh` gates the binary before it can be uploaded.

**Corrected 2026-08-28.** This paragraph previously said to use
`.github/workflows/app-store-upload.yml`. That workflow was retired in `546df1f` and
`.github/workflows/` no longer exists, so following this section as written led nowhere. Actions ran
releases for one stretch in August 2026, as a fallback after the free Xcode Cloud allowance was
exhausted; paid Xcode Cloud capacity replaced it. The reason for not building locally is unchanged
and is the paragraph above. The OpenManual repository hit this first and its release
workflow exists for the same reason.

Everything below describes the local archive mechanics. They are correct and were verified end to
end, and they are still the right reference for what the workflow does — but the resulting binary
cannot be submitted from this machine.

#### Local archive mechanics, for reference


**Why this exists.** On 2026-08-25 Xcode Cloud hit its compute cap mid-release. Runs #376 through
#385 were each created and cancelled 5-9 seconds later with `startedDate: null` — never scheduled.
That is not the workflow's `autoCancel`, because #385 had no successor push to cancel it. The last
run to produce a build was #375.
`[evidence_level: measured, confidence: exact, evidence_source: GET /v1/ciProducts/c6efe188/buildRuns?sort=-number]`

**The toolchain is not optional, and the wrong one ships PCC.** The `Default` workflow builds with
Xcode Version "Latest Release" = **Xcode 26.6 (17F113)** on macOS 26.6 (25G83). Every PCC path sits
behind `#if compiler(>=6.4)` at **12 sites**. Xcode 26.6 ships Swift 6.3 and compiles them out;
**Xcode 27 beta ships Swift 6.4 exactly and compiles them in.** A local Xcode 27 archive of
`cbae053` linked **18** `FoundationModels.PrivateCloudComputeLanguageModel` symbols, including
`__allocating_init()`, `isAvailable` and the `LanguageModel` conformance descriptor. Shipping that
binary would contradict the v5.0 release notes and the in-app copy corrected in `8f76398`.
`[evidence_level: measured, confidence: exact, evidence_source: nm -u + swift-demangle on the 2026-08-25 beta archive]`

**Xcode 27 cannot be submitted regardless.** As of 2026-08-25 Xcode 27 is at beta 6 (27A5252f) with
no Release Candidate. Beta Xcode and beta SDKs are accepted for **TestFlight only**; App Store
submission requires a release or RC toolchain and otherwise fails `ITMS-90111`.

**Build number.** As of 2026-08-26 both platforms are at build **387**, so the next must be **388
or higher**. `CURRENT_PROJECT_VERSION` in `project.pbxproj` reads 150 and is vestigial, because CI
stamps its own. Override it on the command line; do not edit that file, which is hard-boundary.

**A shipped version closes its train on that platform, and nothing local warns you.** macOS 5.0 went
live on 2026-08-26 as build 379. The very next macOS archive, build 386, was still stamped 5.0 and
App Store Connect refused it at the validate step with two errors that say the same thing:

```text
Invalid Pre-Release Train. The train version '5.0' is closed for new build submissions (90186)
CFBundleShortVersionString [5.0] must contain a higher version than the previously approved
version [5.0] (90062)
```

Nothing catches this before the runner. `ci_scripts/ci_post_clone.sh` has a guard against stamping
an already-shipped version, but it infers "already shipped" from whether `[Unreleased]` holds
entries, and has no way to ask App Store Connect what is actually released. `[Unreleased]` was empty
while 5.0 was live, so it stamped 5.0 and the guard stayed silent. Its own error text names the
failure it cannot see.

**One CHANGELOG heading stamps both platforms.** `ci_post_clone.sh` derives `MARKETING_VERSION` from
the first `## <number>` heading and applies it to all 8 targets; the
`MARKETING_VERSION[sdk=macosx*]` override was removed on 2026-07-30. A single commit therefore
**cannot** produce iOS at one marketing version and macOS at another. If one platform's train closes,
either both move up, or you ship the other platform from a build you already uploaded before the
bump. On 2026-08-26 that meant iOS shipped 5.0 from build 386 while macOS shipped 5.0.1 from 387.
`[evidence_level: measured, confidence: exact, evidence_source: Actions run 33023093330 validate step]`

**Installing the release toolchain needs your password**, so no agent can do it. The Mac App Store
offers Xcode 26.6 (`mas info 497799835`). `mas install 497799835` invokes `sudo` and fails without a
terminal. Install from the App Store app, or:

```bash
sudo mas install 497799835
```

Do not `xcode-select` afterwards. Point one command at the release toolchain with `DEVELOPER_DIR`
and leave the beta as the default for device work.

**The procedure.** Steps 1-5 were run end to end on 2026-08-25 against the Xcode 27 beta and all
succeeded, so everything except the toolchain swap is verified: archive, distribution signing,
`app-store-connect` export and a 201 MB `.ipa`. The exported profile was
`iOS Team Store Provisioning Profile: Gunndamental.OpenIntelligence`, with no `ProvisionedDevices`
and `get-task-allow: false`.
`[evidence_level: measured, confidence: exact, not_verified_on_26.6, evidence_source: ARCHIVE SUCCEEDED + EXPORT SUCCEEDED, 2026-08-25]`

**`--exclude '.build'` is not optional, and leaving it out is how a local release fails at the
very last step.** `OpenIntelligence/swift-transformers/` is bundled into the app as resources, and
locally that directory contains a gitignored 150 MB `.build` of SwiftPM artifacts. Xcode Cloud
clones fresh so it never has one; a local `rsync` without this exclusion copies it in, Xcode bundles
it, and App Store Connect rejects the upload after the full build and a 202 MB transfer:

> `Invalid bundle structure. The "OpenIntelligence.app/swift-transformers/.build/out/ModuleCache.noindex/MachO-….pcm"
> binary file is not permitted. (90171)`

Proven on 2026-08-25: 2,510 of the 2,536 `swift-transformers` entries in the rejected `.ipa` were
`.build` artifacts. Excluding it drops the working copy from 3.6 GB to 525 MB.
`[evidence_level: measured, confidence: exact, evidence_source: altool 90171 rejection; unzip -l of the rejected ipa]`

```bash
rsync -a --delete --exclude '.build' --exclude '.build.nosync/' --exclude '.attic.nosync/' --exclude '.device-smoke.nosync/' --exclude '.simulator-smoke.nosync/' --exclude '.git.nosync/' --exclude 'BenchmarkRuns/' --exclude 'Benchmarks/run/' ./ /private/tmp/oi-src/
```

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild archive -project /private/tmp/oi-src/OpenIntelligence.xcodeproj -scheme OpenIntelligence -configuration Release -destination 'generic/platform=iOS' -archivePath /private/tmp/oi-rel/OpenIntelligence.xcarchive -derivedDataPath /private/tmp/oi-rel-dd -skipPackagePluginValidation CURRENT_PROJECT_VERSION=376
```

**Gate before exporting. This is the check that prevents shipping PCC.** It must print `0`. If it
prints anything else the archive was built by Xcode 27 and must be discarded, not uploaded:

```bash
nm -u /private/tmp/oi-rel/OpenIntelligence.xcarchive/Products/Applications/OpenIntelligence.app/OpenIntelligence | grep -c PrivateCloudCompute
```

Then export, using an `ExportOptions.plist` with `method = app-store-connect`, `teamID =
Z3E334EXZD`, `signingStyle = automatic` and `destination = export`. `destination = export` is what
keeps the export local; `upload` would send it:

```bash
xcodebuild -exportArchive -archivePath /private/tmp/oi-rel/OpenIntelligence.xcarchive -exportPath /private/tmp/oi-rel-export -exportOptionsPlist /private/tmp/oi-rel/ExportOptions.plist
```

Upload through the existing lane rather than `altool`, by placing the `.ipa` where the lane expects
it. The lane defaults to **version 4.5 and build 150** and will do the wrong thing silently if the
arguments are omitted:

```bash
mkdir -p build && cp /private/tmp/oi-rel-export/OpenIntelligence.ipa build/OpenIntelligence-5.0-376.ipa && LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 fastlane upload_release_build version:5.0 build:376 skip_build:true
```

**macOS 5.0 is a second, unscoped build.** It sits in `PREPARE_FOR_SUBMISSION` at build 375 like
iOS, and the Xcode Cloud workflow archives both platforms (`ARCHIVE/ANY_MAC` and `ARCHIVE/IOS`).
`upload_release_build` is iOS-only, so a local macOS release needs its own archive with
`-destination 'generic/platform=macOS'`, a Mac App Store export, and an upload path that does not
exist in the Fastfile yet.
`[evidence_level: code_verified, confidence: exact, evidence_source: fastlane/Fastfile upload_release_build; workflow actions]`

### App Store Connect credentials

Check first. Do not diagnose from an error message.

```bash
ruby scripts/asc_healthcheck.rb
```

It reports the configured key, validates the file, authenticates against the live API and confirms
OpenIntelligence is reachable. Green means `push_metadata` will authenticate. It never prints key
material, the issuer UUID or the signed token.

Fastlane reads three variables from the shell, exported in `~/.zshrc`:

| Variable | Value |
|---|---|
| `APP_STORE_CONNECT_API_KEY_ID` | Exactly 10 characters. Any other length is not an ASC API key. |
| `APP_STORE_CONNECT_ISSUER_ID` | Team UUID, top of Users and Access > Integrations. |
| `APP_STORE_CONNECT_API_KEY_PATH` | `~/.appstoreconnect/private_keys/AuthKey_<KEYID>.p8` |

The key lives in `~/.appstoreconnect/private_keys/` because `notarytool`, `altool` and Transporter
auto-discover keys there given only `--apiKey` and `--apiIssuer`.

`.env.appstore` is **not** what fastlane reads. It defines `ASC_KEY_ID`, `ASC_ISSUER_ID` and
`ASC_KEY_BASE64`, which no lane references, and it loads only under `fastlane --env appstore`. Treat
it as unused until something is changed to consume it.
`[evidence_level: code_verified, confidence: exact, evidence_source: fastlane/Fastfile:36-47 reads APP_STORE_CONNECT_*, .env.appstore defines ASC_*]`

Apple returns a byte-identical bare 401 for a revoked key, a wrong issuer, a malformed token and a
file that was never an ASC key. On 2026-08-24 the push had been failing for days across two
sessions, both of which diagnosed it from the error text and both of which were wrong: the path
pointed at `ApiKey_5UNPFIPXPPRC.p8`, a 12-character ID Apple does not issue, while a working key sat
unused in `~/Downloads`. That is what the healthcheck exists to prevent.
`[evidence_level: measured, confidence: exact, evidence_source: 2026-08-24, five keys probed against GET /v1/apps]`

`deliver` needs a UTF-8 locale. The release notes contain non-ASCII characters, and without `LANG`
and `LC_ALL` set it raises `invalid byte sequence in US-ASCII` partway through the metadata upload:

```bash
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 fastlane push_metadata version:5.0
```

CI is `.github/workflows/ci.yml`, building on `macos-26` on push and PR to `main`, selecting the
highest installed Xcode.


## Staging a release without submitting it

*Verified 2026-09-02, both platforms.*

Xcode Cloud uploads a build on every push to `main`, so the binary usually exists before anyone
decides to ship. Attaching it to the version record is one API call per platform and does not
submit anything; the record stays `PREPARE_FOR_SUBMISSION` and the owner can still change
screenshots or copy in App Store Connect before review.

```bash
# JWT as in scripts/asc_healthcheck.rb, then:
# PATCH /v1/appStoreVersions/<versionId>/relationships/build  {"data":{"type":"builds","id":"<buildId>"}}
# -> HTTP 204. Read it back with GET /v1/appStoreVersions/<versionId>/build.
```

Find the build ids with `GET /v1/builds?filter[app]=6756559175&filter[version]=<n>&include=preReleaseVersion`;
the included `preReleaseVersion.attributes.platform` is the only field that says which of the two
same-numbered builds is iOS and which is macOS. Both must be `processingState: VALID`.

`submit_latest` picks the newest processed build for the version on its own, so a staged build
needs no extra argument at submission time; the attach step exists so that the App Store Connect UI
shows the release complete while it waits.

`[evidence_level: measured, confidence: exact, evidence_source: PATCH returned 204 for both 5.1 records on 2026-09-02; GET read back the attached ids]`

## Replacing App Store screenshots through the API

*Verified 2026-09-02 on the iOS 5.1 record.*

`push_metadata` hardcodes `skip_screenshots: true`, and changing that means editing `fastlane/Fastfile`,
which needs the owner to name it. The API route needs nothing in the repo:

1. **Find the display type from the pixel size, not the device.** fastlane's table in
   `deliver/lib/deliver/app_screenshot.rb` (`DEVICE_RESOLUTIONS`) is the local source; a 6.9-inch
   iPhone capture at 1320x2868 belongs to `APP_IPHONE_67`, which also covers 1290x2796. There is no
   `APP_IPHONE_69`. iPad 13-inch captures at 2048x2732 are `APP_IPAD_PRO_3GEN_129`.
2. `POST appScreenshotSets` with that `screenshotDisplayType` under the localization
   (`GET appStoreVersions/<id>/appStoreVersionLocalizations` gives the id), or reuse an existing set.
3. Per image: `POST appScreenshots` (`fileName`, `fileSize`) returns `uploadOperations`; `PUT` each
   byte range to its URL with the headers given; then `PATCH appScreenshots/<id>` with
   `uploaded: true` and the file's MD5 as `sourceFileChecksum`.
4. Poll `assetDeliveryState.state` until every image is `COMPLETE`. Only then delete the superseded
   set with `DELETE appScreenshotSets/<id>`.

**`.jpeg` is rejected after upload, not before.** Every step above succeeds and the asset then
lands in `FAILED` with `IMAGE_BAD_FILE_EXTENSION`. Only `.jpg` and `.png` are accepted. iPhone
captures arrive as `IMG_nnnn.jpeg`; convert with `sips -s format png` and upload the PNGs. Eight
images lost one round trip to this on 2026-09-02.

**Every iPhone size is its own set, and previews are separate from screenshots.** Apple requires
only 6.9-inch (or 6.5-inch when 6.9 is absent) and scales the rest down from it, so an empty 6.5 or
6.3 slot is not a defect. Replacing the 6.5-inch set alone, as happened first on 2026-09-02, leaves
the 6.9-inch tab empty and looks like nothing was uploaded. App preview videos live in
`appPreviewSets` (`previewType`, e.g. `IPHONE_65`), untouched by screenshot work; the 6.9-inch
preview uses the same 886x1920 file as 6.5-inch and is scaled from it when absent. **Apple's hosted
preview (`videoUrl`, an HLS playlist) tops out at 332x720 and is not a recovery source for the
original.** Keep preview masters somewhere findable; the 5.1 one was on no indexed volume.

Order within a set is creation order, so upload in the order the store should show them. The
scripts used (`asc_upload_shots.rb`, `asc_delete_old_set.rb`, on top of the JWT helper from
`scripts/asc_healthcheck.rb`) lived in the session scratchpad; they are about 60 lines to recreate.

`[evidence_level: measured, confidence: exact, evidence_source: eight FAILED assets with IMAGE_BAD_FILE_EXTENSION, then eight COMPLETE after PNG conversion, iOS 5.1 localization 3b8a2fff, 2026-09-02]`

## iOS and macOS need different App Store release notes, and the lane cannot do it yet

*Added 2026-08-31.*

The platforms have diverged, so one set of notes is wrong for at least one of them. On 2026-08-31,
macOS was coming from 5.0.2 and iOS from **5.0** — meaning iPhone and iPad had never received 5.0.1
(17 entries) or 5.0.2 (5 entries), most of which are cross-platform UI and infrastructure fixes that
only reached the Mac. An iPhone user installing 5.1 gets roughly twenty fixes that a Mac user
already had, and none of the macOS-only render work matters to them.

**`push_metadata` hardcodes `metadata_path: fastlane_path("metadata")`,** so it cannot select copy
per platform. Until that lane takes a path, the procedure is:

- `fastlane/metadata/` is canonical **and holds the macOS notes**. `push_metadata ... platform:osx`
  is correct as-is.
- `fastlane/metadata-ios/en-US/` holds the iOS `release_notes.txt` and `promotional_text.txt`.
  `name.txt` and `description.txt` there are **symlinks** into `fastlane/metadata/en-US/`, so the
  shared identity fields cannot drift between platforms.
- To push iOS, swap the two files in, run the lane, and restore. Use a `trap` so a failure mid-run
  cannot leave the canonical copy holding iOS text:

```bash
M=fastlane/metadata/en-US
cp "$M/release_notes.txt" /tmp/mac_rn.bak; cp "$M/promotional_text.txt" /tmp/mac_pt.bak
trap 'cp /tmp/mac_rn.bak "$M/release_notes.txt"; cp /tmp/mac_pt.bak "$M/promotional_text.txt"' EXIT
cp fastlane/metadata-ios/en-US/release_notes.txt "$M/release_notes.txt"
cp fastlane/metadata-ios/en-US/promotional_text.txt "$M/promotional_text.txt"
fastlane push_metadata version:<v> platform:ios
```

**Do not reach for `fastlane run deliver` with `api_key_path`.** That option expects a JSON wrapper;
`APP_STORE_CONNECT_API_KEY_PATH` points at the raw `.p8`, and the run dies with
`JSON::ParserError: invalid number: '-----BEGIN'` before contacting Apple. The lane's
`app_store_connect_api_key(key_id:issuer_id:key_filepath:)` is what handles the `.p8` correctly.

**The durable fix is one line in the Fastfile** — give `push_metadata` a `metadata_path` derived
from `platform`. `fastlane/Fastfile` is not in the `app_store_copy_update` route's allowed edits, so
it needs the owner to name the file.

`[evidence_level: measured, confidence: exact, evidence_source: both platform pushes run 2026-08-31; deliver logs confirming platform=ios and platform=osx against app_version 5.1]`

## A local device build on Xcode 27 already enables PCC, and nothing local warns you

*Found 2026-08-29, while installing a debug build on a physical iPhone to test ingestion changes.*

`DEVELOPER_DIR=/Applications/Xcode-beta.app` is Xcode 27 / **Swift 6.4**, so `#if compiler(>=6.4)`
is **true** and every PCC path compiles in. The development provisioning profile also carries
`com.apple.developer.private-cloud-compute`, so `EntitlementChecker.hasEntitlement` returns true and
the routing is genuinely reachable — not dead code.

**The guards in the section below do not catch this.** `ci_post_clone.sh` and
`ci_post_xcodebuild.sh` run in Xcode Cloud. A local `xcodebuild` for a device runs neither, so a
routine "put it on my phone to test something else" install quietly changes where queries can
execute, on a real library.

Check any bundle before installing it. Note that a **Debug** build puts the code in
`<App>.debug.dylib`, not in the app binary, so checking only the executable reports a clean zero:

```bash
APP=/path/to/OpenIntelligence.app
find "$APP" -type f -perm +111 -exec sh -c \
  'file "$1" | grep -q Mach-O && echo "$(nm -u "$1" 2>/dev/null | grep -ci PrivateCloudCompute) $1"' _ {} \;
```

On 2026-08-29 that reported **19** for `OpenIntelligence.debug.dylib` and **0** for
`OpenIntelligence`, which is why the executable-only check is worth calling out.

**To match the shipped PCC posture, build with `/Applications/Xcode.app`** — Xcode 26.6 / Swift
6.3.3, the toolchain every released binary uses. `#if compiler(>=6.4)` is false there and the count
is zero across the whole bundle. Use it for any device build whose purpose is to test something
other than PCC, so one install does not change two variables at once.

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project /private/tmp/oi-src/OpenIntelligence.xcodeproj -scheme OpenIntelligence \
  -configuration Debug -destination "generic/platform=iOS" \
  -derivedDataPath /private/tmp/oi-device-dd -skipPackagePluginValidation -allowProvisioningUpdates build
```

`[evidence_level: measured, confidence: exact, evidence_source: nm -u across every Mach-O in both bundles, 2026-08-29; xcrun swift --version for both Xcode installs]`

## Enabling Private Cloud Compute (the iOS/macOS 27 release)

Written 2026-08-28, before the fact, because two of this repository's own release guards are built
to refuse exactly the build that enables PCC. They protect the current claim. On the day the claim
changes they will block the release, and both failures look like something else.

**iOS 27 shipping does not enable PCC by itself.** The gate is `#if compiler(>=6.4)`, which is
resolved by the *compiler*, not the device. Every shipped binary was built on Xcode 26.6 / Swift
6.3.3, so PCC is not in it. A user who updates to iOS 27 runs that same binary and gets nothing new.
Enabling it takes four steps, and only the first is Apple's: iOS 27 ships → build on Xcode 27 →
invert both guards → ship an app release.

### The two guards that will stop you

1. **`ci_scripts/ci_post_xcodebuild.sh` fails the build when `nm -u` finds a `PrivateCloudCompute`
   symbol** — it asserts the count is `0`. That is correct today and exactly backwards on enable
   day. Invert it rather than deleting it: it should then fail when the count is **zero**, so a
   toolchain regression that silently compiles PCC back out cannot ship against the new copy. The
   protection is symmetrical; only its direction changes.

2. **`scripts/verify_capabilities.py` requires at least 12 occurrences of the anchor
   `compiler(>=6.4)`**, and it runs in `ci_post_clone.sh` *before* `xcodebuild` starts. Delete the
   gates and this fails first, reporting a missing capability anchor — which reads like the feature
   was removed, at the moment you are shipping it. Update the anchor in
   `Docs/SHIPPED_CAPABILITIES.json` in the same commit as the code, to something that exists in the
   ungated build (`PrivateCloudComputeLanguageModel` is the natural choice).

Also change the Xcode Cloud workflow's Xcode version from 26.6 to 27 in App Store Connect. That is a
UI setting, not a file in this repository, so nothing here can check it for you — but guard 1,
inverted, becomes the proof it happened.

### Every surface that states the claim

`Docs/SHIPPED_CAPABILITIES.json` is the single source: flip `private_cloud_compute.status` from
`built_not_enabled` to `shipping` and rewrite `public_claim`, then bring these into line with it.
All of them are correct in the *future* tense today, so this is a tense change, not a correction.

| Surface | How it updates |
|---|---|
| `fastlane/metadata/en-US/description.txt` | Manual, then pushed to ASC. **Live App Store copy — do not push without the owner saying so.** |
| `README.md` | Manual. Lines about the compiler gate, the route table, and the toolchain paragraph. |
| `WHATS_NEW.md`, `Docs/USER_CHANGELOG.md` | Manual. `OpenIntelligence/Resources/VersionHistory.md` must stay byte-identical to `USER_CHANGELOG.md`; `VersionHistoryTests` asserts it. |
| `Docs/PRIVACY_AND_ROUTING.md`, `Docs/RELEASE_NOTES.md`, `Docs/ROADMAP.md` | Manual. |
| In-app Settings copy | `OpenIntelligence/Features/Settings/HowItWorksView.swift` carries its own `compiler(>=6.4)` branch. |
| `Docs/SHIPPED_VERSION.json` | Update `app_store` and `app_store_by_platform` only when a build is actually live, never when it is submitted. |
| **gunzino.me** | Hand-maintained; the PCC sentence is manual. Only the version number auto-syncs, from the first numbered `CHANGELOG.md` heading. |
| **FascinAIting.me** | Pulls the Notion roadmap nightly. Update Notion and the site follows; never hand-edit its `roadmap.json`. |
| **gunnarguy.me** | Syncs this repository's docs daily. Update the README and the site follows — but its checkout steps set `continue-on-error: true`, so a failed sync reports success having changed nothing. Verify the page, not the run. |

### Order that avoids advertising something that is not live yet

Ship first, then claim. `Docs/SHIPPED_VERSION.json` exists because gunzino.me once advertised a
version nobody could install, and `Docs/SHIPPED_CAPABILITIES.json` exists because nineteen places
described PCC as live when it had never shipped. The copy change belongs *after* App Store approval,
not after upload — approval is the event, submission is not.


## Claude context system

```bash
.claude/hooks/session-start.sh < /dev/null
```

*Verified 2026-08-07.* Prints the startup brief. All three hooks read a JSON object on stdin and
exit 0 on every failure path, so an empty stdin is a safe smoke test. Runtime state lives in
`.claude/.state/`, which is gitignored and safe to delete.

Registered in `.claude/settings.json`: `session-start.sh` on SessionStart
(`startup|resume|clear|compact|fork`), `pre-compact.sh` on PreCompact, `stop-handoff.sh` on Stop.
`.claude/settings.local.json` holds the machine-local permission allowlist and is separate.

### What this system uses, and what it deliberately does not

Detected against Claude Code **2.1.220** on 2026-08-07. Anything marked unused is a choice, not an
oversight; a future session should read this before "adding the missing piece".

| Capability | Status |
|---|---|
| Project `CLAUDE.md` | Used. Root, always loaded. |
| `.claude/rules/` with `paths` frontmatter | Used, six rules, all scoped so none costs startup context. |
| `CLAUDE.local.md` | Available, gitignored, not created. Yours to add. |
| Skills | Used, five including the pre-existing `oi-claim-audit`: `project-orient`, `project-handoff`, `project-context-audit`, `notion-roadmap`, `oi-claim-audit`. |
| Hooks: SessionStart, PreCompact, Stop | Used. |
| Hook: PostCompact | Unused. SessionStart fires with `source: compact` and replays the checkpoint, so a second event adds nothing. |
| Hook: PreToolUse | Unused deliberately, see `DECISIONS.md`. |
| Auto memory | On by default, in use, machine-local at `~/.claude/projects/<project>/memory/`. |
| Subagents and Explore | Available. |
| Agent Teams | Not used, see `DECISIONS.md`. |
| `claude --worktree` / `-w` / `--tmux` | Available. See Parallel work above. |
| `/init`, `/import` | Available, not used. `/init` is interactive and `/import` would have bulk-appended the whole of `AGENTS.md`, which is the thing `DECISIONS.md` records declining. |
| MCP servers | Notion is in use, through the `notion-roadmap` skill. Supabase and Docusign are denied for this repository in `.claude/settings.json` (see below). `MCP_DOCKER` is configured in `~/.claude.json` and was failing `-32000: Connection closed` on 2026-08-07; unused here either way. |

**Denied connectors.** `.claude/settings.local.json`, which is machine-local and gitignored, denies
two whole servers by id. Connector tools carry no human-readable server name, so the rules name
opaque per-install ids; keeping them out of the tracked file avoids publishing which connectors are
installed on a given machine, and the ids would be meaningless to anyone else anyway.

| Denied id | Connector |
|---|---|
| `mcp__b31b8875-1712-42eb-9c02-1cc478fa694e` | Supabase, including `execute_sql` and `apply_migration` |
| `mcp__9ee579cb-760f-4a83-b619-acd1c29dd6e9` | Docusign, including `createEnvelope` |

These ids are per-install and will rot if a connector is removed and re-added. A deny rule matching
no known tool is inert and, because these contain `_`, produces no startup warning either, so the
failure mode is silent: the connector comes back with a new id and the deny stops applying. If you
re-add either connector, re-derive the id from a tool name in the session's tool list and update the
table above with it. Notion is deliberately not denied.

## Recovery

| Symptom | First move |
|---|---|
| Nonsensical build failure, duplicate symbols | `scripts/check_icloud_conflicts.sh --fix` |
| `codesign` rejects "resource fork / Finder information" | DerivedData is inside `~/Documents`; move it |
| `git fsck` fails, broken ref name | iCloud damage; run the conflict check, do not rebuild `.git` |
| Destination resolution failure | Wrong simulator; target iOS 27 explicitly |
| Preflight reports a version that looks wrong | It is. Read `CHANGELOG.md`. |
| Stop hook keeps asking for a handoff | It fires at most once per session; check `.claude/.state/handoff-<id>.done` |
