# v5.0 Flow and Responsiveness Audit

Produced 2026-08-18 by a read-only 11-agent pass: one probe per dimension, each refuted by an
independent agent that also gated every fix on whether it removes functionality. No source edited.
Raw output: `Docs/AuditArtifacts/DefectDiagnosis/flow_audit.json`. Companion throughput audit:
`V50_PERF_AUDIT.md`. Supersedes `flow_audit_partial.json`, which was the unverified early stop.

---

# Felt Responsiveness — Audit Result and Plan

**Read-only pass.** No file was edited, no build was run. Every line cite below was re-verified against `dc097cc` (current HEAD) rather than the tree the dimension passes started on — six commits landed while this ran, and **one finding is already fixed**: the duplicate `.task` on `AdaptiveVisualizationsView` shipped in `dc097cc`. Don't re-file it.

Unless a claim says otherwise, it is read off source. SwiftUI runtime behaviour read off source is the expensive kind of wrong here, so the device list in §5 is not optional.

---

## 1. The single change

**Scope the cancel block in `ChatScreen.swift:605-615` to a real container change.**

`.task(id: ragService.containerService.activeContainerId)` opens at line 600. Its first eleven statements — `continuedQueryCoordinator.cancelCurrentQuery()` at 605, `currentQueryTask?.cancel()` at 607, and the `if isProcessing { resetStreamingState(); isProcessing = false; stage = .idle }` at 611-615 — run on **every** appearance of the task, not only when the id changes. The guard that scopes the rest of the body, `let isSameChatContainer = (lastLoadedChatContainerId == activeId)` at 622 and `if !isSameChatContainer` at 625, sits seventeen lines below it.

So: ask a question, glance at Documents to check a filename, come back, and the answer is gone. No partial text, no error, an idle composer. `stopGeneration()` at 1818 preserves the partial answer as a message; this path calls `resetStreamingState()` and keeps nothing. Worse, the block never calls `ragService.cancelActiveGeneration(...)` the way `cancelInFlightQueryWork()` at ~3019 does — so the visible answer is discarded while the underlying generation may keep running. The user loses the output and the device keeps paying for it.

**Why this over the runners-up.** It is the only finding in the whole audit where navigating destroys work the user cannot get back. Everything else costs a spinner or a scroll position. And it is not merely a bug — it teaches a user model. Right now the correct model is *do not leave the Chat tab*, which quietly cancels the value of every other navigation improvement on this list.

**Why I believe the fix is right and small.** The author's intent is already written down: history reload, suggested-question invalidation and count recalculation are all gated on `isSameChatContainer` / `isSameDocsContainer`. Only the cancellation block was left ungated. The condition already exists 17 lines below. It is roughly five lines — track `lastCancelledContainerId: UUID?` and wrap 605-615 in `if lastCancelledContainerId != activeId`. Prefer that over "move the block inside `if !isSameChatContainer`", because the `#if DEBUG ... if didSeedScreenshotDemo { return }` at ~618-620 sits above that branch and would silently drop the cancel in screenshot mode.

**It needs one companion or it half-breaks something else.** If streaming survives the tab return, the 5 Hz clock does not: `.onDisappear` at 588-592 cancels `processingClockConnection`, and the only restart is `.onChange(of: isProcessing)` at 578-587, which cannot fire because `isProcessing` never changed. Everything driven by `nowTick` (969, 995, 1533, 1539, 1549) would then display a frozen elapsed time for the rest of the answer. Restart the clock in `.onAppear` (~864) when `isProcessing` is true.

**One thing could displace it.** If the device check in §5.3 confirms the Atlas tab genuinely will not scroll over its own hero, that is a whole tab reading as frozen, which beats this. I cannot settle that from source and I am not going to pretend otherwise.

---

## 2. Ranked after that — felt gain per unit of risk

### Tier 1 — one-liners, no judgement calls

