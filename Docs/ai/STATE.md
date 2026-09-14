# Current State

Updated: 2026-09-14
Branch/worktree: main (primary checkout)
Last verified commit: e6dfe30, plus the commit that carries this handoff

## Objective

**5.2 is live on both platforms. 5.3 is open and is where new work goes.** The repository can run
its own test suite again, and the two things that blocked everything on 2026-09-10 (no release
Xcode, no working test action) are both resolved.

### Read this first if you are picking up 5.3

**Nothing is half-finished and nothing is broken.** The working tree is clean, the suite is green
(**440 executed, 0 failures**, re-run 2026-09-13 with the gate in place), macOS builds, and every
change is committed **and pushed** (2026-09-14, 21 commits, `a4a8c6d..4dd8320`, a clean
fast-forward). That push is what put `Docs/SHIPPED_VERSION.json` = 5.2 on GitHub. Until then every
site workflow read 5.1 from origin and published it, four days after 5.2 went live; see "The
websites" under Exact Next Action.

**The camera is gated off for release and that is deliberate.** `ChatScreen.visionCaptureAction` is
`#if os(iOS) && DEBUG`, so the action is nil in a Release build, `AttachmentPicker`'s
`if let onVisionCapture` guard never renders the menu item, and the screen cannot be reached.
Measured against a Release build rather than assumed: the screen's own `Vision Capture` string is
**absent** from the Release binary and present in Debug, checked alongside a control string that
appears in both, so the instrument is known to work. The button's `Look at Something` label **is**
still in the Release binary, because `AttachmentPicker` compiles unconditionally; it is unreachable
rather than absent, which is a distinction worth keeping straight if anyone greps a build.

The owner's decision on 2026-09-13: the work is experimental and "should probably wait".
Removing that `#if DEBUG` is what releasing the feature means; the constraint below says what would
have to be true first. Do not remove it to tidy a diff. **The camera's user-facing notes are held,
not shipped:** `Docs/USER_CHANGELOG.md` is copied byte for byte into
`OpenIntelligence/Resources/VersionHistory.md` and rendered in Settings, so its "Your Camera"
section would have told every 5.3 user about a button their build does not have. The section now
lives in `Docs/Release/5.3/camera_user_notes_held.md` for whichever release carries the camera. The
roadmap row "The entire camera stack is dead code" carries a dated note for all of this and moved from
v5.3 to Future Backlog on 2026-09-14; the rationale is in `Docs/ai/DECISIONS.md` under 2026-09-13.

**The Console.app routing line is written and not yet closed.** Roadmap row "A TestFlight build
writes nothing to Console.app" was implemented 2026-09-14: `RouteLog` writes one `notice` line at
the start and one at the end of every generation to subsystem `Gunndamental.OpenIntelligence`,
category `routing`, carrying only public target names, reason codes, a plan id prefix and a count;
see `Docs/ai/RUNBOOK.md` "Reading the route from Console.app". It cannot be exercised in the
simulator because Foundation Models is device-only, so the row stays In Progress until the next
TestFlight build shows the pair under that predicate on the owner's phone with no debugger. That
is the first thing to do once a TestFlight build at or after `aff80be` is installed: Xcode Cloud
canceled #454 (that commit) when the next push arrived; **#455**, built from `595c660` which
contains it, `SUCCEEDED` on both platforms at 21:51Z on 2026-09-14 and both build-455 artifacts are
`VALID` in App Store Connect. Install build 455 from TestFlight and run the Console procedure.

**The App Store copy has a history now, and a gate.** `Docs/Release/APP_STORE_METADATA_HISTORY.md` holds every version of the store
copy since 2.1.1, per platform, with live dates; read its two newest entries before writing 5.3's
copy and append 5.3's there. A change under `fastlane/metadata*` without that append fails
pre-commit (`scripts/required_docs.sh`, 2026-09-14). One thing it surfaced: the 5.2 iOS and macOS
release notes diverged on 2026-09-10 and the repo does not record which text the iOS listing shows.

**Four decisions belong to the owner and have been carried for several sessions.** They are listed
under Exact Next Action. None of them blocks anything; they are simply not an agent's to make.

## Status

### 5.2 shipped, and the repository did not know it

