# Current State

Updated: 2026-10-09, night (5.7 is open; batches one to four are `af7aaf9`; the fifth, sixth and seventh, two controls rebuilt as the app's own, and the fix for a large text import that froze the owner's iPhone until iOS ended the app are in the commit after it, pushed with `[ci skip]`; that tree is on his iPhone as a development build; 5.6 has been live on iPhone, iPad and Mac since 2026-10-08, 13:18 PT, build 485 from `2bee971`)
Branch/worktree: `main`, primary checkout
Last verified commit: af7aaf9

## Objective

**5.7: JSON Lines import and the Apple surfaces that carry the app to other apps and people (Share Sheet,
Shortcuts, App Intents). The owner wants it mainly for iPhone and iPad, and as complete as it can be made.** He named it
on 2026-10-08 and put 81 rows on `v5.7` in the roadmap that day (82 since a defect found on 10-09 was added). On
2026-10-09 he said "proceed: implement", then "keep going", and named the protected files (see Active
Constraints). `CHANGELOG.md` opens with `## 5.7 <!-- unreleased -->`, so the next source push builds 5.7. He created the
5.7 records in App Store Connect on 2026-10-09 (both platforms, PREPARE_FOR_SUBMISSION, release MANUAL, read back
through the API that afternoon).

On 2026-10-09, shown the list of what was next, he said the work was not done while the Apple model APIs the
sweep had found were untouched. So the rows about the on-device model, speech, image input, Core AI and
Evaluations are part of 5.7 too, and the sixth batch below is the first pass over them.

5.6 ("the first five minutes") is live. Its device checks are still open and are listed under Exact Next Action.

Also local and not started: a small marketing test whose notes are in `Growth/` (git-ignored; start at
`Growth/CURRENT_EXPERIMENT.md`).

## Status

