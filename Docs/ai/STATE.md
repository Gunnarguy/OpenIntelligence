# Current State

Updated: 2026-08-10
Branch/worktree: main, primary checkout
Last verified commit: e7d26cf

## Objective

**v5.0 partial UI makeover, folded into the v5.0 release.** A tester told the owner the app "feels
vibecoded", so the arc is a pass over every tab, page and subpage. The owner chose to fold the
makeover into v5.0 rather than cut v5.0 first, so engine work and interface work ship together.
`PROCEED: IMPLEMENT` was granted for the whole plan on 2026-08-10 and is still in force.

## Status

14 commits on `main` since `436e150`. **Pushed through `322d6a3`; `e7d26cf` is local-only.**
`CHANGELOG.md` has a numbered `## 5.0` heading with 52 entries and an empty `[Unreleased]`, so
`ci_scripts/ci_post_clone.sh` derives `MARKETING_VERSION = 5.0` and its guard passes. Before this
session it would have refused to build, and would have stamped the already-shipped 4.9.

Ingestion of the three onboarding samples went from **1.3 minutes to 7.8 seconds** on an A18 Pro
after `.onboarding` stopped paying for two language-model enrichment calls per document.

## Completed

**Foundation.** `DSSpacing` moved to the 4pt grid the code actually uses; three of its four
commonest values previously had no token, which is why adoption sat near 5%. `DSTypography` is
Dynamic Type instead of five fixed point sizes. All 392 `RoundedRectangle` sites pass
`style: .continuous`, up from 144. The modifiers named "Liquid Glass" returned `.ultraThinMaterial`
and one opted the tab bar *out* of the system treatment; removed.

**Settings.** Root is a native `List` of ~10 `NavigationLink` rows across five sections plus
`.searchable` over a keyword index, replacing 15 flat cards on one plane. `ModelConfigurationSheet`
(614 lines, previously reachable only from its own `#Preview`) opens from Advanced in one tap. Five
switches that gated nothing became status rows; the features are real and always-on, so removing the
claim would have withdrawn something true. Database tab scopes to the selected library. Libraries &
iCloud and Private Cloud Compute rewritten.

**Model parameters.** Sampling is a real choice (Predictable / Balanced / Adaptive) rather than
inferred. `LLMService` switches on `samplingStrategy`, and `llmTopK` now carries the shortlist size
end to end, it previously wrote to no key at all while `ChatScreen` passed a hardcoded 40. Seed
support added. Established from the SDK: `GenerationOptions` exposes only `sampling`/`samplingMode`,
`temperature`, `maximumResponseTokens`, `toolCallingMode`, and the string "penalty" does not occur
anywhere in FoundationModels, so the three penalty sliders cannot affect Apple Intelligence and now
say so. They were **not** deleted; see Active Constraints.

**Device identity.** Four chip-detection implementations collapsed to one. About no longer reports
"A12 or Older" on an iPhone 17. Three Mac defects fixed: every Mac was assumed actively cooled
(MacBook Air is fanless), base M4/M5 were tiered as `.ultraAdvanced` alongside M5 Ultra, and the
sysctl fallback inferred chip class from installed RAM.

**Education layer.** Two TipKit tips render, the first this app has ever shown. A "How This Works"
screen exists and is reachable from Settings. Onboarding gained an on-device panel on the completion
card and can be replayed via `resetAllOnboarding`, which previously had zero call sites.

**Correctness.** The 5 Hz chat timer no longer leaks one connection per query.
`ContainerScopingSelfTestsView` (347 lines of working tests) is linked from the Developer hub.

## Active Constraints

- **Zero call sites is not dead code.** Twice this session that assumption would have destroyed
  something: `LocalOpenAIServerLLMService` is scaffolding for the Notion row "Bring-your-own local
  model on Mac", so the penalty sliders it consumes were kept; and `VisualizationsView.swift` holds
  33 structs of which Atlas uses `EmbeddingSpaceView`, so deleting the file for its one orphaned
  top-level struct would have broken a shipping tab. Run `oi-claim-audit` before any removal.
- **`[Unreleased]` must stay empty.** New entries go under `## 5.0` until 5.0 ships, or Xcode Cloud
  refuses to build.
- Hard-boundary files still need the user to name them in an approval.
- `testSilentAudio_FailsLoudlyInsteadOfProducingAnEmptyDocument` is **flaky in this environment**,
  not broken. Reproduced on clean `436e150` in a throwaway worktree, then passed unchanged. Every
  run log carries `com.apple.modelcatalog` "no underlying assets"; the simulator has no speech
  assets.

## Working Set

- `OpenIntelligence/Features/Settings/SettingsView.swift`, the settings index, `SettingsEntry.all`
  keyword table, and the destination switch.
