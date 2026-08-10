# Current State

Updated: 2026-08-10
Branch/worktree: main, primary checkout
Last verified commit: 436e150

## Objective

**v5.0 partial UI makeover.** The user was told by a tester that the app "feels vibecoded", and the
arc is a six-phase pass over every tab, page and subpage. The user chose to **fold the makeover into
v5.0** rather than cut v5.0 first, so the 39 unreleased CHANGELOG entries and this UI work ship
together. `PROCEED: IMPLEMENT` was granted for the whole plan on 2026-08-10.

**Nothing is committed.** 43 files are modified in the working tree. Phases 0-2 are done and
verified; Phases 3-5 and the cleanup pass are not started.

## Status

The six phases, as agreed with the user:

| Phase | Scope | State |
|---|---|---|
| 0 | Design tokens, continuous corners, fake glass layer | **Done, build-verified** |
| 1 | Onboarding truncation, Silicon HUD wiring, tab-bar safe area | **Onboarding + HUD done.** Safe area open (see Blocker 2) |
| 2 | Collapse four chip-detection paths into one | **Done, simulator-verified** |
| 3 | Unify the two chat pickers | Not started |
| 4 | Restructure Settings | Not started |
| 5 | Education layer (TipKit, InfoButtonView, "How this works") | Not started |
| — | Cleanup: dead UI, decorative toggles, leaked chat timer | Not started |

## Completed

**Phase 0 — design system foundation.** `DSSpacing` moved from 2/6/10/14/20/28 to the 4pt grid
2/4/8/12/16/24/32. This is the root cause of ~5% token adoption: counted against the codebase the
seven commonest spacing literals are 8 (295 uses), 4 (264), 12 (237), 6 (186), 2 (166), 10 (125),
16 (103), so three of the top four had no token while `xl = 28` matched nothing. `DSCorners` gained
`pill` (8) and `panel` (14) additively. `DSTypography` converted from five fixed `.system(size:)`
values to Dynamic Type styles.

All 392 `RoundedRectangle(cornerRadius:)` sites now pass `style: .continuous`; it was 144/392.
Done with a paren-aware Python script (see Working Set), which reported zero multi-line cases.

`DSGlass`, `GlassToolbarModifier` and `GlassTabBarModifier` deleted: all three returned
`.ultraThinMaterial`, not Liquid Glass, and `.toolbarBackground(.ultraThinMaterial, for: .tabBar)`
opts a bar **out** of the iOS 26 system treatment. `ContentView` was calling `.glassTabBar()`; that
call is removed. `glassCard()` now uses the real `glassEffect`.

**Phase 1 — onboarding.** `welcomePage` content sat in a bare `VStack` inside a paged `TabView`,
which fixes page height; the content overflowed and SwiftUI compressed `Text`, so the headline
rendered "Your documents...." with "Clear answers." missing and all three use-case questions
truncated mid-word despite `lineLimit(2)`. Now a `ScrollView` whose content takes
`minHeight: proxy.size.height`. Verified with before/after screenshots on iPhone 17 Pro / iOS 27.

**Phase 1 — Silicon HUD.** The user explicitly wants this trustworthy and is keeping it. Two
defects fixed in `LLMService.swift`: `reportLLMToken(tokenLatencyMs:)` had zero call sites in the
whole repository, so the Neural Engine bar never moved during generation and
`totalLLMTokensGenerated`/`lastLLMTokenLatencyMs` were permanently zero; and the `catch` around the
stream matches only `LanguageModelSession.GenerationError`, so a cancellation from the Stop button
skipped both `sustain(false)` calls and left the indicator lit for the session. A `defer` now
backstops them; the explicit calls are retained deliberately because they release at end-of-stream
rather than end-of-function, and that function can run a continuation pass. The embedding path was
already correctly instrumented and was not touched.

**Phase 2 — device identity.** `RAGService.detectDeviceChip()` stops at `case "iPhone17"` (the
iPhone 16 line), so `iPhone18,x` and newer hit `default: return .older`, rawValue `"A12 or Older"`,
performanceRating `"Limited"` — rendered directly in About. `AboutView` now reads
`DeviceCapabilityService`. `determineDeviceTier` no longer ANDs live availability with that table
(it was demoting capable iPhone 17s from `.high` to `.medium`); its `chip` parameter is now unused
and is documented as such. `DeviceCapabilityService` iPad `case 16` now returns A17 Pro / `.iPadMini`
for `minor <= 2` instead of an M4 iPad Pro. `MotherboardHUDView.chipName` now delegates to the
service; it keeps its exact-identifier table for SoC *position* only.

## Active Constraints

- **Hard-boundary files still need the user to name them.** None have been touched. Phase 4 must
  not touch `QuotaPolicy.swift` or `EntitlementStore.swift` when it surfaces plan limits.
- **`.claude/rules/user-facing-copy.md` governs Phase 4.** The five decorative toggles are
  **not** false claims: the features are real and always-on (Writing Tools ships via
  `.writingToolsBehavior(.complete)` on the composer; `SpeechAnalyzerService` runs in
  `DocumentProcessor`). The switches are what is broken. Fix the control or convert it to a status
  row; do **not** delete the capability claim. Run `oi-claim-audit` before removing any.