- **2026-10-09, 5.7: seven batches written, built, tested and committed with `[ci skip]`. One thing has been seen
  on a device, and it was a crash: an 88.50 MB `.jsonl` froze the app during import and iOS ended it (below).** One
  entry per change is in `CHANGELOG.md` under 5.7, each with what was read, built or tested. Of the 83 rows on
  `v5.7`, 42 are `In Progress` and 41 `To Do`, none `Completed` (read from the roadmap on 2026-10-09, night; the
  83rd is the import crash; each row carries a dated note and what closes it). A defect the new
  evaluation suite found is filed on `Future Backlog`:
  https://app.notion.com/p/3f449a74d54f812d9685f440b8fead30 . The first four groups are `af7aaf9`; the rest is the commit after it:
  - **Import.** `.json`, `.jsonl` and `.ndjson` import as one passage per record, with the file's order and digits
    kept (`JSONRecordExtractor`, its own reader). The app is offered files by other apps (`Info.plist` document
    types and a declared `.jsonl` type; `ContentView.importOpenedFile`). "Save a Web Page" downloads the page
    (`WebPageFetchService`). A passage over the embedding limit is no longer retyped when cut
    (`OversizedChunkSplitter`; this defect predates 5.7 and has its own row).
  - **Shortcuts and Siri.** 22 actions in the built metadata (5.6: 16), 15 returning a value (5.6: 0), 10 App
    Shortcuts (5.6: 9). `RAGAppIntents.swift` is rewritten around one `AskActionRunner`: an answer item as the
    result, thrown errors, the engine's default generation settings, and on "Ask My Documents" and "Ask a
    Library" a mode menu with the free plan's Maximum allowance. "Ask About a Document", Summarize and Compare
    run in Standard, are searched inside their documents (`RAGQueryScope`, applied in `HybridSearchService.search`
    and four places in `RAGService.swift`), and the runner refuses an answer whose passages are not all theirs.
    The ask actions build their own engine per question; the other actions use the app's when it is open. New actions: Find Passages,
    Add to Library, Create Library, Set Active Library, Open Library, Open Document. Every action takes its engine
    from `IntentSupport.engine()` unless it asks a question. Items carry properties; answers, passages and conversations are items.
  - **In the app.** A router (`AppLink`, `AppNavigationRequest`, `ContentView.route`) that links, Spotlight results
    and actions all go through; a Spotlight result opens the tapped item's library; "Add a Document" opens the
    picker and "Scan a Document" the camera. A shared answer lists its sources; Export Conversation (Markdown, JSON
    Lines); Copy works on the Mac; Settings lists the phrases and actions that exist.
  - **Answers.** Evidence sentences are not cut at a line break or after "p.m." (`EvidenceLineSplitter`).
  - **Fifth batch:** menu and keyboard commands for the Mac and iPad, and Home
    Screen quick actions (Ask, Add Document, Scan Document), which gave the app a delegate for the first time.
  - **Sixth batch (2026-10-09, afternoon and evening).** Each has an entry in `CHANGELOG.md` under 5.7.
    - *Answers.* A number is checked as a value (`NumericValueExtractor`; Gate C, the claim check and the
      source-only check): the "2.5 billion" answer no longer passes on "Qwen-2.5-3B". What failed in a generation
      is read from the error's type (`ModelErrorClassifier`): only a real overflow shrinks a Deep Think prompt,
      and an unreadable response is retried.
    - *Import.* Paste on the Documents screen (file, web address, text, a copied PDF or picture). Recordings go
      to Apple's `SpeechTranscriber` first; the code for it had never compiled. The model is shown the picture it
      describes (iOS 27, macOS 27). The Core AI embedding model is prepared after launch when the system's
      cache has no entry for it.
    - *App.* A notification when an import or a 20-second answer finishes in the background (off by default, new
      Notifications page in Settings). Redeem a Code on the plans sheet. Apple's Siri tip on the empty Chat
      screen. Imports and the two reasoning loops space themselves out when iOS 27 asks apps to scale back.
    - *Tests.* A first suite on Apple's Evaluations framework grades the claim check on seventeen labelled
      sentences (`ClaimCheckEvaluationTests`); four are known gaps of the word-and-number check.
    - *Measured and left alone* (`Docs/ai/DECISIONS.md`, 2026-10-09; probes in
      `BenchmarkRuns/2026-10-09-session-cache-probe/`, local): `prewarm` caches nothing, so Deep Think is not
      reordered; question translation already defaults to high fidelity; the build has no deprecation warning,
      and `BGTaskScheduler.submit` is left; the default transcript policy already reverts a failed turn. A change
      that made an answer's token figure Apple's count was withdrawn: two agentic loops budget on that figure.
    - *Two reviewing passes* (16 and 12 findings). Fixed: ranges that share a scale word, time and dose ranges
      read as codes, comma lists, a scale word after a sentence end, "M3" matching 3, the token figure's unit,
      the cloud error type named outside `EntitlementChecker` (now not named), a reconcile after every closed
      redeem sheet, a screenshot's file name, the speech path's permission, cancellation and empty result, the
      image request sharing the fallback's session, and the warm-up's gates. The fixes have had no third pass.
  - **Seventh batch (2026-10-09, evening).** A destination and a link for a library's search
    (`openintelligence://documents/search`); the commands Find in Library, Next Library and Previous Library
    (`AppCommands.swift`, `LibrarySwitching`); "Ask About an Image" and "Search with a Photo" return a string and
    throw on failure, as the other actions do.
  - **Two controls rebuilt as the app's own (2026-10-09; the owner said that evening that anything added has to
    match the app's existing controls).** Paste on the Documents screen is the screen's own chip: `LibraryPasteButton`
    is a plain button that takes `DocumentActionChipLabel` as its label and reads the clipboard itself, so iOS asks
    "Allow Paste" for content copied in another app, which the system `PasteButton` it replaced did not. The
    Notifications card in Settings uses the Apple Intelligence card's header and switch row. Apple's `SiriTipView` on
    the empty Chat screen is drawn by the system and cannot be restyled.
  - **A large text import froze his iPhone and iOS ended the app (2026-10-09, 16:34 PT); changed in the tree the same
    night.** Row https://app.notion.com/p/3f549a74d54f8154b822e4eee927a961 (`v5.7`, In Progress). Read from the
    phone's crash report and `pipeline_trace.log`: termination 0x8BADF00D (scene-update watchdog) with the main
    thread in `SemanticChunker.findOptimalChunkRange`; text cleanup held the main thread 57 s and the chunker's
    passes 52 s before a chunk loop that took 2.2 s a chunk. Three causes, three changes: (1) the chunker split and
    measured the rest of the text for every chunk, now bounded, with the chunks unchanged (75 runs before and after,
    7,719 chunks, same SHA-256); (2) cleanup and the fallback chunker ran on the main actor, now on the concurrent
    pool with a "Chunking 42% (1,250 passages)" status and a working Cancel; (3) the chunker stopped at 50,000
    chunks without a word, now `DocumentProcessingError.tooManyPassages` with a message, and for a text over about
    31 MB the words are counted first so the refusal comes before cleanup. Harness, outputs and the two device
    reports: `BenchmarkRuns/2026-10-09-chunker-large-text/` (local, git-ignored). **His 88.50 MB file is expected to
    be refused by the new build, not imported** (over the 64 MB JSON reader limit, so it is read as text, and by
    estimate over the chunk limit). Whether to split, stream or raise the limit is his decision:
    https://app.notion.com/p/3f549a74d54f81998d02e74ec246580e .
  - **A reviewing pass over the import and paste changes reported 14 things; the confirmed ones are fixed in the
    commit.** A progress status sent to both handlers moved the queue item between two stages on every report
    (a haptic, a saved queue and a Live Activity update each time): now through the rich handler alone, once per
    percent. A cancel during chunking left the stored full text behind: now removed. The limit was flagged when only
    overlap was left: now only when words are left. Also the cancellation test, the Mac paste's file and TIFF
    handling, `stage` copying files on the main actor, the card's stale warning. Left open and filed: whole-document
    passes still on the main actor (https://app.notion.com/p/3f549a74d54f8199aecbf625884285a5), and, seen in passing
    and not run, a large PDF's page rows (https://app.notion.com/p/3f549a74d54f8178ad55d3d273cc832a).
  - **The owner's iPhone carries a development build of the committed tree** (5.7, build 150, Debug, installed with
    `devicectl` on 2026-10-09 at about 17:52 PT, not launched; it replaced the build of 16:25 PT and keeps his
    libraries). The import queue on the phone still holds the 88.50 MB file, waiting for his answer to "resume". No
    screen of this build has been looked at: the device checks under Exact Next Action are his to run on it.
  - **`RAGService.swift` was edited in seven places in `af7aaf9`, and in two more in the sixth batch**
    (`isContextOverflowError` and the rate-limit block of `generateWithFallback`; the owner did not name this file, and
    the RepoOS boundaries file lists it as behaviour-critical): the two evidence-splitter calls, the plan lookup in
    `createNewThread`, the self-registration in its initializer, the library context in `executeAgenticQuery`, the
    query-cache conditions, the document scope after retrieval, and three candidate lists narrowed to the scope.
  - **Two reviewing passes found 16 and 24 things; what was confirmed is fixed in the tree.** The first: the
    retyped passages, the JSON reader's order and digits, the line-join rule, the fetch, Add to Library's failures.
    The second: the document scope leaked in Standard and did nothing in Deep Think and Maximum (now applied at
    the search layer, and those actions run in Standard), the request to open a screen could be replayed or lost
    (now a queue), several files sent together kept only the last, a changelog replacement had damaged three old
    entries (restored), plus smaller ones. The fixes themselves have had no third pass.
  - **Not done yet from 5.7:** the background inference entitlement; long-running and cancellable actions;
    answer cards with buttons; the Share Sheet extension, widgets and controls (new targets); PDF export; an action that
    checks a sentence against a library (it needs the model to judge meaning: the word-and-number check reads a
    flipped "not" as Supported); a model profile per mode and the OCR tool (both go through
    `FoundationModelSessionFactory.swift`, which he has not named); a model-graded evaluation. The roadmap's
    `To Do` rows on `v5.7` are the list.
  - **Open questions:** no scoped question has been run, so the document limit rests on reading the code and on
    the action's last check; the document limit of an engine built while the app is closed still falls back to the
    free limit; App Store validation of the new document types is untested; the 16 MB cap on a `.json` file and how
    often a passage exceeds the embedding limit are unmeasured.
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
- **5.6 is live on both platforms since 2026-10-08, 13:18 PT, build 485.** Apple approved both that day
  (PENDING_DEVELOPER_RELEASE, release MANUAL). The owner said "go ahead and release them"; POST
  `/v1/appStoreVersionReleaseRequests` returned 201 for macOS at 13:18:29 PT and iOS at 13:18:35 PT, and both
  records read READY_FOR_SALE with build 485 seconds later. `Docs/SHIPPED_VERSION.json` says `app_store` 5.6.
  No next version is open: the next source push needs a `## 5.7` heading in `CHANGELOG.md` first, or Xcode Cloud
  stamps the released 5.6. He released knowing the device checks below are open.