iOS 5.2 and macOS 5.2 are both `READY_FOR_SALE` with **build 451**, release type
`AFTER_APPROVAL`, so Apple released them automatically on approval. Read from the App Store
Connect API on 2026-09-10. `[evidence_level: measured, confidence: exact]`

Nothing in the tree recorded it, and that was not cosmetic. `ci_scripts/ci_post_clone.sh` stamps
`MARKETING_VERSION` from the first numbered `CHANGELOG.md` heading, which was still
`## 5.2 <!-- unreleased -->`. The next Xcode Cloud build would have stamped 5.2 a second time and
been rejected by App Store Connect, which is the exact failure of 2026-07-28. Cut in commit
`81b0388`:

- `## 5.2` lost its `unreleased` marker; `## 5.3 <!-- unreleased -->` opened above it.
- `Docs/SHIPPED_CAPABILITIES.json` `private_cloud_compute` moved `built_not_enabled` → `shipping`,
  with `public_claim` rewritten into the present tense. That flip was gated on 5.2 being
  `READY_FOR_SALE`. `verify_capabilities.py` passes, 19 occurrences against a live anchor.
- `Docs/SHIPPED_VERSION.json` reads 5.2 on both platforms, `preparing` 5.3, `in_review` empty.
- The router reports `v5.3 (in_development, last shipped v5.2)`.

**The `LanguageModelSession.usage` capture (`a4a8c6d`) is NOT in build 451.** It landed after 451
was cut, so its CHANGELOG entry moved to 5.3. It reaches users only in the next release.

### The machine changed under us

**Xcode 27.0 release, build `27A266a`, is installed at `/Applications/Xcode.app`** and is what
`xcode-select` points at. **`/Applications/Xcode-beta.app` no longer exists**, and neither does
Xcode 26.6. Seven commands in `Docs/ai/RUNBOOK.md` named the beta path and would now fail; they
are repointed. iOS 27.0 simulators are installed: `iPhone 18 Pro`
`25E29FA1-6A22-4A86-AE9F-A6F48411E6D0` and `iPhone 18 Pro Max`.

**Xcode Cloud's `Default` workflow already builds with `27A266a`**, the same build as the local
release. Both 2026-09-10 blockers are gone.

### The test suite builds again, and the recorded cause was wrong

`xcodebuild test` could not link `OpenIntelligenceEngine.framework`; every `Tokenizers` symbol was
undefined. The cause written into this file and into Notion on 2026-09-10 — that the Engine target
declared no `packageProductDependencies` — **was false**, and came from an inspection regex capped
at 1200 characters that truncated the target block before reaching the declaration. The target
declared `TransformersTokenizers` correctly and always did.

The real cause is one level deeper. `OpenIntelligence/swift-transformers` is a **shim** whose
entire source is `@_exported import Tokenizers`; the module it re-exports comes from a separate
**remote** package, `swift-tokenizers` 0.7.1. Four Engine sources import `Tokenizers` directly, so
their symbols live in `Tokenizers_<hash>_PackageProduct.framework`, which Xcode builds and leaves
unused in `PackageFrameworks/`. Xcode links a product's transitive package dependencies into an
**application** target but not into a **framework** target, which is why the app, the smoke build
and Xcode Cloud were unaffected: the test bundle is the only thing that links the Engine standalone.

**Wiring only the Engine moved the failure rather than fixing it.** Declaring the product
explicitly anywhere turns off the automatic inference the app had been relying on, so
`Ld OpenIntelligence.app/OpenIntelligence.debug.dylib` then failed with exactly the symbols the
Engine had stopped failing on. Both targets now declare it.
`scripts/fix_engine_tokenizers_link.py` performs and documents the edit and reads the target block
with no character cap, deliberately. `[evidence_level: build_verified, confidence: exact]`

### **Builds must not run against the checkout**

This cost about an hour before it was diagnosed. With sources in iCloud-synced `~/Documents`,
`fileproviderd` sits at 98-100% CPU whenever the tree has been written to, and `xcodebuild` gets
essentially no CPU: a run sat for over ten minutes without creating its DerivedData directory or
starting a single compile.

The fix is in `CLAUDE.md` already and was not being followed. **Copy the source out and build
there:**

