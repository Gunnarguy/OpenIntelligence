# App Store metadata history

Every version of the App Store copy this repository has pushed, oldest at the bottom: release
notes per platform, promotional text, and the description, name, subtitle and keywords when they
changed. Reconstructed on 2026-09-14 from the git history of `fastlane/metadata/` and
`fastlane/metadata-ios/` (47 commits, 67 distinct file versions), at the owner's request.

**Why it exists.** `fastlane/metadata*` holds only the *current* copy; the moment a release is
staged, the previous release's text is gone from the working tree. `.claude/rules/user-facing-copy.md`
records what that cost: release notes drifted through three shapes because each one was written
without looking at the last. This file is the last one, and every one before it.

**How to use it.**

1. **Before writing a release's copy**, read the two most recent entries here. Match their shape
   and voice. `WHATS_NEW.md` and `Docs/USER_CHANGELOG.md` are the sources for the *content*; this
   file is the source for the *form*.
2. **When you write a release's copy**, copy the template below into the top of the "Versions"
   section and fill it in: version, platforms, the date it went live (from
   `Docs/SHIPPED_VERSION.json`, never from `CHANGELOG.md`'s heading, which is the version being
   prepared), the commit, and the text verbatim. Pre-commit enforces two things whenever
   `fastlane/metadata*` is staged (`scripts/enforce_docs_hook.sh`): this file is staged too, and it
   holds a `### <version>` heading for the version `Docs/SHIPPED_VERSION.json` says is being
   prepared. It also checks the shape of a staged `release_notes.txt` against the template: an
   intro paragraph, at least one ALL-CAPS section heading, `• ` bullets, under 4,000 characters;
   and `promotional_text.txt` under 170.
3. **Do not edit an old entry's text.** It is what the store showed. If it turns out to be wrong,
   add a dated note under it, as the 5.2 entry does.

**What it is not.** App Store Connect is the authority for what is live. This records what the
repo pushed and when; where the store may have shown something else, the entry says so.

`[evidence_level: code_verified, confidence: exact, evidence_source: git log -- fastlane/metadata fastlane/metadata-ios, 2026-04-15 to 2026-09-10; Docs/SHIPPED_VERSION.json _comment history for live dates; Docs/USER_CHANGELOG.md headings for release dates the marker file predates]`

## Template for the next version

The shape is the one 5.1 and 5.2 shipped in, which is the shape every future release keeps. Copy
this block to the top of "Versions, newest first" and replace the angle-bracket parts. Nothing
else about the block changes: not the field order, not the headings, not the code fences.

```markdown
### <X.Y>

- **Platforms:** <iOS, macOS | iOS only | macOS only>
- **Live:** <YYYY-MM-DD on both platforms, build <N> (`Docs/SHIPPED_VERSION.json`)> | not yet; records in PREPARE_FOR_SUBMISSION
- **Final release notes commit:** `<sha>` (<YYYY-MM-DD>)
- **Notes:** <what changed since the previous entry's copy, and any platform divergence; omit the line if nothing is worth saying>

**Release notes (`fastlane/metadata/`<, the macOS copy | , both platforms>):**

```text
<One or two sentences of plain prose saying what this release is about. No heading, no bullet.>


<SECTION NAME IN CAPS, A SHORT NOUN PHRASE>

• <One bullet per change: a full sentence or two, plain language, what a user notices first.>

• <Next bullet.>


<NEXT SECTION IN CAPS>

• <...>


<One closing line, the same every release unless the truth changed: "Everything still runs on your device." or the 5.2 form, "Everything except that one writing step still runs on your device.">
```

**Release notes (`fastlane/metadata-ios/`, `<sha>` <date>):** <only when iOS and macOS differ; otherwise delete this block and say "both platforms" above>

**Promotional text** (`<sha>`):

```text
<One or two sentences, at most 170 characters, naming the single thing a store visitor should know this release. No version number.>
```

**Description** (`<sha>`): <only when `description.txt` changed; otherwise delete this block>
```

**The rules the template encodes.**

- The release notes open with prose, never a heading, and close with the device line. Section
  headings are short noun phrases in capitals with two blank lines before them and one after.
  Bullets are `• ` (U+2022 and a space), each a complete sentence a user could act on, one per
  change, blank line between bullets. No em dashes anywhere in store copy; `bd70890` stripped them
  on 2026-07-28 and they have not come back.
- Sections are ordered by what a user notices first, not by subsystem. A correction to a claim in
  the previous release gets its own section, headed as such (5.2: "A CORRECTION FROM 5.1").
- Numbers only when measured, with the hardware named (5.2: "on an iPhone with the A18 Pro").
- Limits, from App Store Connect: release notes 4,000 characters, promotional text 170,
  description 4,000. `492bfc7` trimmed 4,972 to fit on 2026-06-10, after the fact.
- Per-platform notes exist only when the platforms genuinely differ (5.1, when iOS was two Mac
  releases behind). When they do not, one text in `fastlane/metadata/` and the same text in
  `fastlane/metadata-ios/`, and the entry says "both platforms". 5.2's divergence (the macOS copy
  rewritten on 2026-09-10, the iOS copy not) is the mistake this line exists to prevent.

`[evidence_level: code_verified, confidence: exact, evidence_source: the 5.1 and 5.2 entries below; scripts/enforce_docs_hook.sh metadata block; App Store Connect field limits as enforced by fastlane deliver]`

## Current listing text, as of 2026-09-14 (the description was superseded in the repo on 2026-09-18; see the 5.3 entry below. This was the listing until 5.3 went live on 2026-09-18.)

The description, name and promotional text that `push_metadata` would send today. The description
changed eleven times between 2026-04-15 and 2026-09-02; the full sequence is in git and only the
current one is reproduced here.

**Name** (`fastlane/metadata/en-US/name.txt`, pinned `94f6546` 2026-08-31):


```text
OpenIntelligence
```

**Description** (`fastlane/metadata/en-US/description.txt`, last changed `a375fc8` 2026-09-02):