- **After the release, same afternoon:** the release record is commit `4c139e0` (pushed; no Xcode Cloud run
  started, #485 is still the newest). GitHub release `v5.6.0` is published as Latest at `2bee971`. `Shipped On`
  reads iOS and macOS on twelve of the thirteen `v5.6` roadmap rows; the wrong-sample-answers row is left empty
  because no fix for it is shown. All thirteen stay In Progress. The three websites pick 5.6 up on their next
  scheduled run; nobody triggered them. The in-app version history inside build 485 still heads the section
  "v5.6 - unreleased" (`OpenIntelligence/Resources/VersionHistory.md:10`, a byte-identical mirror of
  `Docs/USER_CHANGELOG.md`); changing it is a source change and needs a 5.7 heading first.
- **The repository stays public and MIT (owner's decision, 2026-10-08)** after he looked at the numbers: 38 unique
  page visitors and about 130 outside unique cloners in 14 days, 25 stars and 4 forks in a year, none with work of
  its own. A daily launchd job on this Mac now saves GitHub's traffic to
  `~/.agents/data/github-traffic/OpenIntelligence.csv` (`~/.agents/MACHINE-MAP.md`, section 5).
- **Untracked and not from this session:** `.agents/skills/`, `.codex/hooks.json` and `.codex/hooks/` appeared on
  2026-10-08 at 09:17. Left alone.
- **How it got to review (2026-10-07 21:51 PT, build 485, release MANUAL).** The owner said, in his
  Demos session (PostDesk), "update all of the ASC metadata ... and get it into review for both MacOS and iOS", and
  that session did it by the runbook: `asc_prepare_release.rb 5.6 485 --apply` (build attached, What's New,
  description and keywords written), `asc_listing_extras.rb 5.6 --apply` (App Review notes, `fastlane/review_notes/5.6.txt`;
  nothing else changed), then one reviewSubmission per platform: iOS `bb5c00b8-1ba3-40f4-859a-e6fb8b449a39`, macOS
  `af0c0bb9-5e6d-4c06-a945-fdfd1140cc49`, each read back WAITING_FOR_REVIEW. The store notes are the ten-fix draft plus
  one section, YOUR LIBRARY, for the rebuild-banner fix (seen in the owner's iPhone log that evening). The Deep Think
  change is not in store copy. **Not done, and his to know before he presses release:** the ten original fixes have
  no device run sheet, and the in-app What's New compiled into 485 does not mention the rebuild-banner fix or the
  Deep Think change. Pulling it back is one PATCH per submission with `canceled: true` (RUNBOOK). The picked header
  and search result images are still not uploaded; Apple's help page says assets can be submitted on their own later.
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
- **Committed and pushed 2026-10-07 19:42 PT at the owner's word ("commit and push"): `2bee971`,** the
  rebuild-banner fix and the token-budget change in one commit. Xcode Cloud #485 from it succeeded (19:42 to 19:54 PT);
  build 485 is in App Store Connect as 5.6 for iOS and macOS, VALID and IN_BETA_TESTING (read 20:02 PT).
- **The owner's iPhone carries a development build of `2bee971`** (installed 20:00 PT with `devicectl`, Debug,
  `MARKETING_VERSION=5.6`). The build before it (18:27 PT) lacked the fix for a new library's fingerprint.
- **Token budget, first part: written 2026-10-07 at the owner's word ("proceed implement"), in `2bee971`.** Row
  https://app.notion.com/p/3f249a74d54f815cbbd3c2e1c492dfd7 is on `v5.6`, In Progress. He did not say which
  release; with 5.6 unsubmitted it is part of 5.6 (build 485). New
  `OpenIntelligence/Services/Agentic/SessionEvidencePlan.swift` (budget, chunk cap and window arithmetic; one
  exact `tokenCount(for:)` a chunk for the first 56) and edits in `AgenticOrchestrator.swift`:
  `executeReasoningChain` plans each window in tokens against the live window and reads whole chunks when a
  window holds at least as many chunks as the character-sized one would; `buildChainPrompt` takes
  `wholeChunkContext` and then skips its 4,000 and 2,200 character cuts; the overflow retry rebuilds a
  whole-chunk session from sentence extraction. The old path stays for: no exact count, chunks too large, modes
  other than Deep Think and Maximum's chain, and the picker set to PCC. **Maximum's own loop
  (`executeTrueUnlimitedReasoning`) is unchanged**; a first draft edited it and a refuting review showed it would
  have generated for windows the loop skips today. `FoundationModelTokenBudget.swift` was not edited: the owner
  did not name it and the change did not need it. **Left out on purpose:** the structured-answer limit
  (`RAGService.swift:16563`) and passage order. Both change every Standard answer on an 8,192 window,
  `generateStructuredRAGAnswer` throws with no fallback to plain generation, and neither has a measurement.
- **What the review left open** (its other findings are fixed): the overflow test is a substring match on the
  error text (`AgenticOrchestrator.swift`, "context overflow, retry"); an error after ten or more streamed
  characters is returned as a partial answer and never reaches that retry (`RAGService.swift:16649-16688`);
  neighbouring chunks' parent passages can repeat text that sentence extraction used to remove; the chain's
  summary log still prints the old chunks-per-session figure.
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

- **5.7 is open in this repository and in App Store Connect.** `CHANGELOG.md` opens with
  `## 5.7 <!-- unreleased -->`, so the first source push without `[ci skip]` starts an Xcode Cloud build stamped
  5.7, and the owner created the 5.7 records for it on 2026-10-09 (both platforms, Prepare for Submission). No
  such push has been made: ask him before sending one. All work since 5.6 is 5.7.
- Hard-boundary files are edited only when the owner names the file. **For 5.7 he named these on 2026-10-09**, asked
  with the four by name and approving all of them on the condition that nothing is left broken: `RAGAppIntents.swift`, `Info.plist`, `OpenIntelligence.entitlements` with
  `EngineSDKCompatibility.swift`, and `project.pbxproj`. That is for 5.7's roadmap rows and no other work. Not named:
  `ChatMessage.swift`, `WorkspaceSyncService.swift`, the billing files, the storage formats,
  `FoundationModelSessionFactory.swift` and `FoundationModelRoutePolicy.swift`. Edited in the sixth batch without
  being named, each disclosed in the changelog: `RAGService.swift` (two hunks), `FoundationModelErrorMapper.swift`
  (messages moved to shared constants), `ImageUnderstandingService.swift`, `SpeechAnalyzerService.swift`. The
  embedding providers were not edited. A new file under
  `Services/Agentic` compiles into the app and into the iOS-only engine, and under the engine it cannot name
  anything in `RAGAppIntents.swift`, `App/`, `Features/` or `UI/`.
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

## Verification (2026-10-09, night, the committed tree, output read)

Same method as the block below. This is the third run of the night; no Swift file or bundled resource changed after it.

- `xcodebuild build-for-testing -scheme OpenIntelligence -destination "platform=iOS Simulator,id=55AFFA2C-..."` -> TEST BUILD SUCCEEDED. No warning names a file changed that night.
- `xcodebuild test-without-building`, same destination -> 736 XCTest tests, 0 failures, 3 skipped (the same three as below). Swift Testing, same run: 1 test in 1 suite passed. `SemanticChunkerLargeTextTests` (17 tests) and `LibrarySwitchingTests` (2) are new in this run.
- `xcodebuild build -scheme OpenIntelligence -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` -> BUILD SUCCEEDED, no warning in a file changed that night, no deprecation warning.
- `xcodebuild build ... -configuration Debug -destination 'generic/platform=iOS' -jobs 1 -allowProvisioningUpdates MARKETING_VERSION=5.7` -> BUILD SUCCEEDED; `xcrun devicectl device install app` printed the bundle id and an installation URL, and `devicectl device info apps` lists OpenIntelligence 5.7 (150). An earlier build of that night (the crash fix without the review's fixes) had been installed at 17:31 PT and was replaced by this one.
- The chunker alone, in a harness (`BenchmarkRuns/2026-10-09-chunker-large-text/`, local: `build.sh new`, then `SWIFT_DETERMINISTIC_HASHING=1 ./new/harness golden`): 75 runs, 7,719 chunks, digests identical to the chunker at `af7aaf9`; the repository file is byte-identical to the file the harness compiled (`patch_chunker.py` applied to the `af7aaf9` file). `./harness time jsonl <characters>` on this Mac (M3 Pro), before and after: 5.08 and 3.22 s at 0.5 million characters, 13.94 and 6.47 s at 1 million, 42.41 and 13.30 s at 2 million, 148.52 and 26.38 s at 4 million. The timings are from the first version of the change; the later edits (limit, progress, cancel checks) were not re-timed.
- From the phone, with `xcrun devicectl device copy from` (crash logs domain, and the app's data container): `OpenIntelligence-2026-10-09-163430.ips` (FRONTBOARD 0x8BADF00D, scene-update watchdog, main thread in `SemanticChunker.findOptimalChunkRange`), a CPU report from 16:33 (footprint up to 2,858.84 MB), and the stage times in `pipeline_trace.log` (read for those lines only).
- `python3 scripts/verify_doc_claims.py` -> all checked claims match. `python3 scripts/secret_scan.py` -> clean. `python3 .claude/codemap/codemap.py check` -> 0 errors, 0 warnings. `cmp Docs/USER_CHANGELOG.md OpenIntelligence/Resources/VersionHistory.md` -> identical. `scripts/check_icloud_conflicts.sh` -> no damage.
- Not verified: anything on a screen. The new build has not been opened; no file has been imported with it.

## Verification (2026-10-09, evening, the fifth and sixth batches, output read)

Same method as the block below: a copy of the tree at `/private/tmp/oi-src`, DerivedData `/private/tmp/oi-build`,
`-jobs 1`, the memory and disk guard, simulator `OI 5.7 tests` `55AFFA2C-C616-42A2-8227-2E16792B54DD`, left shut down.
This is the last run, after both reviewing passes' fixes; no Swift file or bundled resource changed after it.

- `xcodebuild build-for-testing -scheme OpenIntelligence -destination "platform=iOS Simulator,id=55AFFA2C-..."` -> TEST BUILD SUCCEEDED.
- `xcodebuild test-without-building`, same destination -> 717 XCTest tests, 0 failures, 3 skipped (the same three as below). Swift Testing, same run: 1 test in 1 suite passed (`ClaimCheckEvaluationTests`; it printed "agrees overall: 0.76 over 17 sentences", which is the thirteen it asserts plus four labelled known gaps).
- `xcodebuild build -scheme OpenIntelligence -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` -> BUILD SUCCEEDED. No warning in either log names a file added in these batches, and neither log holds a deprecation warning.
- `python3 scripts/verify_doc_claims.py` -> all checked claims match. `python3 scripts/secret_scan.py` -> clean. `python3 .claude/codemap/codemap.py check` -> 0 errors, 0 warnings. `cmp Docs/USER_CHANGELOG.md OpenIntelligence/Resources/VersionHistory.md` -> identical. `scripts/check_icloud_conflicts.sh` -> no damage.
- Command-line probes on this Mac (macOS 27.0), sources and a results file in `BenchmarkRuns/2026-10-09-session-cache-probe/` (local): `prewarm` and the session cache, the transcript policy, an image in a prompt, the translation strategy, the Core AI cache, `SpeechTranscriber`, each Foundation Models error's text.
- `xcodebuild build ... -configuration Debug -destination 'generic/platform=iOS' -jobs 1 -allowProvisioningUpdates MARKETING_VERSION=5.7` -> BUILD SUCCEEDED (the first device build of this tree, so the Core AI branches compiled for the first time); `xcrun devicectl device install app` -> "App installed"; `devicectl device process launch` -> launched; `devicectl device info apps` -> OpenIntelligence 5.7 (150).
- In the simulator the new speech path steps aside (`[SpeechAnalyzer] Not used for silence.wav: using the older recognizer` in the test log), the model does not generate, and the SDK has no Core AI. So these are compiled and unit-tested only: the transcriber in the app, the image description request, the embedding warm-up, every error-recovery path, the notification, the paste button, the redeem sheet, the Siri tip.

## Verification (2026-10-09, output read)

All from a copy of the tree at `/private/tmp/oi-src`, DerivedData `/private/tmp/oi-build`, `-jobs 1` (because
`RAGService.swift` changed), under a guard that stops the build under 15% free memory or 3.5 GB free disk. The
simulator is `OI 5.7 tests` `55AFFA2C-C616-42A2-8227-2E16792B54DD` (iPhone 18 Pro, iOS 27.0, made that day, no keys
in it, left shut down).

- `xcodebuild build-for-testing -scheme OpenIntelligence -destination "platform=iOS Simulator,id=55AFFA2C-..."` -> TEST BUILD SUCCEEDED (last run after the `project.pbxproj` edit).
- `xcodebuild test-without-building`, same destination, `-collect-test-diagnostics never` -> 670 tests, 0 failures, 3 skipped (the two `EmbeddingProviderAgreementTests` and the interleaved-stream case of `LayoutReadingOrderTests`, which skip themselves). This is the run after the second review's fixes.
- `Metadata.appintents/extract.actionsdata` in the simulator product -> 22 actions (5.6: 16), 15 with an output type (5.6: 0), 5 item types (5.6: 2), 1 enum, 10 App Shortcuts with 27 phrases (5.6: 9 with 23). The Mac product lists 21: "Scan a Document" is iPhone and iPad only.
- The merged `Info.plist` in the simulator product -> holds `CFBundleDocumentTypes`, `UTImportedTypeDeclarations` and `LSSupportsOpeningDocumentsInPlace` false.
- `xcodebuild build -scheme OpenIntelligence -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO` -> BUILD SUCCEEDED, after two failures on the open-in-place key (see the 5.7 changelog entry on document types); the Mac product's `Info.plist` holds the document types and the key as true.
- `python3 scripts/verify_doc_claims.py` -> all checked claims match. `python3 scripts/secret_scan.py` -> clean. `python3 .claude/codemap/codemap.py check` -> 0 errors, 0 warnings. `cmp Docs/USER_CHANGELOG.md OpenIntelligence/Resources/VersionHistory.md` -> identical.
- Not run: any action from Shortcuts or Siri; the web download; "Open in" from another app; the document picker with a `.jsonl` file; Copy on a Mac build; any question, scoped or not, before and after these changes.

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

## Verification (2026-10-07, afternoon, output read)

- Full suite on the iOS 27.0 simulator from `/private/tmp/oi-src` with the token-budget change as it stands ->
  `** TEST SUCCEEDED **`, 568 tests, 0 failures, 3 skipped; `SessionEvidencePlanTests` 17 of 17. Two earlier
  drafts also passed (565 tests), and one draft failed to compile (`activeUserRoutingPreference` is on
  `RAGService`).
- A command-line probe on this Mac -> `tokenCount(for:)` succeeds for one chunk (338 tokens for 1,776
  characters); 20 chunks at three counts each in parallel took 4.9 s with the test suite running beside it, which
  is why the plan makes one count a chunk.
- `xcodebuild build ... -destination 'generic/platform=iOS' ... MARKETING_VERSION=5.6` from `1fbebfe` -> `** BUILD
  SUCCEEDED **`; `devicectl device install app` -> installed on the iPhone.
- Xcode Cloud #484 -> SUCCEEDED; build 484 VALID and IN_BETA_TESTING for iOS and macOS.
- Not run: the token-budget change on any device or in the app at all. The simulator does not generate, so no
  Deep Think session has executed this code.

## Verification (2026-10-07, evening, output read)

- Full suite with the corrected rebuild-banner fix and the token-budget change, built with `-jobs 1` and run with
  `xcodebuild test-without-building` on simulator `EA066452-42A3-4B39-8391-2234C4669313` -> `** TEST EXECUTE
  SUCCEEDED **`, 578 tests, 0 failures, 4 skipped; `RebuildFalseAlarmTests` 10 of 10, `SessionEvidencePlanTests`
  17 of 17. Two test simulators were deleted from outside this session during the evening, one of them between a
  build finishing and its tests starting ("No matching device").
- A Python recomputation of the fingerprint (sha256 of the key, "tokenizer:" and the bundled `tokenizer.json`,
  16 hex) reproduced all four values in the phone's log: `69f06c6c23035978` = Core ML with `default`,
  `3236a5aa2cfabb78` = Core AI with `default`, `b8ea469f52cf5f2b` = Core ML with `balanced/300`,
  `0ca10df0aa1a2d84` = Core AI with `densePrecision/320`.
- The phone's trace log, copied three times with `xcrun devicectl device copy from`: 18:32:04 recorded, 18:32:42
  flagged (first fix), reloads at 18:48:51, 18:48:53, 19:11:39, 19:11:50 and 19:18:18, question at 19:18:38 with
  no flag.
- The phone's trace log copied a fourth time, about 21:40 PT (last line 20:55:59), from the build of `2bee971`:
  20:52:22 "Recorded embedding fingerprint" for a new library, four Standard questions from 20:53:17 to 20:55:54,
  no "Embedding pipeline changed" line after 18:32:42 in the whole file, and no "whole chunks" line (no Deep Think
  question was asked). `QUERY COMPLETE: 0 chars` is printed for every answer on both builds; the answer's size is
  the `Response length:` line above it.
- A GET-only read of the app's `appStoreVersions` at 21:54 PT -> 5.6 `IOS` and `MAC_OS` both `WAITING_FOR_REVIEW`,
  release `MANUAL`; 5.5 `READY_FOR_DISTRIBUTION`.
- A run with `-jobs 2` was killed by the guard when swap took the disk from 11 GB free to 0: `RAGService.swift`
  compiles in both targets. Use `-jobs 1` after any edit to that file.

## Blockers / Unknowns

- **The large-text import change has not been seen on a device.** Row
  https://app.notion.com/p/3f549a74d54f8154b822e4eee927a961 . What would close it: on his iPhone, a text or `.jsonl`
  file of 1 to 20 MB imports with the status moving ("Chunking N%"), the screen responding and Cancel stopping it;
  and the 88.50 MB file ends in the "too long" message instead of a freeze. Read the stage times afterwards from
  `Documents/pipeline_trace.log` (the devicectl commands are in the memory note on building to his iPhone).
  Known to remain: the heading, topic and table passes are as slow as before (30 s, 17 s and 4.6 s on that file),
  now off the main thread; the token-limit and coverage checks are still whole passes on the main actor; a cancel
  after chunking still leaves the stored text.
- **The background inference entitlement cannot be proved from this session.** The device build that would change
  provisioning for the new key was refused by the session's permission check on 2026-10-09 ("Protected-Scope IaC
  Apply"). `OpenIntelligence.entitlements` is as at `af7aaf9`. The owner runs that build himself or says how he
  wants it done. Row https://app.notion.com/p/3f449a74d54f81cc9f9dce8a309ac45c , `To Do`.
- **No 5.7 build has been sent to TestFlight.** Every 5.7 push carried `[ci skip]`, the last one because the tree
  held a crash fix nobody had seen work. A push without it starts the first 5.7 Xcode Cloud build.

- **Rebuild banner on a healthy library ("This library needs its search index rebuilt" after an import and one
  question, and again after Rebuild): fixed 2026-10-07 at the owner's word. Both causes that fired in his iPhone's log are now seen fixed in it; three
  checks still keep the row open (end of this entry).** Row
  https://app.notion.com/p/3f249a74d54f81069664e9431e2e687e , `v5.6`, In Progress. Three causes, all in code
  unchanged since the live 5.5, named by recomputing the fingerprints in his `Documents/pipeline_trace.log` from the
  bundled tokenizer. (1) `stampEmbeddingFingerprintIfAbsent` recorded a new library from the app's default service
  (Core ML) while `resolveEmbeddingContext` compares against the library's own (Core AI on iOS 27), so every new
  Core AI library was flagged on its first question. Both now use `fingerprintService(for:)`. (2) The chunker term
  held the app's own tuning; `EmbeddingFingerprint.chunkerRecipe` now counts only a manual directive. (3) A stored
  fingerprint was gone after `ContainerService.reloadFromDisk`; saves of the library list now go through one serial
  queue and the fingerprint is also kept in a device-local `UserDefaults` record. `WorkspaceSyncService.swift` was
  not edited (not named); its `mergeContainer` still does not carry the fingerprint. **On the phone:** the first
  build of this fix (18:27 PT) had (2) and (3) only. A new library was flagged again at 18:32:42, which is how (1)
  was found; the same library's fingerprint then survived three Documents reloads and a relaunch, and a question at
  19:18:38 raised nothing, so (3) held. On the build of `2bee971` (installed 20:00 PT) he made a new library at
  20:52:22 ("Recorded embedding fingerprint") and asked four Standard questions from 20:53:17 to 20:55:54 with no
  "Embedding pipeline changed" line, so (1) held (log copied about 21:40 PT, last line 20:55:59). **Not seen yet:**
  an import into an existing library plus one question; Rebuild on a library that predates the fingerprint, then a
  reload; and the Documents tab itself without the banner (the log shows the flag was not raised, and nobody has
  reported the tab). The copied phone logs are in a session
  scratchpad and hold his questions and file names: do not commit them.
- **The Simulator's Gate E failures are an artifact: the Simulator library holds all-zero vectors (measured
  2026-10-08, 08:15 PT).** The Demos session's filming takes of a demo build of `2bee971` (iPhone 18 Pro Max
  Simulator `565CCB67`, a new Home library of the ten sample documents) showed "Verification failed: Gate E:
  Semantic Grounding" under 9 of 11 Standard answers and Unverified on all 11, right answers with every Fact Check
  row SUPPORTED included (screen dumps in `/private/tmp/oi56-takes/*.xcodebuild.log`). That library's
  `vector_database_<id>_vectors.bin` (127 x 384 floats) and `_norms.bin` have no non-zero byte.
  **Corrected 2026-10-08 evening: I named `EmbeddingService.createFallbackEmbedding` as the source of the zeros, and
  that function has no caller** (`/usr/bin/grep -rn createFallbackEmbedding OpenIntelligence`: only the two
  NaturalLanguage providers call their own). What the code allows: imports embed through the batch path
  (`EmbeddingService.swift:255-305`), which validates nothing; the single path only logs "Near-zero embedding
  vector" (`:337-340`); and the Core ML provider passes a zero model output through
  (`CoreMLSentenceEmbeddingProvider.swift:414-423`). So the model returned zeros in the Simulator and nothing
  rejected them [inferred from the measured zeros and the CPU-only result]. Gate E's cosine against a zero vector
  is 0, under its 0.25 floor, which the 5.6 change leaves failing on purpose; and search there is keyword-only. On the owner's iPhone the library of 2026-10-07 has 245 chunk
  vectors, none zero, no fallback warning, and no Gate E failure in 8 answers. Consequences: (1) Simulator runs of
  this app say nothing about retrieval, gates or answer quality; check a library's `_norms.bin` for non-zero bytes
  first. (2) The Gate E row https://app.notion.com/p/3ed49a74d54f8186b358d123b6f22d8b was filed on 2026-10-02 from
  the same setup, so it has no device evidence; it stays In Progress until the sample library is asked on a device.
  (3) The wrong-sample-answers row https://app.notion.com/p/3ec49a74d54f813baee7fd58e6484a32 (rent late date, E1,
  the 401(k) match) is a different case: it was filed on 2026-10-01 from the Mac app, not the Simulator, so the
  zero vectors do not explain it. (4) New row, Future Backlog: a library built from zero vectors is recorded as healthy,
  https://app.notion.com/p/3f349a74d54f8134833acf73aac40048 . No source was edited.
  **Confirmed 10:30 PT:** with the Core ML embedding model limited to the CPU in the Demos session's demo copy
  (`config.computeUnits = .cpuOnly` under the Simulator condition, not in this repository), a new Simulator library
  holds 2,375 chunk norms, none zero, and Gate E passes with right answers reading Verified in its takes. The Demos
  session was asked to re-ask the sample Home questions on real vectors, which is the Gate E row's closing test.
- **5.7 is on the roadmap: 81 rows on `v5.7` since 2026-10-08 (fifteen of them were moved to `In Progress` on 2026-10-09 and more since; the count is in the entry above).** The owner said "map where each
  would be integrated, then notion them for 5.7". The `v5.7` option was added to `Target Release` (all 21 other
  options and their row counts unchanged). 69 rows were created and 12 existing rows were moved onto it (the five
  action defects, cut sentences, return values, the share extension, export, widgets, view annotations,
  Evaluations, and the "2.5 billion" row). Priority follows the build order: 24 High (wave 1), 33 Medium (wave
  2), 24 Low (wave 3). Every row has a "Where it goes" section: the files and lines to change, new files and which
  target compiles them, protected files, tests, what it depends on, and a closing condition. The map came from
  three read-only passes over commit `7025657`; nothing was built or run, and line numbers will drift. The same map
  is in the private catalogue page (114 rows, https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ). **Given on 2026-10-09: "proceed: implement", the `## 5.7` heading, and the protected files by name (Active
  Constraints). Still not given: the 5.7 records in App Store Connect.** What the map says about order: (1) per-item links come first, because ten rows wait on
  a router and today it is a private method in `ContentView.swift:482`; (2) the app's services are built inside
  the main view's initializer (`OpenIntelligence/App/ContentView.swift`, lines 44 to 55), so a menu bar item, a second scene or an extension cannot reach them; (3) the
  Live Activities extension's folder is a classic Xcode group, so a new file there needs `project.pbxproj`; (4) new
  files under `Services/Agentic` compile into the app and the iOS-only engine, and under the engine they cannot name
  anything in `RAGAppIntents.swift`, `App/`, `Features/` or `UI/`. Defects the map found and I verified in code: Gate
  C counts a number as present when it appears anywhere in the evidence text (`VerificationGateService.swift:433`),
  which is how "2.5 billion" read Verified; every Shortcuts action builds its own `RAGService()`, which has no
  entitlement store and replaces the weak shared pointer (`RAGService.swift:1876-1880`); "Ask About a Document"
  only writes the file name into the prompt (`RAGAppIntents.swift:630-636`); a document's Spotlight entry expires
  after 30 days and nothing re-indexes (`SpotlightIndexService.swift:115`, `:148`); the 2025 transcriber sits
  behind `#if canImport(SpeechAnalyzer)`, a module that does not exist, so imports use the older recognizer.
  Also noted: `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md` says the Private Cloud Compute entitlement is
  deliberately omitted, and the entitlements file has it.
