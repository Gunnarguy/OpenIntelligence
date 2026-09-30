# Current State

Updated: 2026-09-30, 10:25 PT (5.5 is live on both platforms with build 483, and closed out)
Branch/worktree: `main`, primary checkout
Last verified commit: 7076f30

## Objective

None active. 5.5 shipped on iPhone, iPad and Mac on 2026-09-30 and is closed out. New work starts only when the owner
says to (`Docs/ai/DECISIONS.md`, 2026-09-24); the next source change needs a `## 5.6 <!-- unreleased -->` heading in
`CHANGELOG.md` first.

## Status

- **5.5 is live on both platforms, build 483** (Xcode Cloud #483 from `81b66a8`): iOS released at 06:31 PT and macOS at
  10:14 PT on 2026-09-30, each through the App Store Connect API at the owner's word (POST
  `/v1/appStoreVersionReleaseRequests` -> 201, records READY_FOR_SALE). It carries the "how much" extractor fix, the
  subscription fix (only a Lifetime purchase, or a subscription begun before 2026-09-30 00:00 UTC, earns permanent
  protection) and the plans screen's comparisons (`Docs/BILLING_AND_LIMITS.md` section 2).
- **Closed out as 5.4 was:** `Docs/SHIPPED_VERSION.json` `app_store` 5.5 on both platforms, `in_review` empty;
  `CHANGELOG.md` `## 5.5 - September 30, 2026` with its shipped note; `README.md`, `Docs/README.md`, `Docs/ROADMAP.md`,
  `WHATS_NEW.md`, `Docs/RELEASE_NOTES.md` and the metadata history say 5.5; the GitHub release `v5.5.0` is Latest
  (https://github.com/Gunnarguy/OpenIntelligence/releases/tag/v5.5.0, at `81b66a8`, 44 commits since `v5.4.0`); the
  description row https://app.notion.com/p/3e949a74d54f817f8933e538845009c6 is Completed with Shipped On iOS and
  macOS, verified on both live descriptions; the three v5.5 rows carry Shipped On iOS and macOS.
- **Prices, set 2026-09-29 at the owner's word:** Lifetime $49.99 from 2026-09-30; Pro Annual $24.99 and Pro Monthly
  $4.99 from 2026-10-01; annual win-back $14.99 from 2026-10-01. All read back from the API (`Docs/BILLING_AND_LIMITS.md`
  section 5). The US App Store page read $49.99, $29.99 and $5.99 at 10:20 PT on 2026-09-30.
- **The sale came down on 2026-09-30 at about 08:00 PT**, at the owner's word, ahead of the 09:00 routine: promo text
  replaced on six records by `scripts/asc_end_sale.rb`, and the sale line removed from Fascinaiting `2825951d`,
  Gunnarguy-Portfolio `6e106c5` and Gunzino `bfd41af`, all verified live. The owner then deleted the routine.
- **The local StoreKit test file** holds the October prices at the owner's word (`16c4805`).

## Active Constraints

- **No version is open.** A build now would stamp the released 5.5, which App Store Connect rejects. Until a `## 5.6`
  heading exists, every push says `[ci skip]` (`Docs/ai/RUNBOOK.md`).
- Pushing publishes to a public repository and to gunnarguy.me. Keep the owner's personal plans out of public files.
  `CLAUDE.md` forbids deleting docs: removing one means `git mv` into `Docs/Archive/`.
- App Store Connect writes happen only at the owner's word. Guard memory on builds (18 GB Mac): `-jobs 2`, stop at
  15% free, DerivedData outside `~/Documents`. Commit to `main`, explicit paths, no AI trailer.
- The billing route forbids `StoreKitBillingService.swift`, `EntitlementStore.swift`, `QuotaPolicy.swift` and
  `StoreKitConfiguration.storekit` unless the owner names the file.

## Working Set

- `Docs/SHIPPED_VERSION.json`: the release record the three sites read from `origin/main`.
- `Docs/BILLING_AND_LIMITS.md` sections 2 and 5: what the plans screen says, and the prices.
- `Docs/ai/RUNBOOK.md`: "Submitting for review through the API", "Pulling a submission back", "Releasing an approved
  version through the API".

## Verification (2026-09-29 and 2026-09-30, output read)

- Guarded `xcodebuild test -scheme OpenIntelligence` on simulator `244AA789-A9EA-403B-A922-F12083D14495` (iOS 27),
  `-jobs 2`, DerivedData `/private/tmp/oi-build`, from the `/private/tmp/oi-src` copy of `81b66a8`'s tree ->
  `** TEST SUCCEEDED **`, 521 tests, 3 skipped, 0 failures. After the review's fixes, the two billing test classes
  -> 23 tests, 0 failures.
- The plans screen rendered in that simulator with the October prices from the updated StoreKit test file: $4.99,
  $24.99 with "Save 58% vs Monthly" and "$2.09 a month, billed yearly", $49.99 with "Less than a year of Monthly"
  and 24 months; accessibility sizes 1, 3 and 5 laid out without word breaks.
- Xcode Cloud #483 -> `COMPLETE/SUCCEEDED`, both archives. Both 5.5 records READY_FOR_SALE with build 483.
- `verify_doc_claims.py` -> every claim matches; `verify_sale_prices.py` -> the table matches across its 28 territories.
- Not run: the route's manual purchase and restore in the `OpenIntelligence-StoreKitTesting` scheme.

## Blockers / Unknowns

- **Rows that close on a device check, all Shipped On iOS and macOS:** the plans screen
  (https://app.notion.com/p/3ea49a74d54f817abddae36a4fcc527d) when its three cards read right on a device on the App
  Store build; the subscription fix (https://app.notion.com/p/3ea49a74d54f8163865ff0a7c1ef55e6) after a sandbox check
  (buy Pro Monthly, Settings shows Pro, not Lifetime; let it expire and relaunch, Free); the "how much" row
  (https://app.notion.com/p/3e749a74d54f8115a76ad5b06b196956) stays open because the model still answers the lease
  question wrong.
- **The Lifetime purchase's store name:** its v2 (display name "Lifetime") passed review and every item in the iOS
  submission reads APPROVED, but at 10:20 PT the version still read ACCEPTED and the US App Store page still listed
  "Lifetime Cohort $49.99". No API or publish step exists for product versions (`Docs/ai/RUNBOOK.md`). Recheck the
  page; if it has not changed within a day, look at the product in App Store Connect's web UI.
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

None. 5.5 is shipped, verified live on both platforms and closed out. There is no active objective; ask the owner what
to pick up, or take a roadmap item from the Notion database. One recheck is outstanding: the US App Store page listing
the Lifetime purchase as "Lifetime" (Blockers).