| # | Change | Where |
|---|---|---|
| 1 | Spotlight sets the library via `containerService.setActive(containerId)` instead of assigning `activeContainerId` directly. Currently skips the existence guard and the UserDefaults write, so a Spotlight jump lands in a library the app forgets on relaunch, and a stale entry sets an id matching nothing (empty-looking library, not a stale link). | `ContentView.swift:107` |
| 2 | Refresh icon: accumulate the angle instead of `rotationEffect(.degrees(isRefreshing ? 360 : 0))`. Today every refresh ends by visibly *un*-spinning, which reads as a cancellation. | `ChatScreen.swift:3817` |
| 3 | Drop `withAnimation(.linear(duration: 0.04))` around the streaming string append. A `String` append cannot interpolate; the transaction just fans an ambient animation across every view that changed that tick, 12-25×/sec, during generation. Do **not** substitute `.contentTransition(.opacity)` — it is inert once the transaction is gone. | `ChatScreen.swift:3078` |

### Tier 2 — small, high felt gain, needs a little care

4. **Stop force-scrolling the transcript to the bottom on every appearance.** `.onAppear` at `MessageListV2.swift:128` calls `scrollToBottom(animated: false)` at 130, ignoring the `isPinnedToBottom` state the view maintains for exactly this. And `animated: false` still animates — line 167 is `withAnimation(.easeOut(duration: 0.12))` — so you get a visible jump. **Gated on device check §5.2:** if the scroll offset does not survive a tab switch, gating alone strands the user at the *top* of a long transcript, which is worse than today; ship the `lastVisibleMessageID` restore variant instead.

5. **Collapse the compact atlas's two `.task(id:)` into one composite key.** `CompactAtlasSceneView` has `.task(id: containerService.activeContainerId)` at 2902 and `.task(id: projectionMethod)` at 2905, both firing on appear, both entering `loadAndProject()` whose first line raises `isLoading`. Unlike the outer view fixed in `dc097cc`, there is **no** `analysisTask?.cancel()` here, so these two genuinely run concurrently over up to 50,000 points. Use one `Equatable` key of (container, projection) and raise `isLoading` only when the key differs from the last completed load — not when `points.isEmpty`, or switching projection leaves the old cloud under the new label.

6. **Stop paying a full vector-store load for a value that gets discarded.** `refreshSuggestedQuestions` awaits `getSampleChunks(...)` → `db.allChunks()` → `await awaitLoad()` (`BNNSVectorDatabase.swift:680`), pulling the container's whole vector store off disk. `generateQuestions` uses the sample only when the on-disk bank is empty (`SuggestedQuestionsService.swift:488`), which is not the normal case. Pass a lazy `@Sendable () async throws -> [DocumentChunk]` instead. Separately drop the eager `invalidateCache(for: activeId)` at `ChatScreen.swift:650` — it targets the library you are switching *to*, so it exists only to destroy the fast path. Cost scales with library size, so chip taps get worse the more you use the app.

7. **Time-throttle the streaming auto-scroll.** `MessageListV2.swift:140` is `newText.count % 80 < 20`. When backlog > 400 the adaptive chunk is exactly `max(80, 50)` = 80 (`ChatScreen.swift:3061-3063`), so the residue is **constant for the whole burst** — if it lands ≥ 20, auto-follow is silently absent, not merely uneven. This is the repo's own silent-truncation shape in a UI predicate. Replace with a ~100 ms clock throttle, make the `animated: false` branch at 166-169 a plain `proxy.scrollTo` with no `withAnimation` so a finger can override it, and force a trailing scroll when `isStreaming` flips false.

8. **Scroll the active library chip into view.** `ContainerPicker.swift:46` is a bare horizontal `ScrollView` with no `ScrollViewReader` (the only three in the app are `IngestionQueueOverlay:70`, `ThinkingStreamView:146`, `MessageListV2:72`). With more than a few libraries, a Spotlight jump or a workspace reload leaves the selected pill off-screen and there is no on-screen answer to "which library am I in". Purely additive.

9. **`SourceChipsView.swift:126`** — replace `.onLongPressGesture(minimumDuration: 0, pressing:)` with a `ButtonStyle` reading `configuration.isPressed`. The sibling `MoreChip` at 137-161 is the identical Button with no long press, which proves the gesture is superfluous rather than load-bearing. **Keep the stagger.** Also wire the empty `onTap` at `ChatScreen.swift:791` — chips there fire a haptic and a press animation and then do nothing.

