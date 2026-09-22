# Conversion and reviews: what the app does, what the data says, what the evidence supports

Written 2026-09-22. Four read-only investigations, each cited: a code audit of every paying, limit,
rating and review touchpoint; the owner's own App Store Connect data from `~/ASC/data/asc.sqlite3`;
Apple's APIs and rules read from the iOS 27 SDK and developer.apple.com the same day; and published
conversion research dated 2025 to 2026. Nothing here is from memory.

`[evidence_level: measured, confidence: high, evidence_source: sections name their own sources]`

## 1. The numbers, corrected

The owner's working figures were "100+ installs, 28 purchases, 4 reviews". The archive says:

| Measure | Value | Source |
|---|---|---|
| First-time downloads, all time (2026-02-01 to 09-21) | 333 (iPhone 255, iPad 32, Mac 46) | `funnel_downloads`; `sales` agrees at 355 with the Mac split |
| First-time downloads, last 30 days | 67 | same |
| Still-installed, auto-updating devices | about 130 (every release reaches 114 to 135) | `funnel_downloads` update installs |
| Purchase events | 29 net (9 paid Lifetime, 1 Lifetime at $0, 5 Monthly starts + 6 renewals, 4 Annual trial starts + 2 paid, 1 refund, 3 Doc Pack) | `store_purchases`, cross-checked to `sales` |
| Distinct new paying customers | 17 gross, 16 net | same, row-level |
| Proceeds, all time | $480.66 (Lifetime $395.65 of it) | same |
| Install to paying customer | 5.1% (4.8% net); last 30 days 4.5% | derived |
| Days from download to purchase | median 1.5; 12 of 20 dated purchases within 48 hours | `store_purchases.app_download_date` |
| Deletes | 56% on install day, 22% on day 1; 39 deletes vs 51 opted-in installs since April | `app_lifecycle` |
| Sessions per device-week | 37% one session, 24% two, 13% eleven or more (that 13% is 59% of all sessions) | `app_sessions` WEEKLY, 93 rows |
| Star ratings | 5 (US 4 at 4.75, Portugal 1 at 5.0), 1 written review dated 2026-03-25 | public lookup across 47 storefronts; ASC customerReviews |
| Listing funnel, last 30 days | 25,840 impressions, 532 page views, 99 Get taps, 67 downloads | `funnel_engagement`, `funnel_downloads` |
| Active subscriptions today | 3 | `subscription_state` |
| Retention messaging on cancel | none configured; 5 of 5 cancel-sheet views ended in a cancel | `retention_messaging` |

Against published benchmarks: freemium install-to-paid median 2.1% (RevenueCat 2026), install-to-direct
3.71% (Adapty 2026). 5.1% is about 2.5 times the freemium median. Conversion is not the problem.
Installs and the first session are.

Two ratios in the listing funnel, because they point at different fixes: impression to page view is
2.1%, and page view to Get is 18.6%. The page converts well once opened; the search result does not
get opened. That is icon, name, subtitle and the first three screenshots, which show inline in search.

What the data cannot see: anything inside the app. There is no analytics of any kind (grep for
eleven vendors and MetricKit returns nothing). Nobody knows how many questions a user asks. Apple's
own analytics are opt-in (46%) and never produced daily session data for this app.

## 2. What the app actually shows, from code

Full map with file and line in the audit transcript; the facts that change decisions:

1. **The Maximum-mode daily cap is not enforced.** `EntitlementStore.consumeMaximumModeUseIfNeeded()`
   and `MaximumModeQuotaStore.consumeIfAllowed` have no caller. `RAGServiceError.maximumModeQuotaReached`
   is declared and never thrown (added 6dc093c, 2026-05-12, without a throw). The pill says "3 left
   today" and never decrements. The paywall's headline promise, "Pro and Lifetime lift the daily cap on
   Maximum mode", gates nothing. Every free user has had unlimited Maximum since May.
2. **Two independent rating prompts fire on the same third answer**, `ReviewPromptService` at 2 s and
   the legacy `AppReviewPromptTracker` in `ChatScreen` at 4 s. Apple counts both against its three
   prompts per device per year.
3. **Deep Think and Maximum answers never count toward the rating prompt**: the agentic path leaves
   `gatingDecision` nil, and `isVerified` treats nil as not verified.
4. **Until 5.2 (2026-09-10) the rating prompt required two distinct usage days.** 37% of device-weeks
   have one session. That is why five ratings in eight months is not a mystery.
5. **The paywall's "social proof" banner has no social proof**: "Upgrade anytime, cancel in App Store
   settings."
6. **Onboarding never mentions plans.** The first pricing a user meets is the "Document Quota 0/5"
   meter on the Documents tab, shown from zero documents. Most buyers decide on day 0 (RevenueCat
   2026: over 50% overall, 72% in Productivity) and the app makes no offer until a limit or the 4th
   verified answer.
7. **Only one in-app route to a written review ever worked**, and it was dead code until 5.4.
8. **Subtitle and keywords live only in App Store Connect.** Both repo metadata trees have them
   blank, so a `deliver` push with `force: true` would erase "Chat With Your Files Offline" and all 14
   keywords. Same class of hazard as the screenshot overwrite closed on 2026-09-22.

## 3. Apple's rules and APIs, verified 2026-09-22