```text
You already have the answers. They're just buried in a 300-page manual, a folder of contracts, a semester of lecture recordings, or a codebase you inherited.

OpenIntelligence reads what you import and answers questions about it in plain language, with citations you can tap to see exactly where each claim came from. And when your files don't actually contain the answer, it tells you so instead of guessing confidently.

ANSWERS START IN YOUR FILES

Not in a chatbot's imagination. OpenIntelligence searches your library first, pulls the exact passages that matter, and only then writes, using Apple's on-device Apple Intelligence models. Requires an Apple Intelligence-capable device: iPhone 15 Pro or later, or an M1-or-later iPad or Mac, on iOS/iPadOS/macOS 26. Your device already had the intelligence. This gives it your knowledge, and rules of evidence.

WHAT YOU CAN DO

- Summarize long documents, recordings, or entire libraries.
- Compare claims and details across multiple sources.
- Find exact facts, dates, specifications, measurements, and table values.
- Ask follow-up questions without losing the sources or the thread.
- Choose Standard for quick factual work, Deep Think for multi-step questions, or Maximum for broader evidence synthesis.

BRING YOUR OWN MATERIAL

Import PDFs, Office documents, text and Markdown files, CSVs, code, images and scans, audio, or video. Pages, Numbers and Keynote files need to be exported to PDF first. OpenIntelligence extracts text, uses Vision OCR where needed, transcribes speech, and builds a searchable index for each library.

HOW ANSWERS ARE BUILT

Exact keyword matching and semantic search work together to retrieve the passages that matter. Apple Foundation Models turn those passages into a natural-language response. Then the app checks its own answer against the passages it actually used, so you can inspect what it's standing on instead of taking its word.

If the sources do not establish an answer, the app flags weak support or abstains. No confident filler.

WHERE YOUR FILES GO (AND DON'T)

Reading your files, searching them, and choosing what to cite all happen on your device, start to finish, before anything is written. On-device answers need no connection at all. On a plane, in a dead zone, in a locked-down office, your library still works. For longer, evidence-heavy questions on iOS, iPadOS or macOS 27, you can optionally allow Apple Private Cloud Compute to write the answer. The app shows you exactly what would be sent and asks you to approve it first, and Apple's servers keep nothing afterwards. Your material is never sent to a third-party AI provider.

ANSWERS YOU CAN INSPECT

Inline citations connect answers to their supporting pages and passages, one tap from claim to source. If you want more, response details go deeper: source snippets, retrieval quality, verification warnings, timing, and the route that actually produced the answer. The optional telemetry interface goes deeper when you want it and stays out of the way when you don't.

LIBRARIES THAT FIT YOUR WORK

Keep different subjects, projects, or clients in separate libraries. Choose Local Only or iCloud Drive for each library, and organize ongoing research in saved conversation threads. Siri and Shortcuts actions are available for common document and library workflows.

OpenIntelligence is built and maintained by one developer. Pro and Lifetime support directly fund continued development. To everyone already supporting the app: thank you. It has been a wild journey.

Privacy Policy: https://gunzino.me/openintelligence/privacy
```

**Promotional text**, both platforms (`a375fc8` 2026-09-02):

```text
Private Cloud Compute is on. Questions too big for the on-device model can be written on Apple's servers, after you approve exactly what would be sent.
```

## Versions, newest first

### 5.4

- **Platforms:** iOS, macOS
- **Live:** not yet; records in PREPARE_FOR_SUBMISSION on both platforms (iOS `edac9a46-fd9c-4082-99f8-372008d20289`, macOS `0e7e7d98-9878-4418-b977-3bc0b04ddf96`, read from the API 2026-09-20)
- **Final release notes commit:** the store-copy commit of 2026-09-22 that follows `0f6c5a0`; revise if 5.4 gains more user-facing entries before it ships
- **Notes:** this entry exists for the promotional text, which is the only copy that changed. **The two repo trees had drifted apart and both were wrong for 5.4.** `fastlane/metadata*` is a push source, not a record of what is live, and both trees held the 5.3 *sale* text while App Store Connect's 5.4 records already held non-sale text. A `fastlane` push for 5.4 would therefore have put a sale line onto a release that ships after the sale ends on 2026-09-30. Both trees now carry the same non-sale text that is already on the 5.4 records, so the repo and the store agree. **The sale text still stands on the live 5.3 records and is corrected separately:** it said "Lifetime is 33% off", which one string cannot be across storefronts that measure 32.2% in India, 30.8% in Mexico and 40.0% in Australia, while the app computes and shows the true percentage for the customer's own storefront. `scripts/asc_fix_listing_copy.rb` replaces it on both live records and drops the figure. "Unlimited documents" is kept there deliberately: `QuotaPolicy.lifetimeDocumentLimit` is `unlimitedDocumentLimit`, so for Lifetime it is true.

**Promotional text (`fastlane/metadata/` and `fastlane/metadata-ios/`, both platforms, 166 characters):**

```text
The sample library's questions are back, the welcome screens follow light and dark, and a new off-by-default setting adapts each answer to the question you asked.
```

**Release notes (`fastlane/metadata/`, both platforms, written 2026-09-22):** in the two `release_notes.txt` files; the text is the 5.4 section of `WHATS_NEW.md` in the store's shape. Subtitle "Chat With Your Files Offline" and the keywords were written into both trees the same day; before that they existed only in App Store Connect. The description's opening was rewritten for a buyer.

**Screenshots and keywords, 2026-09-22.** The iPhone and iPad sets were replaced with four captioned scenes, in order: "Ask your own documents anything / Every claim cites the page it came from", "It tells you when your files don't say it / No guessing. No made-up answers.", "See where every answer came from / The real passages, page by page", "Built on Apple Intelligence / On your device. Private Cloud Compute only when you approve it." Keywords became `ai,llm,pdf,private,local,apple,intelligence,document,search,summarize,ocr,transcribe,research,manual` (100 characters), replacing "rag" with "manual". The macOS set is unchanged, still seven captures from 2026-06-21.

**Also corrected outside the metadata trees, recorded here because it is store copy:** both Pro subscription descriptions in App Store Connect read "unlimited documents and 5 libraries". `QuotaPolicy.proDocumentLimit` is `1_000` and `proLibraryLimit` is `10`, so both halves were wrong and the library count understated the plan. Corrected to "up to 1,000 documents and 10 libraries" by the same script.


**Description corrected 2026-09-22, before submission.** Two sentences overstated privacy. "Nothing you import leaves your device" is false on the Private Cloud Compute path, where `CloudEvidenceMinimizer` sends passage text with document names and page numbers once consent is given; it now reads "Nothing you import leaves your device unless you allow it". "The app shows you exactly what would be sent" overstated `CloudConsentPromptView`, which shows the provider, model, prompt and context character counts, the passage count, the payload size and the reason, never the text; it now reads "The app shows you how much would be sent and why, and asks you first", and the retention sentence is attributed to Apple rather than promised. Description length 3,986 of 4,000. The live 5.3 description keeps the "exactly what would be sent" sentence until 5.4 replaces it. The same overstatement is in the in-app sample guide (`SampleDocumentManager.swift:59`), `README.md:31`, `Docs/HOW_IT_WORKS.md:44` and `Docs/STUDY_GUIDE.md:1650`, which are outside the store-copy route and unchanged. `[evidence_level: code_verified, confidence: high, evidence_source: ModelExecutionPlanner.swift CloudEvidenceMinimizer; CloudConsentPromptView.swift:164-183; CANONICAL section 8]`

**Corrections and additions, 2026-09-23, before submission.** None of these is in App Store Connect until the owner runs `scripts/asc_prepare_release.rb 5.4 <build> --apply` and then `scripts/asc_listing_extras.rb 5.4 --apply`; the permission classifier refuses both from an agent, and `api.appstoreconnect.apple.com` was unreachable from the agent shell that morning while Apple reported no incident. Read the records back after the run before treating any line below as live.