10. **Two rows that are `.onTapGesture` and should be `Button`:** `ChunkInspectorView.swift:256` (release-reachable via `SettingsView:560` → `DeveloperDiagnosticsHubView:159`, outside the `#if DEBUG`) and `SettingsView.swift:2158` (the Intelligence Mode selector, the primary control in Settings). Neither flashes on press, neither carries `.isButton`. On the Settings one, also move `DSHaptics.selection()` (2164) ahead of the `canSelectMode` guard so a blocked Maximum press confirms it registered, and split `canSelectMode` (2431-2437) into a pure predicate plus an explicit `presentPlanSheet()` — it currently mutates `planEntryPoint` and `showPlanSheet` while reading like a predicate. **Do not add `.buttonStyle(.plain)`** — it opts out of the row highlight the fix exists to restore.

### Tier 3 — structural, worth the effort

11. **Stop blanking populated content — identity-gated, not emptiness-gated.** Three screens do this:
   - `DatabaseDashboardView.swift:215` raises `isLoading` unconditionally and 492 gates `overviewSection` on it, while `stats` is still in `@State`. The 10 s watchdog at ~220 tells you the author already knows the blank period can be long.
   - `AdaptiveVisualizationsView.swift:123` swaps insights, recommended views, expanded view and library stats for `analyzeLoadingCard` while the hero at 117 and `libraryHeader` at 121 keep rendering the live profile. The screen visibly tears in half.
   - Both must gate on **identity**, not emptiness: `stats == nil` *and* scope unchanged; `currentProfile == nil` *or* `currentProfile?.containerId != activeContainerId`. Emptiness-gating alone shows library A's data under library B's header. And the "analysing" signal must stay legible — `libraryHeader` already renders a small `ProgressView` at 529-531 and is already outside the gated branch, so reuse it rather than inventing one.

12. **Database first-open runs two overlapping loads.** `.task` at 180 runs `loadAllData()`; `.onAppear` at 191-195 seeds `databaseScope` from `.allLibraries` (35) to `.library(activeContainerId)`, which is always a change on first appearance, which trips `.onChange(of: databaseScope)` at 188 into a second `loadStatistics()`. Both write `isLoading`, so the screen can go spinner → content → spinner. Seed the scope before the load can observe it. **Constraint:** `documentStats = await loadDocumentStats(for: scopedContainerId)` at 237 reads the scope after a suspension point — suppress the seeding `onChange` without guaranteeing the seed lands first and the tab shows all-libraries stats where it currently shows the active library. That would be a real regression.

13. **One ingestion overlay, not two.** `IngestionQueueOverlay` is mounted independently at `ChatScreen.swift:520` and `DocumentLibraryView.swift:1327`, each holding its own `@State isMinimized` (299) and `isDismissed` (300). Dismissing it on one tab reads as broken because it comes back full-size on the other. Hoist both booleans into a `@StateObject` presentation object on ContentView. The deep-link handler at 481 actually improves: it currently un-dismisses both copies blindly.

14. **The composer should stay typable during generation.** `ChatComposerV2.swift:87` is `.disabled(isProcessing)`, so the keyboard is taken away the moment you send, and the attach button is unmounted entirely at 93 (layout jump). Remove the modifier, add `guard canSend else { return }` at the top of `send()` (218) — `canSend` already requires `!isProcessing` — and keep the attach button mounted-but-disabled. Note for the writeup: `sendMessage` at 2471 already handles an in-flight query by cancelling it at 2489-2496, so `.disabled` was blocking an interrupt-and-resend, not preventing corruption.

15. **Make the written-but-dead transitions actually run.** Four exist in source and never fire because nothing opens a transaction: message insertion (`MessageListV2.swift:92-95`), the metrics bar, the follow-up chip row and the writing-tools overlay. Wrap the `messages` mutations in `withAnimation(.spring(response: 0.3, dampingFraction: 0.8))` — **all six sites**, not the four originally listed: 1729, 1751, 1796, 2516, plus **939** (writing-tools insert-as-reply) and **1859/1862** (regenerate removal, the only user-triggerable removal). Put presence-keyed `.animation(_:value:)` on the `mainContentArea` VStack at 2012 and delete only 2141 and 2166. **Keep 2027** — see §4. `MessageBubbleV2.swift:175-179` + 209 is the working template already in the codebase.

16. **`@SceneStorage` for the composer draft** (`ChatComposerV2.swift:26`) and tab selection (`ContentView.swift:22`). The draft is the sharper half: the app persists your transcript on background (`ContentView.swift:329-330`) but not the sentence you had not sent yet, which is the one piece of text only you could have produced.

