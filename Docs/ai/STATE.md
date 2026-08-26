# Current State

Updated: 2026-08-26
Branch/worktree: `main` (single checkout, `~/Documents/GitHub/OpenIntelligence`)
Last verified commit: f0ed8c0

## Objective

Ship v5.0. Builds 385 (iOS and macOS) are uploaded to App Store Connect and `VALID`, but
they **predate** commit `f0ed8c0`, which fixes the Documents tab stall the owner reported on
device. The release is not submitted. The remaining decision is whether to cut a build 386
carrying `f0ed8c0` or submit 385 without it.

**Notion is authoritative for the roadmap row list** — use the `notion-roadmap` skill rather
than re-deriving it here.

## Status

The Documents tab performance complaint is diagnosed, fixed, verified by the suite, committed
and pushed. It is **not yet verified on device**, which is what would close it.

## Completed this session

- **Documents tab stall found and fixed.** The appear path awaited
  `DocumentationCacheService.shared.statistics().count` before anything else. That count has a
  single consumer — a `cachedDocumentCount > 0` gate on an optional "Cached Documents" row at
  `DocumentLibraryView.swift:508` — and the device reports the count as **0**, so the row never
  renders. The service is an `actor` whose initialiser does synchronous disk I/O. It now runs in
  a child task nothing awaits.
- **`NavigationTiming` added** (`OpenIntelligence/Core/Support/NavigationTiming.swift`). This is
  what made the diagnosis possible. Five earlier attempts each instrumented work occurring
  *after* the view appeared, correctly measured it as fast, and moved on.
- **Library switching instrumented.** `ContainerPicker` marks the tap; `DocumentLibraryView`
  reports `state` and `settled`. There was previously **no measurement of this path at all**.
- **iOS 27 safety refusals classified.** `ContentTaggingService` caught
  `GenerationError.guardrailViolation`, but iOS 27 raises `LanguageModelError.guardrailViolation`,
  so refusals fell through and logged as `Unexpected error`. Same defect already fixed for context
  overflow in the same `catch`. Routed through `FoundationModelErrorMapper`.
- **A user-facing overclaim narrowed, not withdrawn.** `USER_CHANGELOG.md` and `WHATS_NEW.md`
  claimed reference-list exclusion fixed the mangled `pychatry` tag. Exclusion works and is
  confirmed (137 reference passages excluded on that paper), but the token is still present and
  originates elsewhere. Both docs now say so.

## Active constraints

- **The active release is scope-frozen.** New findings default to `Future Backlog` unless they
  lose data, break an advertised capability, or block shipping.
- Hard-boundary files untouched this session. `project.pbxproj` still reads
  `CURRENT_PROJECT_VERSION = 150`; the release workflow stamps the real build number.
- Do not edit `Docs/USER_CHANGELOG.md` during a test run — `VersionHistoryTests` reads it as a
  build input, and `OpenIntelligence/Resources/VersionHistory.md` must be an exact copy.
  It failed exactly this way today; `cp Docs/USER_CHANGELOG.md OpenIntelligence/Resources/VersionHistory.md`
  is the fix.

## Working set

| File | Why |
|---|---|
| `OpenIntelligence/Features/Documents/Library/DocumentLibraryView.swift` | The fix, and both instrumentation sites. |
| `OpenIntelligence/Core/Support/NavigationTiming.swift` | New. Times from the tap, not from view appearance. |
| `OpenIntelligence/Features/Documents/Components/ContainerPicker.swift` | Marks the library-switch tap. |
| `OpenIntelligence/Services/Document/Chunking/ContentTaggingService.swift` | Guardrail classification. |
| `SlowDocumentTab.txt` (repo root, gitignored) | The device capture the diagnosis rests on. |
| `.github/workflows/app-store-upload.yml` | The only working route to App Store Connect. |

## Verification

- `xcodebuild test` (iOS 27 sim `8FA2B3CE-5EB0-4339-8629-F40684EDCE2D`, DerivedData
  `/private/tmp/oi-t9-dd`) -> **348 tests, 3 skipped, 0 failures**, `** TEST SUCCEEDED **`,
  0 compile errors. Log `/private/tmp/oi-t12-full.log`.
- `python3 scripts/secret_scan.py` -> no sensitive tokens.
- `scripts/check_icloud_conflicts.sh` -> no iCloud damage; `.git` pointer intact.
- PCC gating -> 3 real uses, all inside `#if compiler(>=6.4)` and entitlement-checked. The 2
  further matches in `PCCRouteEvaluator.swift` are inside `//` comments.
- **Not run:** `scripts/build_simulator_smoke.sh`. `xcodebuild test` compiled the same sources.
- **Not verified on device:** the Documents tab fix itself.

## Blockers / Unknowns

1. **The library-switch cost is still unmeasured.** The owner's original words were "SUPER slow
   when i tap around the documents tab going library to library". The fix shipped addresses *tab
   appear*, which is what the capture actually showed. `.task` fires on tab entry only, so a
   library switch may never have been in the measured path. The new `[LibrarySwitch]` line answers
   this on the next capture; do not claim the complaint is resolved until it reads back.
2. **Build 386 not cut.** 385 is uploaded and `VALID` but predates `f0ed8c0`.
3. **Rotated page furniture becomes a section heading.** `[LayoutAwareExtractor] Block 1:
   X=0.08-0.25, text='IN Pychatry an'` — a narrow left-edge strip, OCR'd from the journal's
   sideways spine text, promoted to a heading and inherited by every chunk beneath it
   (`SemanticChunker.swift:1481`), then harvested as a tag. Body text extracts "Psychiatry"
   correctly 178 times, so this is marginal-block handling, not extraction quality. **Future
   Backlog** under the freeze rule.

## Exact Next Action

Ask the owner which they want, then do it:

**(a)** Run the release workflow for build 386 on both platforms so the Documents tab fix ships:

```bash
gh workflow run app-store-upload.yml -f platform=ios -f build_number=386
```

then the same with `-f platform=macos`, **sequentially, not in parallel** —
`scripts/asc_certificates.rb revoke-new` refuses when two runs each see the other's certificate,
and the account hit its certificate cap at build 384 for exactly this reason.

**(b)** Submit 385 as-is and carry `f0ed8c0` to 5.0.1.

Independently of that choice, the highest-value next diagnostic is a fresh device capture of the
Documents tab that contains `[LibrarySwitch]` lines, which decides blocker 1.
