# Current State

Updated: 2026-10-15, 11:30 PT (5.7 is open and unreleased, no 5.7 build in TestFlight; the 5.7 work since the last handoff is in 8 commits, `67977e4` through `617df48`, each pushed with `[ci skip]`; 5.6 has been live on iPhone, iPad and Mac since 2026-10-08, build 485)
Branch/worktree: `main`, primary checkout
Last verified commit: 617df48

Earlier detail is in git: `git show 7270a91:Docs/ai/STATE.md` (the evening of 2026-10-14) and older copies named there;
the long record through 2026-10-10 is `Docs/Archive/STATE_record_through_2026-10-10.md`.

## Objective

**5.7: JSON Lines import and the Apple surfaces that carry the app to other apps and people, mainly for iPhone
and iPad.** Named by the owner on 2026-10-08, widened on 2026-10-09 and 2026-10-10. On 2026-10-14 he said "5.7 is
to be massive"; on 2026-10-15, "legit go until all 5.7 is finished, all backlogs, EVerything", and then asked
whether everything in the Native Surfaces catalogue was done. It is not: 27 of its 118 rows are unfinished (Status,
Blockers). The same day he asked for one thing at a time, each finished and checked before the next.

## Status (2026-10-15)

| What | Where it stands |
|---|---|
| 5.7 source | All pushed (`git rev-list --count origin/main..HEAD` prints 0). Since the last handoff: `67977e4` iCloud sends only what changed, empty vectors stop an import; `3cc0518` a Stop button on a long answer's Live Activity, Pause for imports; `d78ce2f` Get Settings, the tab bar shrinks on scroll, Apple's accessibility audit fixes; `a8c036f` fifteen roadmap rows settled; `397f3b2` retrieval's best passage reaches the model whole, a file goes to the library it was queued for, the Opened File sheet chooses the library; `af720fb` an import saves its document before the model work, an extracted value is judged by its own line, the X-Ray steps aside for sheets; `a9b682b` the privacy policy in the app (Settings, About) with the published text; `617df48` cached searches no question can reach are deleted. |
| Tests | 1,067 run, 0 failures, 5 skipped (two need Core AI, one layout case, the two scale benchmarks), 2026-10-15 at 11:17 PT on `617df48`'s tree; on `a9b682b`'s at 10:35 PT, 1,064 and 0 failures. Both trees: iOS test build and Mac build succeeded. Earlier the same day, before `af720fb` was committed, 1,064 and 0 failures, and the UI-testing target's accessibility audit passed. |
| TestFlight | No 5.7 build. Every 5.7 push carried `[ci skip]`; a push whose newest commit lacks it starts one. |
| His iPhone | A development build of `af720fb` installed 2026-10-15 at 09:39 PT; nothing after it. |
| Website | gunzino.me/openintelligence/privacy has the 2026-10-15 policy (Gunzino `a8c53f4`, then `ce7c6bb` for the search-cache line). The app's in-app policy and both Gunzino files are written by `scripts/privacy_policy.py`; the procedure is in `Docs/ai/RUNBOOK.md`, "Changing the privacy policy", and the code check behind each statement in `Docs/BILLING_AND_LIMITS.md`, section 6. |
| Catalogue | https://claude.ai/artifact/Thu24syf3CbVtpwhjAm4mJ, version 11: 69 built, 14 partly, 4 not started, 7 needing him, 2 checked, 22 the app already had (118 rows). |
| Test simulator | `OI 5.7 tests` `7652732F-FCEA-47A3-B345-7EC57B9EFE67` (iPhone 18 Pro, iOS 27.0), shut down. Simulators on this Mac are deleted between sessions: check `xcrun simctl list devices` first. |

The 27 unfinished catalogue rows, by what each waits on:

- **His Apple account in Xcode (6):** Share Sheet entry, Scan from the Lock Screen, Universal links (and a file on
  the website), Enhanced Security, Widgets with library data (app group), Quick Look extensions.
- **His word in App Store Connect (3):** the product page header and search image (this session's permission check
  refused the upload), nominating a release for featuring, accessibility labels on the product page.
- **Apple (1):** the background inference entitlement ("not a valid entitlement" in Xcode).
- **His iPhone or a paired Mac (4):** long background jobs, the Atlas on a very large library, selecting part of an
  answer, import activity in the Mac menu bar and CarPlay.
- **Code still to do here (8):** delete with undo, folder automations, actions from Spotlight on the Mac, Apple's
  token count on each answer (a stored field in `ChatMessage.swift`, named 2026-10-15), the OCR tool, the dates and
  money detector in the number check (`VerificationGateService.extractNumbers`), one progress tree, reorder and
  swipe in more lists.
