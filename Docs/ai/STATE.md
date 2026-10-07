# Current State

Updated: 2026-10-07 (5.6 is open and committed at the owner's word: ten fixes, the suite passes, nothing seen on a device; the promotional text is live; eleven roadmap rows are on `v5.6`, In Progress)
Branch/worktree: `main`, primary checkout
Last verified commit: 9999659

## Objective

**5.6, "the first five minutes".** On 2026-10-07 the owner said `PROCEED: IMPLEMENT` for ten fixes (C1 to C10 in
`Growth/PROPOSAL_5.6.md`, a local file) and said go on a new promotional text. The 5.6 records exist in App Store
Connect on both platforms (PREPARE_FOR_SUBMISSION, release MANUAL, created by him on 2026-10-01). All ten fixes are
written, with tests, and were committed and pushed on 2026-10-07 at his word ("commit"). `CHANGELOG.md` carries
`## 5.6 <!-- unreleased -->`, so that push started an Xcode Cloud build stamped 5.6.

Also local and not started: a small marketing test whose notes are in `Growth/` (git-ignored; start at
`Growth/CURRENT_EXPERIMENT.md`). It waits for 5.6.

## Status

- **2026-10-07, 5.6 committed, not yet seen on a device.** One entry per fix is in `CHANGELOG.md` under 5.6, each with
  what was read, compiled or tested. In short: inline citations link by chunk id (`CitationLinker`); the answer
  cleanup stops rewriting "$300.00" as "$300. 00" and never merges sentences whose numbers or codes differ
  (`AnswerSentenceSplitter`, three functions in `LLMService.swift`); the Evidence-First prompt lost the outline the
  model printed; Fact Check and streaming text show no markdown markers; the Verified badge reads one classifier with
  a Not Checked state (`VerificationOutcome`); Gate E passes on Gate B's claims when its ratio alone fails; "Just
  Once" consent is cleared before every Deep Think or Maximum question; a device without Apple Intelligence gets one
  wording per reason (`AppleIntelligenceCopy`); an empty library offers no prompts; the hardware legend waits for the
  welcome screen. The suite passes (Verification, 2026-10-07). **None of it has been seen on a device.**
- **The promotional text is live** since 2026-10-07 08:13 PT on the 5.5 and 5.6 records, both platforms, set through
  the API at the owner's word and read back equal (`Docs/Release/APP_STORE_METADATA_HISTORY.md`, 5.6).
- **Store notes for 5.6 are written and not pushed** (`fastlane/metadata*/en-US/release_notes.txt`). They describe the
  fixes before any device check and are to be re-read against the owner's phone run.
- **Roadmap, 2026-10-07:** `Target Release` has a `v5.6` option, and the eleven rows these fixes track are on it as
  `In Progress` (URLs under Blockers). None is `Completed`: each closes on a device. The verified-badge row and the
  wrong-answers row each carry a dated note saying what 5.6 does and does not do for them. The empty-library fix
  has no row.
- **Pushed 2026-10-07 10:10 PT:** `b453ab8` (the three doc corrections of 2026-10-05 and the README's routing
  sentence) and `7236c8a` (5.6). Xcode Cloud build #484 from `7236c8a` succeeded (10:10 to 10:28 PT). Build 484
  is in App Store Connect as 5.6 for iOS and macOS, processing VALID, internal testing state IN_BETA_TESTING
  (read 10:35 PT), so internal testers can install it from TestFlight.
- **App Store creative assets: the owner picked A for both on 2026-10-07, and nothing is uploaded.** Apple opened
  product page headers (3840x1646) and search result images (3:2, up to 3840x2560) on 2026-10-05, for iOS and
  iPadOS 27, as placements on a version in Prepare for Submission. The files are in `Growth/store-assets-5.6/`
  (local, git-ignored): `search-A-answer.png` and `header-A-answer-centered.png`, the picked header with its
  headline and card moved inside the middle of the frame, because Apple's one layout rule is to keep the focal
  point centred and its template safe areas were not read. The agent session's permission check refused the
  upload as a production deploy, so `asc_assets_upload.rb` in that folder is for the owner to run (dry run by
  default, `--apply` to send). Its upload and placement calls have never run; the reads it starts with have
  (asset library 6756559175, 5.6 iOS en-US localization `916b39be-9547-48bc-8a15-342de0a03250`, no header or
  search placement on it yet).
- **The owner's iPhone was unreachable from this Mac at 10:15 PT on 2026-10-07** (`xcrun devicectl list devices`:
  "unavailable"), so 5.6 was not installed on it.
