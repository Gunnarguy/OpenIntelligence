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

Each takes `platform: ios` (default) or `osx`. Credentials come from `.env.appstore`; never commit
values, only the variable names.

CI is `.github/workflows/ci.yml`, building on `macos-26` on push and PR to `main`, selecting the
highest installed Xcode.

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
