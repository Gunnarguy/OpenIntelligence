# Current State

Updated: 2026-10-14, 16:36 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; the 5.7 work of 2026-10-14 is in seven commits through `07c0cbb`, each pushed with `[ci skip]`; 5.6 has been live on iPhone, iPad and Mac since 2026-10-08, build 485)
Branch/worktree: `main`, primary checkout
Last verified commit: 07c0cbb

Earlier detail is in git: `git show 131f989:Docs/ai/STATE.md` (the morning of 2026-10-14), `git show 5bf6860:Docs/ai/STATE.md`
(2026-10-13), and the long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7: JSON Lines import and the Apple surfaces that carry the app to other apps and people, mainly for iPhone
and iPad.** Named by the owner on 2026-10-08, widened on 2026-10-09 (the Apple model APIs) and 2026-10-10 (the
whole import path, very large libraries). On 2026-10-14 he asked whether the Native Surfaces Catalogue and the
open Notion rows were done, and said "5.7 is to be massive": build the rest of the catalogue and the open rows
into 5.7, everything that can live inside the app first. That in-app part is built, apart from the two rows under
Blockers that were left with a reason. What is left needs his word, a device, or both.

## Status (2026-10-14)

| What | Where it stands |
|---|---|
| 5.7 source | Seven commits that day, all pushed (`git rev-list --count origin/main..HEAD` prints 0): `131f989` system surfaces; `004e6f7` Visual Intelligence, Delete Documents, the Mac menu bar item, syncable items, state reporting; `7844e2c` Siri's answer card, library order, Check a Claim; `0369098` the 27 asset input for recordings, Think Deeper, PDF export and Export Conversation, one import figure, the first action tests; `73e42fc` Ask a Follow-up and the New Chat data-loss fix; `cac89fb` the fixes a refuting review of those two asked for; `07c0cbb` the chat menu's export off the main actor. |
| Tests | 980 run, 0 failures, 5 skipped (two need Core AI, one layout test, the two scale benchmarks), 2026-10-14 at 16:22 PT (cycle `h10`), with a device build before and a Mac build after, on the tree of `07c0cbb`. |
| TestFlight | No 5.7 build. Every 5.7 push carried `[ci skip]`; a push whose newest commit lacks it starts one. The newest Xcode Cloud run is still #485 (2026-10-08). |
| His iPhone | Which 5.7 build is installed is not known from here: every 5.7 build reads 5.7 (150). As of 2026-10-13 it was `ec4fb74`'s. The build of `07c0cbb`'s tree is staged at `/private/tmp/oi-install/OpenIntelligence.app` (built 2026-10-14 at 16:18 PT). A script started at 11:30 PT polls to install it the first time the app is absent from two process listings in a row; it gives up at about 17:30 PT and never launches the app. Its output is `install_when_idle.out` in `/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/02a2f913-1d63-449c-8ccc-8c198da128bc/scratchpad/` (`INSTALLED` with a time when it did; empty when it has not). |
| Roadmap | 115 rows on `v5.7`: 101 In Progress, 14 To Do, none Completed (queried 2026-10-14 after the updates). New that day: https://app.notion.com/p/3f949a74d54f81e08612c07f34b9e0b5 (New Chat at the conversation limit saved over the old conversation; scope test 1). |
| Catalogue | https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ, version 9: 65 built, 13 partly, 9 not started, 7 needing him, 2 checked, 22 the app already had (118 rows). |

## Completed (2026-10-14)

Built, compiled for iPhone and Mac, and in the suite; none of it seen on a device. `CHANGELOG.md`, section 5.7,
has one entry per change with its evidence and what closes it.

- The system surfaces (`131f989`): Handoff, Spotlight items that leave with their document, Siri search, a Focus
  filter, three controls, a long answer's Live Activity, the Mac's Services menu, Quick Look, image cards, link
  previews, dictation, Apple's document scanner; a setting saved with its new value; PDF page rows numbered by the
  pages with text.
- `004e6f7`: Visual Intelligence lists matching documents (device and Mac only; the Simulator SDK has no Visual
  Intelligence); "Delete Documents" asks first; a menu bar item on the Mac; documents and libraries as
  `SyncableEntity`; the system's diagnostics name the import or answer mode; a deleted document stays deleted.
- `7844e2c`: Siri's answer card opens the documents its evidence names; libraries drag into an order kept on the
  device; "Check a Claim" (no language model judges the sentence; negation checked on the best-matching sentence).