### Tier 4 — blocked or needs a redesign before it is worth doing

17. **Atlas hero gesture conflict** — potentially the worst defect in the app, and the least certain. `Embedding3DView.swift:3423` sets `allowsCameraControl = true` on an SCNView mounted 280-420pt tall directly inside the Atlas tab's root `ScrollView` (`AdaptiveVisualizationsView.swift:104` → 117 → 229 → 2947 → 3391 → 3402). Two UIKit pan recognizers, no failure relationship. SceneKit's pan begins on near-zero movement; UIScrollView's must first clear its slop. The scene even prints "Drag to rotate • Pinch to zoom" at 3019, advertising the gesture that may be eating the scroll. Pull-to-refresh (211) is on the same ScrollView. **The engagement-gate fix must not ship as specified** (§4). Blocked on §5.3.

18. **Suggested-prompt card has no loading state.** `refreshSuggestedQuestions` sets `isRefreshingSuggestions` only inside `if force` (1648), the array is cleared to `[]` at 643, and `supportingText` therefore prints its terminal fail-closed verdict "No grounded suggestions are ready yet" (3744) *while it is still working* — then contradicts itself when chips appear. Because in-progress and genuinely-empty are the same empty array, the whole load re-fires on every Chat entry forever for a library that legitimately yields nothing. Needs a tri-state (`notLoaded`/`loading`/`loaded`), a loading sentence that describes the action rather than promising an outcome, and skeleton rows. Keep 3744 verbatim for the resolved-empty case — that message is the design, not a bug (`SuggestedQuestionsService.swift:32`). Larger than it looks; it is a state-machine change, not a copy change.

19. **Reduce Motion.** 14 `repeatForever` sites, exactly one reader of `accessibilityReduceMotion` (`OnboardingChecklistView.swift:36`). Honour it — but see §4 for the constraint that makes this an accessibility *fix* rather than an accessibility *regression*.

---

## 3. Changes the user sees or can do — needs your sign-off, routes to `WHATS_NEW.md` and `Docs/USER_CHANGELOG.md`

Behaviour changes:
- Chat answers survive leaving the tab (previously cancelled and discarded).
- The transcript stays where you left it instead of jumping to the newest message.
- Database and Atlas keep showing the previous result while refreshing, instead of a spinner.
- The composer stays typable during generation; the attach button is disabled rather than absent.
- Spotlight's library switch now persists across relaunch.
- Ingestion overlay dismissal becomes app-wide rather than per-tab.
- Composer draft and last tab survive scene restoration.

Affordance and copy changes:
- Suggested-prompt card gains a loading state; the "No grounded suggestions are ready yet" line stops appearing while the app is still looking. **This is user-facing copy on the honesty surface — `oi-claim-audit` before touching 3744.**
- Settings mode rows gain press feedback, `.isButton`/`.isSelected` traits, and a haptic on the blocked Maximum press.
- Chunk Inspector rows gain the standard press highlight.
- Library chip strip scrolls the active chip into view.
- Message bubbles gain `.accessibilityAction`s for Copy / Regenerate / Details / Share / Report / Export Trace / Go Deeper / Translate / Illustrate — VoiceOver currently has no route to any of them that does not depend on the visual toolbar.

Motion changes:
- Message insertion, metrics bar and follow-up chips actually animate instead of popping.
- Streaming text stops carrying an ambient animation.
- The refresh icon stops un-spinning.
- Reduce Motion is honoured outside onboarding for the first time.
- If #17 ships: the Atlas hero requires a tap to engage camera control.

---

## 4. Rejected — proposals that trade away functionality

Named plainly, because the record is worth keeping.

**Rejected: `NavigationPath` bindings for pop-to-root and deep-link targeting.** The proposal claimed `NavigationStack` tracks `NavigationLink(destination:)` pushes in a bound path. It does not — a path binding tracks value-based links resolved through `navigationDestination`. This repo has 18 `NavigationLink`s, only 3 value-based, and `navigationDestination` appears only at `GlossaryViews.swift:183` and `GlossaryView.swift:64`. The exact link the proposal named as safe (`DocumentLibraryView.swift:204`) is destination-based. As written it either does nothing for the Spotlight/deep-link case it exists for, or it forces migrating 15 destination-based links, which is precisely the operation that drops destinations. Re-scope to a per-tab migration with the destination inventory enumerated first, or leave it. Related sub-claim, also rejected as asserted: "re-tapping the active tab does nothing" was never established — `TabView` is UIKit-backed and pop-to-root may come through from `UITabBarController` regardless.