- `OpenIntelligence/Features/Settings/Components/ModelConfigurationSheet.swift`, sampling section
  and the scope-labelled penalty section.
- `OpenIntelligence/Features/Onboarding/OnboardingChecklistView.swift`, both pages now wrapped in
  `ScrollView` with `minHeight`, and `logTickerView`.
- `OpenIntelligence/Features/Onboarding/WhatsNewStore.swift`, the `"5.0"` release entry, currently
  **8 items with no deep links**. See Blocker 3.
- `OpenIntelligence/Services/Infrastructure/Monitoring/DeviceCapabilityService.swift`, the single
  chip/tier/ceiling source.
- `OpenIntelligence/Features/Telemetry/Dashboard/MotherboardHUDView.swift`, `SiliconLegend` and its
  one-time drag hint.

## Verification

Every line below was run in this session and its output read.

- `bash scripts/build_simulator_smoke.sh` -> **BUILD SUCCEEDED**, on `e7d26cf`.
- `xcodebuild test` on iPhone 17 Pro / iOS 27.0 -> **202 tests, 1 skipped, 1 failure**. The failure
  is the flaky audio test above. An earlier run the same day was 202/0 failures.
- CI guard simulated against `CHANGELOG.md` -> derives `5.0`, `[Unreleased]` count 0.
- `python3 scripts/secret_scan.py` -> clean. `scripts/check_icloud_conflicts.sh` -> clean.
- Screenshots on iPhone 17 Pro / iOS 27 for: the Settings index, a pushed detail screen, the list
  bottom clearing the tab bar, both TipKit tips rendering, and the quality menu across three label
  forms.
- SDK ground truth read from
  `iPhoneOS.sdk/.../FoundationModels.swiftinterface` -> `GenerationOptions` has four properties and
  zero occurrences of "penalty".

**Not verified:** Settings `.searchable` input (the simulator's hardware keyboard does not reach the
field, so the filter is code-verified only); Neural Engine telemetry during generation and the model
pill's `.ready` state (Foundation Models do not run in the simulator); every Mac fix (no Mac
hardware was used).

## Blockers / Unknowns

**1. Two device checks close every open verification item at once.** On a physical device: open
Settings and type in the search field; and run one query with the Silicon HUD visible and watch
whether the Neural Engine bar moves while the answer streams.

**2. The retrieval eval set is saturated and cannot score a model change.** The last benchmark
measured R@5 = 1.00 at every stage but `lexical` 0.94, 0 hallucinated, abstention 100%.
`RetrievalStageMetrics.swift:45` states that recall@5 "gives no information beyond 'did a chunk from
the right file appear'. MRR@10 and nDCG are the metrics that actually discriminate between stages on
this corpus." **Read MRR@10 and nDCG before any embedder or reranker decision.** If MRR is also at
ceiling, retrieval is not the bottleneck; if MRR is mediocre while R@5 is 1.00, the right chunks are
being found and ranked badly, which is a **reranker** problem and the cheap Apache-licensed swap.

**3. The v5.0 What's New sheet is a changelog, not a splash.** `WhatsNewStore` is well built, keyed
by version, correctly silent on fresh install, re-reachable from About, but the `"5.0"` entry has
**8 items and no deep links**, and `WhatsNewView` has no tappable rows (only a Done button). Cutting
to 3-4 items and making them navigate would be the improvement.

**4. Licensing shapes the embedder decision.** The shipped stack (MiniLM-L6-v2,
`ms-marco-TinyBERT-L2-v2`) is Apache 2.0. **EmbeddingGemma is not**, it ships under the Gemma Terms
of Use, whose §3.1 requires the use restrictions to be enforceable against *your* users. Jina's v2
reranker weights are reported CC-BY-NC; **verify before relying on that.** Not legal advice.

**5. Carried from 2026-08-09, untouched.** The malformed `[Needs Verification]` block still reaches
users (`SourceOnlyAnswerService.swift:349`). The verification gate still hedges correct answers.

**6. Notion roadmap was not touched this session.** "Liquid Glass UI Refresh" (In Progress, v5.0) is
substantially delivered and its row has not been updated. Several other v5.0 rows are now affected.

## Exact Next Action

**Push `e7d26cf`, then update the Notion roadmap via the `notion-roadmap` skill**, at minimum set
"Liquid Glass UI Refresh" to reflect what shipped, and sweep the other v5.0 rows this session
touched. That is repo-required work (`.agents/rules/01-docs-and-notion-sync.md`) that was deferred
and is the only outstanding obligation from the makeover arc.

After that the makeover is done and the next v5.0 objective is the owner's call. The two candidates
already scoped are Blocker 2 (read MRR@10 and nDCG to decide whether an embedder or reranker change
is justified at all) and Blocker 3 (the What's New splash).