- **The token-budget work has a roadmap row, Future Backlog:**
  https://app.notion.com/p/3f249a74d54f815cbbd3c2e1c492dfd7 (filed 2026-10-07). The preflight routes it as
  `core_ai_ios27_change`, risk high, and `OpenIntelligence/Services/AIPlatform/**` (where
  `FoundationModelTokenBudget.swift` lives) is editable only when the owner names the file.
- **2026-10-06, local only.** Product facts were checked against the live US store page, Apple's
  device-requirements page and this repository, and a test of five questions over three public federal PDFs was
  written with its answer key before any run of the app. The notes are in `Growth/` (git-ignored). Nothing was
  posted, sent, published or spent.
- **2026-10-05, three doc corrections, committed 2026-10-07 beside 5.6.** `Docs/LIMITATIONS.md` (Technical
  Limits: the AFM 3 Core Advanced bullet rewritten, and one bullet added on how much of the on-device window Standard
  fills), `Docs/PRIVACY_AND_ROUTING.md` ("What Apple reports", one correction paragraph) and `Docs/STUDY_GUIDE.md`
  (three sentences). Cause: the docs said the SDK gives an app no way to observe which on-device model it has; the
  release SDK (Xcode 27.0 `27A266a`) has `SystemLanguageModel.variant` (`.core3`, `.coreAdvanced3`), every response
  carries `Transcript.Response.assetIDs` (iOS 26.0), and this Mac reads `.coreAdvanced3` with `contextSize` 8192.
  A refuting reviewer found seven defects in the first draft of these edits; all are fixed in the working tree.
  The owner asked for the limitations file to be updated. On 2026-10-06 the two notes
  saying a Private Cloud Compute response's `assetIDs` were unmeasured (`Docs/LIMITATIONS.md`,
  `Docs/PRIVACY_AND_ROUTING.md`) were replaced with the measurement. `README.md`, "Routing", was brought in line in the same
  commit: an app cannot choose the on-device model and can read which one it has.
- **5.5 is live on both platforms, build 483** (iOS and macOS released 2026-09-30 from `81b66a8`). How it was
  released and closed out, the prices set on 2026-09-29 (Lifetime $49.99, Pro Annual $24.99, Pro Monthly $4.99,
  annual win-back $14.99), the end of the sale and the local StoreKit test file are recorded in
  `git show 9def410:Docs/ai/STATE.md`, Status, and in `Docs/BILLING_AND_LIMITS.md` section 5.

## Active Constraints

- **5.6 is open in App Store Connect and in this repository** (read 2026-10-07: iOS and macOS records,
  PREPARE_FOR_SUBMISSION, release MANUAL, created 2026-10-01 by the owner). `CHANGELOG.md` opens with
  `## 5.6 <!-- unreleased -->`, so the first source push starts an Xcode Cloud build stamped 5.6. All work since 5.5
  is 5.6.
- Pushing publishes to a public repository and to gunnarguy.me. Keep the owner's personal plans out of public files.
  `CLAUDE.md` forbids deleting docs: removing one means `git mv` into `Docs/Archive/`.
- App Store Connect writes happen only at the owner's word. Guard memory on builds (18 GB Mac): `-jobs 2`, stop at
  15% free, DerivedData outside `~/Documents`. Commit to `main`, explicit paths, no AI trailer.
- The billing route forbids `StoreKitBillingService.swift`, `EntitlementStore.swift`, `QuotaPolicy.swift` and
  `StoreKitConfiguration.storekit` unless the owner names the file.

