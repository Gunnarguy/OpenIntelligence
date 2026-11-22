# Custom product pages for 5.8

App Store custom product pages for OpenIntelligence (app id 6756559175), built 2026-11-21 at the owner's word
("custom pages" means App Store custom product pages, and the work may be submitted for review without showing him
first). This file is the plan, then the record: each page's id, link, state, copy and where each screenshot came from.

## 1. What Apple allows (read 2026-11-21)

| Fact | Source |
|---|---|
| Up to 70 custom product pages per app, for iPhone and iPad. There is no Mac custom product page. | `developer.apple.com/app-store/custom-product-pages/` and App Store Connect Help, "Configure multiple product page versions" |
| A page may change screenshots, app previews, promotional text and keywords. The name, icon, subtitle and description stay the default page's. | same |
| A page is seen only through its link (`?ppid=<page id>`), through an Apple Ads ad that uses it, or in search results for keywords assigned to it. Everyone else sees the default page. | App Store Connect Help, same page |
| Pages are reviewed. They can be submitted without an app version: a platform may have two submissions in review at once, one with an app version and one with items only. | App Store Connect Help, "Overview of submitting for review" |
| An approved page is published when approved. Editing an approved page makes a new version and keeps the link. | "Configure multiple product page versions" |
| An app deep link on a page works from iOS 18 and must be approved with the page. | same |
| Screenshots: up to 10 per device size, PNG or JPEG, no alpha. iPhone sizes used here: 1320x2868, 1284x2778, 1206x2622. iPad: 2048x2732. | App Store Connect Help, "Screenshot specifications" |
| More than half of a device's screenshots must show the app in use; overlays may not crowd out the app; fictional account data, not a real person's. | App Review Guidelines 2.3.3 and 2.3.9, and "2.3.3 Screenshots" in App Review's guideline reference |
| No unverifiable product claims in subtitles and creative assets, no prices in screenshots. | App Review Guidelines 2.3.7 and 2.3.14 |
| Images are uploaded once to the app's asset library and placed on a page (`appAssetLibraryImages`, `appAssetLibraryPlacements`); the screenshot-set resources are deprecated. | App Store Connect API, "Migrating to the App Asset Library" |

`[evidence_level: documented, confidence: high, evidence_source: the Apple pages named, fetched 2026-11-21]`

## 2. What is known about what converts

| Claim | Kind | Source |
|---|---|---|
| Sending people to a custom product page raises conversion by 2.5 percentage points on average, against 1.6% on default pages. | Apple's own figure, no sample or method given | `developer.apple.com/app-store/custom-product-pages/`, read 2026-11-21 |
| Custom-page ads in Apple Ads converted 47.57% of taps in 2025 and 55.87% in 2024. | A vendor's ad data, no sample size, no default-page comparison | MobileAction, Apple Ads 2026 benchmark report |
| One app (SoundCloud) reported 58% more conversions on competitor-keyword ads with pages built on review themes. | One case, no control described | AppTweak, "Best practices for custom product pages with Apple Ads" |
| The first screenshots should repeat the reason the visitor came (the ad's keyword, the post's subject). | Advice. No published test of screenshot position was found. | AppTweak, same article; MobileAction |
| A page is not judged against the default page, because the visitors differ. | Advice | AppTweak |

So the evidence supports one thing: a page that matches why the visitor came does better than the default page, by an
amount nobody has measured for an app this size. Everything below about order and wording is judgment.
`[evidence_level: documented, confidence: low for the size of any effect]`