**Rejected: reading `LibraryVisualizationEngine.profileCache` in `analyze()`.** The cache is real and genuinely dead (declared 304, written 381, removed 332/341, never read), and it looks like an obvious win. It is not, for two reasons. First, all three call sites of `invalidateCache(for:)` are container **deletion** paths (`ContentView.swift:395`, `DocumentLibraryView.swift:1640`, `LibraryDeletion.swift:108`); ingest, document removal and `clearAllDocuments` (`RAGService.swift:6040/6968/6993`) invalidate `ProjectionCache` only. Today that gap is harmless because nothing reads the cache; making it read converts a dormant gap into live staleness — and a count-based fingerprint is exactly blind to the v5 additive-then-swap migration, which holds chunk count constant by design. Second, `LibraryProfile` embeds time-derived fields computed at build time (`libraryAge` at `LibraryVisualizationEngine.swift:423`, `recentAdditions` at 415) and both are rendered (`AdaptiveVisualizationsView.swift:1449` and `751`), so a count-keyed cache with no TTL prints a library age that stops advancing. The app would state a figure that is no longer true, on the screen whose job is describing the library. Acceptable only with a TTL, recomputed time fields on a hit, **and** the three missing invalidation hooks added first.

**Rejected: emptiness-gated "keep the previous content".** Gating on `stats == nil` / `currentProfile == nil` / `points.isEmpty` renders the *previous* library's or scope's or projection's data under the *new* header. `invalidateCache(for:)` is not called on library switch, and the Database gate at 492 also serves `loadStatistics()` from the scope picker. Must gate on identity. This is a fix to the fix, not a rejection of the finding.

**Rejected: deleting `.animation(..., value: metricsData.tokens)` at `ChatScreen.swift:2027`.** Two of the three in-branch animation modifiers are genuinely dead (2141, 2166 — their `value:` is invariant inside the branch that mounts them). 2027 is not: its value is `metricsData.tokens`, which changes continuously while the bar stays mounted during streaming. It currently animates the live token counter and works. The proposed parent-level replacement is keyed on presence and does not cover it. Delete 2141 and 2166 only.

**Rejected: dropping the `SourceChipsView` staggered reveal (`:39-41`).** It is a deliberate affordance documented in the file header, and the symptom it was proposed to cure — chips fluttering in on transcript scroll — cannot occur. `RetrievalSourcesTray` has zero references outside its own file and `#Preview`, and the only live mount is `ChatScreen.swift:791` inside a sheet, where a one-time stagger is correct.

**Rejected pending evidence: `.contextMenu` on the message bubble.** The finding is real and important — `MessageBubbleV2.swift:177` is the *only* site that can set `showActions = true`, so an arbitration loss makes eleven actions momentarily unreachable. But `.contextMenu` on an ancestor competes for the same long press that drives `.textSelection(.enabled)` (`MarkdownRenderer.swift:466/471/737`). If the menu wins, long-press-to-select and the system Copy / Look Up / Translate / Share menu are gone. If the text interaction wins, the menu only opens in the bubble's 16/12pt padding, which is not where the tap lands. Ship the `.accessibilityAction` half now — unambiguously additive — and hold the context menu for §5.4.