## Working Set

- The 5.6 change (`git show --stat` on the commit titled "5.6:" lists it). New source:
  `OpenIntelligence/Features/Chat/Response/CitationLinker.swift`, `OpenIntelligence/Core/Models/VerificationOutcome.swift`,
  `OpenIntelligence/Core/Models/AppleIntelligenceAvailability.swift`, `OpenIntelligence/Core/Extensions/StreamingMarkdown.swift`,
  `OpenIntelligence/Services/LLM/AnswerSentenceSplitter.swift`. Edited source: `LLMService.swift` (three cleanup
  functions), `RAGService.swift` (the Evidence-First prompt's last line, the consent clear before
  `executeAgenticQuery`, `DeviceCapabilities.foundationModelUnavailability`), `VerificationGateService.swift`
  (`runGateE`), `GroundedAnswerView.swift`, `ResponseDetailsView.swift`, `MessageBubbleV2.swift`, `MessageListV2.swift`,
  `ChatScreen.swift`, `SettingsView.swift`, `ModelStatusIndicator.swift`, `MotherboardHUDView.swift`, `ContentView.swift`,
  `WhatsNewStore.swift`. Six new test files under `OpenIntelligenceTests/`.
- `CHANGELOG.md`, section 5.6: one entry per fix with its evidence and its closing condition. Read it before the
  device run.
- `Growth/PROPOSAL_5.6.md` (local only): the proposal the ten fixes came from; parts B (screenshots, description) and
  D (phone checks) are not started.
- `Docs/LIMITATIONS.md`, `Docs/PRIVACY_AND_ROUTING.md`, `Docs/STUDY_GUIDE.md`: also carry corrections from
  2026-10-05, each with its evidence tag.
- `Growth/` (untracked, self-ignored, local only): start at `CURRENT_EXPERIMENT.md`; the five-question test is in
  `campaign/sample-package/` (`ANSWER_KEY.md`, `RUN_SHEET.md`).
- `Docs/SHIPPED_VERSION.json`: the release record the three sites read from `origin/main`.
- `Docs/BILLING_AND_LIMITS.md` sections 2 and 5: what the plans screen says, and the prices.
- `Docs/ai/RUNBOOK.md`: the three "through the API" sections (submit, pull back, release an approved version).

## Verification (2026-09-29 and 2026-09-30, output read)

- The 5.5 release checks (521 tests with 0 failures, the plans screen at three accessibility sizes, Xcode Cloud #483,
  both records READY_FOR_SALE, the price table across 28 territories) are listed in full in
  `git show 5d572a1:Docs/ai/STATE.md`. Not run then: the manual purchase and restore in the
  `OpenIntelligence-StoreKitTesting` scheme.

## Verification (2026-10-05, output read)