This app's own numbers set the limit on how many pages are worth having: the rule in `~/ASC/EXPERIMENTS-2026-11.md`
(#5) is 300 views per page before a page is read against the default page's 4.4%. More pages means fewer views each.

## 3. What exists already

Four pages, approved 2026-11-07, all aimed at offline and many-PDF searches, with the September screenshots:
Offline (named CPP1), Research across files (CPP2), Chat with PDFs offline, Questions across PDFs. The Offline page
is shown by a live Apple Ads ad, Questions across PDFs by the Google Ads App Store ad, and the guides on
openintelligence.me link all four. They are left exactly as they are: a new version of any of them changes what a
running ad shows, which is outside this work.
`[evidence_level: measured, confidence: exact, evidence_source: GET /v1/apps/6756559175/appCustomProductPages, 2026-11-21; ~/ASC/CHANGES-2026-11-06.md sections 14 and 19]`

## 4. The pages

Each page is for one reason to install, and its first screenshots show that reason. The rest of each set is the
5.8 listing's own scenes in an order that fits. Every feature named is a line in `fastlane/metadata-ios/en-US/` or
`WHATS_NEW.md`. No figures, no comparisons, no version number, two spaces after a sentence, and "Needs Apple
Intelligence." last, the form of the promotional text the owner chose on 2026-11-20.

| Page | Who it is for | Leads with | Why this page |
|---|---|---|---|
| Exact words | People who don't trust an AI answer until they see the source | The document open on the cited page with the passage highlighted | It is the first thing the owner's own promotional text names, and the default listing has no screenshot of it. |
| Private files | People with documents they would not upload | "No server. No account.", then where answers are written and the permission sheet | The reason the app exists (`Docs/ai/PURPOSE.md`). The four older pages say offline; none shows the permission step. |
| Hard questions | People whose questions need more than a lookup | Intelligence Mode: Standard, Deep Think, Maximum | Deep Think and Maximum are in every plan, and the 5.8 page shows what each one does. |
| New look | People who come from a 5.8 post, or who tried an earlier version | The Settings panel, Plain English, the Database tab, a tip | The redesign is the visible half of 5.8 and the default listing can only give it four of ten places. |

Considered and left out:

- **Research papers and tables.** 5.8 keeps tables whole, and the app has no staged scene that shows it. A page whose
  first screenshot does not show its own claim is worse than no page. It needs a table scene first (a demo paper
  written for the purpose, never a real paper, whose pages are someone else's). Recorded as the next page to make.
- **The Mac app.** Apple has no custom product pages for Mac.
- **A second "offline" page.** Two of the four existing pages already say it.

### Copy

| Page | Promotional text | Characters |
|---|---|---|
| Exact words | `Tap a citation and your document opens with the exact words highlighted.  Every answer comes from your own files, with the passage it used.  Needs Apple Intelligence.` | 166 |
| Private files | `Ask about the files you wouldn't upload anywhere.  Nothing you import leaves your device unless you allow it, and it works in airplane mode.  Needs Apple Intelligence.` | 167 |
| Hard questions | `Choose how hard it thinks.  Standard answers fast, and Deep Think works through a multi-step question and checks every claim it lists.  Needs Apple Intelligence.` | 161 |
| New look | `The biggest update yet.  Settings has fewer, fuller pages, small tips show you around and every answer shows where it came from.  Needs Apple Intelligence.` | 155 |

Where a wording was a matter of taste, the choice was the one closest to his two sentences of 2026-11-20: a full
sentence about something a visitor sees in the first minute. `~/.claude/skills/gunnar-voice/lint.py` reports no error
and no warning on any of the four. Each sentence's source:

- "Tap a citation ... highlighted." and "The biggest update yet." are his promotional text.
- "Every answer comes from your own files, with the passage it used." is the description's first paragraph, and
  "the passage it used" is the wording `Growth/PRODUCT_TRUTH.md` section 8 asks for (a citation is not proof).
- "Nothing you import leaves your device unless you allow it" is the description's second sentence. "It works in
  airplane mode" is the description's "On-device answers need no connection at all."
- "Deep Think ... multi-step question" is the description's "Deep Think for multi-step questions"; "checks every
  claim it lists" is the release notes' "It checks every claim it lists."
- "Settings has fewer, fuller pages, small tips show you around" is the release notes' last bullet.

### Keywords, deep links, tests and events: none made

- **Keywords on a page.** A page with keywords replaces the default page in search results for those keywords, so it
  moves the default page's traffic. None assigned. Worth doing later for one page at a time, once a page has its 300
  views: "private" and "local" fit Private files, "research" fits Exact words. The call is
  `POST /v1/appCustomProductPageLocalizations/{id}/relationships/searchKeywords` with `appKeywords` ids.
- **Deep link.** It only acts for someone who already has the app and taps Open, and it has to be reviewed. None set.
- **Product page optimization test.** It splits the default page's visitors. One test ("Screenshot Order A/B") was
  approved on 2026-11-07. A second cannot run beside it, and the app's traffic gives one test a slow answer. Not worth
  another until that one has been read.
- **In-app event.** An event card shows on the default page and in search. 5.8 would fit a Major Update event, and it
  needs event art and a date the owner picks. Worth doing once iPhone 5.8 is live; not made here.

## 5. Links

The link form is the owner's, with the page id added. No new campaign tag: App Analytics already separates pages by
page, and the tag keeps naming the place the link was posted. Use the tag of the place: `X_OI` for an X post,
`LI_OI` for LinkedIn, `RD_OI` for Reddit, `Fascinaiting_Site` for openintelligence.me, `GitHub_Repo` for the README.

`https://apps.apple.com/app/apple-store/id6756559175?pt=127101782&ct=<tag>&mt=8&ppid=<page id>`

The table of ids and ready links is in section 7, filled in once the pages exist.

## 6. The screenshots

| Mark | What | Where it came from |
|---|---|---|
| New (7 scenes: source, page, factcheck, modes, tips, atlas, dark) | Captured 2026-11-21 in the iOS 27.0 Simulator (an iPhone simulator capturing at 1320 x 2868 and an iPad simulator at 2064 x 2752, named "OI custom pages iphone" and "OI custom pages ipad", deleted afterwards), a Debug build of the 5.8 code, with the app's own screenshot launch flags, the demo lease and the app's own guides. No real document. | `Growth/custom-pages-5.8/capture.sh`, composed by `Growth/custom-pages-5.8/compose_pages.py`, which runs `scripts/compose_store_screenshots.py` unchanged for the frame, the callout and the type |
| 5.8 listing (9 scenes) | The 5.8 listing's own images, used again by their asset ids in a new order. Nothing was uploaded twice. | App Store Connect, the iOS 5.8 version's screenshot sets |

28 new images were uploaded: 7 scenes in four sizes (1320 x 2868, 1284 x 2778 and 1206 x 2622 for iPhone, 2048 x 2732
for iPad). All 28 read `PREPARE_FOR_SUBMISSION` with the right pixel size after upload
(`Growth/custom-pages-5.8/state.json`). The main session looked at the seven iPhone images side by side at 03:55: same
frame, type and blue panel as the listing's. Two of them ("Every claim opens its source" and "Small tips show you
around") show the same tip from the same screen under different headlines; they sit on different pages.
`[evidence_level: measured, confidence: high for sizes and states; the look was judged by eye, by an agent]`

## 7. The record

Submitted for Apple's review on 2026-11-21 at 03:20 PT (11:20:59 UTC), one iOS review submission
(`08fd4f85-b2b7-4ac7-ac30-fe0965071f79`) holding the four page versions and nothing else. At 03:53 PT the submission
read `WAITING_FOR_REVIEW` with 4 items `READY_FOR_REVIEW`, and `Growth/custom-pages-5.8/cpp.py verify` printed
`ALL EQUAL`: each page's promotional text and each group's screenshots, in order, matched `pages.json`. Apple accepted
this submission beside the open 5.8 version submission (`001409e4`), which was not touched and still read
`WAITING_FOR_REVIEW` with the version at `WAITING_FOR_REVIEW`. A page's link works once Apple approves it.

| Page | Page id | State at 03:53 PT | iPhone / iPad screenshots |
|---|---|---|---|
| Exact words | `907e8ee1-8709-43e1-82ca-6178c035b4cc` | `WAITING_FOR_REVIEW` | 8 / 7 |
| Private files | `72a799a2-0da6-4418-98c0-5c82528362f5` | `WAITING_FOR_REVIEW` | 8 / 7 |
| Hard questions | `57dc5a5d-19be-4321-a3f2-d2254424eaf0` | `WAITING_FOR_REVIEW` | 8 / 7 |
| New look | `d14d52c9-31f3-412a-a48b-c3e8a157bf39` | `WAITING_FOR_REVIEW` | 9 / 8 |

Ready links, with the X tag (swap `ct=` for the place a link is posted, section 5):

- Exact words: `https://apps.apple.com/app/apple-store/id6756559175?pt=127101782&ct=X_OI&mt=8&ppid=907e8ee1-8709-43e1-82ca-6178c035b4cc`
- Private files: `https://apps.apple.com/app/apple-store/id6756559175?pt=127101782&ct=X_OI&mt=8&ppid=72a799a2-0da6-4418-98c0-5c82528362f5`
- Hard questions: `https://apps.apple.com/app/apple-store/id6756559175?pt=127101782&ct=X_OI&mt=8&ppid=57dc5a5d-19be-4321-a3f2-d2254424eaf0`
- New look: `https://apps.apple.com/app/apple-store/id6756559175?pt=127101782&ct=X_OI&mt=8&ppid=d14d52c9-31f3-412a-a48b-c3e8a157bf39`

Contact sheet (private to the owner): `https://claude.ai/artifact/BWJTTV15wVQyAuhyGH5vtD`, built by
`Growth/custom-pages-5.8/make_sheet.py`.

**Every write made to App Store Connect:** four custom product pages created (each with one version and an en-US
localization carrying its promotional text); 28 images uploaded to the app's asset library; each page's screenshot
placements set for four size groups; one review submission created with the four page versions and submitted. Nothing
else: no keyword, no deep link, no test, no event, no ad, and no change to the default page, a version, a price or the
four older pages.

**How it was made, and what was not done.** A subtask of the main session did the research, the strategy, the
captures, the pages and the submission, at the owner's word of 2026-11-21 ("Submit for review too"). It then stopped
at a permission prompt nobody was awake to answer, and the main session finished this record, the read-back and the
contact sheet. Not done: a page for research papers and tables (it needs a table scene first, section 4); keywords on
a page; the links are not yet used anywhere (a site, a post or an ad is the owner's to place). Not verified: how the
pages look on the App Store itself, which only exists after approval.
`[evidence_level: measured, confidence: exact for ids and states read from the API at 03:53 PT on 2026-11-21]`

## 8. Approved (read 2026-11-22 12:18 PT)

Apple approved all four pages. The review submission `08fd4f85-b2b7-4ac7-ac30-fe0965071f79` reads `COMPLETE` and its
four items `APPROVED`, so each link in section 7 now opens its page. The pages are not used anywhere yet: a post, a
site link or an ad is the owner's to place.
`[evidence_level: measured, confidence: exact, evidence_source: GET /v1/reviewSubmissions/08fd4f85...?include=items, 2026-11-22 12:18 PT; the pages were not opened in the App Store by this session]`