```bash
rsync -a --delete --exclude='.build*' --exclude='build' --exclude='*.nosync' --exclude='.git' \
  OpenIntelligence OpenIntelligence.xcodeproj OpenIntelligenceTests OpenIntelligenceLiveActivities \
  Package.swift Package.resolved Info.plist Docs CHANGELOG.md ci_scripts /private/tmp/oi-src/
xattr -cr /private/tmp/oi-src
cd /private/tmp/oi-src && xcodebuild test -scheme OpenIntelligence \
  -destination "platform=iOS Simulator,id=25E29FA1-6A22-4A86-AE9F-A6F48411E6D0" \
  -derivedDataPath /private/tmp/oi-fast-dd
```

159 MB copied, and the build compiles at full speed immediately. It also lets sources be edited
while a build runs, since the build reads the copy.

**A contributing find, not yet acted on:** `.build` (582 MB) and `build/` (444 MB) sit at the repo
root **without** the `.nosync` suffix, so iCloud is syncing roughly a gigabyte of build output. The
other build directories are correctly named `.build.nosync`, `.simulator-smoke.nosync`,
`.device-smoke.nosync`. Renaming or removing the two unsuffixed ones is the owner's call.

## Completed this cycle (5.3 working set)

- **Vision's data detection is used instead of being recomputed badly.**
  `StructuredDocumentParser.extractDetectedData` ignored
  `DocumentObservation.Container.Text.detectedData` and re-derived entities from five regexes that
  matched US phone numbers and three currencies. It now reads Apple's ten parsed categories, keeps
  the regexes as a per-type fallback for when the parse degraded to plain text, and gained
  `flightNumber`, `shipmentTracking` and `paymentIdentifier` cases. `Docs/INGESTION_PIPELINE.md` §2.7.
- **Object detection stopped looking for a model that has never been in the bundle.**
  `YOLODetectionService` searched for four YOLOv3 `.mlmodelc` files, none of which exist here, so it
  always fell through to classification with a **fabricated full-frame bounding box**.
  `LiveObjectDetectionService` replaces it with five OS detectors, four of which return real
  geometry. `Docs/INGESTION_PIPELINE.md` §2.8.
- **Three Model Parameters sliders stopped claiming to do something Apple cannot do.** See
  the constraint below before touching them.
- **Adaptive generation profiles, opt-in and off by default.** The registry was a placeholder that
  would have replaced the app's real instructions with "You are a helpful assistant"; it now
  produces generation parameters only. `Docs/OPENINTELLIGENCE_ARCHITECTURE_ATLAS.md`,
  `Docs/PRIVACY_AND_ROUTING.md`.

## Active Constraints

- **The camera is EXPERIMENTAL, and the owner has said so explicitly (2026-09-13).** Treat the
  whole `Features/Camera` surface as work in progress rather than a settled feature: it was
  unreachable from v1 until 2026-09-11, everything in it was built and repaired across two days,
  and its detection behaviour has been observed by one person on one phone. The user-facing notes
  label it experimental in the section heading. **Do not quietly promote it** to settled language in
  a later pass, and do not cite it as a shipped capability in Settings copy, the App Store listing
  or the roadmap until it has real use behind it.
- **The camera UI is ON as of 2026-09-11, and has never run on real hardware.** It had been off
  since v1 at three independent points: `ChatScreen` passed `onVisionCapture: nil`,
  `AttachmentPicker` guards its Scan Document button on `if let onVisionCapture`, and the
  presenting `fullScreenCover` was commented out. All three are now live, the presenter inside
  `#if os(iOS)`. **This is the single least-verified thing in the tree.** A live camera feed cannot
  be exercised in a simulator, so about 4,300 lines under `Features/Camera/` went from running for
  nobody to running for every iOS user on the strength of a clean build. Before 5.3 ships, point a
  phone at a room: check the boxes land on the right things, that the Vision-to-SwiftUI coordinate
  flip is right way up, and that the permission prompt appears.
  **Session teardown is already written and does not need re-investigating:**
  `CameraVisionOverlayView` pairs `.onAppear { cameraManager.startSession() }` with
  `.onDisappear { cameraManager.stopSession() }`, and `CameraManager.stopSession` calls
  `stopRunning()`. So the failure worth watching for is not a missing teardown, it is
  `.onDisappear` not firing on some dismissal path; the symptom is the green camera indicator
  staying lit after the screen closes. `CameraManager` has no `deinit` fallback, which is worth
  adding only if that symptom is ever actually seen.