**Rejected as written: the Atlas engagement gate.** `configure(_:)` is called from `updateUIView` (`Embedding3DView.swift:3415-3418`) and unconditionally reassigns `view.scene = buildScene(...)` at 3422. Driving `allowsCameraControl` from new SwiftUI state means the engage tap triggers a full scene rebuild over up to 50,000 points and resets the camera pose — at the exact instant the user asked to interact. Repairable: hoist `allowsCameraControl` out of `configure` and gate the scene assignment on `reloadToken` actually changing. The alternative proposal (reassigning SceneKit's pan delegate) is riskier and should not be the first attempt.

**Rejected as phrased: "substitute a static value" under Reduce Motion.** At several sites the motion *is* the signal — ShimmerBar (`MessageListV2.swift:370`), the blinking cursor (254), `StatusPillV2.swift:106`, `ThinkingStreamView.swift:355`. A static value resolving to the off-phase removes the only in-progress cue for users who turned Reduce Motion on. The requirement is a static **visible** state: cursor solid on, shimmer present at full opacity, pill at full tint.

**Rejected: making the `ChatScreen.swift:791` source chips non-interactive.** Removes an affordance. Wire the empty `onTap` instead.

**Wrong, not lossy — corrected:** `.buttonStyle(.plain)` on Chunk Inspector rows suppresses the row highlight the fix is meant to restore. And "delete the dead property at `ChatScreen.swift:273` to defer singleton construction" does not achieve that on the default path — `HardwareXRayOverlay` (`MotherboardHUDView.swift:291`) holds the same stored property and renders whenever `showSiliconHUD` is true, which is the default (`SettingsStore.swift:581`). Delete the line; drop the claim attached to it.

---

## 5. What needs a device, and what to look at

1. **Does `.task` restart and `onAppear` fire on a `TabView` tab switch here?** This gates §1. Log at `ChatScreen.swift:600`, start a Deep Think answer, switch to Documents, switch back. In-repo circumstantial evidence is strong — the `isAppeared` flag declared at 285 and set at 882/889 exists only to defer suggested-question refreshes while Chat is hidden, which only makes sense if the author watched these fire — but circumstantial is not the same as observed.
2. **Does `ScrollView` content offset survive a tab switch?** Temporarily comment out `MessageListV2.swift:130`, scroll up in a long transcript, leave, return. If the offset is lost you land at the top, and the `lastVisibleMessageID` restore variant is mandatory rather than optional. **Check this before the edit, not after.**
3. **Atlas hero, highest priority.** Library with ≥10 chunks. Drag vertically starting on the globe: does the page scroll or does the globe rotate? Try pull-to-refresh starting on the globe. Try both compact (280pt) and expanded (420pt). Scrollable gutter is ~24pt each side (`LazyVStack` `.padding()` at 190 plus the scene's 8pt at 239). If the page will not scroll, this outranks §1.
4. **Message bubble long press, both branches.** Today: does long-press select text on the `MarkdownText` branch? Note the `structuredAnswer` branch (`MessageBubbleV2.swift:91-97`) renders `GroundedAnswerView`, which has no `.textSelection` at all. Then, on a scratch branch with `.contextMenu` added, re-check both. Also check the citation `Button` nested at `GroundedAnswerView.swift:149`.
5. **Is the Database first-open flicker visible?** Source cannot settle `.task` vs `.onAppear` ordering. Cold-open the tab and watch for spinner → content → spinner.
6. **Instruments, offscreen passes during transcript scroll.** Look at the HUD's `.blur(radius:)` at `MotherboardHUDView.swift:577/640` re-animating from the 25 Hz intensity writes at `HardwareTelemetryState.swift:471`. **Not `glassEffect`** — that was checked and cleared (see §7).
7. **`SourceChip` 44pt hit region overhang.** The strip is padded by `DSSpacing.xxs` (`:56`); a `minHeight: 44` contentShape may steal taps from neighbours.
8. **Curve contention on send.** `messages.append` (2516), `followUpSuggestions = []` (2484) and `scrollToBottom`'s own spring (`MessageListV2.swift:162`) all fire in the same frame. Note the correction: `withAnimation` around the append does **not** put the insertion and the scroll in one transaction — they are two transactions with matching curves starting in the same runloop turn.

---

## 6. Overlap with the throughput audit

- **Already collided and resolved:** the Atlas duplicate `.task` was flagged by both audits and shipped in `dc097cc`. Also in that commit: the streaming bubble now renders plain `Text` and swaps to `MarkdownText` on close. My items #3 and #7 both sit on top of that change — re-read `MessageListV2.swift:132-171` before editing.
- **Launch (`2.94s`) is theirs, not mine.** The CoreML load in `ContentView.init` (`CoreMLSentenceEmbeddingProvider.swift:93` → `:168`) and the synchronous `loadDocumentsFromDisk()` at `RAGService.swift:1654` belong to the throughput audit. Hand them over with one constraint: `isAvailable` is literally `model != nil` (`:203-215`), so a lazy load must be awaited by its callers or `EmbeddingService.forProvider`'s fallback chain picks the wrong provider — and `KnowledgeContainer.embeddingProviderId` is persisted permanently at creation, so a wrong pick is forever.
- **`forProvider` memoisation is theirs.** The create-library hitch (`DocumentLibraryView.swift:1522`, uses only `.actualProviderId` and `.outputDimension`, both already constants at `EmbeddingService.swift:75-81`) and the Container Settings sheet probe (`ContainerSettingsSheet.swift:580`, non-detached `Task` inheriting `@MainActor`) are main-actor blocking. Same constraint as above. Cache the resolved metadata, never the service — `RAGService.swift:5363` calls `enableIngestionMode()` on a per-container instance.
- **The HUD must be one change, not two.** The animation dimension wants one `repeatForever` instead of 25 discrete writes/sec; the deferral dimension wants refcounted start/stop tied to the HUD's `onAppear`/`onDisappear`. Same file, same lines (`HardwareTelemetryState.swift:333/471`, `MotherboardHUDView.swift:615/663/702`). Coordinate or one will land on top of the other. One correction for whoever takes it: the four history arrays (`:150-153`) have zero readers anywhere, but `recordHistory()` also calls `rebuildComponentActivities()` (`:773`) and `componentActivities` **is** read at `MotherboardHUDView.swift:485/1018`. Gate the wrong half and the HUD legend goes static.
- **Stop-blanking vs. list construction.** My #11 edits `DatabaseDashboardView.swift:492` and `AdaptiveVisualizationsView.swift:123`. If the throughput audit is restructuring how those sections build, these must land together or in that order.
- **Not duplicated on purpose:** `ContentView.onChange` string-building, publisher fan-out, `$documents` observation churn and list construction were all left to them.

---

## 7. What turned up nothing

No dimension came back empty — all five have real findings. But several specific hypotheses were checked and **cleared**, and those are worth as much as the hits:

- **`glassEffect` is not the scroll cost.** It appears on chips, three buttons and two containers (`Theme.swift:321-368` plus five call sites) and on **no list row**. Bubble shadows are opacity 0.04 / radius 2. The offscreen work worth measuring is the HUD blur, not the glass.
- **No `.id()`-forced container teardown anywhere.** The only `.id()` calls are per-row identity inside scroll content (`MessageListV2.swift:77-119` and 321, `ThinkingStreamView.swift:152`, `IngestionQueueOverlay.swift:75`). Nothing forces a tab rebuild.
- **No view model built in a tab root's `View.init`.** Every long-lived object is a `@StateObject` on ContentView (14-21) or a singleton. One `StateObject(wrappedValue:)` exists at `ValidationDashboardView.swift:15` — the safe idiom, not a tab root.
- **`@State` genuinely survives tab switches.** Selections, sheet flags and expanded sections come back intact. The defects are appearance callbacks throwing state away, not SwiftUI losing it.
- **Only one instance of the long-press-in-a-horizontal-ScrollView pattern remains** (`SourceChipsView.swift:126`), and it is a different shape from the one you fixed — `minimumDuration: 0` with an empty `perform`, a press tracker, not `0.45` plus a `confirmationDialog`. `ContainerPicker.swift:216-233` is genuinely fixed and the reasoning is written down in the file.
- **Nothing competes with the swipe-back edge.** The app contains exactly one `DragGesture` and it is vertical, on the `UnifiedMetricsBar` handle, which is a sibling of its ScrollView and pinned outside the transcript.
- **Also clear:** `DocumentLibraryView`'s `NavigationLink` + `contextMenu` is textbook; the onboarding paged `TabView`'s inner ScrollViews are orthogonal-axis; the MotherboardHUD pan lives on its own `UIWindow` by design; `hapticTap`'s `simultaneousGesture` has zero call sites; `ThreadSidebarView`'s scrim is an HStack sibling and does not overlay the list.

**Two scope questions, not responsiveness findings, surfaced in passing:** `RetrievalSourcesTray.swift` is an entire unreferenced source-provenance component (zero call sites outside its own file and `#Preview`), and `EmptyStateV2` (`MessageListV2.swift:75-78`) is unreachable because `MessageListV2` is only instantiated at `ChatScreen.swift:2074`, inside the `!messages.isEmpty` branch. Both are yours to decide before anyone touches them.
