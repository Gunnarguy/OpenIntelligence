# Current State

Updated: 2026-08-11
Branch/worktree: main, primary checkout
Last verified commit: 01f94ea

## Objective

**v5.0 partial UI makeover, folded into the v5.0 release.** A tester told the owner the app "feels
vibecoded", so the arc is a pass over every tab, page and subpage. `PROCEED: IMPLEMENT` was granted
for the whole plan on 2026-08-10 and is still in force.

The makeover is **done**. The next objective is named in Exact Next Action and is a new piece of
work the owner scoped at the end of this session.

## Status

21 commits on `main` since `436e150`, all pushed. `CHANGELOG.md` has a numbered `## 5.0` heading
with 56 entries and an empty `[Unreleased]`, so `ci_scripts/ci_post_clone.sh` derives
`MARKETING_VERSION = 5.0` and its guard passes.

Suite is **205 tests, 0 failures** on iOS 27.0.

## Completed

Beyond the makeover itself, this session:

- **Version History.** `Settings > Version History` renders every shipped release, parsed from
  `VersionHistory.md` in the app bundle. That file is a copy of `Docs/USER_CHANGELOG.md`;
  `VersionHistoryTests` fails the suite if they diverge or if a `## ` heading stops parsing.
- **Sample corpus corrected and made self-updating.** The three shipped samples claimed
  Pages/Numbers/Keynote support, credited Accelerate for embedding (it is Core ML on the ANE;
  Accelerate compares vectors afterwards), and documented a "Telemetry HUD" screen that does not
  exist. Samples now carry a SHA-256 and re-import themselves once when the shipped text changes,
  with a banner explaining why.
- **Onboarding sample import: 1.3 minutes to ~6-8 seconds**, by skipping two per-document
  language-model enrichment calls that onboarding never displayed.
- **Em-dashes removed from every document a user can read.** This became functional rather than
  stylistic once Version History shipped, because `USER_CHANGELOG.md` now renders in the app.

## Active Constraints

- **The owner does not want em-dashes. Anywhere.** `USER_CHANGELOG.md` renders inside the app now,
  so this is a product rule, not a preference.
- **Prefer short, scannable bullets** in user-facing docs. Long paragraphs read as walls of text at
  phone width. Engineering entries in `CHANGELOG.md` stay detailed.
- **Zero call sites is not dead code.** Twice this session that assumption would have destroyed
  something real: `LocalOpenAIServerLLMService` is scaffolding for an open roadmap row, and
  `VisualizationsView.swift` holds 33 structs of which Atlas uses `EmbeddingSpaceView`. Run
  `oi-claim-audit` before any removal.
- **`[Unreleased]` must stay empty.** New entries go under `## 5.0` until 5.0 ships, or Xcode Cloud
  refuses to build.
- **Anything the app imports on its own must pass an explicit `containerId`.** `enqueueDocuments`
  defaults to the *active* library, which is right for a user pressing Add Document and wrong for
  automatic work; a sample refresh with "Library 2" open would otherwise deposit samples there.
- Hard-boundary files still need the user to name them in an approval.

## Working Set

- `OpenIntelligence/Features/Onboarding/OnboardingChecklistView.swift`, the completion card, its
  `onDevicePanel` device chips, and `pipelineTheaterContent`. This is where the next task starts.
- `OpenIntelligence/UI/Components/InfoButtonView.swift`, a `(title, explanation)` popover that
  already exists and has only three call sites, all in Atlas. It is the obvious primitive for the
  next task.
- `OpenIntelligence/Features/Settings/HowThisWorksView.swift`, the existing plain-language
  explainer. Its copy is the tone to match and should not be duplicated.
- `OpenIntelligence/Features/Settings/VersionHistory.swift` and `VersionHistoryView.swift`.
- `OpenIntelligence/Features/Documents/Library/SampleDocumentManager.swift`, sample text plus the
  hash-based refresh.

## Verification

Every line below was run this session and its output read.

- `xcodebuild test` on iPhone 17 Pro / iOS 27.0 -> **205 tests, 0 failures**.
- `bash scripts/build_simulator_smoke.sh` -> **BUILD SUCCEEDED**.
- CI guard simulated against `CHANGELOG.md` -> derives `5.0`, `[Unreleased]` count 0.
- `python3 scripts/secret_scan.py` -> clean.
- Screenshots on iPhone 17 Pro / iOS 27: the Settings index, Version History row and rendered
  history, both TipKit tips, the HUD drag hint.