- **Do NOT delete Frequency, Presence or Repetition Penalty from Model Parameters.** They do
  nothing: `GenerationOptions` in the iOS 27 SDK exposes exactly `samplingMode`, `temperature`,
  `maximumResponseTokens` and `toolCallingMode`, and the string "penalty" does not occur anywhere
  in the FoundationModels interface, so Apple Intelligence ignores all three. They are still
  collected by `ChatScreen`, persisted by `SettingsStore` and threaded into `InferenceConfig`
  before being dropped at the point `GenerationOptions` is built. **Deleting them is the obvious
  move and it is wrong**, which a session on 2026-09-11 proposed out loud before reading the
  comment three lines above the sliders: their consumer `LocalOpenAIServerLLMService` is
  scaffolding for the roadmap row "Bring-your-own local model on Mac (third-party model host)",
  which is still open. Zero call sites is what an open roadmap row looks like. What was actually
  wrong was the footer claiming they affect sampling, and that is now fixed.
- **Adaptive profiles are unmeasured.** Retrieval is nondeterministic, so no A/B here is
  trustworthy. The values are reasoned, not measured. Do not claim they improve answers.
- **Adaptive profiles apply to Standard only, and that was a correction.** The gate sits **below**
  the `if useAgentic` return in `RAGService`. Deep Think and Maximum leave through
  `executeAgenticQuery`, which reads neither the config nor the mutated local for generation: it
  builds `optimizedConfig` from `qualityMode.agenticConfig` and hands that to
  `AgenticOrchestrator`. The first version placed the gate above that branch, where it mutated a
  local the agentic path never reads **while logging `temperature 0.4 -> 0.35` as though it had
  taken effect**. Found by an adversarial review of the diff after it was committed. Do not move
  the gate back up without changing where `AgenticOrchestrator` gets its parameters; the log would
  start lying again.
- **Entities still come from table cells only.** `extractDetectedData` is called from `parseTable`
  and nowhere else, so paragraphs contribute none. Most documents are not tables.
- **`fastlane/metadata*` hold 5.2 copy.** Running `push_metadata version:5.1` would overwrite the
  live listing.
- **Do not build a release on this Mac** (prerelease `BuildMachineOSBuild`, ITMS-90111).
- **The three website patches under `Docs/Release/5.2/sites/` are still unapplied.** They flip
  future-tense PCC copy on three live sites, each of which deploys on push. Held for the owner.

## Verification

Run 2026-09-14 from `/private/tmp/oi-src` against the iOS 27 simulator, output read, with the
routing line in the tree:

- `xcodebuild test` — **`** TEST SUCCEEDED **`, exit 0, 446 executed, 3 skipped, 0 failures.**
  Six new cases in `RouteLogLineTests` pin the unified-log line's shape and vocabulary; the same
  three self-skipping guards as the 2026-09-13 run; the silent-audio test excluded by name as before.
- **macOS**: `xcodebuild -destination "platform=macOS" build` — **`** BUILD SUCCEEDED **`, exit 0.**
  Run because `RouteLog.swift` compiles into the Engine for both platforms and this repository's
  `#else` halves have diverged silently before.
- `xcodebuild -configuration Release build` (simulator) — **`** BUILD SUCCEEDED **`**, and the
  Release app binary contains `Gunndamental.OpenIntelligence`, `route started actual=` and
  `route completed actual=`, checked alongside a control string present in every build. So the
  routing line is compiled into what TestFlight installs; only its arrival in Console.app is
  unproven, and that needs the phone.

Run 2026-09-13 from `/private/tmp/oi-src` against the iOS 27 simulator
(`25E29FA1-6A22-4A86-AE9F-A6F48411E6D0`, iPhone 18 Pro), output read:

- `xcodebuild test` — **`** TEST SUCCEEDED **`, exit 0, 440 executed, 3 skipped, 0 failures.**
  This is the run that covers the camera release gate. `CameraOverlayGeometryTests` 15/15 and
  `LiveObjectDetectionTests` 7/7, so gating the screen out of Release removed no coverage: the
  geometry and the detector are tested independently of whether anything presents them.
  **The three skips are the tests' own guards, not a clean pass:**
  `EmbeddingProviderAgreementTests.testCoreAIAndCoreMLAgreeOnTheSameText`,
  `EmbeddingProviderAgreementTests.testShortTextsRemainDistinguishable` and
  `LayoutReadingOrderTests.testInterleavedContentStreamIsReorderedByGeometry`.
  **A fourth test did not run at all** and is excluded at the command line:
  `IngestionFormatCoverageTests/testSilentAudio_FailsLoudlyInsteadOfProducingAnEmptyDocument`,
  passed to `-skip-testing:` because it hangs its full 60-second timeout here. It is not counted in
  the 440. See the open device question at the end of this file.