- **What's New.** "Never twice in four months" now reads "Never twice in four months on its own", in both `release_notes.txt` files and `WHATS_NEW.md`. The 120-day gate covers only the automatic request (`ReviewPromptService`); a thumbs-up followed by "I love it" calls `requestReview` again, limited to once per version and 14 days apart (`ChatScreen.swift` thumbs-up alert). The in-app text that makes the same promise (`WhatsNewStore.swift`, `Docs/USER_CHANGELOG.md`, `OpenIntelligence/Resources/VersionHistory.md`) now says "on the app's own initiative" and ships in the build after 472.
- **The Pro subscription line above did not land.** A GET at 22:02 PT on 2026-09-22 still read "Annual billing for unlimited documents and 5 libraries." and "Monthly billing for unlimited documents and 5 libraries"; Apple refused the earlier PATCH with 409 UNMODIFIABLE (`scripts/asc_fix_listing_copy.rb`), and those target strings were 58 and 59 characters against a 55-character limit. `scripts/asc_listing_extras.rb` retries with "Annual billing for 1,000 documents and 10 libraries." and "Monthly billing for 1,000 documents and 10 libraries.", and corrects Lifetime's "Permanent Pro - 10 Libraries + Unlimited Documents" to 20 libraries (`QuotaPolicy.lifetimeLibraryLimit`). A 409 again means the change goes through the App Store Connect web page with the next submission.
- **Promotional text.** The 5.4 records hold the non-sale line above because 5.4 was expected after the sale. Released before 2026-09-30, 5.4 would drop the sale line from the store page early, so `scripts/asc_listing_extras.rb` copies the live 5.3 sale line onto 5.4 through 2026-09-29, and `scripts/asc_end_sale.rb` replaces it on whichever version is live on 2026-09-30.
- **App Review notes.** The 5.3 notes told the reviewer to try Maximum and said nothing of the three-a-day cap. `fastlane/review_notes/5.4.txt` is appended on both platforms.
- **Subscription images.** Neither subscription had one, and a win-back offer is promoted on the App Store only with an approved image (StoreKit, "Supporting win-back offers", read 2026-09-22). `fastlane/iap_images/pro_monthly.png` and `pro_annual.png`: 1024 x 1024, RGB, no text, the flame symbol the app uses for Maximum mode on two different gradients, drawn by `scripts/render_iap_images.swift`. They are reviewed with the next submission.
- **Written 2026-09-23 by the owner's run, read back GET-only at 08:40 PT.** Both 5.4 records: build 474 attached, What's New with "on its own", App Review notes 701 to 1,116 characters with the 5.4 addition, promotional text the live sale line. Both subscription images uploaded, state `PREPARE_FOR_SUBMISSION`, so they need the subscriptions included in the next submission. All three descriptions were refused again: HTTP 409 `ENTITY_ERROR.ATTRIBUTE.INVALID.UNMODIFIABLE`, "Cannot edit SubscriptionLocalization when it is in ACTIVE state" (and the same for the Lifetime `InAppPurchaseLocalization`). The store still shows "unlimited documents and 5 libraries" for Pro and "10 Libraries" for Lifetime; the app itself never displays these strings.

### 5.3

- **Platforms:** iOS, macOS
- **Live:** 2026-09-18 on both platforms, build 464, released manually by the owner after approval (`Docs/SHIPPED_VERSION.json`). The promotional text recorded below is the **sale** text; replace it after 2026-09-30 with the non-sale text noted under it.
- **Final release notes commit:** the one that adds this entry (2026-09-18)
- **Notes:** the first release written into the template above. One text for both platforms, in both `fastlane/metadata/` and `fastlane/metadata-ios/`, because the platforms do not diverge in 5.3. The description gains a PLANS block, written to the rule in `Docs/BILLING_AND_LIMITS.md`: a plan is described by what it gates, and the model as what every plan includes. No trial is mentioned anywhere; Pro Annual's 7-day free trial was withdrawn the same day. Release notes 3002 characters, promotional text 157 (the sale text; see the note under it), description 3,979, all against the 4,000 / 170 / 4,000 limits.

**Release notes (`fastlane/metadata/`, both platforms):**

```text
This release is about what you see first: the sample library's questions, the welcome screens, and the upgrade screen. Underneath it, documents are read with Apple's own detector and there is a new, off-by-default control over how answers are written.


THE SAMPLE LIBRARY MAKES SENSE AGAIN

• The three sample documents come with questions written by hand to walk you through the app. One leftover duplicate of a sample was enough to switch them off and replace them with questions built from templates, which is where "What is nothing?" came from. Duplicates are cleaned up on your next visit to Documents, and the written questions show whenever the three samples are there.

• When Apple Intelligence has nothing well-grounded to ask about a document, the app now shows no suggestion rather than a bad one.


READING YOUR DOCUMENTS

• Addresses, phone numbers, dates, amounts of money, measurements, flight numbers and tracking numbers inside tables are now recognised by Apple's own detector instead of pattern matching that only understood US phone numbers. Prose on the same page does not yet contribute; that is the current limit, stated plainly.


ANSWERING

• Three sliders in Model Parameters said they changed how the model picks words. Apple's generation API has no penalty setting of any kind, so they never did, on the device or on Private Cloud Compute. They now say so.

• New, and off until you turn it on: Adapt to the question. The app picks a temperature and a length from what you asked, so looking up a value gives the same number twice and comparing two things gets room to work. It applies in Standard, Deep Think and Maximum. It is off because nobody has shown it produces better answers yet; it is a setting you can judge for yourself.

• You can write your own reasoning profile for the questions that reason on Private Cloud Compute, in your own words, in Model Parameters.


THE WELCOME SCREENS AND THE UPGRADE SCREEN

• The welcome screens follow your light or dark setting. In light mode the status bar was nearly invisible against them; it is not now.

• A thumbs-up on an answer now offers to rate the app, write a review, or send feedback, once per version. The Lifetime card says how many months of Pro Annual its price buys, from the store's own prices.

• While Lifetime is on sale, one line at the top of Chat and Documents says the real discount and the last day, computed from the store's own price. Dismiss it and it stays away. And once, after the fourth answer the app has verified against your files, it shows you the plans; it will not ask again.

• The upgrade screen leads with what a plan actually changes. Every plan runs the same model, on your device, with Deep Think and consent-gated Private Cloud Compute included. Pro and Lifetime lift the daily cap on Maximum mode and raise the document and library limits. Pro Annual no longer offers a free trial; it is one payment a year.


Everything except that one writing step still runs on your device.
```

**Promotional text**, both platforms:

```text
Lifetime is 33% off until September 29: one payment, no renewal, no daily cap on Maximum mode, unlimited documents. Every plan runs the same on-device model.
```

*Promotional text is the one field editable on a live version. The sale text above was set by API on 2026-09-18 on the live 5.2 records and the 5.3 records, both platforms. **After 2026-09-30 it must be replaced**, on whichever version is live, with the non-sale text: "The sample library's questions are back, the welcome screens follow light and dark, and a new off-by-default setting adapts each answer to the question you asked." (162 characters). A sale promo outliving its sale is a false claim on the listing.*

**Description** (`fastlane/metadata/en-US/description.txt`, `6a6a520` 2026-09-18):

