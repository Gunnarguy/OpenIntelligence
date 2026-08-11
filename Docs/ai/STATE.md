# Current State

Updated: 2026-08-10
Branch/worktree: main, primary checkout
Last verified commit: 9b73148 — **pushed**, `origin/main` matches, tree clean

## Objective

**v5.0 partial UI makeover, folded into the v5.0 release.** A tester told the owner the app "feels
vibecoded"; the arc is a pass over every tab, page and subpage. The owner chose to fold the makeover
into v5.0 rather than cut v5.0 first, so the engine work and the interface work ship together.
`PROCEED: IMPLEMENT` was granted for the whole plan on 2026-08-10 and is still in force.

## Status

Five commits landed on `main` today, all building, none pushed:

| Commit | Scope |
|---|---|
| `f9fbf6a` | v5.0 cut + Phases 0-2 (tokens, continuous corners, onboarding, HUD, device identity) |
| `f3ecca8` | Phase 4: Settings restructure |
| `38c8bff` | Model-parameter honesty + two backwards routing claims |
| `f1e8b2a` | One-tap Advanced |
| `4f70463` | Explicit sampling strategy, seed, Top-P fix |

| Phase | Scope | State |
|---|---|---|
| 0 | Design tokens, continuous corners, fake glass layer | **Done** |
| 1 | Onboarding truncation, Silicon HUD wiring, tab-bar safe area | **Done.** Safe area closed as not-a-bug |
| 2 | Collapse four chip-detection paths into one | **Done, simulator-verified** |
| 3 | Unify the two chat pickers | **Done, device-confirmed by owner screenshots** |
| 4 | Restructure Settings | **Done, simulator-verified** |
| 5 | Education layer (TipKit, InfoButtonView, "How this works") | **Not started** |
| — | Cleanup: dead UI, decorative toggles, leaked chat timer | **Partly done** (5 toggles + 3 dead cards); ~6,000 lines of unreachable UI and the chat timer remain |

**CI is armed for 5.0.** `ci_post_clone.sh` refuses to build while `[Unreleased]` has entries and
derives `MARKETING_VERSION` from the first numbered heading. Both checks were simulated against the
edited file: it derives `5.0` and the guard passes. `WhatsNewStore` has a `"5.0"` key, without which
an updating user would see an empty What's New sheet. **Do not add entries under `[Unreleased]`
while v5.0 is the target — put them in the `## 5.0` section or CI will refuse to build.**

## Completed

Beyond the phase table, three findings worth not rediscovering:

**The design system was abandoned because its scale was wrong.** `DSSpacing` was 2/6/10/14/20/28
while the seven commonest spacing literals in the app are 8 (295 uses), 4 (264), 12 (237), 6, 2, 10,
16. Three of the top four had no token; `xl = 28` matched nothing. Now on the 4pt grid.

**Everything named "Liquid Glass" returned `.ultraThinMaterial`,** and `.glassTabBar()` was actively
opting the tab bar *out* of the system treatment. Removed.

**Four chip-detection implementations disagreed.** `RAGService.detectDeviceChip()` stops at the
iPhone 16 line, so every newer identifier resolved to the literal string "A12 or Older" with
"Limited" performance — rendered in About and ANDed into the device tier. All routed through
`DeviceCapabilityService` now.

## Active Constraints

- **`oi-claim-audit` earned its keep today and must be run before removing any capability claim.**
  It stopped the deletion of the frequency/presence/repetition penalty sliders. Their only consumer,
  `LocalOpenAIServerLLMService`, has zero call sites — which looks like dead code until you notice
  the Notion row "Bring-your-own local model on Mac" targets v5.0. **Zero call sites is what an open
  roadmap row means.** The same pattern applies to `FoundationModelDynamicProfileRegistry` (Notion
  row "Dynamic Profiles", v5.0). Do not delete either.
- **Never stack builds.** Five concurrent `xcodebuild` processes against one DerivedData spent ~30
  minutes blocking each other on locks, with almost no compilation. Run one, detached via `nohup` so
  a tool timeout cannot orphan it, and wait.
- Touching a type in `Core/Models/` (e.g. `InferenceConfig`) forces a near-full rebuild of 188k
  lines. Batch those edits and build once.
- Hard-boundary files remain untouched and still require the owner to name them in an approval.

## Working Set

- `OpenIntelligence/Features/Settings/SettingsView.swift` — `SettingsEntry.all` is the index that
  drives both the rows and `.searchable`. Adding an entry is a compile error until it has a
  destination, which is deliberate.
- `OpenIntelligence/Features/Settings/Components/ModelConfigurationSheet.swift` — the Sampling
  section and the honest scope footers.