- `python3 scripts/verify_doc_claims.py` -> 776 claims checked, every checked claim matches source.
- Command-line probes built with `xcrun swiftc -parse-as-library` on macOS 27.0 `26A428` (sources were in a session
  scratchpad, not in the repository): `SystemLanguageModel.default.variant` -> "AFM 3 Core Advanced";
  `contextSize` -> 8192; prompts of 6,090 and 7,949 tokens answered, 9,691 refused ("exceeds the maximum allowed
  context size of 8192"); `supportedLanguages` -> the same 24 locales on-device and on Private Cloud Compute, no
  Greek; `tokenCount(for:)` -> 1.38 characters per token on a numeric table, 4.2 to 5.5 on 25 samples of recorded
  chunk text; one response's `assetIDs` -> three `com.apple.fm.language.instruct_3b` assets.
- `sh scripts/probe_afm_advanced_canary.sh` from the repository root -> "still absent from this SDK (expected)",
  exit 0. `sh ../scripts/probe_afm_advanced_canary.sh` from the same directory, the form
  `ci_scripts/ci_post_clone.sh:106` uses after its `cd ..` at line 80 -> "No such file or directory", exit 127.
- `BenchmarkRuns/2026-09-23-sourceonly-after-greedy25/results.jsonl` read: `Context budget: base=8192` in 25 of 25
  cases, `context_chars` 3,177 to 9,494 (median 9,324), structured answer generation skipped in 25 of 25.
- Not run: any build or test, because no source changed.

## Verification (2026-10-06, output read)

- A development-signed command-line probe that carried the Private Cloud Compute entitlement (source in a session
  scratchpad, not in the repository) reached PCC from an agent shell on macOS 27.0 `26A428`, at the owner's word:
  51 requests in five runs, quota "below the limit" before and after. `PrivateCloudComputeLanguageModel().contextSize`
  -> 32768; `supportsLocale(el_GR)` -> false; the first response's `assetIDs` in every run ->
  `com.apple.fm.language.instruct_server_v2.fm_api.generic_11.110003.18` and
  `com.apple.fm.language.instruct_server_v2.base_zap.generic_11.3.0`. An unsigned or ad hoc binary still gets
  `ModelManagerError Code=1046`, and `/usr/bin/fm` now refuses to run until `sudo fm license` is accepted.
- The same probe asked 16 lookup questions over 11 articles of EU directives in their official English and Greek
  text, plain text, greedy sampling. PCC: 13 of 13 answerable questions right from the English text and 13 of 13
  from the Greek text with English answers (3 of 3 unanswerable questions declined in both); with Greek questions
  and Greek answers 12 of 13 right, one request failed with "Streamed response may contain sensitive or unsafe
  content", and 1 of 3 unanswerable questions was answered anyway. On-device (`.coreAdvanced3`): 12 of 13 from the
  English text, 6 of 13 from the Greek text with English answers, and with everything in Greek 11 of 13 with all 3
  unanswerable questions answered anyway. Each PCC configuration ran once.
- `git status --porcelain` after creating `Growth/` -> the same four modified docs and nothing else, so the folder
  is invisible to git. `git diff --stat 81b66a8 HEAD -- OpenIntelligence OpenIntelligenceTests` -> four files
  (`LaunchSale.swift`, the StoreKit test file, `VersionHistory.md`, `LaunchSaleTests.swift`): no capability differs
  from build 483.
- The live US store page (`curl` of apps.apple.com/us/app/openintelligence/id6756559175, about 22:05 PT) -> In-App
  Purchases "Lifetime $49.99", "Pro Annual $24.99", "Pro Monthly $4.99"; version 5.5; iOS, iPadOS and macOS 26.0 or
  later; Data Not Collected; 4.8 from 4 ratings.
- `python3 ~/.claude/skills/gunnar-voice/lint.py` on seven local drafts -> 0 errors.
- Not run: any build or test, because no source changed.

## Verification (2026-10-07, output read)

- `xcodebuild test -scheme OpenIntelligence -destination "platform=iOS Simulator,id=0C3BBD22-E7FD-400D-8E71-6C6EDA985C4C"
  -derivedDataPath /private/tmp/oi-build -jobs 2 -collect-test-diagnostics never`, run from `/private/tmp/oi-src` (an
  rsync copy of this tree; the simulator is `OI 5.6 tests`, iOS 27.0, made that day) -> `** TEST SUCCEEDED **`,
  551 tests, 0 failures, 3 skipped (two in `EmbeddingProviderAgreementTests`, one in `LayoutReadingOrderTests`).
  The six new suites: `AnswerSentenceSplitterTests` 9, `CitationLinkerTests` 8, `VerificationOutcomeTests` 4,
  `AppleIntelligenceCopyTests` 3, `StreamingMarkdownTests` 3, `SemanticGroundingClaimTests` 3.
- The run before it -> `** TEST FAILED **`, 550 tests, 2 failures, both in `AnswerSentenceSplitterTests` and both
  fixed in `AnswerSentenceSplitter.swift` and its tests (`CHANGELOG.md`, the cleanup entry). In that run
  `testSilentAudio_FailsLoudlyInsteadOfProducingAnEmptyDocument` skipped itself after 60 s on the new simulator; it
  passed in 0.19 s in the second run. Without `-collect-test-diagnostics never`, a failing run sits in
  `simctl diagnose` for up to ten minutes after the last test.
- Promotional text: four PATCH calls to `/v1/appStoreVersionLocalizations/{id}` (5.5 and 5.6, iOS and macOS) -> 200
  each, read back equal at 08:13 PT.
- Roadmap: rows per `Target Release` counted before and after adding `v5.6` -> equal for all 20 existing options
  (296 rows); after the move `v5.6` holds 11 and `Future Backlog` 101 (was 112).
- `bash scripts/required_docs.sh` over all 46 changed paths -> every required doc is among them.
- `python3 .claude/codemap/codemap.py check` -> 0 errors, 29 warnings (the new files are not in a slice yet).
- Not run: the app on any device or simulator screen; the Mac benchmark harness; `scripts/build_simulator_smoke.sh`
  (the test run built the same app target); the five-question run in `Growth/campaign/sample-package/RUN_SHEET.md`.

## Blockers / Unknowns

- **The eleven 5.6 rows, each open until its closing condition is seen on a device** (`CHANGELOG.md` 5.6 and each
  row's "Closes when"): Just Once consent https://app.notion.com/p/3ea49a74d54f81fd814ae82ce9449e41; inline citations
  https://app.notion.com/p/3ec49a74d54f81d6980ad6deb0dc7744; no Apple Intelligence
  https://app.notion.com/p/3e449a74d54f8170a3cbfb570a41d0a5; answer cleanup
  https://app.notion.com/p/3ec49a74d54f81c99348dbe44263dbd9; Fact Check asterisks
  https://app.notion.com/p/3ec49a74d54f816c8acfcd0dcbb9c486; streaming markdown
  https://app.notion.com/p/3ec49a74d54f81958ae8f84b2db284e1; the prompt's outline
  https://app.notion.com/p/3ec49a74d54f81d2a20afe103ad55419; the Verified badge
  https://app.notion.com/p/3e749a74d54f81b1ae8bc414159799ed (5.6 has the label half only: Deep Think and Maximum
  still run no gates, and read Not Checked unless their source-only check ran); Gate E
  https://app.notion.com/p/3ed49a74d54f8186b358d123b6f22d8b (cause inferred, never logged); the hardware legend
  https://app.notion.com/p/3df49a74d54f81e3a350ff1d1d34af2b; the three wrong sample answers
  https://app.notion.com/p/3ec49a74d54f813baee7fd58e6484a32 (not re-asked; 5.6 changes two things that may bear
  on them and neither is shown to fix them).