- **Backlog with reasons (2):** large result sets by reference, dynamic instructions and profiles.
- **Measured, nothing to change (3):** one passage per embedding call, translation strategy, deprecations.

## Completed (2026-10-15)

Each change has its CHANGELOG 5.7 entry with its evidence and what closes it. None of today's work has been checked
on a device: the phone's build is `af720fb`, which has everything through the X-Ray change and nothing after it.

- The privacy policy, at his word ("Publish both now"): gunzino.me and the app carry one text, each statement checked
  against the code; the in-app screen had no way in since 2026-05-28 and opens from Settings, About now.
- Cached searches (`semantic_query_cache`) are deleted once the documents or the app's version change
  (`RAGService.deleteUnreachableCachedSearches`, after a save and at launch); `SQLiteFullTextService.swift` edited at
  his word on 2026-10-15. Through 5.6 nothing deleted them.

## Active Constraints

- A push whose newest commit lacks `[ci skip]` starts the first 5.7 Xcode Cloud build. Ask him first.
- Hard-boundary files only when he names them. Named for 5.7: `RAGAppIntents.swift` (10 of 10 App Shortcut
  slots used), `Info.plist`, `OpenIntelligence.entitlements`, `EngineSDKCompatibility.swift`, `project.pbxproj`,
  `WorkspaceSyncService.swift`, `FoundationModelSessionFactory.swift` (2026-10-14), and `SQLiteFullTextService.swift`
  for the cached-search delete (2026-10-15), and `ChatMessage.swift` for an optional token-count field (2026-10-15).
  Not named: the billing files, `FoundationModelRoutePolicy.swift`, `Package.swift`. The provider internals are out
  of bounds.
- Held, uncommitted: `project.pbxproj`, `OpenIntelligence/OpenIntelligence.entitlements` and the untracked
  `OpenIntelligenceLiveActivities/OpenIntelligenceLiveActivities.entitlements` (App Groups and Enhanced Security, waiting
  on provisioning). The scratchpad's `hold_provisioning.sh` puts HEAD's copies into the build copy; commit by name,
  never `git add .`. After `codemap.py index`, take the held file's line out of `Docs/ai/codemap/UNMAPPED.md`.
- App Store Connect writes only at his word, through `zsh -ic`; never copy the key id, issuer or key anywhere. His
  word on 2026-10-15 covers three: upload the prepared product page header and search image; declare accessibility
  labels, only the features a test backs; draft a 5.7 featuring nomination and show it to him before it is sent.
- Public repository and site: no personal plans in public files or row titles. Never delete a doc, a benchmark run
  directory or a Notion row. No co-author or attribution lines in commits.