- `OpenIntelligence/Services/LLM/LLMService.swift:672` — explicit `SamplingMode` construction.
- `OpenIntelligence/Core/Models/LLMModel.swift` — `SamplingStrategy`, `InferenceConfig.seed`.
- `OpenIntelligence/Services/Infrastructure/Tips/AppTips.swift` — five TipKit tips with copy and
  rules, configured at launch, **zero rendering call sites**. Phase 5 starts here.
- `OpenIntelligence/UI/Components/InfoButtonView.swift` — `(title, explanation)` popover, three call
  sites, all in Atlas.
- `Docs/Engineering/V5_EMBEDDING_ARC_LEDGER.md` — read before any model-swap conversation.

## Verification

Run this session and output read:

- `xcodebuild test` -> **202 tests, 0 failures** on iOS 27.0 (iPhone 17 Pro simulator), after the
  Settings restructure. Two earlier runs reported one failure,
  `testSilentAudio_FailsLoudlyInsteadOfProducingAnEmptyDocument`; it was reproduced on clean
  `436e150` in a throwaway worktree with none of these changes present, then passed unchanged. It is
  **flaky in this environment** (no simulator speech assets, `com.apple.modelcatalog` "no underlying
  assets" in every log), not a defect.
- `build_simulator_smoke.sh` -> succeeded, repeatedly, including after every commit above.
- Simulator screenshots on iPhone 17 Pro / iOS 27 for: onboarding before/after, the chat pills, the
  open quality menu across three label forms, the Settings index, a pushed detail screen, the list
  bottom clearing the tab bar, and Model Parameters in one tap.
- Owner screenshots on a physical A18 Pro device confirmed the menu titles and checkmarks, and
  caught the pill height mismatch that the simulator structurally could not show.
- `python3 scripts/secret_scan.py` -> clean. `scripts/check_icloud_conflicts.sh` -> clean.
- CI guard simulated against `CHANGELOG.md` -> derives `5.0`, `[Unreleased]` empty.

**Not verified:** Settings `.searchable` input (the simulator's hardware keyboard does not reach the
field, so the filter is code-verified only), and the Neural Engine telemetry during generation plus
the model pill's `.ready` state (Foundation Models do not run in the simulator).

## Blockers / Unknowns

**1. Two device checks would close every open verification item at once.** On a physical device:
open Settings and type in the search field; and run one query with the Silicon HUD visible and watch
whether the Neural Engine bar moves while the answer streams.

**2. The retrieval eval set is saturated and cannot score a model change.** The last benchmark
measured R@5 = 1.00 at every stage but `lexical` 0.94, 0 hallucinated, abstention 100%. A comment in
`RetrievalStageMetrics.swift:45` states that recall@5 "gives no information beyond 'did a chunk from
the right file appear'. MRR@10 and nDCG are the metrics that actually discriminate between stages on
this corpus." **Read MRR@10 and nDCG before any embedder or reranker decision.** The Notion row
"Build quality fixtures with external ground truth" (v5.0, High) is the real gate.

**3. Licensing changes the embedder recommendation.** The shipped stack (MiniLM-L6-v2,
`ms-marco-TinyBERT-L2-v2`) is Apache 2.0: commercial use, attribution preserved in
`THIRD_PARTY_NOTICES.md`, no obligation flowing to end users. **EmbeddingGemma is not Apache 2.0** —
it ships under the Gemma Terms of Use, whose §3.1 requires the use restrictions to be an enforceable
provision in the agreement with *your* users, and §3.2 binds them to a Prohibited Use Policy Google
can update. For a paid App Store app that is a real compliance burden. Jina's v2 reranker weights
are reported CC-BY-NC and would be disqualified outright; **verify before relying on that.** Not
legal advice.

**4. Carried from 2026-08-09, untouched.** The malformed `[Needs Verification]` block still reaches
users (`SourceOnlyAnswerService.swift:349`). The verification gate still hedges correct answers.

## Exact Next Action

**Start Phase 5, the education layer, at
`OpenIntelligence/Services/Infrastructure/Tips/AppTips.swift`.** Five TipKit tips exist with written
copy and event rules, `AppTipConfiguration.configure()` already runs at launch
(`OpenIntelligenceApp.swift:32`), and there are **zero rendering call sites** — no `InlineTipView`,
no `popoverTip`, and the events (`queryPerformed`, `documentIngested`) are never donated, so every
rule evaluates true forever. Settings advertises this as shipping: "App Tips — Contextual guidance &
onboarding". Render the five tips at their natural moments and donate their events; then spread
`InfoButtonView` beyond Atlas into Chat, Documents and Settings; then add the reachable "How this
works" screen and wire up `OnboardingStateStore.resetAllOnboarding()`, which has zero call sites so
onboarding currently cannot be replayed.

The owner's standing instruction on copy for this: state the mechanism plainly, name the one
exception honestly, and do not oversell. The register that works is
`Docs/USER_CHANGELOG.md`, not marketing copy.
