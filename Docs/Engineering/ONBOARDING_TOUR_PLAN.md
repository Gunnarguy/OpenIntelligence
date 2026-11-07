# Onboarding tour: every screen teaches itself (5.8)

Drafted 2026-11-03 at the owner's word ("Yep, go, do it 10x sdk 27 style") and built the same day (`TourTips.swift`).
**As built: 41 stops.** Left out of the draft below: the two tab-bar tips and the Settings search tip (a tab and a search
field take no popover), and the Atlas full-screen tip (the Atlas's existing `AtlasTip` already points there). Groups are
`.firstAvailable`, not `.ordered`: tips still show in list order, but one whose rules can't pass yet doesn't hold up the
rest. Each tip's
text is a claim about the app, so each one was written from the control's own code (file and line given) and is
checked again when it is built. `[evidence_level: code_verified for the controls and the TipKit calls, confidence: high]`

## How it works

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