- `requestReview`: at most 3 prompts per device per 365 days; the app cannot tell whether it showed;
  never shows in TestFlight; always shows in debug. Do not call from a button.
- Custom review prompts are disallowed (5.6.1). Forcing a review to unlock anything is banned
  (3.2.2(x)). "Filtered" feedback is named as manipulation (5.6 preamble, 5.6.3). Asking at onboarding
  now draws rejections (RevenueCat, June 2026).
- A plain `?action=write-review` link in Settings is endorsed by Apple's own docs and is the only way
  to a written review from inside an app.
- Offer codes work for non-consumables from iOS 16.3 / macOS 15, up to 10 active offers, one
  redemption per customer per offer. A free or discounted Lifetime can be handed to a cohort without
  touching the price.
- Win-back offers (iOS 18 / macOS 15) need only App Store Connect configuration, no signing.
- Custom product pages: Apple's published figure is a 2.5 point lift over the 1.6% default conversion.
- `SubscriptionStoreView` renders trial text and the compliance footer for free; it has no "most
  popular" badge without a custom control style (iOS 18+).

## 4. What the evidence supports, and what it does not

Supported, with a number behind it:
- Ask for a rating at the success moment, on the first success, not after strong engagement. Cases:
  +400% ratings per month (Appbot, WordBoard); 2.2 to 4.7 stars in two weeks (Jake Lee, Dec 2024);
  moving the prompt to end-of-onboarding cut rating velocity (Appbot, 7 Minute Workout).
- Show the offer on day 0. Over half of paid conversions happen on install day; onboarding paywalls
  convert 1.35% vs 0.89% in-app per view (Adapty, March 2026); dismissible, not hard.
- No free trial for Productivity. Direct buyers are worth more ($56.95 vs $49.13 LTV) and the funnels
  land at the same install-to-paid (Adapty 2026). The trial withdrawal on 2026-09-18 was right.
- Reply to every review. Apple notifies the reviewer, who can update the rating; reply rate
  correlates with rating gains (AppFollow 2025).
- Written reviews are about 1 per 43 ratings across 432M ratings (Appbot). The lever is rating volume.
- Discount the post-plateau cohort, not new installs (RevenueCat). Utilities discount 1.2% of
  subscriptions (Adapty 2026).

Not supported:
- Countdown timers on a mobile paywall (evidence is web e-commerce; fake timers carry FTC exposure).
- "Most popular" badges as a lever (visual edits win 34.6% of tests, plan structure 58.7%, Adapty).
- The two-step "Do you like it?" gate (no measured lift, and the pattern Apple's rejections target).
- "Join N users" or rating counts in-app at under 100 ratings (no test exists at this scale).
- The $1-app pattern (Appfigures, Nov 2025: paid apps are 3.6% of the store and the claims are
  anecdotal).
- Adding a lifetime tier to raise total conversion (Dark Noise: under 10% more conversions, annual
  buyers shifted to lifetime and monthly, churn +57%).

## 5. The plan

Ordered by expected effect per hour, each with what closes it.

| # | Change | Why | Decision needed |
|---|---|---|---|
| 1 | Enforce the Maximum cap, with the existing dialog and "See Plans" | The product's paid value is currently free. This is the one change that makes Pro and Lifetime mean something. | Owner: free users lose unlimited Maximum. Recommended: yes, in 5.4, with the cap stated in the release notes. |
| 2 | One rating request, on the first verified answer, both quality modes counting; retire the legacy tracker | Apple's budget is 3 per year; two prompts on one answer waste it. First success beats third. | None, it is a defect fix. |
| 3 | A dismissible plans screen at the end of onboarding, after the sample questions | Day-0 is where buyers are. Soft, one tap to dismiss, never again. | Owner. Recommended: yes. |
| 4 | Replace the empty "social proof" banner with the two true sentences: the rating and "Data Not Collected" | The banner exists and says nothing. | None. |
| 5 | Write subtitle and keywords into both metadata trees; add them to the metadata history | Stops the next push erasing them. | None. |
| 6 | Rewrite the first two lines of the description and the release notes for a buyer, not a maintainer | The listing's first lines show before "more"; release notes currently open "This release is about what you see first". | None. |
| 7 | Reply to the one review, ask nothing | Reviewer is notified and can update. | Owner writes it, or approves a draft. |
| 8 | Configure a retention message and a win-back offer in App Store Connect | 5 of 5 cancel views ended in cancel with no message. | Owner, in the App Store Connect UI. |
| 9 | Ten Lifetime offer codes for the twelve heaviest users and the tester cohort | Free to give; no price change; a working lever for word of mouth. | Owner picks recipients. |
| 10 | One custom product page for the "chat with PDF" search intent | The only Apple-published conversion lever. | Owner; needs screenshots that tell that story. |

Deliberately not in the plan: analytics. Measuring questions per session would answer the owner's
question, and every vendor that can do it changes the privacy label from "Data Not Collected", which
is the listing's strongest line and the paywall's second sentence. Keep the label. Use the rating
prompt's own effect on the rating count as the measurement.

## 6. What this document does not claim

No item above has been A/B tested on this app, and at 67 installs a month none can be for a year.
The numbers are the best published evidence and this app's own history, and the expected effect of
each change is an inference from them, not a measurement.