- `xcodebuild -configuration Release build` — **`** BUILD SUCCEEDED **`**, which is what the gate
  was checked against: `Vision Capture` absent from the Release binary, present in Debug, with a
  control string present in both.

Run 2026-09-11 from `/private/tmp/oi-src` against the iOS 27 simulator, output read:

- `xcodebuild test` — **`** TEST SUCCEEDED **`, exit 0, 416 passed, 0 failed.** The first green
  suite since 2026-09-02, and it includes 10 new adaptive-profile cases and 7 new
  object-detection cases. The Engine and the app both link, and
  `[DocumentProcessor] Loaded Rust-backed Tokenizer` in the test log shows the fix working at
  runtime rather than merely at link time.
  **One test was skipped by name and that is not a clean pass:**
  `IngestionFormatCoverageTests/testSilentAudio_FailsLoudlyInsteadOfProducingAnEmptyDocument`.
  It hangs for its full 60-second timeout on this simulator. Its own failure message states the
  open question: "Unresolved: whether ingestion genuinely hangs on speechless audio, or this
  simulator has no speech model." The simulator log is full of
  `[UAFAssetProvider] ... com.apple.linguisticdata failed`, which points at the missing speech
  model rather than at an ingestion hang, but that is a lead and not a finding. **Verify it on a
  device** by importing an audio file with no speech and watching the ingestion queue. It is
  unrelated to anything in this cycle: nothing here touches audio or transcription.
- **macOS**: `xcodebuild -destination "platform=macOS" build` — **`** BUILD SUCCEEDED **`, exit 0,
  zero errors.** Run because this repository has a documented history of the `#else` half of a
  `canImport(UIKit)` pair diverging silently, and because `LiveObjectDetectionService` sits in
  `Services/Document/Classification` with no `#if os(iOS)` guard, so it compiles for both
  platforms. Its Vision and DataDetection requests were checked against the **native macOS**
  `.swiftinterface` (not the Catalyst one) before being used: `RecognizeDocumentsRequest` is
  `@available(macOS 26.0, iOS 26.0, ...)` and `DataDetector.MatchType` carries the same cases.
- `plutil -lint OpenIntelligence.xcodeproj/project.pbxproj` — OK.
- `python3 scripts/verify_capabilities.py` — all declared capabilities still have their
  implementation, `private_cloud_compute shipping ok (19 occurrences)`.
- `zsh -ic 'python3 scripts/verify_sale_prices.py'` — every recorded regular price matches App
  Store Connect; the sale intervals read 59.99 → 2026-09-15, 39.99 → 2026-09-30, 59.99 open-ended.
- `scripts/check_icloud_conflicts.sh` — no iCloud damage.
- `repoos_router.py preflight` — `v5.3 (in_development, last shipped v5.2)`.

**Not verified:** no device run of any of this. Adaptive profiles have never been switched on
outside a unit test. `LiveObjectDetectionService` has never processed a real camera frame, because
nothing presents the camera.

## Blockers / Unknowns

1. **The launch sale fires on 2026-09-15 with no further action.** Verified scheduled in App Store
   Connect. `LaunchSale.window` in the shipped 5.2 binary matches, and the paywall will read "ends
   September 29".
2. **PCC has never been observed serving an answer.** `Response` carries no route field, so the
   only available signal is `usage.output.reasoningTokenCount`, and that capture is not in build
   451. It arrives with 5.3.
3. **`v5.3` was added to the Notion `Target Release` options on 2026-09-11.** Row counts were
   compared before and after the schema change: 252 rows across 17 options, identical afterwards,
   so nothing lost its value.

## Exact Next Action

**No code work is outstanding.** The tree is clean, the suite is green, macOS builds. Do not re-run
the suite to discover where things stand; read the Verification block above.