- **No test reaches four of the fixes:** the three cleanup functions in `LLMService.swift` (private; only the
  splitter they call is tested), the consent clear in `queryInternal`, the legend's visibility, and the empty
  library's prompts. Each is read, compiled and in a passing suite, and none is exercised.
- **Left on the Mac by the test runs:** the simulator `OI 5.6 tests` (`0C3BBD22-E7FD-400D-8E71-6C6EDA985C4C`, shut
  down, no keys in it; `xcrun simctl delete` it to remove), `/private/tmp/oi-src` and `/private/tmp/oi-build`.
- **Measured 2026-10-07, the 8,192 window on the raw model** (this Mac only; logs and the probe are in
  `BenchmarkRuns/2026-10-07-context-window-probe/`, git-ignored, with a README). Time to first token grows faster
  than the prompt: 0.8 s at 935 input tokens, 2.3 s at 2,574, 5.9 s at 5,105, 10.7 s at 7,608. A second question in
  the same session reuses the cache (5,924 of 5,945 input tokens cached; 2.9 s to first token against 7.3 s fresh).
  A planted sentence with no look-alike was found 16 of 16 times up to 7,608 tokens. With two look-alike sentences
  it was 17, 14, 13 and 16 of 25 at 800, 2,000, 4,000 and 6,600 tokens of evidence, and 0 of 5 at 6,600 when both
  look-alikes came before it. When the question shared few words with its sentence, "NOT IN EXCERPTS" came back
  for 3, 4, 4 and 7 of 15. Every agentic session is a fresh `LanguageModelSession` sized in characters
  (`AgenticOrchestrator.swift:4809-4812`, `:6617`, `:8061-8062`, `:3088`), and its evidence passes a keyword filter
  first (`RAGService.extractRelevantSentences`, a sentence with no query keyword is dropped). The structured-answer
  gate is a fixed 3,600 estimated tokens (`RAGService.swift:16563-16564`). Not measured: any iPhone or iPad, the
  app's own loops, energy. Nothing was changed in the app. The owner has not said to build any of it.
