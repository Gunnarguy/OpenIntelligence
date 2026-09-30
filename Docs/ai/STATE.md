# Current State

Updated: 2026-09-30, 06:40 PT (iOS 5.5 is live with build 483; the Mac record is still in review)
Branch/worktree: `main`, primary checkout
Last verified commit: 16c4805

## Objective

iOS 5.5 is live (build 483, released through the API at the owner's word, 2026-09-30 06:31 PT); the Mac record is in
App Review with the same build. 5.5 carries the "how much" extractor fix, the subscription fix and the plans screen's
price comparisons. The owner pulled build 482 back out of review on 2026-09-29, while it was still waiting,
to carry the comparisons ("Just reject it for now and make ALLLL the proper changes, then get it back into review"),
and means to request an expedited review. Release is manual and his call. New work starts only when he says to
(`Docs/ai/DECISIONS.md`, 2026-09-24).

## Status

- **iOS 5.5 released 2026-09-30 06:31 PT:** POST `/v1/appStoreVersionReleaseRequests` -> 201, record READY_FOR_SALE
  with build 483. Recorded as on 2026-09-24 for 5.4: `## 5.5` lost its unreleased marker, `SHIPPED_VERSION.json` has
  iOS 5.5 and `app_store` still 5.4, the user changelog is dated. The Pro Annual, Pro Monthly and Lifetime versions
  read ACCEPTED, which Apple's "Working with In-App Purchase versions" defines, with APPROVED, as passed review; no
  release endpoint exists for them. The description row closed with Shipped On iOS, and the three In Progress v5.5
  rows carry Shipped On iOS.
- **5.5 resubmitted 2026-09-29 14:52 PT** with build 483 (Xcode Cloud #483 from `81b66a8`): iOS submission `861f9fe2-45f2-429d-a423-0bbaeead72a6` holds
  the version plus the three product drafts (Pro Annual and Pro Monthly subscription versions, the Lifetime purchase
  version, whose display name is now "Lifetime"); macOS submission `9691fad8-8026-4ed5-b348-37886c00ab84` holds the version. Records: iOS
  `d7b9bb32-0694-41fc-9692-75cc63cb4a7f`, macOS `73bc0eaa-c670-479c-941e-b75998ac0142`, release MANUAL. What's New,
  description and keywords written from `fastlane/metadata/en-US/` by `scripts/asc_prepare_release.rb`; the App
  Review note on both records carries the plans-screen paragraph (`fastlane/review_notes/5.5.txt`). The first
  submissions (409aead4 iOS, 6d81ae2c macOS, 00242f20 products) were cancelled through the API; the procedure is in
  `Docs/ai/RUNBOOK.md`, "Pulling a submission back".
- **Plans screen, `81b66a8`, at the owner's word.** Annual shows "Save N% vs Monthly" and "$X a month, billed
  yearly"; Lifetime shows "Less than a year of Monthly" and its months-of-Annual line; every card shows its label;
  all computed per storefront from live StoreKit prices and placed under the billed price (Apple's rule, quoted in
  `Docs/BILLING_AND_LIMITS.md` section 2). "Lifetime Cohort" is "Lifetime" in the app and App Store Connect.
  Fallback prices and `LaunchSale.regularLifetimePrices` moved to the new prices (`verify_sale_prices.py`: all
  match across its 28 territories; not one price per currency across all 175, see Blockers). Win-back offers on the plans screen: offered, declined by the owner (DECISIONS 2026-09-29). Roadmap row
  https://app.notion.com/p/3ea49a74d54f817abddae36a4fcc527d (In Progress, v5.5).
- **Entitlement fix, in 482 and 483, at the owner's word:** only a Lifetime purchase, or a subscription that began
  before 2026-09-30 00:00 UTC, earns permanent protection (`EntitlementStore.protectionEarned`); stored protection is
  never lowered. Row https://app.notion.com/p/3ea49a74d54f8163865ff0a7c1ef55e6 (In Progress, v5.5).
- **Prices, set 2026-09-29 at the owner's word:** Lifetime $49.99 from 2026-09-30; Pro Annual $24.99 and Pro Monthly
  $4.99 from 2026-10-01; annual win-back $14.99 from 2026-10-01. All read back from the API (`Docs/BILLING_AND_LIMITS.md`
  section 5). The sale came down on 2026-09-30 at about 08:00 PT, at the owner's word, ahead of the 09:00 routine: promo
  text replaced on six records by `scripts/asc_end_sale.rb` (the live macOS 5.4 listing among them), and the sale line
  removed from Fascinaiting `2825951d`, Gunnarguy-Portfolio `6e106c5` and Gunzino `bfd41af`. The owner deleted
  the routine `openintelligence-end-lifetime-sale` afterwards (it no longer appears in the scheduled task list).
- **5.4 is live** on iOS and macOS, build 478.
- **Cleanup, 2026-09-29, `35024f0`:** 27 files archived, two pointers, 86 documents corrected; details in the two
  2026-09-29 `[General]` entries under `## 5.5` in `CHANGELOG.md` and in `Docs/Archive/README.md`.

## Active Constraints

- **No version is open.** `## 5.5` lost its unreleased marker when iOS shipped, so a build would stamp 5.5, which App
  Store Connect rejects for iOS. Any source change needs the owner's say and a new `## 5.6 <!-- unreleased -->` heading
  first. Until then every push says `[ci skip]` (`Docs/ai/RUNBOOK.md`). The filter skips only
  `*.md`, `Docs/`, `.claude/`, `.agents/`, `.codex/`, `fastlane/metadata/`, `.github/`.
- Pushing publishes to a public repository and to gunnarguy.me. Ask before pushing. Keep the owner's personal plans
  out of public files. `CLAUDE.md` forbids deleting docs: removing one means `git mv` into `Docs/Archive/`.
- App Store Connect writes happen only at the owner's word. Guard memory on builds (18 GB Mac): `-jobs 2`, stop at
  15% free, DerivedData outside `~/Documents`. Commit to `main`, explicit paths, no AI trailer.
- The billing route forbids `StoreKitBillingService.swift`, `EntitlementStore.swift`, `QuotaPolicy.swift` and
  `StoreKitConfiguration.storekit` unless the owner names the file.

## Working Set

- `OpenIntelligence/Features/Billing/PlanUpgradeSheet.swift`: `dealBadge(for:)`, `comparisons(for:)`, `livePrices`.
- `OpenIntelligence/Features/Billing/PlanPriceComparison.swift` and its tests.
- `Docs/BILLING_AND_LIMITS.md` section 2 ("What each plan says against the others") and section 5 (prices).
- `Docs/SHIPPED_VERSION.json` `in_review`; `Docs/Release/APP_STORE_METADATA_HISTORY.md` `### 5.5`.

## Verification (2026-09-29, output read)

- Guarded `xcodebuild test -scheme OpenIntelligence` on simulator `244AA789-A9EA-403B-A922-F12083D14495` (iOS 27),
  `-jobs 2`, DerivedData `/private/tmp/oi-build`, from the `/private/tmp/oi-src` copy of `81b66a8`'s tree ->
  `** TEST SUCCEEDED **`, 521 tests, 3 skipped, 0 failures.
- The plans screen rendered in that simulator with `StoreKitConfiguration.storekit`'s products (a throwaway test in the
  copy only, never committed), light, dark and XXXL text: badges and captions under the billed price as specified.
  At the owner's word that file now holds the October prices ($4.99, $24.99, $49.99, "Lifetime", no trial); loaded in
  a StoreKit test session it returned those three prices, and the screen rendered $2.09, 58% and 24 months.
- `scripts/verify_sale_prices.py` -> every recorded currency matches App Store Connect's $49.99 schedule across its 28
  territories; a read of all 175 found two USD and two EUR prices (Blockers).
- `verify_doc_claims.py` -> all 778 claims match; secret scan clean; codemap 0 errors, 0 warnings.
- Xcode Cloud #483 -> `COMPLETE/SUCCEEDED`, both archives; builds 483 VALID on iOS and macOS.
- Accessibility sizes 1, 3 and 5 rendered the same way: "Pro (Monthly)" wraps at the space beside its label, no word
  breaks. Those renders used the test file's old prices; the October prices were rendered after the file changed (above).
- An adversarial review of `81b66a8` found no blocker; its accuracy fixes are in the commit after it (`[ci skip]`),
  and the two billing test classes pass after it (23 tests, 0 failures).
- Not run: the route's manual purchase and restore in the `OpenIntelligence-StoreKitTesting` scheme.

## Blockers / Unknowns

- **macOS 5.5 after App Review.** On `PENDING_DEVELOPER_RELEASE`, release only at the owner's word (`Docs/ai/RUNBOOK.md`,
  "Releasing an approved version through the API"). Then close 5.5 out as 5.4 was in `5b1c378`: `SHIPPED_VERSION.json`
  `app_store` and macOS to 5.5 and `in_review` empty, READMEs and doc headers, the GitHub release `v5.5.0` as Latest,
  the three sites, and Shipped On macOS on the description row https://app.notion.com/p/3e949a74d54f817f8933e538845009c6
  and the three v5.5 rows. The subscriptions row https://app.notion.com/p/3ea49a74d54f8163865ff0a7c1ef55e6 closes after
  a sandbox check (buy Pro Monthly, Settings shows Pro, not Lifetime; let it expire and relaunch, Free); the plans-screen
  row closes when the three cards read right on a device on the App Store build.
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
- **Future Backlog rows filed 2026-09-29:** "Just Once" PCC consent carries over in Deep Think and Maximum
  (https://app.notion.com/p/3ea49a74d54f81fd814ae82ce9449e41, High); Settings lists 4 tool functions, 6 run
  (https://app.notion.com/p/3ea49a74d54f8167a9b3d92c94539567); iOS 26 Settings blames the build for PCC
  (https://app.notion.com/p/3ea49a74d54f8126a005f0a27a318498); MMR lambda never read
  (https://app.notion.com/p/3ea49a74d54f817ab4bcf5bb6ad07509); sentence-opening words become entities
  (https://app.notion.com/p/3ea49a74d54f81059b20e8bda0663798).
- **Carried:** six `v5.4` rows close on the owner's device check (URLs in `git show 8be003a:Docs/ai/STATE.md`);
  Evidence Threads sync may copy nothing (`EvidenceThreadStore.swift:60` against `WorkspaceSyncService.swift:2739`).
- **Unverified, needs a device:** source chips and inline citations may not open anything (`ChatScreen.swift:901`,
  `RAGService.swift:17623`, `GroundedAnswerView.swift:31-35`).
- **Owner decisions left open:** six Google Ads scripts with no copy elsewhere; the 28 Swift files no other file
  names; `THIRD_PARTY_NOTICES.md` lacks the Rust crates swift-tokenizers links; `Docs/RepoOS/01_TASK_ROUTER.md:9`
  cites playbook 07.

## Exact Next Action

Wait for macOS App Review. Read the record with GET `/v1/apps/6756559175/appStoreVersions?filter[versionString]=5.5`.
On `PENDING_DEVELOPER_RELEASE`, ask the owner whether to release; on `REJECTED` or `UNRESOLVED_ISSUES`, read the
review message and bring it to him with a proposed fix. Also confirm the store shows the Lifetime purchase as
"Lifetime": its v2 passed review (ACCEPTED), and the v1 localization still read "Lifetime Cohort" at 06:40 PT.