- **Next work the owner named on 2026-10-08, the research behind those rows: JSONL support and "everything Apple
  related that spreads this app" (Share Sheet, Shortcuts, App Intents).** (Written before the rows above existed; the
  go-ahead and the heading came on 2026-10-09.) Measured that day: the 5.6 build's `Metadata.appintents/extract.actionsdata` lists 16
  actions, none with an output type, 9 App Shortcuts (23 phrases, 6 with a parameter), 2 entities (document,
  library) with no properties, and no schema adoption; the app uses 10 of the 93 public protocols and macros in the
  iOS 27 SDK's App Intents interface (Xcode 27A266a). `.jsonl` has no system type (`.ndjson` is `public.ndjson`,
  `.json` is `public.json`); `.json` imports today as raw text, `.jsonl` has no route, and nothing exports a
  conversation. No share or action extension, no document types in `Info.plist`, no widgets or controls (the
  `OpenIntelligenceLiveActivities` target is a WidgetKit extension and could hold them), no App Group, no
  associated domains. Spotlight indexing exists but a result only opens the Documents tab. Five defect rows filed
  (Future Backlog): no action returns a value https://app.notion.com/p/3f449a74d54f8153bac7f4996d704249 ; the
  Ingest Webpage action never downloads a page https://app.notion.com/p/3f449a74d54f8152bc4af3b9baa7d8d4 ; Copy does
  nothing on the Mac https://app.notion.com/p/3f449a74d54f814aa0dbf4632c3db478 ; Spotlight tap
  https://app.notion.com/p/3f449a74d54f81638f6deb6813c46711 ; two stub actions
  https://app.notion.com/p/3f449a74d54f8147ac8fc70b43976266 . Apple's 2026 additions that fit, each confirmed in the
  SDK: `.system.searchInApp` and `.system.open` schemas with the `@AppIntent(schema:)` macro, `LongRunningIntent`
  (default background limit 30 s), `IndexedEntityQuery`, `SyncableEntity`, `EntityCollection`, `AppUnionValue`,
  `RunSystemShortcutIntent` for widgets, `SpotlightSearchTool`, and the `AppIntentsTesting` framework. A fetcher
  for Apple's doc JSON is in this session's scratchpad (`tools/adoc.py`); it will not outlive the session. Hard
  boundaries the work would need named: `RAGAppIntents.swift`, `Info.plist`, and later `project.pbxproj` and the
  entitlements file (a share extension and an App Group).
  **The full catalogue is a private page, 113 rows:** https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ (read it
  with the Artifact tool; its source was in a session scratchpad). It covers App Intents, Siri, Spotlight, sharing,
  system surfaces, the Mac, and every June 2025 and June 2026 addition found in Apple's updates pages that fits,
  with status, Apple's names, limits, needs, wave and source per row. Counts: 5 broken, 59 missing, 21 partial, 4
  to check, 14 have, 10 set aside; 42 rows new in 2026, 20 new in 2025.
  **One 2026 finding is a shipping risk, not a feature:** Apple's Background Inference entitlement
  (`com.apple.developer.background-tasks.continued-processing.inference`, iOS 27) is required "for any Neural Engine
  access while your app is in the background". The entitlements file lacks it, and the GPU one for continued tasks
  that `BackgroundTaskService.swift:272` requests. What the app does if the Neural Engine is refused in the background
  is not established (see the correction below) [not observed]. Verify on the owner's iPhone: start an import, leave
  the app at once, then read the library's `_norms.bin` for zeros and the trace log for "zero-vector fallback".
  Noted on https://app.notion.com/p/3f349a74d54f8134833acf73aac40048 . Also from the sweep: 17 references to
  `LanguageModelSession.GenerationError`, deprecated in 27, and five `BGTaskScheduler.shared.submit` calls,
  deprecated in 27.