- **Found 2026-10-05, not on the roadmap** (no open row matches; filing one needs the owner's yes, because rows
  feed the public page). Standard packs on-device evidence in characters at 1.4 per token with a 10,000-character
  ceiling that cannot bind at 8,192 (`RAGService.swift:12664-12735`), so on English prose it sent a median 9,324
  characters, about 2,000 tokens of an 8,192 window (tokens counted on like text; the assembled prompts were not
  saved). The structured-answer path is gated at 3,600 estimated tokens (`RAGService.swift:16556`). Deep Think and
  Maximum sessions use fixed character budgets: 3,500 or 3,000 in the chain (`AgenticOrchestrator.swift:4812`), cut
  to 2,200 after the first session (`:8059-8062`), and 2,500 in Maximum's own loop (`:6617`). A `contextSize` of 0
  drops the budget to 800 characters (six cases in `BenchmarkRuns/2026-09-23-sourceonly-before-greedy25`). The app
  reads neither `variant` nor `assetIDs`; a Private Cloud Compute response's `assetIDs` name `instruct_server_v2`
  assets and an on-device response's name `instruct_3b` (measured 2026-10-06, Verification), so reading the field
  would give outcome-based evidence of the route. The CI canary cannot run as wired (Verification above). Verify
  by reading those lines and grepping that run's `results.jsonl` for `Context budget: base=`.