- One `xcodebuild` at a time on this 18 GB Mac (another session's PostDesk tests run too: check `pgrep -x xcodebuild`),
  DerivedData outside `~/Documents`, `-jobs 1` with a memory guard. Never edit the repository between a run's start
  and its last copy of the tree.
- Edit `RAGService.swift` and other large Swift files by script: the post-edit formatter re-wraps a file Claude edits.
- Installing on his iPhone ends the running app: check `xcrun devicectl device info processes` first.

## Working Set

- Privacy: `OpenIntelligence/Features/Billing/PrivacyPolicyView.swift` (generated), `Features/Settings/AboutView.swift`
  (the row), `PRIVACY.md`, `Docs/BILLING_AND_LIMITS.md` section 6; Gunzino `src/content/pages/openintelligence.privacy.md`
  and `openintelligence/privacy/index.html`.
- Search cache: `RAGService.swift` (`queryCacheKey`, `queryCacheDocumentsToken`, `deleteUnreachableCachedSearches`,
  the end of `saveDocumentsToDisk`, `loadDocumentsFromDisk`), `SQLiteFullTextService.deleteAllCachedQueries`,
  `OpenIntelligenceTests/Services/RAG/Orchestration/QueryCacheClearingTests.swift`.
- Import order: `RAGService.enrichImportedDocument`, `deferEnrichment`, `runDeferredEnrichmentsIfNeeded`.
- Answer path: `RAGService.leadingWithTopRanked`, `extractRelevantSentences(leadingCandidateWhole:)`,
  `extractedValueAnswersQuestion`, `valueLine`.

## Verification (2026-10-15, output read)

- `617df48` (search cache): `build57.sh build-for-testing` -> `TEST BUILD SUCCEEDED`, no warning in the new code;
  `build57.sh test-without-building` -> `Executed 1067 tests, with 5 tests skipped and 0 failures`, with
  `QueryCacheClearingTests` 3 passed and the keyword-search suites the preflight asks for (`HybridSearchServiceTests`,
  `PageRowsAcrossBatchesTests`, `LargeLibraryCostTests`) passed; `buildmac.sh` -> `BUILD SUCCEEDED` (11:20 PT).
- `a9b682b` (in-app privacy policy): `TEST BUILD SUCCEEDED`; `Executed 1064 tests, with 5 tests skipped and 0
  failures`; Mac `BUILD SUCCEEDED`; in the iOS 27 Simulator, Settings, About, Privacy Policy opened the sheet with the
  bold labels rendered and the hardware X-Ray hidden behind it.
- A default closure that calls the store actor (`{ await SQLiteFullTextService.shared.deleteAllCachedQueries() }`) is
  refused in the Swift 6 language mode: `xcrun swiftc -swift-version 6` on a five-line probe -> "actor-isolated default
  value in a main actor-isolated context". The app's build only warned; the call is in the function body now.
- `python3 .claude/codemap/codemap.py check` -> 0 errors, 52 warnings (files changed since their slice was stamped by
  earlier commits; only `billing-and-quotas` was stamped today).
- Gunzino: `npm run build` then `./scripts/verify-site.sh source` in a copy of the tracked files -> exit 0 for `a8c53f4`
  and `ce7c6bb`; Deploy runs 38775401964 and 38785077646 -> success (build, deploy, verify); the live page carries the
  October 15 text and the search-cache line. Run 38771097266 for `631e537` failed with `LOST
  openintelligence/privacy/index.html` and published nothing.
- After every push the newest Xcode Cloud run was still #485: no 5.7 build started.
- Not run: anything on his iPhone after `af720fb`; the cache delete and the About row on a device.

## Blockers / Unknowns

- **Provisioning.** Xcode here has no Apple account ("No Accounts"), and `xcodebuild -allowProvisioningUpdates` with
  the App Store Connect key failed on 2026-10-14 with "Authentication failed: Make sure a bearer token was provided,
  it is properly configured and signed, and it has not expired", though a script with the same key reads
  certificates (7), devices (7) and profiles (0). The key's path is absolute; why xcodebuild's request fails is not
  established. His sign-in in Xcode (Settings, Accounts) unblocks the six rows above; on 2026-10-15 he said he would
  sign in shortly. Check it with a device build that passes `-allowProvisioningUpdates` before building the rows.
- **App Store Connect, at his word:** the three rows above, and 5.7's App Store notes on both records when he cuts it.
- **Two duplicate roadmap rows wait for him to delete:** https://app.notion.com/p/3f949a74d54f819d9fddd5a90087fb1e
  and https://app.notion.com/p/3fa49a74d54f815a98c9d84ea08d9287.
- **Nothing in 5.7 is closed on a device.** The phone's build is `af720fb`; the in-app privacy policy and the cache delete came after.
- **Library `BDB0BCA5`** on his phone held 27 passages with no document (seen in a trace on 2026-10-15); not investigated.

## Exact Next Action

Work through the queue below in order, one item finished, checked and committed before the next (his words on
2026-10-15: "one thing at a time", then "Fix everything dude don't just leave things"). When he says Xcode has his
account, finish the item in hand and switch to the six provisioning rows.

1. The consent prompt's own claims. `OpenIntelligence/UI/Components/CloudConsentPromptView.swift`,
   `explanationSection`, says "End-to-end encrypted / Your data is never stored", "Same security as your device" and
   "No data retention / Deleted after processing" in the app's voice; `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`
   section 4 rules out unconditional enclave promises. Read Apple's Private Cloud Compute statements on
   developer.apple.com and security.apple.com first (the `oi-claim-audit` and `apple-api-truth` skills), then attribute
   each row to Apple or reword it to what Apple states.
2. Passages that outlive their documents. `RAGService.rebuildLocalSearchIndexesFromCanonicalState` (line 8747) wipes
   passages whose document is not in the catalog but skips a library with no documents (`guard
   !containerDocuments.isEmpty else { continue }`, line 8759); his phone's library `BDB0BCA5` held 27 passages and no
   document. Read its callers (lines 2517 and 4726), look for any other path that clears such a library, then test and fix.
3. The token count on each answer (`ChatMessage.swift`, approved). 4. Delete with undo: a few seconds to undo, the
   default chosen on 2026-10-15. 5. The dates and money detector in `VerificationGateService.extractNumbers`. 6. The
   OCR tool: measure, then switch it on or record why not. 7. One progress tree (`ProgressManager`). 8. Reorder and
   swipe in more lists. 9. The three App Store Connect writes above. 10. A development build on his iPhone, installed
   only while the app is closed, for the device checks.
