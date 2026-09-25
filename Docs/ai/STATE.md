# Current State

Updated: 2026-09-24, 17:40 PT (5.4 live on iOS and macOS and closed out everywhere; development paused)
Branch/worktree: `main`, primary checkout
Last verified commit: 5b1c378

## Objective

None active. 5.4 shipped on both platforms on 2026-09-24 and is closed out in this repository, on
GitHub, on all three websites and in Notion. The owner paused development after 5.4 the same day
(`Docs/ai/DECISIONS.md`, 2026-09-24). Pick work up only when he says to. The next version is 5.5,
his pick.

## Status

- **5.4 is live on iOS and macOS**, build 478 (Xcode Cloud #478 from `c276b9a`), release MANUAL.
  Apple approved each platform, and the owner could not get the Release button in App Store Connect
  to work, so at his request each went out through `POST /v1/appStoreVersionReleaseRequests`: iOS
  at 14:32 PT and macOS at 17:00 PT. Both returned 201 and read back `READY_FOR_SALE`
  (`appVersionState` `READY_FOR_DISTRIBUTION`) within seconds. Records: iOS
  `edac9a46-fd9c-4082-99f8-372008d20289`, macOS `0e7e7d98-9878-4418-b977-3bc0b04ddf96`. The procedure
  is in `Docs/ai/RUNBOOK.md`, "Releasing an approved version through the API".
- **Repository close-out, done:** `Docs/SHIPPED_VERSION.json` has `app_store` 5.4 on both platforms,
  `preparing` 5.4 and `in_review` empty. `CHANGELOG.md` has `## 5.4 - September 24, 2026` with no
  version open above it. `Docs/USER_CHANGELOG.md` and the byte-identical bundled copy have
  `## v5.4 - September 24, 2026`. `Docs/Release/APP_STORE_METADATA_HISTORY.md` records both release
  times, and `README.md`, `WHATS_NEW.md`, `Docs/README.md`, `Docs/ROADMAP.md` and the pipeline doc
  headers say 5.4.
- **GitHub:** `v5.4.0` is a full release, and it is Latest, at `c276b9a`. Its first line reads "live
  on iPhone, iPad and Mac since 2026-09-24". `v5.3.0` (`a2d99ab`, build 464) covers 5.2 and 5.3.
- **Websites, all at 5.4 by 17:15 PT and read back live with curl:**
  - fascinaiting.me: Fascinaiting `91c9b21e` made the hero span 5.4 and 5.4 the current timeline
    entry, marked 5.3 superseded, and removed the in-development entry. Site Verification, the
    OpenIntelligence Version check and the Pages deploy all passed.
  - gunzino.me: Gunzino `6f08666` changed all four version lines in one commit; Deploy passed.
  - gunnarguy.me: its version bot committed `f23820a`, "sync site to v5.4", and Build and Deploy
    passed.
  - What follows Apple's lookup, which still read 5.3 at 17:05 PT: gunnarguy.me's store-listing
    fields (`data/appstore.json`, refreshed daily at 15:00 UTC) and Gunzino's App Store Versions
    check (daily at 06:20 UTC). If the lookup has not caught up by then, that check fails once.
- **Notion:** all six `v5.4` rows carry `Shipped On` iOS and macOS, and stay In Progress until the
  owner's device check (Blockers). fascinaiting.me's board counts 5.4 as shipped from its live
  version regardless. Its roadmap sync ran at 00:11 UTC; the nightly sync a minute later lost a
  rebase race on `roadmap.json` and failed harmlessly.
- **Post Desk** (https://claude.ai/artifact/RgpvBXBViCZpSvtXFpNUb7): the 5.4 switch is on, so the 5.4
  posts are unlocked, with the "It's live" quote post first.
- Scheduled: 2026-09-30 09:00 PT, task `openintelligence-end-lifetime-sale`, which takes the sale
  line off the listing and the three sites. It is still needed.

## Active Constraints

- **No version is open in `CHANGELOG.md`.** Before any app-change push, open
  `## 5.5 <!-- unreleased -->` above `## 5.4` with `<!-- next-version: 5.5 -->`, and create the 5.5
  records in App Store Connect. Otherwise `ci_post_clone.sh` stamps 5.4, and App Store Connect rejects
  the upload. Pushes of documentation only do not start a build.
- App Store Connect writes happen only at the owner's word. Auto mode refused a release-type change
  and a website version move on 2026-09-24, and allowed the same work once he asked outright.
- Guard memory on builds (18 GB Mac): `-jobs 2`, stop at 15% free, and build from `/private/tmp/oi-src`.
  swift-format rewrites Swift files edited with Edit/Write. Commit to `main`, no AI trailer.

## Working Set

- `Docs/SHIPPED_VERSION.json`, `CHANGELOG.md`, `Docs/USER_CHANGELOG.md` and
  `OpenIntelligence/Resources/VersionHistory.md` are the release records.
- In the site repos: Fascinaiting `index.html` (timeline), Gunzino `openintelligence/index.html:226`,
  `index.html:374`, `src/content/pages/openintelligence.md:4` and `src/data/home.json:9`.

## Verification (2026-09-24, output read)

- App Store Connect, 17:00 PT: iOS 5.4 and macOS 5.4 are both `READY_FOR_SALE`, build 478.
- `python3 scripts/verify_doc_claims.py` passes, apart from a stale path in the previous copy of this
  file. The router preflight reports active release `v5.4`, state shipped, last shipped `v5.4`.
- Fascinaiting `./scripts/verify-site.sh source` and Gunzino `npm run verify` each exited 0 before
  the push. Every site run since the push passed, apart from the harmless roadmap race above.
- Live, by curl: fascinaiting.me reads "App Store 5.4", gunzino.me "Version 5.4" on both pages, and
  gunnarguy.me "Version 5.4". Fascinaiting's four internal files (`/CLAUDE.md`,
  `/ANALYTICS_AUDIT.md`, `/google_ads_config.json`, `/FACT_CHECK-2026-09.md`) return 404.
- Earlier, on the 5.4 code: the full iOS suite ran 500 tests with 0 failures and 3 skipped
  (2026-09-23).

## Blockers / Unknowns

- **Six `v5.4` rows close on the owner's device check**, and nothing can verify that from here:
  - answers finish when the last word appears:
    https://app.notion.com/p/3e449a74d54f818197d4c6e45f8d2142
  - the haptic, badge and clock for an answer that finishes off screen:
    https://app.notion.com/p/3e449a74d54f8193964bdda0f50d16c3
  - Deep Think and Maximum stream:
    https://app.notion.com/p/3e449a74d54f813787a6cf91ef814767
  - the free plan's Maximum cap is enforced:
    https://app.notion.com/p/3e349a74d54f81b49205d1a75f2a4b99
  - the plans screen after setup does not crash:
    https://app.notion.com/p/3e449a74d54f81afb55fc318f81244f9
  - 5.4's What's New shows to updaters:
    https://app.notion.com/p/3e149a74d54f819aba78e2b85f0e9942

  When he says they work, set each row to `Completed` with `date:Completed:start` 2026-09-24 or later.
- The three subscription descriptions in App Store Connect are still wrong ("unlimited documents and
  5 libraries" for Pro, "10 Libraries" for Lifetime). The API refuses them (409, ACTIVE), so they are
  a web-page edit, the owner's.
- Cleanup, test data only:
  - `/private/tmp/oi-ui-appsupport-2026-09-23`
  - simulators `6CD2218C-EA61-46B3-B31E-0667FBCDF2B6`, `57E0CE08-EA1A-4D02-9D74-FEBD238709ED` and
    `F798E00A-9F48-44B8-A087-45413A96783A`, all shut down
  - `/private/tmp/oi-bench/`
  - in the owner's iCloud Documents, `~/Documents/SampleDocuments` and
    `~/Documents/SampleDocuments.evicted-2026-09-23`, which hold sample copies only

## Exact Next Action

None. 5.4 is shipped and closed out, and the owner paused development after it. When he confirms
the device checks, close the six rows in Blockers. When he resumes building, open 5.5 as Active
Constraints describes before the first app-change push.