- `VersionHistory.md` confirmed present inside the built `.app`.

**Not verified:** Settings `.searchable` input (the simulator's hardware keyboard does not reach the
field); Neural Engine telemetry during generation and the model pill's `.ready` state (Foundation
Models do not run in the simulator); HUD rotation against physical chip position; the sample
auto-refresh firing (needs a pre-v5.0 library); every Mac fix (no Mac hardware used).

## Blockers / Unknowns

**1. Four device checks close every open verification item.** On a physical device: type in Settings
search; run a query with the HUD visible and watch the Neural Engine bar; rotate with the HUD on;
and update from a pre-v5.0 build to see the sample refresh banner.

**2. A stale Xcode DerivedData will fail to link.** Adding a defaulted parameter to
`ingestDocuments` changed its mangled name, so a stale `.o` referencing the old default-argument
generator breaks the link. `rm -rf ~/Library/Developer/Xcode/DerivedData/OpenIntelligence-*`. Clean
CLI builds are unaffected, which is why it was not caught here.

**3. The retrieval eval set is saturated and cannot score a model change.** R@5 = 1.00 at every
stage but `lexical` 0.94. `RetrievalStageMetrics.swift:45` states recall@5 "gives no information
beyond 'did a chunk from the right file appear'. MRR@10 and nDCG are the metrics that actually
discriminate". **Read MRR@10 and nDCG before any embedder or reranker decision.** If MRR is also at
ceiling, retrieval is not the bottleneck; if MRR is poor while R@5 is 1.00, it is a **reranker**
problem, which is the cheap Apache-licensed swap rather than a re-embed.

**4. Licensing shapes the embedder decision.** The shipped stack (MiniLM-L6-v2,
`ms-marco-TinyBERT-L2-v2`) is Apache 2.0. **EmbeddingGemma is not**; it ships under the Gemma Terms
of Use, whose §3.1 requires the use restrictions to be enforceable against *your* users. Jina's v2
reranker weights are reported CC-BY-NC; verify before relying on that. Not legal advice.

**5. The What's New sheet is a changelog, not a splash.** The `"5.0"` entry has **8 items and no
deep links**, and `WhatsNewView` has one button, "Done". Cutting to 3-4 and making rows navigate is
the improvement.

**6. Notion roadmap has not been touched all session.** "Liquid Glass UI Refresh" is still marked
In Progress and is substantially shipped. Several other v5.0 rows are affected. This is
repo-required work under `.agents/rules/01-docs-and-notion-sync.md`.

**7. Carried from 2026-08-09.** The malformed `[Needs Verification]` block still reaches users
(`SourceOnlyAnswerService.swift:349`). The verification gate still hedges correct answers.

## Exact Next Action

**Make the app explain its own vocabulary, in place, to a non-technical user.** The owner's words:
people see "38 TOPS", "32/batch", "768 search", "16-core ANE", "Chunks", "Vectors" and have no idea
what any of it means, which risks them uninstalling rather than engaging. He wants the app
"digestible to all crowds, the technical and nontechnical, almost a blend".

Two parts, and he explicitly wants this to **not** be hidden in Settings:

1. **Tappable inline definitions** on the numbers already on screen. `InfoButtonView`
   (`UI/Components/InfoButtonView.swift`) is a `(title, explanation)` popover that already exists
   and is used in only three places, all in Atlas. Start there rather than inventing anything. The
   first surfaces are the onboarding completion card's device chips
   (`OnboardingChecklistView.onDevicePanel`) and its Words/Chunks/Vectors/Time metric strip, then
   `Settings > Device & Performance`, whose Hardware Envelope is the densest jargon in the app.
2. **Fold the explanation into onboarding** rather than leaving it only at
   `Settings > How This Works`. Do not duplicate that screen's copy; it is the correct tone and
   should be the single source, linked or excerpted.

Write the definitions in the voice `HowThisWorksView` already uses: state the mechanism plainly,
no adjectives doing the work of facts, no em-dashes. A chunk is "a passage small enough to search
precisely and large enough to still make sense on its own", not "a semantic unit of retrieval".

**Before writing copy, read `Docs/ai/DECISIONS.md` if it covers tone, and reuse
`HowThisWorksView`'s wording.** Show the owner drafted copy before wiring it in; he has said
previous attempts at this kind of writing came out cringe, and he approved the last batch only
after seeing it first.