- `0369098`: recordings read through `AssetInputSequenceProvider` a track at a time on 27 (probe in
  `BenchmarkRuns/2026-10-14-asset-transcriber-probe`); Think Deeper on the card; PDF export and "Export
  Conversation"; `ImportProgress`, one import figure (the background task's own counted a finished document twice);
  `ShortcutsActionTests`, the first tests that run actions.
- `73e42fc`: Ask a Follow-up on the card (a new conversation seeded with Siri's question and answer, added to the
  conversation memory when missing); a New Chat refused at the conversation limit keeps the conversation on screen
  (it used to be saved over).
- `cac89fb`, after a refuting review: both card buttons open the library the question ran in and are not offered
  after a document-scoped question; Think Deeper waits for an answer in progress; New Chat clears only after it
  starts a conversation; the PDF reads Markdown with the chat's parser; the Live Activity keeps finished documents
  in its list, so its count goes up (it read 0/3, 0/2, 0/1), and all three surfaces count `currentImportItems`.
- `07c0cbb`: the chat menu writes its export file off the main actor.

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Hard-boundary files only when he names them. Named for 5.7: `RAGAppIntents.swift` (10 of 10 App Shortcut
  slots used; an eleventh breaks them all), `Info.plist`, `OpenIntelligence.entitlements`,
  `EngineSDKCompatibility.swift`, `project.pbxproj`, `WorkspaceSyncService.swift`, the tool registry work.
  Not named: `ChatMessage.swift`, the billing files, `SQLiteFullTextService.swift` (the preflight protects the
  whole file), `FoundationModelSessionFactory.swift`, `FoundationModelRoutePolicy.swift`, `Package.swift`.
  `BNNSVectorDatabase.swift`: read-side additions on 2026-10-13 that he has not confirmed; nothing further
  without his word. A new entitlement or capability (the Mac's audio input, Enhanced Security) needs his word.
- The provider internals (`CoreAISentenceEmbeddingProvider`, `CoreMLSentenceEmbeddingProvider`) are out of
  bounds (`.claude/rules/ingestion-and-indexing.md`); selection logic is not.
- App Store Connect writes only at his word, through `zsh -ic`; never copy the key id, issuer or key anywhere.
- Public repository and site: no personal plans in public files or row titles. Never delete a doc or a
  benchmark run directory. No co-author or attribution lines in commits.
- One `xcodebuild` at a time on this 18 GB Mac, DerivedData outside `~/Documents`. The post-edit format hook
  rewrites whole Swift files it has not formatted before; apply edits to those by script. Start long jobs with
  the Bash tool's background option, never `&`: a test run started with `&` on 2026-10-14 stalled before its
  tests loaded.
- Installing on his iPhone ends the running app: check `xcrun devicectl device info processes` first, never
  launch it remotely.
- Untracked and left alone: `.agents/skills/`, `.codex/hooks.json`, `.codex/hooks/`.

## Working Set

- Siri and Shortcuts: `OpenIntelligence/Services/Agentic/RAGAppIntents.swift` (`AskActionRunner`: `ask`,
  `makeEngine`, `card`, `sourceEntities`, `sourceDocumentIds`; `AnswerCardSnippetIntent`, `AnswerCardSnippetView`;
  `DocumentImportStatusIntent`), `OpenItemIntents.swift` (`ThinkDeeperIntent`, `AskFollowUpIntent`),
  `CheckClaimIntent.swift`, `DeleteIntents.swift`, `AppNavigationRequest.swift`
  (`.ask(_:sendsAtOnce:inDeepThink:libraryId:)`, `.continueAnswer(question:answer:libraryId:)`).
- Chat: `OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift` (`takeNavigationRequest`, `newChat`),
  `ChatComposerV2.swift` (an empty draft only focuses), `Features/Chat/Pipeline/ConversationExporter.swift`
  (`pdf`, `plain`, `data`), `ExportConversationIntent.swift`.
- Import: `OpenIntelligence/Services/Document/Analysis/SpeechAnalyzerService.swift` (`transcribeEachTrack`,
  `transcribe`), `OpenIntelligence/Core/Models/ImportProgress.swift`, `IngestionLiveActivityService.swift`.
- Libraries: `ContainerService.swift` (`orderedContainers`, `move`), `ContainerPicker.swift` (`LibraryReordering`).
- Tests: `OpenIntelligenceTests/Services/Agentic/ShortcutsActionTests.swift` (a stand-in model, notes it adds and
  deletes), `ClaimCheckTests.swift`, `AskControlTests.swift`, `AppLinkTests.swift`,
  `Services/Infrastructure/ImportProgressTests.swift`, `LibraryOrderTests.swift`,
  `Features/Chat/ConversationExporterTests.swift`.

## Verification (2026-10-14, output read)

- Batch seven (`07c0cbb`), cycle `h10`: device build `BUILD SUCCEEDED`, `TEST BUILD SUCCEEDED`, `Executed 980 tests, with 5 tests skipped and 0 failures`, Mac `BUILD SUCCEEDED` (16:22 PT).
- Batch six (`cac89fb`), cycle `h9`: device build, test build, `Executed 979 tests, with 5 tests skipped and 0
  failures`, Mac build, all succeeded (16:15 PT).
- Batch four (`0369098`), cycle `h7`: device build `BUILD SUCCEEDED`, `TEST BUILD SUCCEEDED`, `Executed 978 tests,
  with 5 tests skipped and 0 failures`, Mac `BUILD SUCCEEDED` (14:34 PT).
- Batch three (`7844e2c`): `Executed 966 tests, with 5 tests skipped and 0 failures`, device and Mac builds succeeded.
- `python3 scripts/verify_doc_claims.py` -> all claims match. `python3 .claude/codemap/codemap.py check` -> 0 errors,
  0 warnings. `python3 scripts/secret_scan.py` -> nothing found. `grep -c "AppShortcut(" RAGAppIntents.swift` -> 10.
- After each push the newest Xcode Cloud run was still #485: no 5.7 build started.
- The five skips are the usual ones: two need Core AI, one layout case, the two scale benchmarks.
- Not run: any of this on his iPhone or a Mac in use.

## Blockers / Unknowns

- **Nothing in 5.7 is closed.** Every row waits on a device; each row's note and each CHANGELOG entry's evidence
  tag says what closes it.
- **His decisions, each a single word:** the Mac's microphone (audio-input entitlement, for dictation on the Mac);
  naming `FoundationModelSessionFactory.swift` (one model profile per answer mode; the OCR and barcode tools);
  provisioning an app group, associated domains and extension targets (Share Sheet entry, widgets, Lock Screen
  scan, crash report, universal links); the Enhanced Security capability; a read-only viewer for files opened
  from outside versus the current Open In import; Evidence Threads sync versus conflict copies; confirming the
  `BNNSVectorDatabase.swift` additions of 2026-10-13; asking for Private Cloud Compute consent in the foreground
  (the route forbids it without his word); the two rows that ask him (the 27 deprecations to Future Backlog?
  the Deep Think cache row: drop, or measure on an iPhone?); a UI-testing target in the project file for
  AppIntentsTesting; App Store Connect (nominate the release, the page header image, accessibility declarations);
  deleting the duplicate roadmap row https://app.notion.com/p/3f949a74d54f819d9fddd5a90087fb1e.
- **Left with a reason:** passages by reference (Find Passages returns at most 20, and passages are not items the
  system can look up by id; row note 2026-10-14) and two embeddings at once (measured on the Mac only, where
  imports are already fast; the provider internals are out of bounds).
- **Not seen working:** Think Deeper and Ask a Follow-up from a real Siri card; the answer card's buttons in
  general; the asset input on an iPhone recording; whether Core Spotlight moves an entry's expiry on an update;
  whether a Live Activity started as the app leaves the front succeeds.
- **Simulators on this Mac are deleted between sessions.** Expect to make one before any test run.

## Exact Next Action

If he has given any of the decisions above, start with the one he gave. Otherwise the next work is a device pass on
his iPhone. First read `install_when_idle.out` (His iPhone above): if it is empty, the staged build was never
installed, and it is installed with `xcrun devicectl device install app --device 00008140-001130DA1863C01C
/private/tmp/oi-install/OpenIntelligence.app` once `xcrun devicectl device info processes` shows the app is not
running (build it again first if `/private/tmp` was cleared). Then ask Siri a question about a document in a
library, tap Ask a Follow-up on its card, and ask a second question that only makes sense after the first: the
answer card row (https://app.notion.com/p/3f449a74d54f8193a750d1099b83a8c5) closes for that button when the app
opens on that library with the two messages and the second answer uses the first. Do the same for Think Deeper on
another Standard answer: the app opens in Deep Think and sends the question.