```text
You already have the answers. They're just buried in a 300-page manual, a folder of contracts, a semester of lecture recordings, or a codebase you inherited.

OpenIntelligence reads what you import and answers questions about it in plain language, with citations you can tap to see exactly where each claim came from. And when your files don't actually contain the answer, it tells you so instead of guessing confidently.

ANSWERS START IN YOUR FILES

Not in a chatbot's imagination. OpenIntelligence searches your library first, pulls the exact passages that matter, and only then writes, using Apple's on-device Apple Intelligence models. Requires an Apple Intelligence-capable device: iPhone 15 Pro or later, or an M1-or-later iPad or Mac, on iOS/iPadOS/macOS 26. Your device already had the intelligence. This gives it your knowledge, and rules of evidence.

WHAT YOU CAN DO

- Summarize long documents, recordings, or entire libraries.
- Compare claims and details across multiple sources.
- Find exact facts, dates, specifications, measurements, and table values.
- Ask follow-up questions without losing the sources or the thread.
- Choose Standard for quick factual work, Deep Think for multi-step questions, or Maximum for broader evidence synthesis.

BRING YOUR OWN MATERIAL

Import PDFs, Office documents, text and Markdown files, CSVs, code, images and scans, audio, or video. Pages, Numbers and Keynote files need to be exported to PDF first. OpenIntelligence extracts text, uses Vision OCR where needed, transcribes speech, and builds a searchable index for each library.

HOW ANSWERS ARE BUILT

Exact keyword matching and semantic search work together to retrieve the passages that matter. Apple Foundation Models turn those passages into a natural-language response. Then the app checks its own answer against the passages it actually used, so you can inspect what it's standing on instead of taking its word.

If the sources do not establish an answer, the app flags weak support or abstains. No confident filler.

WHERE YOUR FILES GO (AND DON'T)

Reading your files, searching them, and choosing what to cite all happen on your device, start to finish, before anything is written. On-device answers need no connection at all. On a plane, in a dead zone, in a locked-down office, your library still works. For longer, evidence-heavy questions on iOS, iPadOS or macOS 27, you can optionally allow Apple Private Cloud Compute to write the answer. The app shows you exactly what would be sent and asks you to approve it first, and Apple's servers keep nothing afterwards. Your material is never sent to a third-party AI provider.

ANSWERS YOU CAN INSPECT

Inline citations connect answers to their supporting pages and passages, one tap from claim to source. If you want more, response details go deeper: source snippets, retrieval quality, verification warnings, timing, and the route that actually produced the answer. The optional telemetry interface goes deeper when you want it and stays out of the way when you don't.

LIBRARIES THAT FIT YOUR WORK

Keep different subjects, projects, or clients in separate libraries. Choose Local Only or iCloud Drive for each library, and organize ongoing research in saved conversation threads. Siri and Shortcuts actions are available for common document and library workflows.

PLANS

Every plan runs the same model: Apple Intelligence on your device, Deep Think, and Private Cloud Compute after you approve what is sent. Free: 5 documents, one library, Maximum mode three times a day. Pro lifts that cap and grows to 1,000 documents and 10 libraries, monthly or yearly. Lifetime: one payment, unlimited documents, 20 libraries, Maximum every day, no renewal.

OpenIntelligence is built and maintained by one developer. Pro and Lifetime support directly fund continued development. To everyone already supporting the app: thank you. It has been a wild journey.

Privacy Policy: https://gunzino.me/openintelligence/privacy
```

### 5.2

- **Platforms:** iOS, macOS
- **Live:** Live 2026-09-10 on both platforms, build 451 (`Docs/SHIPPED_VERSION.json`).
- **Final release notes commit:** `8ef6ab8` (2026-09-10)
- **Notes:** Two rewrites on 2026-09-10: `1e4d9d1` said Deep Think and Maximum now ask for the reasoning they describe; `8ef6ab8` put the notes in the 5.1 shape, scoped to what changed since 5.1. **Only `fastlane/metadata/` (the macOS copy) received them. `fastlane/metadata-ios/` still holds the 2026-09-02 text from `a375fc8`, headed PRIVATE CLOUD COMPUTE, TURNED ON.** Whether the iOS listing was pushed from the old text or the new one is not recorded in the repo; App Store Connect is the authority.

**Release notes (`fastlane/metadata/`, the macOS copy):**

```text
This release turns on Private Cloud Compute. It needs iOS, iPadOS or macOS 27; on earlier systems everything continues to run on the device exactly as it did in 5.1.


PRIVATE CLOUD COMPUTE

• When a question needs more room than the model on your device can hold, the app can now hand that single writing step to Apple's Private Cloud Compute. Reading your files, searching them, choosing what to cite and checking the finished answer still happen on your device.

• Nothing leaves without asking. Before anything is sent, a sheet shows you what would go: how many passages, how large, and why. Allow it once, allow it always, or keep everything on the device. You can also pin routing to On-Device in Settings and the question never comes up.

• Every answer says where it was written. Expand the metrics bar under an answer to see On-Device or Private Cloud Compute.

• Apple's servers keep nothing after the answer, the connection is end-to-end encrypted, and the request is not accessible to Apple or to the developer.

• Measured on an iPhone with the A18 Pro: roughly 86 tokens per second from Private Cloud Compute, against 27 on the device.


DEEP THINK AND MAXIMUM ASK FOR MORE

• iOS 27 lets an app tell the server model how hard to think, and only one of the paths that write an answer was asking. The most common one was not, so those two modes often ran at ordinary effort while describing themselves as doing more. All of them ask now.

• Expect both modes to take longer than they did in 5.1, and to use more of your daily Private Cloud Compute allowance.


A CORRECTION FROM 5.1

• How It Works and the About screen told every iOS 26 user that the app asks before sending a question to Private Cloud Compute. Those builds could not send anything anywhere. Both screens now describe the build you are actually running, and so do the built-in guides, the Glossary and the Settings capability list.


Everything except that one writing step still runs on your device.
```

**Release notes (`fastlane/metadata-ios/`, `a375fc8` 2026-09-02):**

```text
PRIVATE CLOUD COMPUTE, TURNED ON

Every release since 4.6 has carried Apple's Private Cloud Compute support compiled out, waiting on iOS and macOS 27. This one turns it on. Requires iOS, iPadOS or macOS 27; on earlier systems everything continues to run on the device.

• When a question needs more room than the model on your device can hold, the app can now hand that single writing step to Apple's Private Cloud Compute. Reading your files, searching them, choosing what to cite and checking the finished answer still happen on your device, exactly as before.

• Nothing leaves without asking. Before anything is sent, a sheet shows you what would go: how many passages, how large, and why. Allow it once, allow it always, or keep everything on the device. You can also pin routing to On-Device in Settings and the question never comes up.

• Every answer says where it was written. Expand the metrics bar under an answer to see On-Device or Private Cloud Compute.

• Apple's servers keep nothing after the answer, the connection is end-to-end encrypted, and the request is not accessible to Apple or to the developer.

• Measured on an iPhone with the A18 Pro: roughly 86 tokens per second from Private Cloud Compute, against 27 on the device.


ALSO IN THIS RELEASE

• How It Works and the About screen said the app asks before sending to Private Cloud Compute, on builds that could not send anything. They now describe the build you are running, and so do the built-in guides, the Glossary and the Settings capability list.
```

**Promotional text (iOS)** (`a375fc8`):

```text
Private Cloud Compute is on. Questions too big for the on-device model can be written on Apple's servers, after you approve exactly what would be sent.
```

### 5.1

- **Platforms:** iOS, macOS
- **Live:** macOS live 2026-09-02 (build 433); iOS recorded as shipped the same day at the owner's decision while in review, approved 2026-09-02.
- **Final release notes commit:** `5a291dc` (2026-08-31)
- **Notes:** The first release with per-platform notes: iOS was two Mac-only releases behind (5.0.1, 5.0.2), so `029c798` gave `fastlane/metadata-ios/` its own text that brings iPhone and iPad up to date. The lane could not push different notes per platform; see RUNBOOK.

**Release notes (`fastlane/metadata/`, the macOS copy):**

