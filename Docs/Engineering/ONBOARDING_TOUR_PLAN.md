# Onboarding tour: every screen teaches itself (5.8)

Drafted 2026-11-03 at the owner's word ("Yep, go, do it 10x sdk 27 style") and built the same day (`TourTips.swift`).
**Rebuilt 2026-11-13 as 52 small, paced tips (next section).** First built with 42 stops (41 on 2026-11-03; the X-Ray step added 2026-11-10). Left out of the draft below: the two tab-bar tips and the Settings search tip (a tab and a search
field take no popover), and the Atlas full-screen tip (the Atlas's existing `AtlasTip` already points there). Groups are
`.firstAvailable`, not `.ordered`: tips still show in list order, but one whose rules can't pass yet doesn't hold up the
rest. Each tip's
text is a claim about the app, so each one was written from the control's own code (file and line given) and is
checked again when it is built. `[evidence_level: code_verified for the controls and the TipKit calls, confidence: high]`

## Rebuilt 2026-11-13: small tips, one at a time, when they apply

The owner approved the rebuild ("YES BUILD IT", 2026-11-13) and then widened it the same day: tips "on the parts of the app
that would be ambiguous otherwise", "small, nice and easy to read, little arrows", popping up "when intuitively
necessary"; and, when a draft cut the tour to 30, "removing 11 tips sounds worse???". So every first-tour tip stayed,
and a read-only pass over every screen as a newcomer found nine more (the model pill, the check badge, Fact Check,
swipe to delete a conversation, a library's hold menu, the two icon-only delete chips, the import panel's X, the Atlas's
size buttons). The first tour confused people: the owner's iPhone journal from 2026-11-03 to 11-13 recorded 19 tips used, 14
of them closed without doing the thing, `processingMode` shown on 13 separate launches and still showing, and `newLibrary`
on 13 launches before it was used. `[evidence_level: measured, confidence: high, evidence_source: the owner's iPhone
VerificationJournal tip.status and tip.shown events, 2026-11-03 to 11-13, as relayed by the session that started this
work]` Everything below "How it works" further down is the first tour as built on 2026-11-03, kept as the record.

### What changed, and where in the code

| Part | Before | Now | Code |
|---|---|---|---|
| Pacing | `.displayFrequency(.immediate)`, no per-tip limit: a tip came back every launch until closed | Each tip gives up after 3 showings (`MaxDisplayCount`) or 60 s on screen in all (`MaxDisplayDuration`; 60 s is TipKit's floor, developer.apple.com/documentation/tipkit/tips/maxdisplayduration, fetched 2026-11-13, and the Simulator's TipKit log showed the 60 s monitor). One new tip at most every 90 s, none in the first 60 s after launch | `TourTip.options`, `Tour.claimTurn`, `Tour.startPacing`, `TourContext.pace` |
| Why a rule paces it | | TipKit's `DisplayFrequency` offers `immediate`, `hourly`, `daily`, `weekly`, `monthly` and nothing shorter (Xcode 27.0's `iPhoneOS27.0.sdk` TipKit.swiftinterface), so "every few minutes" is a `#Rule` on a `.transient` parameter: "launch", then "open", then the name of the one paced tip that holds the turn | `TourTip.rules` |
| Essentials | none | Six skip the pacing, each tied to the moment it applies: the empty chat, the first source, a source's match line, the answer modes, "not in your documents", Add Document | `TourStep.isEssential` |
| Count | 41 tips, plus `AtlasTip` and `ModelConfigTip` | 52: the 41 kept and rewritten short, "not in your documents", and nine found by the newcomer pass (`TourTipTests` keeps it at 41 or more) | `TourStep`, `Tour.screens` |
| Triggers | the screen opened | what the person did: an answer that found nothing (`StructuredAnswer.refuse` → `TourContext.lastAnswerNotFound`), a large import running (3+ files, or a file of 50 pages or 10 MB → `TourContext.largeImportRunning`), the second answer, the third document | `ChatScreen+Sending.swift`, `IngestionQueueOverlay.isLargeImport` |
| Placement | popovers everywhere, toolbar items included | popovers with an arrow on in-content controls; cards in content (`TourCard`) for the empty chat, the first answer with a source, and an answer that found nothing; the three toolbar buttons (sidebar, Apple Intelligence, More) get a `TipView` under the toolbar whose arrow points at the button through iOS 26's `tipAnchor`, never a popover on the toolbar item | `TourTipModifier`, `TourCard`, `TourCardStyle`, `TourToolbarTips`, `tourAnchor` |
| Look | system popover; `CompactTipViewStyle` on `.ultraThinMaterial` for two inline tips | system popover (Liquid Glass on iOS 26 and later); cards on `glassEffect(.regular)` with the app's accent, its caption and subheadline sizes and a 44-point close button | `TourCardStyle` |
| Anchoring | the popover on the control | a popover hangs from a clear layer behind its control (`TourTipModifier`): on a control with interactive Liquid Glass (Documents' action chips) the popover attached to the control drew its words with no background (the iOS 27 Simulator, 2026-11-13). The toolbar tips are drawn over Chat's header (`ChatScreen+Content.swift`): drawn at the top of the whole chat they sat behind the navigation bar, shown by TipKit's own log and invisible | `TourTipModifier`, `TourToolbarTips` |
| Size | Apple's popover with a 40-point icon and 17-point body text, about a third of a 6.3-inch screen | a 24-point icon (`tipImageSize`) and text set on the tip's own `Text`: subheadline semibold title and footnote sentence (15 and 13 points at the default size, against TipKit's 17), still following Dynamic Type. Tried first and dropped: a custom popover style (it broke the popover's layout, the close button clipped) and a smaller `dynamicTypeSize` around the popover (it reached the inline toolbar tip, not the popover) | `TourTip.title`, `TourTip.message`, `tourTipSize()` |
| Words | up to 220 characters, several sentences | a title of at most four words, one sentence of at most 130 characters, each rewritten from its control's code | `TourTipTests.testEveryTipIsShort` |
| Actions | none | Try a Question (asks the first suggested question), Show Me (opens the first source; opens an answer's buttons), Go Deeper, New Library | `TourStep.actionTitle`, `.tour(perform:)`, `TourCard(perform:)` |

`[evidence_level: code_verified, confidence: high]`

Tests: `TourTipTests` (unit, 9 of 9 pass) and `TourTipCloseUITests` (each tip closes on one tap of its X, 3 of 3 pass) on an iOS 27 Simulator, 2026-11-13. `TourFlowUITests` (a fresh install's empty-chat card asks a question, the answer carries the citation card, Show Me opens the source with its match-line tip) has not passed yet: it skipped twice, because on a heavily loaded Mac the guide library's import outlasted the card's minute on screen. Run it on a freshly erased simulator on a quiet Mac. Nothing here was checked on a device.

No popover sits on a toolbar item. Through the first 5.8 builds a `.popoverTip` on Chat's toolbar buttons put TipKit's
`UIAppearanceMonitor` controller into Chat's navigation stack, and tapping the Chat tab again blanked Chat (fixed in
9049d416 by attaching a popover only while its tip shows; that fix stays in `TourTipModifier`). The toolbar tips use
iOS 26's `tipAnchor(_:)` with `TipView(_:arrowEdge:anchorID:)`, drawn in Chat's content (Apple: "Use this modifier to
specify an anchor view for a TipView's arrow to point towards", developer.apple.com/documentation/swiftui/view/tipanchor(_:),
fetched 2026-11-13). Settings › How This Works › Where Things Are also describes them.

### The 52 tips

One at a time per screen (`TipGroup(.firstAvailable)`, in this order). "Paced" means it waits its turn (`Tour.claimTurn`).

| Screen | Tip (step) | Control | File | Shows when |
|---|---|---|---|---|
| Chat | Ask your documents (`composer`) | card in the empty chat, Try a Question | `FirstQueryPromptView.swift` | no answer yet, suggestions ready |
| Chat | Not in your documents (`notFound`) | card under the answer, Go Deeper | `MessageBubbleV2.swift` | the newest Standard answer found nothing to stand on |
| Chat | Check the source (`citation`) | card under the answer, Show Me | `GroundedAnswerView.swift` | the newest answer has a source |
| Chat | Checked against your files (`factCheck`) | Fact Check count | `GroundedAnswerView.swift` | the newest answer has claims, paced |
| Chat | Standard or Deep Think (`modePicker`) | mode picker | `ChatScreen.swift` | after the first answer |
| Chat | Where answers are written (`modelPill`) | model pill (Hybrid, On-Device, PCC) | `ChatScreen.swift` | after the first answer, paced |
| Chat | Tap an answer (`answerBubble`) | the newest answer, Show Me | `MessageBubbleV2.swift` | after the second answer, paced |
| Chat | Not enough? Go Deeper (`goDeeper`) | Go Deeper | `MessageActionsBar.swift` | the answer's buttons are open, paced |
| Chat | How it was answered (`details`) | Details | `MessageActionsBar.swift` | the answer's buttons are open, paced |
| Chat | Where it ran (`routeBadge`) | route badge | `MessageBubbleV2.swift` | after the first answer, paced |
| Chat | How it held up (`verdictBadge`) | check badge (Verified ... Not Checked) | `MessageBubbleV2.swift` | after the first answer, paced |
| Chat | Rework an answer (`aiHub`) | Apple Intelligence toolbar button, tip under the toolbar | `ChatScreen+Actions.swift` | after the first answer, paced |
| Chat | Questions search one library (`libraryPills`) | another library's pill | `ChatScreen.swift` | 2+ libraries, paced |
| Chat | Add a file here (`attach`) | attach | `ChatComposerV2.swift` | after the first answer, paced |
| Chat | Say it instead (`dictation`) | microphone | `ChatComposerV2.swift` | after the first answer, paced |
| Chat | New chat and export (`moreMenu`) | More toolbar menu, tip under the toolbar | `ChatScreen+Body.swift` | after the second answer, paced |
| Chat | Your conversations (`sidebar`) | sidebar toolbar button, tip under the toolbar | `ChatScreen+Body.swift` | after the third answer, paced |
| Chat | Keyboard shortcuts (`keyboard`) | question box | `ChatComposerV2.swift` | Mac, second launch, paced |
| Conversations | Swipe to delete (`threadSwipe`) | first conversation | `ThreadSidebarView.swift` | the list is open, paced |
| Source | Is it really there? (`matchBanner`) | match line | `SourceTextView.swift, SourcePageView.swift` | the first source opened |
| Source | Need more context? (`moreContext`) | Show Earlier/Later Text | `SourceTextView.swift` | paced |
| Documents | Add your files (`addDocument`) | Add Document chip | `DocumentLibraryView+DocumentList.swift` | first visit |
| Documents | This library's settings (`librarySettings`) | Library Settings chip | `DocumentLibraryView+DocumentList.swift` | 1+ document, paced |
| Documents | Paste works too (`paste`) | Paste chip | `DocumentLibraryView+DocumentList.swift` | 1+ document, paced |
| Documents | Search by meaning (`semanticSearch`) | Semantic Search chip | `DocumentLibraryView+DocumentList.swift` | 3+ documents, paced |
| Documents | Keep topics apart (`newLibrary`) | New Library, New Library button | `ContainerPicker.swift` | 3+ documents, paced |
| Documents | Hold a library (`libraryMenu`) | first library pill (hold menu) | `ContainerPicker.swift` | 1+ document, iPhone and iPad, paced |
| Documents | Touch and hold (`documentMenu`) | first document card | `DocumentLibraryView+DocumentList.swift` | 3+ documents, iPhone and iPad, paced |
| Documents | Drop files here (`dragAndDrop`) | document list | `DocumentLibraryView+DocumentList.swift` | iPad and Mac, paced |
| Documents | Empty this library (`removeAll`) | Remove All Documents chip | `DocumentLibraryView+DocumentList.swift` | 1+ document, paced |
| Documents | Delete this library (`deleteLibrary`) | Delete Library chip | `DocumentLibraryView+DocumentList.swift` | 2+ libraries, paced |
| Import | Pause anytime (`pauseImport`) | Pause | `IngestionQueueOverlay.swift` | an import of 3+ files, or of 50 pages or 10 MB, paced |
| Import | Stop or hide (`importStop`) | the panel's X | `IngestionQueueOverlay.swift` | an import can be stopped, paced |
| Import | Faster or cooler (`processingMode`) | processing mode | `IngestionQueueOverlay.swift` | an import runs, paced |
| Library Settings | Watch a folder (`watchFolder`) | Watch a Folder | `WatchedFolderSection.swift` | paced |
| Library Settings | How this library searches (`searchStyle`) | search style | `ContainerSettingsSheet+Search.swift` | paced |
| Library Settings | Documents in another language? (`translation`) | Translation Language | `ContainerSettingsSheet+Intelligence.swift` | paced |
| Atlas | What the map found (`insights`) | first insight card | `AdaptiveVisualizationsView.swift` | paced |
| Atlas | Change the view (`atlasSettings`) | slider button | `AdaptiveVisualizationsView.swift` | paced |
| Atlas | Map size (`atlasMode`) | smaller and larger buttons | `AdaptiveVisualizationsView.swift` | paced |
| Atlas | All libraries at once (`allLibraries`) | libraries picker, full screen | `Fullscreen3DAtlasView.swift` | 2+ libraries, paced |
| Database | One library or all (`databaseScope`) | scope chips | `DatabaseDashboardView+Header.swift` | paced |
| Database | Look inside the index (`databaseSections`) | section picker | `DatabaseDashboardView+Header.swift` | paced |
| Database | Something off? (`runCheck`) | Run Check | `DatabaseDashboardView+MaintenanceAndSearch.swift` | paced |
| Settings | How it really works (`howItWorks`) | How This Works row | `SettingsView+List.swift` | paced |
| Settings | Cloud use is optional (`privateCloud`) | Private Cloud Compute row | `SettingsView+List.swift` | the device supports it, paced |
| Settings | Every term explained (`glossary`) | Plain English row | `SettingsView+List.swift` | second Settings visit, paced |
| Settings | Ask with Siri (`siri`) | Siri & Shortcuts row | `SettingsView+List.swift` | second Settings visit, paced |
| Settings | See the work (`technicalDetails`) | Appearance › Technical Details | `SettingsView+AppearanceAndSupport.swift` | paced |
| Settings | Where your chip is (`xray`) | Appearance › Telemetry HUD | `SettingsView+AppearanceAndSupport.swift` | not a Mac, a measured chip spot, paced |
| Settings | Menu bar questions (`menuBar`) | Appearance, Mac | `SettingsView+AppearanceAndSupport.swift` | Mac, paced |
| Plans | Have a code? (`redeemCode`) | Redeem a Code | `PlanUpgradeSheet.swift` | paced |

Every tip also needs the welcome closed, and goes for good once its control is used (`Tour.used`), its X is tapped, it
has been shown 3 times, or it has been on screen 60 s in all.

## The first tour as built on 2026-11-03 (superseded 2026-11-13)

### How it works

1. **The welcome stays as the first-run path.** Its two pages and the sample library are unchanged.
2. **Each screen teaches itself the first time it is opened.** A screen's tips are one `TipGroup(.ordered)`: one arrow at a
   time, in a set order, each on its control. The next appears when the last is closed or used.
3. **A tip goes the moment its control is used.** Every tip has an event, donated in the control's own action, and a rule
   that hides it once the event has happened. So nobody is shown a button they already found.
4. **The screen keeps working while a tip is up** (`tipBackgroundInteraction(.enabled)`). A tip never blocks a tap.
5. **Tips that need context wait for it.** Answer tips wait for the first answer, the import queue's tips for an import,
   the Atlas's for 10 passages. A Pro or Lifetime control's tip says so plainly.
6. **"Show Me Around"** in Settings › How This Works, beside Replay Introduction, shows every tip again without a relaunch
   (`resetEligibility()` on each tip). Replay Introduction also replays the welcome.
7. **Measured.** Each tip shown, closed and acted on is written to the development build's event log
   (`VerificationJournal`, from each tip's `statusUpdates`), so the next phone pull shows where people stop.

### The SDK calls, read from the iOS 27 SDK on this Mac (Xcode 27, 2026-11-03)

| Call | Available from | Used for |
|---|---|---|
| `TipGroup(.ordered) { ... }`, `group.currentTip` | iOS 18, macOS 15 | One screen's tips in order |
| `.popoverTip(_:arrowEdge:)`, and `arrowEdges:` (a set) | iOS 17; the set from iOS 26 | The arrow on a control |
| `.tipAnchor(id)` with `TipView(tip, anchorID: id)` | iOS 26, macOS 26 | A tip for a toolbar button or a menu, drawn beside it and pointing at it |
| `.tipBackgroundInteraction(.enabled)` | iOS 26, macOS 26 | The screen stays usable under a tip |
| `Tips.Event` with `DonationLimit` | iOS 26 | One event per control, kept small |
| `#Rule` with `disjunction` (either-or rules) | iOS 26 | "Hide when used here or there" |
| `tip.resetEligibility()` | iOS 26 | Show Me Around, no relaunch |
| `tip.statusUpdates` | iOS 17 | Recording shown and invalidated in the event log |
| `Tips.ConfigurationOption` CloudKit sync | iOS 18 | Not used: it needs a CloudKit container, an entitlements change. A tip seen on the iPhone shows once on the Mac too |

TipKit has no API tagged iOS 27 in this SDK. Apple's own change list stops at 2024.

## Found while inventorying, fixed with the tour

- **Three tips never show.** `FirstQueryTip`, `IngestDocumentTip` and `ContainerTip` (`AppTips.swift:17, 42, 67`) exist
  and nothing displays them or donates their events (removed with the tour; `AppTips.swift:19-20` records it). They become the composer, Add Document and New Library tips below.
- **The setup step that may never finish.** The welcome's third step completes only when the model is changed by hand
  (`OnboardingStateStore`, `ContentView.swift:423`), and the only screen that changes it, `QuickModelPickerSheet`, isn't
  used anywhere (removed 2026-11-06: only a `#Preview` created it; `ModelStatusIndicator`'s menu is the live picker `[evidence_level: code_verified, confidence: exact, evidence_source: grep -rw QuickModelPickerSheet OpenIntelligence: no hits after removal; ModelStatusIndicator.swift:11]`). So the launcher at the bottom right may stay until skipped. Not seen on a device; checked first.
- **An answer's buttons are hidden behind a tap on the bubble** (`MessageBubbleV2.swift:191`) and nothing says so. Tip 2.4.
- **Not tipped, because they don't work:** Illustrate under an answer is never shown (ChatScreen never passes
  `onIllustrate`); the source chips under an answer do nothing (an empty closure, ChatScreen :971); the old 3D view's
  controls are unreachable (`VisualizationsView` was used by nothing; removed 2026-11-06 with `PipelineTimelineView` and `SemanticClusteringView`, and the Atlas tab shows `AdaptiveVisualizationsView` `[evidence_level: code_verified, confidence: exact, evidence_source: grep -rw VisualizationsView OpenIntelligence: only provenance comments in moved files, no declaration or use after removal; AdaptiveVisualizationsView.swift exists]`). Each gets a Future Backlog row rather than a tip.

## The tips, screen by screen

Each line: **the control** (file:line) — the tip's title / its one sentence — when it shows. 46 in all.

### 1. Tab bar (`ContentView.swift:433`)
1. **Documents tab** (:446) — "Your documents live here" / "Add files, switch libraries, and see what's imported." — first launch after the welcome.
2. **Atlas tab** (:457) — "See your library as a map" / "Similar passages sit together, so you can see what your documents cover." — after 10 passages exist.

### 2. Chat (`ChatScreen.swift`, `ChatComposerV2.swift`)
1. **Composer** (`ChatComposerV2.swift:122`, was `FirstQueryTip`) — "Ask about your documents" / "Answers come from your own files, with links to where each point came from." — empty chat.
2. **Mode picker** (`ChatScreen.swift:330`) — "Choose how hard it works" / "Standard is fastest. Deep Think checks several searches. Maximum goes deepest." — after the first answer.
3. **Library pills** (`ChatScreen.swift:405`) — "Switch libraries here" / "Questions only search the library that's selected." — when 2 or more libraries exist.
4. **Answer bubble** (`MessageBubbleV2.swift:198`) — "Tap an answer for more" / "Copy, share, retry, translate, or see exactly how it was answered." — first answer.
5. **A citation** (`GroundedAnswerView.swift:40`) — "Tap a citation to check it" / "It opens the passage in your document, highlighted, and says whether it was found word for word." — first answer with a citation.
6. **Go Deeper** (`MessageActionsBar.swift:63`) — "Not enough? Go Deeper" / "Asks again with several searches and checks." — first time the actions bar opens on a single-pass answer.
7. **Details** (`MessageActionsBar.swift:126`) — "See how it was answered" / "Which passages were used, how each claim held up, and where it ran." — same, after 2.6.
8. **Route badge** (`MessageBubbleV2.swift:252`) — "Where it ran" / "On-device means nothing left your phone. Private Cloud Compute only runs if you allow it." — first answer.
9. **Dictation** (`ChatComposerV2.swift:135`) — "Or just say it" / "Dictate your question." — second visit to Chat.
10. **Attach** (`AttachmentPicker.swift:339`) — "Add a file from here" / "A file you attach joins this library and this conversation." — second visit.
11. **Sidebar** (`ChatScreen+Body.swift:438`) — "Your conversations" / "Each conversation is kept, with its sources." — after the second conversation.
12. **AI Hub** (`ChatScreen+Actions.swift:699`, iPhone and iPad) — "Rework an answer" / "Key facts, step by step, plain English, or what's missing." — after the first answer.
13. **More menu** (`ChatScreen+Body.swift:485`) — "New chat and export" / "Start fresh, export a conversation, or turn on Technical Details." — third visit.

### 3. Citation screens (`SourcePageView.swift`, `SourceTextView.swift`)
1. **Match banner** (`SourceTextView.swift:240`, `SourcePageView.swift:51`) — "Is it really there?" / "This line says whether the passage was found word for word, in part, or not at all." — first open.
2. **Show Earlier/Later Text** (`SourceTextView.swift:255`) — "Need more context?" / "Show the text around the passage." — first open of a non-PDF source.

### 4. Documents (`DocumentLibraryView.swift`)
1. **Add Document** (`DocumentLibraryView+DocumentList.swift:420`, was `IngestDocumentTip`) — "Add your files" / "PDFs, Word, spreadsheets, slides, images, recordings and more." — empty library.
2. **Paste** (`DocumentLibraryView+DocumentList.swift:437`) — "Paste works too" / "A copied file, link or text becomes a document." — after the first import.
3. **New Library** (`ContainerPicker.swift:165`, was `ContainerTip`) — "Keep topics apart" / "Each library has its own documents and settings." — after 3 documents.
4. **Library Settings** (`DocumentLibraryView+DocumentList.swift:460`) — "Tune this library" / "Search style, chunking, translation, and a watched folder." — after the first import.
5. **Semantic Search** (`DocumentLibraryView+DocumentList.swift:449`) — "Search by meaning" / "Find passages without asking a question." — after 3 documents.
6. **Document card, long press** (`DocumentCard.swift:118`) — "More on a document" / "Hold it to copy its link or delete it." — after 3 documents.
7. **Drag and drop** (`DocumentLibraryView+DocumentList.swift:71`, Mac and iPad) — "Drop files here" / "Drag files or a whole folder in." — first Documents visit on a Mac or iPad.

### 5. Import queue (`IngestionQueueOverlay.swift`)
1. **Pause** (:662) — "Pause anytime" / "Pick up later right where it stopped." — first import of 3 or more files or a large PDF.
2. **Processing mode** (:718) — "Faster or cooler" / "Choose how hard the phone works while importing." — same, after 5.1.

### 6. Library Settings (`ContainerSettingsSheet*.swift`)
1. **Watch a Folder** (`WatchedFolderSection.swift:52`) — "Keep up with a folder" / "New files there import by themselves. Pro and Lifetime." — first open.
2. **Search style cards** (`ContainerSettingsSheet+Search.swift:24`) — "How this library searches" / "Automatic suits most. Technical Manual favors exact words and part numbers." — first open.
3. **Translation Language** (`ContainerSettingsSheet+Intelligence.swift:33`) — "Documents in another language?" / "Passages are translated into the language you pick before they're searched." — first open, after 6.2.

### 7. Atlas (`AdaptiveVisualizationsView.swift`)
1. **Full screen** (:229, keeps `AtlasTip`) — "Open the full map" / "Turn it, zoom it, and see every library at once." — first visit.
2. **Atlas settings** (:431) — "Change the view" / "Projection, point size, labels and background." — after 7.1.
3. **Insight cards** (:749) — "What the map found" / "Tap one to see that part of your library." — first visit with insights.
4. **Libraries picker** in full screen (`Fullscreen3DAtlasView.swift:459`) — "All libraries at once" / "Compare what each library covers." — first full screen with 2 or more libraries.

### 8. Database (`DatabaseDashboardView.swift`)
1. **Scope chips** (`DatabaseDashboardView+Header.swift:330`) — "One library or all" / "Pick which library these numbers describe." — first visit.
2. **Section picker** (`DatabaseDashboardView+Header.swift:365`) — "Look inside the index" / "Documents, vocabulary, maintenance and search." — after 8.1.
3. **Run Check** (`DatabaseDashboardView+MaintenanceAndSearch.swift:32`) — "Something off?" / "Run Check looks for problems in this library's index." — first Maintenance visit.

### 9. Settings (`SettingsView.swift`)
1. **Search settings** (`SettingsView+List.swift:302`) — "Find any setting" / "Type what you're after." — first visit.
2. **How This Works** (`SettingsView+List.swift:82-92`) — "How it really works" / "What runs where, in plain words, and Show Me Around." — first visit, after 9.1.
3. **Private Cloud Compute** (`SettingsView+ModelAndCloud.swift:143`) — "You decide when it's used" / "Never, ask each time, or for long questions." — first visit on a device that supports it.
4. **Plain English** (Glossary) — "Every term explained" / "What each word in the app means." — second visit.
5. **Appearance › Technical Details** (`SettingsView+AppearanceAndSupport.swift:79`) — "Want to see the work?" / "Show the metrics bar and passage counts under answers." — first Appearance visit.
5a. **Appearance › Telemetry HUD** (`TourStep.xray`, added 2026-11-10) — "Where your chip is" / what the outline marks, the component colors, the Taptic Engine outline (the motor behind each tap), and that the Labels switch hides the names (revised 2026-11-10: every outline is the chip itself now, so the logic-board sentence is gone) — first Appearance visit, not on a Mac and not on a device with no measured chip spot.
6. **Siri & Shortcuts** — "Ask without opening the app" / "Siri and Shortcuts can ask, search and add." — second visit.
7. **Advanced** (`SettingsView+List.swift:233`, keeps `ModelConfigTip`) — unchanged.

### 10. Plans (`PlanUpgradeSheet.swift`)
1. **Redeem a Code** (:405) — "Have a code?" / "Redeem it here." — first open.

### 11. Mac only
1. **Keyboard shortcuts** (`AppCommands.swift`) — "Faster with the keyboard" / "⌘1 Chat, ⌘2 Documents, ⌘F search, ⌘[ and ⌘] switch libraries." — third launch on a Mac.
2. **Menu bar** (Appearance, `SettingsView+AppearanceAndSupport.swift:205`) — "Ask from the menu bar" / "A question box that's always one click away." — first Appearance visit on a Mac.

## Size and order of work

About 46 tips across 11 screens, built screen by screen: Chat first, then Documents, Library Settings and the citation
screens, then Atlas, Database, Settings, Plans and the Mac. Each screen is built, run in the Simulator with every tip
forced on (`Tips.showAllTipsForTesting()` in a Debug launch argument only), screenshotted, and installed on the owner's
phone before the next. The tip text above is a draft: he edits it before it is built.

## Open for the owner

- The wording of any tip above.
- Whether the Database tab gets tips at all, since it is the most technical screen.