- **Live in 5.6 and unchanged from 5.5: a lookup answer can repeat a sentence cut at a line break or at "p.m."
  (found 2026-10-08, cause read and reproduced).** Row, Future Backlog, passes test 2 for the next release:
  https://app.notion.com/p/3f349a74d54f81748e49d885416a4ced . The Demos session's take of the 5.6 source showed
  "towed at the owner's [S1]", "from 6:00 [S1]" and "Rent received after 11:59 p.m. [S2]." as whole sentences.
  `RAGService.extractRelevantSentencesOffMain` (`RAGService.swift:3296-3347`; Standard lookup questions call it at
  `:12924`, Deep Think and Maximum sessions through the orchestrator) splits each chunk at every line break, then
  each line at every ". ", and scores each piece alone. A port of those two rules over the lease text stored in
  the Simulator's Home library gives exactly those three cuts, and also splits "A late charge of $75.00 applies
  on" from "the 6th, ...", which fits the wrong rent answer of 2026-10-01. `git blame` dates the lines to
  2026-05-12 at the latest; no 5.6 commit touches the function. **Written 2026-10-09 for 5.7 (`EvidenceLineSplitter`, two call sites in
  `RAGService.swift`, 12 tests), uncommitted and not seen on a device.** The change in the row: join a wrapped sentence before
  splitting (headings and table rows stay lines), split with `AnswerSentenceSplitter`, and test with these lease
  lines. The Demos session took the clip off the 5.6 release post.