```text
Most of this release is about the Mac, where importing a large document had become slow enough to be unusable. The text recognition changes apply to iPhone and iPad as well.


THE MAC WAS DOING FOUR TIMES THE WORK

• Every page of every PDF was drawn at four times the resolution it asked for, then encoded to an uncompressed image in memory and decoded straight back again, once per page. Measured on a Retina display that is roughly 370 MB written and read per page, for nothing. The iPhone never did this. It now draws each page once, at the size it asked for.

• With the app open and untouched, it was re-reading the search index of every library about seventeen times a second. Left running for a few hours it built up a backlog of work it could never catch up on and stopped responding. It now re-reads an index only when that index has actually changed.


A PAUSED IMPORT NO LONGER LOOKS LOST

• If you quit while a large PDF was still importing, reopening the app showed it sitting at zero, as though the work was gone. It never was. The app has always resumed from the last page it finished. But the screen said otherwise, and the one action that does throw that progress away is removing the item, which is exactly what the screen was inviting you to do. A resumed import now tells you how far it got.


TEXT RECOGNITION

• The app was asking the system to guess what language each page was written in, on every page, while simultaneously handing it a list of thirteen languages. Those two instructions contradict each other, and a wrong guess means your text is corrected against the wrong dictionary, which damages it rather than just slowing things down. The language is now worked out once, from the document itself.

• Page images were being handed to text recognition at the highest possible resolution with no downscaling at all, which is the slowest setting available. Recognition now scales to what is needed to read the smallest print a real document contains.


Everything still runs on your device.
```

**Release notes (`fastlane/metadata-ios/`, `029c798` 2026-08-31):**

```text
Two releases went out on the Mac that iPhone and iPad never received. This one brings them across, along with the changes made since.


OPENING AND MOVING AROUND

• The Documents tab made you wait while it counted your cached documents. That count fed a single row which stays hidden unless the number is above zero, and on the device this was traced on it was always zero, so the row was never drawn. You waited for a number that was then thrown away. It now loads in the background and the tab opens straight away.

• Switching libraries was the slow thing people actually noticed, and nothing on that path was being measured, so four separate attempts to find the cause had missed it. It is measured now, and faster.

• "Analyzing corpus…" was an empty state wearing a progress spinner. It could never finish, because nothing was running behind it.


THINGS THAT WERE TELLING YOU THE WRONG THING

• The Semantic Atlas labelled a neuroscience paper "API Reference" and "Glossary". The fault was in three separate places, not one.

• Turning the execution profile up removed hardware instead of adding it, and the control itself was a dropdown showing one option while hiding three, on a setting whose only purpose is choosing between them.

• The Deep Think card described a minimum number of reasoning steps that does not exist.

• Temperature stayed adjustable under a sampling mode that ignores it entirely.

• The hardware panel reported a limit of 1,073,741,824 threads, which is 1024 cubed and not a real ceiling. It also now reports free memory rather than a number that looked like it but was not.


DOCUMENTS

• Refreshing one of the built-in samples left the old copy behind, so the library grew a duplicate every time you did it.

• A tag that appears exactly once in a document no longer gets treated as a description of the whole thing.


TEXT RECOGNITION

• The app was asking the system to guess what language each page was written in, on every page, while also handing it a list of thirteen languages. Those two instructions contradict each other, and a wrong guess means your text is corrected against the wrong dictionary, which damages it rather than just slowing things down. The language is now worked out once, from the document itself.

• Page images went to text recognition at the highest possible resolution with no downscaling, which is the slowest setting available. Recognition now scales to what is needed to read the smallest print a real document contains.


IF YOU QUIT MID-IMPORT

• A large PDF interrupted by quitting the app came back showing zero progress, as though the work was gone. It never was: the app resumes from the last page it finished. But the screen said otherwise, and removing the item is the one action that does discard that progress. A resumed import now tells you how far it got.


Everything still runs on your device.
```

**Promotional text** (`5a291dc`):

```text
Large documents import far faster on Mac, and the app no longer works away in the background while idle. Text recognition got quicker and more accurate.
```

**Promotional text (iOS)** (`029c798`):

```text
iPhone and iPad catch up on two Mac-only releases: a faster Documents tab, clearer library switching, and better text recognition.
```

### 5.0.2

- **Platforms:** macOS only
- **Live:** Live 2026-08-28 (`Docs/SHIPPED_VERSION.json`); build 389 superseded 388.
- **Final release notes commit:** `a3a4575` (2026-08-27)
- **Notes:** Mac only. The two ways to get a document in were broken or absent in 5.0 and 5.0.1.

**Release notes:**

```text
On the Mac there was no way to get a document into the app. Both ways in were broken. This release fixes them.


GETTING DOCUMENTS IN

• The Add Documents button opened nothing. It asked macOS for a file picker at the one moment the system refuses to open one, so the request was discarded and no window ever appeared. The same fault hit the two file buttons inside a chat, where it was worse: those open into a panel that is otherwise empty, so there was no button to fall back to and no sign anything had gone wrong.

• You can now drag files from Finder straight into a library. This had never worked, because nothing in the app was listening for a dropped file. The whole library area accepts them, so a drop does not have to be aimed at anything precise, and dropped files go through the same size and quota checks and the same import review as files picked with the button. Folders are not accepted yet, so drop the files from inside them instead.


LIBRARY SETTINGS

• Library Settings was unreadable on the Mac. It was drawn as a narrow strip down the left with a large blank area beside it, squeezed hard enough that words broke apart mid-way — "Documents" came out as "Doc ume nts". It was built on an older navigation container that macOS turns into a two-pane layout meant for a sidebar and a detail view, which is not what a settings screen wants. It now uses a single column at a sensible width. Other screens still use that older container and may show the same thing; those are being worked through separately.


YOUR DOCUMENTS

• The built-in sample documents were quietly duplicating themselves. When a sample is corrected in a new version, the app replaces your copy with the updated one. It was deleting the original but not any duplicate an earlier update had already left behind, so each round added another. One library ended up with five documents for three samples. This matters beyond tidiness: the app answers out of these documents, so a duplicate meant the same passage counted twice when it decided what to quote. Existing duplicates are cleaned up on the next update, and documents you named yourself are never touched, even if the name looks similar.


iPhone and iPad are unchanged by this release.
```

**Promotional text** (`a3a4575`):

```text
Importing on Mac works now: the Add Documents button opens, and you can drag files straight in from Finder. Everything still runs on your device.
```

### 5.0.1

- **Platforms:** macOS only
- **Live:** Approved and live 2026-08-27.
- **Notes:** No metadata commit sits between the 5.0 notes (`a1508d6`, 2026-08-25) and the 5.0.2 notes (`a3a4575`, 2026-08-27), so the repo holds no distinct 5.0.1 copy. What the store showed for 5.0.1 is not recorded here.


### 5.0

- **Platforms:** iOS, macOS
- **Live:** macOS live 2026-08-26 (build 379); iOS approved 2026-08-27 (build 386). `Docs/USER_CHANGELOG.md` dates the release August 10, 2026.
- **Final release notes commit:** `a1508d6` (2026-08-25)
- **Notes:** `a0fd9e0` (2026-08-24) fixed a listing that was advertising 4.9; `96e73a1` added the vector-deletion fix; `a1508d6` (2026-08-25) corrected a claim that `91ea045` had made false. 3,997 characters, against the 4,000 limit.

**Release notes:**