- Build with `-derivedDataPath` outside `~/Documents`; `scripts/build_simulator_smoke.sh` handles it.
- A full build takes 8-12 minutes here, most of it before the first compile. It is not hung; check
  `pgrep -f "xcodebuild -scheme"` before concluding otherwise.

## Working Set

- `OpenIntelligence/UI/DesignSystem/Theme.swift` — the retuned tokens. Read before any styling work.
- `OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift:3430` — `QualityModeQuickPicker`,
  the start of Phase 3. `:3453-3462` is the suspected hidden-subtitle bug: a `VStack` of two `Text`s
  in a `Label`'s title slot inside a native `Menu`.
- `OpenIntelligence/UI/Components/ModelStatusIndicator.swift:11-50` — the model pill. Different
  shape, radius and colour language from the quality pill; `:108-113` records why `pickerDetail` was
  removed.
- `OpenIntelligence/Features/Settings/SettingsView.swift` — 2805 lines, 15 flat cards. Phase 4.
  `:2011-2110` holds the ten Apple Intelligence toggles, five of which bind nothing.
- `OpenIntelligence/Features/Settings/Components/ModelConfigurationSheet.swift` — 614 complete,
  unreachable lines binding temperature/maxTokens/topP/penalties. Phase 4 gives it a destination.
- `OpenIntelligence/Services/Infrastructure/Tips/AppTips.swift` — five TipKit tips with copy and
  rules, configured at launch, **zero rendering call sites**. Phase 5 wires these.
- `OpenIntelligence/UI/Components/InfoButtonView.swift` — `(title, explanation)` popover, only three
  call sites, all in Atlas. Phase 5 spreads it.
- `/private/tmp/claude-501/-Users-gunnarhostetler-Documents-GitHub-OpenIntelligence/e5871f68-e5fe-43c4-9537-c96266d07b7f/scratchpad/continuous.py`
  — the paren-aware corner script, if a similar sweep is needed. Scratchpad, not durable.

## Verification

Every line below was run in this session and its output read.

- `bash scripts/build_simulator_smoke.sh` -> **BUILD SUCCEEDED**, 0 errors. Run twice: after Phase 0
  plus onboarding, and again after Phases 1-2.
- `xcrun simctl getenv booted SIMULATOR_MODEL_IDENTIFIER` -> `iPhone18,1`, which is precisely the
  identifier that used to produce "A12 or Older".
- Simulator screenshots on iPhone 17 Pro / iOS 27, before and after: headline renders both lines,
  all three use-case questions readable, HUD reads **A19 Pro** where it previously read A18 Pro.
- `grep` count of `RoundedRectangle(cornerRadius:` -> 392 total, 392 with `.continuous`, 0 missing.
- `python3 scripts/secret_scan.py` -> `no sensitive tokens discovered`.
- `scripts/check_icloud_conflicts.sh` -> `OK: no iCloud damage found`.

**Not run this session:** `xcodebuild test`. The full suite has not been run against any of these
changes. Do this before committing — `Theme.swift` token values changed and 43 files were edited.

## Blockers / Unknowns

**1. The full test suite has not been run against this working tree.** 202 tests passed two sessions
ago against different source. Run the `xcodebuild test` invocation in `Docs/ai/RUNBOOK.md` with an
explicit iOS 27 destination before committing anything here.

**2. Whether Settings genuinely clips behind the floating tab bar is unresolved.** A screenshot
showed "PCC Quota Status" behind the bar, but on iOS 26 content is *meant* to scroll under a
floating tab bar. Verify by scrolling `SettingsView` to the very bottom in the simulator and
checking whether the last card (`aboutCard`) fully clears the bar. If it does, there is no bug and
task 5 should be closed rather than "fixed".

**3. The HUD's generation half is build-verified only.** The simulator cannot run Foundation Models,
so the `reportLLMToken` wiring was never observed moving the bar. Needs a physical device.

**4. `mode.description` may never reach users.** `ChatScreen.swift:3456` puts a two-`Text` `VStack`
in a `Label` title slot inside a native `Menu`. A web fetch of Apple's `Menu` docs returned no
usable content, so this is unconfirmed. Verify by opening the quality picker in the simulator and
looking for the second line before rewriting it.

**5. Blockers carried from 2026-08-09, untouched.** The malformed `[Needs Verification]` block
(`SourceOnlyAnswerService.swift:349`) still reaches users. The verification gate still hedges
correct answers. Neither was in scope for this arc.

## Exact Next Action

**Start Phase 3: unify the two chat pickers.** Open
`OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift:3430` (`QualityModeQuickPicker`) and
`OpenIntelligence/UI/Components/ModelStatusIndicator.swift:11`. The user chose "two matching glass
pills, fix the hidden subtitles". Concretely: give both controls one capsule shape via
`glassEffectHelper`, give the model pill a `chevron.down` so it reads as tappable, add a text status
beside its coloured dot so state is not colour-only, and visually disable the Maximum row when
`entitlementStore.canUseMaximumModeNow` is false instead of letting a tap open the paywall
(`ChatScreen.swift:3525`). Before changing the menu labels, resolve Blocker 4 by looking at the open
menu in the simulator.

Docs owed for work already done: `WHATS_NEW.md` and `Docs/USER_CHANGELOG.md` have **not** been
updated. `CHANGELOG.md` has three `[UI]` entries under `[Unreleased]`. The user-facing pair was
deliberately deferred to the end of the arc rather than written in fragments; it is owed before any
commit.