- **The sample Home library re-asked on real vectors (2026-10-08, 10:56 to 11:12 PT, Simulator, 127 chunk norms,
  none zero; screen dumps `/private/tmp/oi56-takes/h2-*.mov.xcodebuild.log`). Neither row closes.** Pipe burst:
  right, Fact Check 2 of 3, "Verification failed: Gate E", Unverified (the 5.6 rule needs every claim supported).
  Cleaning the basket: right, 4 of 4, "Verification failed: Gate C: Numeric Sanity", Unverified, with citations
  printed as `[S7]`, `[10]`, `[9]`, `[18]`. Dog: right, 5 of 6 (a heading counted as a claim), Unverified. E1: wrong
  ("does not provide a specific definition for E1") and **Verified**. 401(k): right figures after "do not address
  a 401(k) match directly", Unverified. Frozen fries: "The excerpts do not address", Unverified. The stored chunks
  hold the E1 row and the fries row of the manual's tables, so the import is not the fault; which chunks reached
  the prompt needs a trace log, which only a development build writes. **The store notes in review say "A right
  answer doesn't get 'Verification failed' under it when the claim check already supported every sentence"; the
  cleaning answer is a counter-example through Gate C.** `Docs/USER_CHANGELOG.md` words it more narrowly ("When
  that's the only check that fails, the claim check decides"). Next evidence: these questions on the owner's
  iPhone in the sample library, then `Documents/pipeline_trace.log`.
- **Seen in those real-vector takes (2026-10-08, Simulator, 13 research PDFs), not on a device:** (1) an answer gave
  "2.5 billion" parameters for Apple's on-device model, a figure that exists in the paper only inside the model
  name "Qwen-2.5-3B", and its Fact Check row read SUPPORTED with the badge Verified. Row, Future Backlog:
  https://app.notion.com/p/3f349a74d54f81b1b6c5c9cf7713d3bf . (2) Maths symbols are mangled in stored chunk text:
  the MMR paper's lambda is stored as "1" and "X", and the RRF formula line is garbled. Whether that is the PDF's
  own text layer or the app's extraction is not established; no row yet. Verify by reading the same pages with
  `PDFDocument.string` outside the app and comparing with the library's `_meta.json` content.
- **Seen in the 20:5x phone log and not traced:** one Standard question asked twice got a 12-word answer each
  time, with Gate I failing and `[SourceOnly]` finishing `abstain=true, supported=0, unsupported=0`. What the screen
  showed is not established, nor whether any 5.6 change touches that path. Verify by reading how a `SourceOnly`
  abstention is consumed for a Standard `lookup` answer (`/usr/bin/grep -n "SourceOnly"
  OpenIntelligence/Services/RAG/Orchestration/RAGService.swift`) and by asking the owner what he saw.
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

1. **Read what the new build does with a large text file on his iPhone.** The development build of the committed
   tree is installed. The import queue still holds the 88.50 MB `.jsonl` and asks whether to resume. When he has
   resumed it (expected: "Measuring a very large text...", then the "too long" message; not seen), copy the trace
   with `xcrun devicectl device copy from --device 00008140-001130DA1863C01C --domain-type appDataContainer
   --domain-identifier Gunndamental.OpenIntelligence --source Documents/pipeline_trace.log --destination <file>`
   and grep it for `DocumentProcessor` and `SemanticChunker` lines after the last `Processing` line: the stage
   times and the refusal are there. Then the same for a text or `.jsonl` file of 1 to 20 MB, which should import
   with "Chunking N%" moving. If either freezes or crashes, the crash report is in the crash logs domain
   (`devicectl device info files --domain-type systemCrashLogs`). That closes or reopens row
   `3f549a74d54f8154b822e4eee927a961`.
2. **Keep going down the `To Do` rows on `v5.7`** (`SELECT ... WHERE "Target Release" = 'v5.7' AND "Status" = 'To Do'`
   on the roadmap data source). Next, in the order that needs least from him: PDF export of a conversation; a Live
   Activity for a Deep Think answer (`QueryLiveActivityAttributes` exists, the widget target is a synchronized
   folder); Spotlight entries as app items. Then what needs him: the background inference entitlement (see
   Blockers), `FoundationModelSessionFactory.swift` named for the model-profile and OCR-tool rows, an app group on
   his developer account for the Share Sheet extension, widgets and controls, and his choice for text files over
   the limits (split, stream, or keep the refusal). A TestFlight build of 5.7 is one push without `[ci skip]` away
   and has not been sent; send it when he says.
3. **Device checks for what is written, on his iPhone and Mac.** From `af7aaf9`: send a PDF to the app from Files
   ("Open in"); pick a `.jsonl` file, import it and ask about one record; run Ask My Documents with each mode,
   Ask About a Document, Find Passages, Add to Library (a file, a link, text), Create Library and Save a Web Page
   from Shortcuts; say "Ask OpenIntelligence a question" to Siri; tap a document in Spotlight; share an answer
   and export a conversation; press Copy on an answer on the Mac; ask one lookup question whose source sentence
   contains "p.m." or wraps over two lines. From the fifth and sixth batches: the Home Screen quick actions and
   the keyboard commands, with Command-F, Command-] and Command-[ among them; how the Paste chip and the Notifications card look beside the app's own controls; Paste on the Documents screen with a copied file, a link and text, and what iOS asks when the copy came from another app; import a voice memo
   and look for `[SpeechAnalyzer] Complete` in the log; import a PDF with a chart and read its description;
   turn on Notifications in Settings, start an import, leave the app and wait; Redeem a Code with a sandbox
   code; ask the on-device-model question on arXiv 2507.13575 again and read the badge; after a fresh install,
   look for `[EmbeddingWarmup] Prepared the embedding model ... in` and its seconds.

Still open from 5.6:

1. 5.6 is live. The checks still open, on the owner's iPhone (the App Store 5.6, or the development build of
   `2bee971`, which is the one that writes `Documents/pipeline_trace.log`): three sample-library questions (E1,
   frozen fries, cleaning the basket) to see what a phone user gets where the Simulator showed Unverified on right
   answers and Verified on a wrong one; one Deep Think question (look for "whole chunks, N of B evidence tokens,
   window W"); an import into an existing library plus one question; Rebuild on a library that predates the
   fingerprint, then a reload. The new-library case is done (2026-10-07, 20:52 PT). Keep copied logs out of the
   repository.
2. He still has the phone checks for the eleven Fixed rows (`Growth/campaign/sample-package/RUN_SHEET.md`) and the
   window in Settings, "On this device".
3. The owner runs the asset upload from the repository root, or says how else he wants it done:
   `ruby Growth/store-assets-5.6/asc_assets_upload.rb Growth/store-assets-5.6/header-A-answer-centered.png Growth/store-assets-5.6/search-A-answer.png --apply`
   It does not have to precede the release: Apple's help page "Manage your App Store assets" (fetched 2026-10-07)
   says creative assets can be submitted alone through Asset Library, reviewed against the app's latest version, and
   published on a live version without a new version. The script attaches the placements to the 5.6 iOS en-US
   localization; whether that is accepted while the version reads WAITING_FOR_REVIEW is not verified.