```text
Documents were quietly losing parts of themselves, answers were built from a fraction of what was found, and the app rewrote your library on every launch. 5.0 is the fix for all three.


SEARCH

• The part of the app that reads what a passage means was looking at one position in it instead of the whole thing. It reads all of it now.
• A broken length check returned the same number for every input, so long passages were cut short before they were ever indexed.
• Libraries you already have will offer to rebuild their index once, because anything indexed before this update was built the old way. Nothing is deleted and the library keeps working while you decide.
• Keyword and meaning-based search combined stopped scoring worse than keyword search alone, and strong keyword matches are no longer dropped before ranking.


ANSWERS

• Deep Think was writing from a fraction of what it found, discarding its own best passages before the first word. It keeps them now, and says what it left out.
• Citations are checked against the real source list. An answer could cite a source number past the end of its own list.
• Deep Think is about three times faster, and stops when it runs out of new material instead of re-reading the same passages.
• A long answer no longer fails at the last step after minutes of work.


YOUR DOCUMENTS

• Tables in Word documents were read and then thrown away. A file could import looking complete with all of its numbers missing.
• Images keep their layout instead of collapsing into one line of text.
• A page the reader knew it had read badly is no longer repaired and then discarded.
• Importing certain files could deadlock the whole queue until you force-quit.


YOUR LIBRARIES

• A document you import no longer loses its searchability to the app's own housekeeping, which deleted a just-built index and said nothing. If one is lost, the app says so and rebuilds in about four seconds.
• "Remove Local Copies" is now "Remove All Documents", because that is what it did. It deleted from iCloud and your other devices while telling you Sync Now could bring them back. It could not.
• Deleting a library from its settings screen no longer removes it here when iCloud refused.
• Changing the embedding model no longer wipes your vectors before you agree to rebuild them.


SPEED

• The app starts faster. A 43 MB model loaded on every launch before anything appeared on screen.
• iCloud stopped re-uploading libraries that had not changed. One launch could rewrite hundreds of megabytes identical to what was already there.
• Leaving the chat no longer cancels the answer you were waiting for, and coming back keeps your place.


SETTINGS

• Settings is a searchable list instead of one long scroll. Type "temperature" and you land on it.
• Temperature and response length are reachable. They were built with no way into them.
• Choose Top-K, Top-P or Greedy. The app used to decide, and always picked the same one.
• Turn on Reproducible answers and the same question returns the same answer.
• Five switches that never controlled anything are no longer switches.
• Tap any figure the app shows you and it explains itself, plainly first and in detail if you want it.


THINGS WE WERE CLAIMING THAT WEREN'T TRUE

• Settings listed eight agentic tools and all eight were the wrong ones. Four are wired up. Those four are what it names now.
• We removed the claim that answers can run on Apple's Private Cloud Compute today. Shipped builds do not contain it yet.
• Pages, Numbers and Keynote were advertised and never worked. They are no longer advertised, and importing one now fails clearly.
• Speed figures that were never measured are gone, including from the sample documents the app reads back to you as fact.
• Every remaining capability line was checked against the code that would have to run it.


ALSO

• The app icon follows your device's dark mode.
• iPhone 17 and M5 hardware no longer reports itself as "A12 or Older".
```

### 4.9

- **Platforms:** iOS, macOS
- **Live:** Cut 2026-08-02 (`5e6e863`, "release: cut 4.9 for iOS and macOS"); `Docs/USER_CHANGELOG.md` dates it August 2, 2026. Store live date not recorded in the repo.
- **Final release notes commit:** `d29583b` (2026-08-03)
- **Notes:** `d29583b` (2026-08-03) added the atomic workspace-metadata write after the cut.

**Release notes:**

```text
Deep Think and Maximum were not wired up correctly in previous releases. This release fixes that, and everything it uncovered.


DEEP THINK AND MAXIMUM

• Both modes now reason across your documents. Previously they returned Standard quality answers after a much longer wait.
• Answers cite their sources in every mode. Maximum produced none at all.
• Both stop once they stop finding new material, typically halving Maximum's run time.
• A single failed pass no longer ends a query.
• Resolved "The selected model isn't available right now."


PRIVACY AND ROUTING

• On-Device now covers the entire query, including the final answer.
• The model picker governs every mode. It previously reached Standard only, so Deep Think and Maximum fell back to a default.


WHAT YOU SEE

• The live pipeline names each stage correctly, including verification and query rewriting.
• Reasoning detail wraps instead of cutting off mid-sentence.
• Follow-up suggestions come from the answer rather than stray words.
• Raw model output no longer appears in answers.
• Passes skipped for having no relevant text are shown instead of leaving gaps.
• An answer reporting that your documents do not cover something is kept, not replaced with generic help text.


YOUR LIBRARIES

• Fixed documents disappearing shortly after import. A document that finished importing while the app was saving your library could be dropped from the list, even though it had imported correctly.
• Documents processed on one device no longer need re-importing on another.
• Libraries no longer appear to lose documents while iCloud is still catching up.


ALSO

• Document import works on Mac. The file picker there was a placeholder.
• Opening the app after an update now shows what changed.
```

### 4.8

- **Platforms:** iOS
- **Live:** `Docs/USER_CHANGELOG.md` dates it July 31, 2026. Store live date not recorded in the repo.
- **Final release notes commit:** `23d4df1` (2026-08-02)
- **Notes:** Three drafts on 2026-07-30/31 (`1c5442f`, `8cad627` to cover all 36 commits, `de2fac1` reformatted for the store), then `23d4df1` recorded the iCloud sync fix.

**Release notes:**

```text
Deep Think and Maximum were not wired up correctly in previous releases. This release fixes that, and everything it uncovered.


DEEP THINK AND MAXIMUM

• Both modes now reason across your documents. Previously they returned Standard quality answers after a much longer wait.
• Answers cite their sources in every mode. Maximum produced none at all.
• Both stop once they stop finding new material, typically halving Maximum's run time.
• A single failed pass no longer ends a query.
• Resolved "The selected model isn't available right now."


PRIVACY AND ROUTING

• On-Device now covers the entire query, including the final answer.
• The model picker governs every mode. It previously reached Standard only, so Deep Think and Maximum fell back to a default.


WHAT YOU SEE

• The live pipeline names each stage correctly, including verification and query rewriting.
• Reasoning detail wraps instead of cutting off mid-sentence.
• Follow-up suggestions come from the answer rather than stray words.
• Raw model output no longer appears in answers.
• Passes skipped for having no relevant text are shown instead of leaving gaps.
• An answer reporting that your documents do not cover something is kept, not replaced with generic help text.


ALSO

• iCloud libraries no longer ask you to re-import documents another device already processed, and a library's search index is no longer removed while iCloud is still catching up.
• Document import works on Mac. The file picker there was a placeholder.
• Opening the app after an update now shows what changed.
```

### 4.7 (iOS) / 3.0 (macOS)

- **Platforms:** iOS, macOS
- **Live:** `Docs/USER_CHANGELOG.md` dates 4.7 July 28, 2026. Store live date not recorded in the repo.
- **Final release notes commit:** `bd70890` (2026-07-28)
- **Notes:** The 2026-07-28 rewrite around distrust repair (`f6ae713`), a human What's New (`71b7194`), and every em dash stripped (`bd70890`). The `push_metadata` lane was added the same day.

**Release notes:**

```text
This update makes OpenIntelligence more precise about what it tells you.

- Labels now say exactly where each answer ran: on your device, or Apple Private Cloud Compute with your permission. Nothing claims more than the system can verify.
- The key ideas pulled from your documents now come out the same every time, for steadier search and more reliable connections across files.
- New internal checks make sure every answer's recorded route matches what actually ran.

Same goal as always: ask hard questions of your own files, see exactly where every answer came from, and trust what you can verify, not what you're told.
```

**Promotional text** (`bd70890`):