- **The same stale fact, left alone 2026-10-05** (Swift, a skill file and two directive docs are outside a docs
  pass): the comment at `OpenIntelligence/Core/Models/LLMModelType.swift:86-88` ("can neither pick nor observe");
  the rows dated 2026-09-10 in `.claude/skills/apple-api-truth/SKILL.md` ("no tier or variant type in any public
  framework", "Nothing names the backend"); the header of `scripts/probe_afm_advanced_canary.sh:8-11`; the label
  "On-Device Only (4K tokens)" at `OpenIntelligence/Core/Models/LLMModel.swift:292`; `Docs/ai/ARCHITECTURE.md:126` and `Docs/ai/PROJECT.md:58`, which say the SDK exposes "no server
  context window" although `PrivateCloudComputeLanguageModel.contextSize` exists and `RAGService.swift:16299`
  reads it. `WHATS_NEW.md:286`, `Docs/USER_CHANGELOG.md:337` and `OpenIntelligence/Resources/VersionHistory.md:337`
  say it too, as history that was true when written.
- **Not measured:** `contextSize` and `variant` on an iPhone or iPad (Settings shows the window in the row "On this
  device"); a PCC response's `assetIDs` on an iPhone or under another OS release.
- **Rows that close on a device check, all Shipped On iOS and macOS.** The plans-screen row
  (https://app.notion.com/p/3ea49a74d54f817abddae36a4fcc527d) closed 2026-09-30 on the owner's iPhone screenshots of
  the App Store build ($5.99, $29.99 with $2.50 a month and 58%, $49.99 with 20 months, the prices in force that
  day). Still open: the subscription fix (https://app.notion.com/p/3ea49a74d54f8163865ff0a7c1ef55e6) after a sandbox check
  (buy Pro Monthly, Settings shows Pro, not Lifetime; let it expire and relaunch, Free); the "how much" row
  (https://app.notion.com/p/3e749a74d54f8115a76ad5b06b196956) stays open because the model still answers the lease
  question wrong.
- **The Lifetime purchase's store name: resolved.** The US App Store page listed "Lifetime $49.99" on 2026-10-06
  (Verification); it had read "Lifetime Cohort $49.99" on 2026-09-30.
- **The five-question test waits on one device run,** on the owner's iPhone
  (`Growth/campaign/sample-package/RUN_SHEET.md`): Pass A with the network on, Pass B in airplane mode.
  The run sheet checks first whether tapping a citation opens the passage
  (the carried item below). Two public claims get their first check on build 483 in that run: that the
  app says so when the files lack the answer (`Docs/EVALS.md:349` records 2 of 5 on external questions, 2026-08-12),
  and "Offline" in the store subtitle (no recorded airplane-mode test of build 483 was found). Neither was edited.
- **Before the next Lifetime sale:** the $49.99 price has two USD prices (49.99 in 87 territories, 59.99 in 22) and two
  EUR prices (59.99 in 24, 49.99 in Montenegro), and `LaunchSale` keys by currency, so a sale window would show
  Montenegro a false discount. No build is exposed (the only window closed 2026-09-30). Row, Future Backlog:
  https://app.notion.com/p/3ea49a74d54f81a9867ffbf641a2ccbb
- **Privacy row open:** https://app.notion.com/p/3e949a74d54f81b79775e99953132f98; the published policy still says
  PCC gets data for final synthesis only.
- **Public Private Cloud Compute wording, the owner's call:** `README.md:30-32`, `Docs/SHIPPED_CAPABILITIES.json:102`,
  `Docs/PRIVACY_AND_ROUTING.md:116`, `Docs/ai/ARCHITECTURE.md:113-114` and `CLAUDE.md:7` imply only the final answer
  can reach PCC; with PCC chosen in the picker, Deep Think and Maximum's reasoning passes can go too
  (`AgenticOrchestrator.swift:9000-9014`).
- **Future Backlog rows filed 2026-09-29** (the "Just Once" consent row filed with them is on `v5.6` now, above):
  Settings lists 4 tool functions, 6 run
  (https://app.notion.com/p/3ea49a74d54f8167a9b3d92c94539567); iOS 26 Settings blames the build for PCC
  (https://app.notion.com/p/3ea49a74d54f8126a005f0a27a318498); MMR lambda never read
  (https://app.notion.com/p/3ea49a74d54f817ab4bcf5bb6ad07509); sentence-opening words become entities
  (https://app.notion.com/p/3ea49a74d54f81059b20e8bda0663798).
- **Carried:** six `v5.4` rows close on the owner's device check (URLs in `git show 8be003a:Docs/ai/STATE.md`);
  Evidence Threads sync may copy nothing (`EvidenceThreadStore.swift:60` against `WorkspaceSyncService.swift:2739`).
- **Unverified, needs a device:** source chips may not open anything (`ChatScreen.swift:901`,
  `RAGService.swift:17623`). Inline citations were rewritten for 5.6 (`CitationLinker`) and have not been tapped.
- **Owner decisions left open:** six Google Ads scripts with no copy elsewhere; the 28 Swift files no other file
  names; `THIRD_PARTY_NOTICES.md` lacks the Rust crates swift-tokenizers links; `Docs/RepoOS/01_TASK_ROUTER.md:9`
  cites playbook 07.

## Exact Next Action

1. The owner runs the asset upload from the repository root, or says how else he wants it done:
   `ruby Growth/store-assets-5.6/asc_assets_upload.rb Growth/store-assets-5.6/header-A-answer-centered.png Growth/store-assets-5.6/search-A-answer.png --apply`
2. He installs 5.6 (484) on his iPhone from TestFlight. He runs
   `Growth/campaign/sample-package/RUN_SHEET.md` plus the closing condition of each of the eleven rows, and reads
   the window in Settings, "On this device". Nothing closes on the suite alone.
3. Still unanswered: for the token budget, `PROCEED: IMPLEMENT` naming `FoundationModelTokenBudget.swift`, and
   whether it joins 5.6 or the release after.