**Pushed 2026-09-14.** `origin/main` is at `4dd8320` or later. That push started Xcode Cloud
build **#453**, stamped 5.3, on the Xcode 27 release toolchain (`27A266a`). **It succeeded**: Archive
iOS, Archive macOS and both TestFlight Internal Testing actions all `SUCCEEDED`, finished 15:21Z,
and two build-453 artifacts are `VALID` in App Store Connect under the 5.3 records, read from the
API the same day. The build before it, **#452 on 2026-09-11, failed** on macOS at
`PrepareBuildForAppStoreConnect` because the 5.3 version records did not exist in App Store Connect
yet; the owner created them afterwards, which is why #453 got through. Neither 5.3 record has been
submitted; both are `PREPARE_FOR_SUBMISSION`. No Xcode Cloud build lister exists in `scripts/`;
`load` the first 50 lines of `scripts/xcode_cloud_toolchain.rb` for its `api` helper and GET
`ciWorkflows/<WORKFLOW>/buildRuns?sort=-number` through `zsh -ic`.

**The websites, fixed 2026-09-14.** All three sites read `Docs/SHIPPED_VERSION.json` from GitHub on
a daily schedule, so with 5.2 unpushed they published "5.1" and "Private Cloud Compute is built but
not enabled" for four days after 5.2 shipped with it. Gunzino's `App Store Versions` check, the one
job that compares against the real App Store, had failed every morning since 2026-09-12 for exactly
that. Fixed by: the three patches under `Docs/Release/5.2/sites/` (Gunzino and Portfolio applied
unchanged; Fascinaiting's hero had been reworded since and was redone by hand), version anchors
moved to 5.2, Fascinaiting's timeline given a released 5.2 entry and a 5.3 in-development entry so
its version check passes against `preparing`, Fascinaiting's stranded local commit (`Add Claude
Code kit`, 2026-09-08, held back by its pre-push overlap guard behind seven bot commits) rebased and
pushed, and all three sites pushed. Gunzino's build gate compares the served Astro pages against
the hand-written HTML by text, which is why both had to change identically. The site patches are
applied and can be treated as historical.

**Four decisions that are the owner's, carried across several sessions:**

1. **The camera's release gate.** Currently `#if os(iOS) && DEBUG`. Before removing it: run the
   screen on a device through every dismissal path and confirm the camera indicator goes out each
   time, because a path where `.onDisappear` does not fire leaves the capture session live; and
   decide whether an in-app "experimental" label should accompany it, since someone who never reads
   release notes gets no signal that the feature is new.
2. **The system prompt**, which is set to "You are an extremely unhelpful assistant…". The default is
   "You are a helpful assistant." It reaches `FoundationModelPromptCompiler` on every Standard answer,
   so if it is live it is degrading answers more than any setting on the Model Parameters screen.
3. **`MARKETING_VERSION`**, still `5.2` across all 8 targets, so a local build's splash says 5.2 while
   the code is 5.3. Cosmetic and local only: Xcode Cloud stamps from `CHANGELOG.md` and gets it right.
   `project.pbxproj` is a hard-boundary file and needs naming in an approval.
4. **`.build` (582 MB) and `build/` (444 MB)** at the repository root, which lack the `.nosync` suffix
   every other build directory has, so iCloud syncs roughly a gigabyte of build output. This is the
   same mechanism that starved builds against the checkout.

**And one question that needs a design answer rather than a decision:** a custom reasoning profile
currently reaches only Apple's model-internal effort dial, which is PCC-only. The app's own
reasoning, the multi-session chains in Deep Think and Maximum pinned on-device at four call sites,
is driven by this app's prompts and is untouched by what the owner writes in that field. Feeding
that text into `executeReasoningChain`'s prompts is what would make the feature match its name. It
was deliberately not attempted: those prompts are the product, and answer quality cannot be A/B
tested here.

**The open question that needs a device, not a decision:**
`IngestionFormatCoverageTests/testSilentAudio_FailsLoudlyInsteadOfProducingAnEmptyDocument` hangs its
full 60-second timeout on this simulator and is skipped by name in every run recorded above. Import
an audio file with no speech on a real device and watch the ingestion queue. Either ingestion hangs
on speechless audio, which is a real defect, or this simulator has no speech model, which the
`com.apple.linguisticdata` asset failures in the log suggest. Nothing in this cycle touches audio.