```text
Apple Intelligence, put to work on your files. Ask real questions, get answers with citations you can tap and check. When your files don't hold the answer, it says so.
```

### 4.6

- **Platforms:** iOS, macOS
- **Live:** `Docs/USER_CHANGELOG.md` dates it July 15, 2026.
- **Final release notes commit:** `8569642` (2026-07-15)

**Release notes:**

```text
Version 4.6 is a major Apple Intelligence routing, transparency, and reliability update for OpenIntelligence.

EVIDENCE-FIRST MODEL ROUTING

- OpenIntelligence now searches your library before deciding where an answer should run. The decision uses the evidence actually found, the amount of context required, and whether the question needs synthesis across multiple documents.
- Normal work remains on-device. On supported iOS, iPadOS, and macOS 27 systems, longer evidence-backed requests can use Apple's native Private Cloud Compute when entitlement, availability, network, quota, and consent requirements are satisfied.
- Missing or weak evidence never triggers cloud escalation. The app can stay local or abstain when the library does not contain enough information.

CLEARER CONSENT AND EXECUTION HISTORY

- Private Cloud Compute consent now happens after the final evidence package is prepared. The confirmation view explains why PCC was selected and shows the number of source passages, context size, and estimated payload size.
- Saved response details now distinguish the intended route, attempted route, route that actually ran, any fallback, and the route that completed the answer.
- Automatic mode can fall back on-device before meaningful response text has streamed. Cloud and local partial answers are never stitched together, and Cloud Only requests report why they could not run instead of silently changing routes.
- Model labels and diagnostics now reflect the Apple model route the public SDK actually executed instead of claiming a selectable model tier that the operating system does not expose.

PRIVATE CLOUD COMPUTE SUPPORT

- Enabled OpenIntelligence's approved native PCC capability for supported builds and added platform-specific entitlement checks for iPhone, iPad, and Mac.
- Availability and quota are checked again immediately before a PCC session begins. Unknown or unavailable quota states fail safely and do not authorize cloud execution.
- Retrieval, evidence selection, citation checking, and final verification remain on-device even when PCC performs the final synthesis step.

INGESTION THAT RESPECTS STOP

- Closing or discarding an ingestion queue now records that decision during iCloud reconciliation, preventing those exact jobs from reappearing after a workspace reload or stale sync snapshot.
- Automatic repair of an empty document index now runs one library at a time and stays disabled for a dismissed library on that device until you explicitly import or rebuild again.
- Cancellation waits for a safe document boundary so stopping a repair does not leave half-removed catalog metadata behind.

INDEXING AND EXTRACTION RELIABILITY

- Knowledge-index migrations now use a fixed, code-owned migration catalog with stricter identifier validation, reducing the risk of malformed database upgrades.
- Document chunk metadata has a deterministic fallback when system language tagging cannot return named entities, keeping retrieval useful in asset-constrained environments.
- Expanded regression coverage now protects model routing, fallback behavior, embeddings, citation parsing, structured answers, ingestion recovery, and launch configuration.

Version 4.6 keeps OpenIntelligence focused on the same goal: help you question complex source material, understand how each answer was produced, and return to the evidence when you need to verify it.
```

**Promotional text** (`8569642`):

```text
Turn your Apple Intelligence-capable device into a source-grounded research engine for your files—local hybrid search, inspectable citations, and evidence-driven PCC.
```

### 4.2

- **Platforms:** iOS
- **Live:** `Docs/USER_CHANGELOG.md` dates it June 2026; `3e2e961` bumped build 71 for the Xcode 27 RC submission on 2026-06-18.
- **Final release notes commit:** `3e2e961` (2026-06-18)
- **Notes:** The 4.0/4.1/4.2 notes were one running "Changes since 3.7.5" text through seven commits (2026-06-10 to 06-18); `492bfc7` trimmed it to meet the 4,000-character limit. `3e2e961` is the first headed "Version 4.2".

**Release notes:**

```text
Version 4.2:
- Modernized UI for macOS/iOS: Completely rebuilt the live telemetry HUD with ultra-thin materials, interactive haptics, and smooth symbol animations.
- Dynamic Verification Gates: The visual HUD for RAG telemetry now adapts its pipeline dynamically based on your active Quality Mode.
- Fixed Chat History Persistence: Resolved an issue that sometimes skipped loading your previous chat history during a cold boot.
- Granular Hardware Telemetry: The Execution Badge now dynamically fetches and displays exact onboard RAM allocations alongside TOPS processing power.
- Accuracy in Retrieval Metrics: Corrected UI labels to differentiate between semantic Database Matching (Vector Similarity) and active LLM reasoning thresholds (Total Confidence).
- Agentic Tool Visibility: The telemetry HUD now surfaces implicit, hidden engine calls (such as Vector Search Engine lookups) during standard modes that do not trigger recursive tool event streams.
- Clean Sub-second Telemetry: Fixed a visual bug presenting Time-To-First-Token in raw oversized milliseconds (e.g., 12000ms), standardizing values to an elegant `under 1.2s` formatted duration.
- Native Resizable Telemetry Drawer: Completely rebuilt the expanded metrics panel to behave like a fluid, native iOS bottom sheet. Users can now physically pull the handle down to manually resize the metrics view seamlessly during live telemetry inspection or recording.
```

### 4.1

- **Platforms:** iOS
- **Live:** `Docs/USER_CHANGELOG.md` groups 4.0 and 4.1 under the WWDC26 Apple Intelligence update.
- **Final release notes commit:** `b378eac` (2026-06-12)

**Release notes:**

```text
Changes since 3.7.5:

Version 4.1:
- Core AI Sentence Embedding Provider: Added CoreAISentenceEmbeddingProvider for high-speed, local silicon-accelerated vector calculations on Apple device hardware.
- Real-Time Thinking Telemetry: Added ThinkingStreamView inside the UnifiedMetricsBar to show live reasoning and model processing states.
- Enhanced Suggested Questions: Upgraded SuggestedQuestions with a two-pass section-diversity selector and strict POS-tagging grammar filters to generate high-quality follow-ups.
- Metal GPU-accelerated retrieval: Integrated a custom Metal compute shader pipeline with SIMD4 and threadgroup-level execution, driving a 4x speedup in batch cosine similarity RAG retrieval.
- Atomic Database & Purging: Hardened RAG pipeline with atomic vector database writes and cascading file/index deletion of discarded uploads to prevent data corruption.
- Thread-Safe Safety Routing: Thread-safe MainActor routing for LLM availability checks.

Version 4.0:
- Dynamic Model Routing (On-Device & PCC): Automatically routes queries based on complexity and context size. Standard queries execute locally using the 4K-token on-device model, while complex logic scales to Private Cloud Compute (PCC) enclaves supporting a 32K-token context window.
- Under the Hood Telemetry Dashboard: Added an interactive details popover detailing active model routing, token budgets, execution path telemetry, and pulsing status indicators.
- Core AI Engine Integration: Integrates a direct, custom local Core AI silicon execution engine and model registry.
- Native Liquid Glass UI: Re-engineered key view components with premium native glasscard modifiers for an immersive visual experience.
- RAG Evaluations Suite: Built-in dataset validation against target Recall@5 and Citation Precision quality gates, exposing an Apple Evaluations Bridge for native CLI testing compatibility.
- Agentic Retry Safeguard: Hardened agentic RAG reasoning cycles to preserve non-empty drafts and protect against rate-limit empty responses.
- Brand Realignment: Realigned all branding assets, HUD panels, and logs to standardized "Apple Intelligence" styling.
```

### 4.0

- **Platforms:** iOS
- **Live:** Build 46, 2026-06-10.
- **Final release notes commit:** `492bfc7` (2026-06-10)
- **Notes:** `8eae662` was 4,972 characters; `492bfc7` trimmed it to the 4,000 limit the same day.

**Release notes:**

```text
Changes since 3.7.5:

Version 4.0:
- Dynamic Model Routing (On-Device & PCC): Automatically routes queries based on complexity and context size. Standard queries execute locally using the 4K-token on-device model, while complex logic scales to Private Cloud Compute (PCC) enclaves supporting a 32K-token context window.
- Under the Hood Telemetry Dashboard: Added an interactive details popover detailing active model routing, token budgets, execution path telemetry, and pulsing status indicators.
- Core AI Engine Integration: Integrates a direct, custom local Core AI silicon execution engine and model registry.
- Native Liquid Glass UI: Re-engineered key view components with premium native glasscard modifiers for an immersive visual experience.
- RAG Evaluations Suite: Built-in dataset validation against target Recall@5 and Citation Precision quality gates, exposing an Apple Evaluations Bridge for native CLI testing compatibility.
- Agentic Retry Safeguard: Hardened agentic RAG reasoning cycles to preserve non-empty drafts and protect against rate-limit empty responses.
- Brand Realignment: Realigned all branding assets, HUD panels, and logs to standardized "Apple Intelligence" styling.
```

### 3.7 / 3.7.1

- **Platforms:** iOS
- **Live:** 3.7 build 39 on 2026-05-22; 3.7.1 build 43 resubmitted 2026-05-23.
- **Final release notes commit:** `a666a9b` (2026-05-28)
- **Notes:** "Changes since 3.6" text through five commits, the last (`a666a9b`, 2026-05-28) alongside a BNNS and consent-view refactor.

**Release notes:**

```text
Changes since 3.6:

Version 3.7.5:
- Hardened iCloud synchronization concurrency by offloading all synchronous database merging, file copying, and conflict resolutions off the Main Actor (UI Thread) to completely eliminate UI freezes and watchdog crashes.
- Accelerated multi-device data transfers using parallel Swift TaskGroups to download iCloud ubiquitous files concurrently rather than sequentially.
- Hardened download error recovery, ensuring isolated iCloud file download failures or timeouts do not stall or fail the entire library synchronization.

Version 3.7/3.7.1:
- Resolved a gesture conflict on iOS where long-pressing library pills in the horizontal scroll view failed to trigger the context menu, fully restoring library deletion on iPhones.
- Preserved full library identity in the Documents pill strip more reliably by preventing the document-count badge from collapsing names into ambiguous truncation.
- Fixed a synchronization issue in iCloud Sync where deleted libraries could be merged back and resurrected on other devices, and implemented deletion tombstones to automatically propagate deletions across all synced devices.
- Added automated local cleanup of vector databases, Spotlight search indexes, and UI presentation caches when a synced library is deleted on another device.
- Documents was tightened again with cleaner library pills, a less crowded header, smaller sync controls, and clearer organization/management surfaces.
- Shared-workspace and background-ingestion plumbing are more robust, with safer queue cleanup, cleaner reconciliation, and better handling for long-running work.
- Camera capture, OCR-heavy pages, and mixed digital/scanned documents import more reliably.
- Clean digital text is preserved more faithfully, while noisy scans and image-heavy pages still get the heavier recovery path when they need it.
- Retrieval is stronger across Standard, Deep Think, and Maximum, with better context packing, better use of surrounding document context, and less drift away from the source.
- Suggested questions and follow-ups are more grounded in the active library and less repetitive across refreshes.
- Chat handles direct attachments and captured content more smoothly, so it is easier to bring new material into the conversation flow.
- Answer inspection is much richer now, with clearer source review, timing, retrieval-quality, and evidence-detail surfaces when you want to see how a response was built.
- Technical answers and structured output render more cleanly, including stronger code block handling and clearer response detail views.
- Diagnostics and device-aware performance behavior are more stable on larger libraries and longer-running work, with deeper inspection tools behind the scenes for validation and monitoring.
- Added native App Store rating and review prompting triggers after successful query tasks.
- Resolved Mac Catalyst layout truncations, including the Sync Mode picker, action chips, and scrollable library selector pills.
- Enabled full iCloud ubiquity container access and network permissions for Mac Catalyst by packaging universal sandbox entitlements.
- Resolved Xcode build catalog warnings with a unified universal AppIcon configuration across iOS and macOS targets.
- Redesigned the Silicon hardware telemetry HUD to dynamically rotate motherboard borders (SoC and Taptic outlines) to match device layout rotation, added iPad layout coordinates, and cleanly hid visual outlines on Mac targets.
- Hardened suggested questions and 3D visualization keywords to aggressively filter out OCR junk, syntax noise, and generic templates.

This release is about making OpenIntelligence feel more complete from import to answer review: fewer weak spots between "I added a file" and "I trust this answer."
```

### 3.6

- **Platforms:** iOS
- **Live:** 2026-05-14 to 05-15 (per-library iCloud libraries).
- **Final release notes commit:** `9758f6e` (2026-05-15)

**Release notes:**

```text
Changes since 3.5:

Version 3.6 adds optional iCloud reuse for the libraries you choose, without giving up the app's local-first default.

If you've been loading a large library on iPad and wishing that exact processed library could show up on iPhone or your other devices without starting over, this is the update aimed at that problem.

Shoutout to Tim for asking for this.

- Every library can now be set to Local Only or iCloud Drive individually.
- Local Only libraries stay fully on-device unless you explicitly change them.
- Libraries you mark iCloud Drive can reuse imported files and processed state across your own Apple devices on the same iCloud account.
- Shared-library refresh and review is clearer now, so additions or removals from another device are easier to understand before you pull them in or remove them here too.
- Same-name shared libraries are much less likely to merge together unexpectedly.
- iCloud library sync is now positioned as a paid workspace feature, and paid plan capacity is clearer: Pro supports up to 10 libraries and Lifetime supports up to 20.
- If a long-running import is interrupted on one device, another device can pick up queued work for that iCloud library instead of forcing a full restart.
- Plain text and other digital documents are preserved more faithfully during import, with safer handling for text, markdown, code, CSV, transcripts, and Office-style files.
- This follow-up 3.6 build also smooths the Documents layout, improves import cancellation, and prevents old queued work from deleted libraries from coming back unexpectedly.

This release is about making cross-device reuse practical without compromising the app's privacy-first, local-by-default model.
```

### 2.1.1

- **Platforms:** iOS
- **Live:** 2026-04-15 to 04-19; the earliest App Store copy in this repository.
- **Final release notes commit:** `fa7792c` (2026-04-19)
- **Notes:** Also the only versions of `subtitle.txt` and `keywords.txt` ever committed (`fa7792c`, `170121f`).

**Release notes:**

```text
Version 2.1.1

NEURAL ANSWERS
- Better source-backed answers with clearer source review
- Better handling when the app does not have enough evidence to answer

BETTER REVIEW
- Clearer answer review and source inspection in chat
- Improved behavior with larger or messier files

PRODUCT COPY
- Cleaner onboarding, settings, and App Store wording
```

**Promotional text** (`fa7792c`):

```text
Private neural document answers on iPhone. Import PDFs and other files, get cited answers, review the source, and see when evidence is weak.
```
