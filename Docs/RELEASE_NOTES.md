> **Documentation status:** Source-verified and simulator-compiled for OpenIntelligence v5.0, most
> recently on August 17, 2026. The latest suite run is **236 tests, 0 failures** on iOS 27.0 (iPhone
> 17 Pro simulator). It read 202 until 2026-08-11, then 230 after the vocabulary and correctness
> passes added 28 cases, and 236 since.
> **The agentic path has no test coverage at all**, so the Deep Think evidence-budget work of
> 2026-08-17 is build-verified and suite-verified only, and its behavioural claim is unverified
> until the same query is re-run on a physical device.
> **No test covers the library management screens**, so the interface work of 2026-08-11 is
> build-verified and simulator-screenshot-verified only. Two earlier runs the same day reported one failure,
> `testSilentAudio_FailsLoudlyInsteadOfProducingAnEmptyDocument`, timing out at 60s waiting on
> `processDocument(silence.wav)`. That test is **flaky in this environment, not broken**: it was
> reproduced on clean `436e150` in a separate worktree with none of the v5.0 changes present, it
> then passed unchanged, and every run log carries `com.apple.modelcatalog` "no underlying assets"
> errors, the simulator has no speech assets, so the transcription path's timing is not
> deterministic here. Audio transcription remains **unverified on real speech**, as it was at v4.9. Native PCC execution is owner-confirmed on a
> physical iOS 27 device; PCC edge scenarios (quota exhaustion, network transition, background
> consent) and Archive/TestFlight distribution validation remain pending. The v5.0 interface work is
> simulator-verified by screenshot; the `.ready` state of the model pill and the Neural Engine
> telemetry during generation are **build-verified only**, because Foundation Models do not run in
> the simulator.


# OpenIntelligence Release Notes

This document provides a comprehensive, version-by-version breakdown of major architectural and feature updates to the OpenIntelligence Apple Intelligence-native evidence system.

---

## v5.0 - August 10, 2026

161 entries, 49 `[UI]`, 36 `[Orchestration]`, 31 `[General]`, 23 `[Retrieval]`, 17 `[Ingestion]`, 2 `[Infrastructure]`, 2 `[Indexing]`, 1 `[Chunking]`. Recounted from `CHANGELOG.md` on 2026-08-18. This figure has gone stale four times: it read
46 before the interface pass, 74 before the correctness pass that followed, and 87 on 2026-08-11,
because it is a typed number describing a countable fact. Recount it rather than trusting it, with:

```bash
awk '/^## 5\.0/{f=1;next} /^## 4\./{f=0} f' CHANGELOG.md | grep -c '^- \*\*\['
```

A fourth theme arrived on 2026-08-17 and is the sharpest instance of the first: **two stages that
were each defensible alone, composing into a defect neither had by itself.** Retrieval ends with a
Lost-in-the-Middle reorder that places the highest-scoring chunk at the array midpoint; Deep Think's
synthesis then truncated what it received with a fixed `prefix(3000)`. Neither is unreasonable in
isolation. Together they guaranteed the best evidence was the first thing discarded on any large
retrieval, which is exactly inverted from what truncation is for. The visible symptom was a mode
inversion: Deep Think reported that the documents contained no evidence, in 202.7 seconds, on a
question Standard answered correctly in 6.7. Synthesis now packs in score order against a budget
derived from the real prompt, and every assembly logs what it dropped.

**That fix is not verified where it matters.** The agentic path has no test coverage, so a green
build and a green suite say only that it compiles and broke nothing else. Whether Deep Think stops
asserting absence can be answered only on hardware, and had not been at the time of writing. It is
recorded here because the mechanism is code-verified and the measurement it invalidates is
load-bearing for other work, not because the outcome is known.

Three themes run through nearly all of them. The first is **loss that was invisible from the
outside**: ingestion reported success on documents whose tables, figures and layout had already been
discarded, and the evaluation harness structurally could not catch it because it scored answers
rather than extraction. The second is **claims the app was making about itself that were not true**,
withdrawn here with the mechanism described in place of the figure. The third arrived last and is the
inverse of the second: **claims that were true and checkable, and still cost trust because nobody
outside the project could read them.** A completion card reading `38 TOPS` and `768 search` is
verifiable in a way a privacy banner is not, which is exactly why it is there, and is also a wall to
a reader who has met neither term. That is a vocabulary problem rather than a claims problem, and it
is fixed by explaining rather than by deleting.

### Ingestion

*   **Format coverage, asserted on extraction rather than on answers.** The automated corpus was 25
    markdown files against 20 advertised formats, so PDF parsing, OCR, Office extraction, iWork and
    A/V had none. `IngestionFormatCoverageTests` drives real files through `processDocument` across
    8 formats. Fixtures are synthesised in Swift at test time, so no binary enters this
    iCloud-synced repository and hard-boundary `project.pbxproj` is untouched. This is what found
    the six defects below. `[evidence_level: test_verified, confidence: exact]`
*   **Every table in every Word document was parsed into rows and then dropped.** A `<w:tbl>` is a
    sibling of `<w:p>`, never nested inside one, so the marker left in its place sat outside every
    paragraph match and the re-insertion pass found nothing to replace.
*   **Every ingested image became one unbroken line of text.** Both joins now preserve line breaks.
*   **Photographing a document produced flat text where importing the same page produced table cells.**
*   **A page the parser knew it had read badly was repaired, and the repair was then thrown away.**
*   **A PDF with figures but no tables lost every figure chunk** after paying to produce them.
*   **Vision's document understanding ran on imported PDFs only,** never on imported images or
    camera captures.
*   **A fully scanned PDF reported that it had used OCR on zero pages.** `usedOCR` was hardcoded
    `false` on the primary structured path, so the documents where recognition did all the work were
    exactly the ones that under-reported it.
*   **iWork extraction is recorded as non-functional rather than fixed.** It cannot reach content in
    any file current iWork produces; it fails loudly and two tests pin both shapes. `.pages`,
    `.numbers` and `.keynote` are unsupported-but-honest.
    `[evidence_level: code_verified+test_verified, confidence: exact]`

### Retrieval and its measurement

*   **The shipped evaluation harness had never measured retrieval.** Every committed eval case
    carries `groundTruthChunkIds: null`, so `retrievalRecallAt5` reported exactly `0.0` on every run
    and the `>= 0.85` quality gate could never pass. Per-stage recall@k, MRR, nDCG and precision now
    exist, are wired into the harness, and judge relevance by source document rather than chunk UUID.
*   **The retrieval measurement itself was wrong in seven ways before it measured anything.**
*   **`Docs/RETRIEVAL_PIPELINE.md` claimed a recall gate that had never once been met, and a harness
    that does not exist.**
*   **BM25 column weights were shifted one slot left,** dropping `section_path` out of ranking
    entirely and reducing the documented 10x heading boost to 5x. Reproduced in `sqlite3` against a
    copy of the real schema before anything was changed.
    `[evidence_level: code_verified+reproduced, confidence: exact]`
*   **Sentence extraction that matched nothing discarded the evidence retrieval had just found.**
*   **The chunker stopped calling itself "Late Chunking",** which is a different published technique
    it does not implement. The sentence describing the actual mechanism was already accurate and is
    unchanged.

### Orchestration

*   **Oversized prompts stayed on-device precisely when they could have escalated to Private Cloud
    Compute.** The token estimate selected its chars-per-token ratio from the assumed destination,
    so allowing PCC produced a count ~44% below the on-device figure and then compared it against an
    on-device limit. `[evidence_level: code_verified, confidence: exact_for_the_defect, unverified_on_device]`
*   **The planless routing branch now logs the decision it makes,** so the change above can be
    confirmed on a device rather than inferred.
*   **Deep Think's unreachable stop threshold confirmed fixed and correctly wired.**

### Claims the app withdrew or corrected

This is the group most worth reading. Each is a statement the app made to users that the code did
not support.

*   **Settings named eight agentic tools, and all eight were the unregistered ones.** A tool declared
    in the registry file but not returned by `createTools` does not run. Corrected to the four that
    are actually registered.
*   **The app no longer advertises two features it does not have.**
*   **The model picker stops naming a model tier the app cannot select.**
*   **Unmeasured performance figures no longer ship,** including inside the sample corpus the app
    ingests and cites back to users as sourced fact.
*   **Two unmeasured multipliers removed from the public-facing history** (`1000x` dedup, `240x`
    scrolling). Both underlying changes are real and are now described by mechanism. Historical
    entries were corrected in place with a dated note rather than deleted.
*   **Every remaining claim in the Settings mode-capability list was audited** against call sites.
*   **"TinyBERT" was restored, having been removed on a false premise.** A Core ML `.mlpackage`
    manifest is a packaging descriptor and never carries the source architecture, so its silence
    proved nothing; `THIRD_PARTY_NOTICES.md` bound the model by exact path the whole time. Absence
    of evidence in one artifact is not evidence of absence.
*   **The QA suite stopped grading the engine on repeating an unverified claim.**

### Interface, and the design-system foundation

*   **The About screen told an iPhone 17 Pro it was running "A12 or Older" with "Limited"
    performance.** `RAGService.detectDeviceChip()` stops at the iPhone 16 line, so every newer
    identifier fell to `default: return .older`. That value was rendered directly, and ANDed into
    the device tier, demoting capable hardware. Four independent chip-detection implementations
    collapsed to one; the M5 iPad Pro and iPad mini 7 were also mislabelled.
    `[evidence_level: code_verified+simulator_verified, confidence: exact]`
*   **The first screen a new user sees dropped half its headline and truncated all three of its
    examples mid-word.** The welcome page overflowed its paged `TabView`, and SwiftUI resolves
    overflow by compressing `Text`.
*   **The quality-mode menu showed three bare words,** no selection state, and hid its billing limit
    until you tapped it. Note the mode descriptions still cannot be rendered in a native menu on this
    OS, three label forms were tried and photographed, and the source records all three.
*   **The two chat header controls were built to two different designs** and, on a device where
    Apple Intelligence is available, two different heights.
*   **Stopping a generation left the HUD's Neural Engine indicator lit for the rest of the session,**
    and token generation never moved it at all, `reportLLMToken` had no call sites anywhere.
*   **Settings was fifteen cards on one plane, all at the same volume.** 2805 lines, six corner
    radii, your billing plan level with the GPU execution profile. The root is now a native `List`
    of about ten `NavigationLink` rows across five sections, each pushing to a detail screen that
    renders the same cards untouched, plus `.searchable` over a keyword index so a knob is findable
    by the name it has in the code rather than by the screen it sits on. The diagnosis that matters:
    this was a **depth** problem, not a styling one, fifteen `Form` sections would have changed
    nothing.
*   **Five switches in the Apple Intelligence card controlled nothing,** and three of them were
    counted toward an "active capability" badge. The features are real and always on, so these are
    status rows now rather than deletions, removing the claim would have withdrawn something true,
    removing the control removes something false.
*   **614 finished lines of generation controls had no way in.** `ModelConfigurationSheet` binds
    temperature, maxTokens, topP and the three penalties, and its only reference was its own
    `#Preview`, while the card promising "Customize how the AI responds" held one text field. It is
    now reachable from Settings -> Advanced.
*   **Sampling was inferred rather than chosen, so Top-P was unreachable and greedy decoding was
    impossible.** `LLMService` picked `.random(top:)` whenever `topK` fell in `(0,100)`, and every
    chat query passes a hardcoded `topK: 40`, so the Top-P slider was read, persisted, threaded
    through `InferenceConfig` and then discarded. `InferenceConfig` now carries an explicit
    `SamplingStrategy`; the default is `.topK`, so upgrading changes nothing until the user chooses
    otherwise. Two capabilities become reachable: greedy decoding, and `seed`, both random modes
    accept one, the app never sent it, and without it the same question could not reproduce the same
    answer. Verified against the SDK interface, not assumed.
    `[evidence_level: code_verified+build_verified+sdk_verified, confidence: exact, unverified_on_device]`
*   **Design-system foundation.** `DSSpacing` moved to the 4pt grid the code actually uses; three of
    its four commonest values previously had no token, which is why adoption had stalled near 5%.
    All 392 `RoundedRectangle` sites now pass `style: .continuous`, up from 144. The modifiers named
    "Liquid Glass" returned `.ultraThinMaterial`, and one of them opted the tab bar *out* of the
    system treatment; they are removed.
    `[evidence_level: code_verified+build_verified+simulator_verified, confidence: exact]`

### Vocabulary, in both registers

The onboarding completion card is the app's best argument and was its most alienating screen. It shows
`38 TOPS`, `32/batch`, `768 search`, `16-core ANE`, `Chunks` and `Vectors` about ninety seconds after
install, and every one of those is read live from `DeviceCapabilityService` rather than printed, which
is the point: "this ran on your A19 Pro at 32 passages per batch" can be checked, and "your data stays
private" cannot. A reader who has met none of the words concludes the app is not for them.

`Glossary.swift` defines **24 terms twice**. The `plain` register uses no code identifier, model name or
framework name. The `technical` register names `MiniLM-L6-v2`, `vDSP_mmul`, `ms-marco-TinyBERT-L2-v2`
and Apple TN3193 freely. Definitions are returned from one exhaustive `switch` over `GlossaryTermID`
rather than looked up in a string-keyed dictionary, so a call site cannot name a term that does not
exist, lookup returns no optional, and adding a term is a compile error until both registers are
written. The predecessor is instructive: `InfoButtonView` took `(title, explanation)` as free strings
typed at each of its three call sites, which is the mechanism by which one word acquires two
definitions.

The technical register sits behind a disclosure bound to a single `AppStorage` key, so opening it once
opens it everywhere. That is what lets both registers occupy one screen without either becoming noise:
a technical reader configures the entire app with one tap, and a non-technical reader is never shown
jargon.

Placement is the substance of the change. Definitions attach where the word already is, because a
definition in Settings is a definition nobody reads at the moment they need it. The four pipeline
capsules explain themselves while the stage they name is the one running. The Words, Chunks, Vectors
and Time counters each carry their own. All six device chips are tappable. `Settings > Device &
Performance` annotates the Hardware Envelope, which is the densest jargon in the app.
`Settings > Plain English` is the index for looking a word up by name, not the way in.

Two definitions are pinned by tests because their hedges are load-bearing. **TOPS must keep saying it
is a per-chip lookup rather than a measurement**: `npuTops` reads a table keyed by device identifier,
several entries are explicitly projections for unreleased silicon, and Apple exposes no live Neural
Engine occupancy API, so an implied measurement would be the same class of claim as the `65 tok/s`
figure this release withdrew. **Neural Engine must keep saying Core ML makes the final scheduling
decision**, the hedge `HowItWorksView` already carries, because the glossary must not be the more
confident of the two documents.

### The library surfaces, and what verifying the vocabulary work turned up

The vocabulary pass above was meant to be the end of the interface work. Checking its claims against
code instead opened a second arc, because the screens that manage libraries were making the same
kind of statement and, in two cases, destroying data while making it.

**Two controls deleted data and told users they had not.** "Remove Local Copies" was never local:
`clearAllDocuments` writes a tombstone that the sync service unions into both workspace roots and
then uses to filter the shared inventory, so the next pass removes those documents from iCloud and
from every other device. The alert promised "Sync Now can bring them back". The per-document card
carried the same promise, and its "Remove Local Copy" button also always deleted everywhere. That
action is, incidentally, the wipe the app had been missing, so it is named **Wipe Library** now and
states the real outcome. Separately, flipping a library to Local Only deletes its iCloud copy, and
the most reachable path to that was a segmented control in the header with no confirmation at all.

**Deleting a library existed twice and the copies had diverged.** Given an iCloud library whose
shared copy fails to delete, one path aborted and reported while the other logged the error and
deleted locally anyway, leaving the shared copy to restore the library on the next sync. One
implementation now, and it aborts.

**Library Settings described a pipeline that does not exist.** Its chunking sliders offered more
than twice the range ingestion honours, its "elastic" strategy claimed embedding similarity between
sentences that never runs, and its storage description named a format the vector store had stopped
using. Saving a model change also deleted the library's vectors *before* asking whether to rebuild
them, so answering "Later" left documents that could not be searched.

**A fix in this release had already drifted by the end of the day.** The glossary shipped saying
chunks are split where cosine similarity between sentences drops. That pass is implemented and never
runs, because the chunker is never given an embedding service. Corrected in the same release, by the
audit the glossary exists to make possible.

The through-line is the same one the vocabulary work started: **a value written into copy drifts, a
value read from code cannot.** Five separate defects here were a typed number sitting next to the
real one. The projection tooltip, the device chips, the wipe count and both chunking sliders now
read theirs.

### Repository, agents and documentation

Not user-facing, recorded because they change how the project is maintained.

*   **Claude Code sessions could not see this repository's agent directives at all,** and now have a
    control plane, routed rules and a cross-session handoff.
*   **The task router read a roadmap section number as the app's version** and told every agent to
    write releases against it.
*   **The mandated Notion roadmap workflow named tools that do not exist,** and Claude Code could not
    have read it anyway.
*   **The benchmark graded the verifier's explanation instead of the model's answer, for the second
    time.** Re-scoring saved runs with the fixed grader moves 2026-08-09 from 17/20 to 18/20 and
    reproduces an independently recorded 14/20 -> 17/20 regrade of the baseline exactly, which is
    what shows the change corrects rather than inflates. **The app-side defect is untouched and users
    still see the malformed banner.**
*   **All 144 Notion roadmap rows swept against the code.**
*   **Wrote down how the pipeline's "29 steps" are counted,** and retracted the finding that said the
    figure was wrong.
*   **Reconciled the documentation set and the roadmap against the shipped 4.9 tree.**
*   **Scoped this repository's MCP surface** to what it actually uses.
*   **Deleted three Core AI files that were scaffolding, not integration.**
*   Pipeline and evaluation docs carry explicit "verified at vX, not re-verified since" headers
    rather than being restamped as current.

## v4.8 (iOS) - in progress

*   **Pipeline Signposts (Phase A of the benchmark plan):** `PipelineSignposts` puts `OSSignposter` interval boundaries at twelve load-bearing seams, document processing, hybrid search, context assembly, execution planning, generation, verification gates, and every agentic synthesis strategy, under subsystem `Gunndamental.OpenIntelligence.Pipeline`. Near-zero cost unattached; ships in release so `xcrun xctrace` can attribute per-stage wall-clock on physical hardware. `[evidence_level: build_verified+test_verified, confidence: exact_for_simulator, evidence_source: PipelineSignposts.swift]`
*   **Receipt Fidelity (F-06/F-07 resolved):** partial streams record a `.partial` attempt that attests the completed route while staying distinguishable from clean completion; `RouteEvalMetrics` counts partial completions. F-07 closed without code change, construction-time fallbacks never attempted the intended route, so their one-element chains were already truthful. `[evidence_level: code_verified+test_verified, confidence: high, evidence_source: ModelExecutionReceipt.swift, RouteEvalMetricsTests.swift]`

## v4.7 (iOS) / v3.0 (macOS) - July 2026

**Live on the App Store since 2026-07-28 (build 199).** Deliberately small: the 4.6 binary (build 192) had already shipped the PCC dynamic-routing work, so 4.7 is the honesty-and-verification pass on top of it, every remaining claim brought in line with what the code and SDK actually do, plus the first runnable evaluation corpus.

*   **Private Cloud Compute Confirmed on Device:** native PCC execution is owner-confirmed on a physical iOS 27 device, PCC actually runs rather than silently falling back on-device. Quota exhaustion, mid-stream network-transition fallback, background/App Intent consent behavior, and Archive/TestFlight distribution signatures were not part of that confirmation and remain unverified. `[evidence_level: user_confirmed, confidence: high_for_execution_path_unverified_for_edge_scenarios, evidence_source: owner device testing 2026-07-28]`
*   **Honest Model Labels Everywhere:** removed the last user-facing 3B/20B parameter-count claims, finishing work that had already corrected execution and telemetry but left the presentation layer behind. The Settings capability card, `ModelInfoCard`, the per-answer metrics bar, and the container settings sheet no longer assert a parameter count. Re-verified against the current SDK first: `SystemLanguageModel` has no member `advanced`, the public surface offers only `UseCase{.general, .contentTagging}` (a task selector, not a size selector), `.onDeviceAdvanced` executes `SystemLanguageModel.default` on every device, and the `physicalMemory >= 11.5GB` gate has no call sites, so device RAM does not select a larger model. `[evidence_level: sdk_verified+code_verified+build_verified, confidence: exact, evidence_source: swiftc probe on iPhoneSimulator27.0.sdk, LLMModelType.swift, FoundationModelSessionFactory.swift]`
*   **Deterministic Entity Extraction:** chunk entity extraction no longer varies with Natural Language's process state. The capitalized-entity supplement was gated so it only ran when every tagging pass failed, which let the same chunk yield different entities between runs and propagate into the entity index and 2-hop graph expansion. The supplement now runs unconditionally, bounded by the existing 15-entity cap. `[evidence_level: code_verified+test_verified, confidence: high, evidence_source: SemanticChunker.swift, three consecutive 142/142 suite runs]`
*   **Route Evidence Gates:** Added `RouteEvalMetrics`, which scores execution receipts rather than answers. Six invariants are enforced: a receipt may only claim a route that actually succeeded, intent/outcome divergence must carry a fallback reason and only then, non-authorizing quota states (including `unknown`) must block cloud attempts, and every non-abstaining receipt must record the attempt chain containing the route it attempted. Reports per-route completion latency, PCC→on-device fallback counts, and a markdown evidence summary. An empty run fails the gates: absence of receipts is not evidence of correctness. Scoring is receipt-only, so the same gates apply to simulator, physical-device, and TestFlight data, this makes device evidence checkable, it does not replace it. `[evidence_level: code_verified+test_verified, confidence: high, evidence_source: RouteEvalMetrics.swift, RouteEvalMetricsTests.swift]`
*   **First Runnable Eval Corpus + Self-Checking CI:** `Benchmarks/rag_eval_v1.jsonl`, 20 ground-truthed cases generated from the committed synthetic fixture manifest by `scripts/build_eval_dataset.py` (with a `--check` staleness guard), gives the documented quality gates their first runnable dataset. `ci_scripts/ci_post_clone.sh` now refuses to stamp an already-released version (the failure mode that blocked the first 4.7 build) and runs an SDK canary that alerts the moment Apple exposes developer selection of AFM 3 Core Advanced. `[evidence_level: code_verified+test_verified, confidence: exact, evidence_source: rag_eval_v1.jsonl, build_eval_dataset.py, ci_post_clone.sh, probe_afm_advanced_canary.sh]`
*   **Build Infrastructure:** the git object store is shielded from iCloud sync (`.git` is now a `gitdir: .git.nosync` pointer) after iCloud produced four conflict copies of the git index and a duplicate branch ref. `scripts/check_icloud_conflicts.sh` detects and repairs iCloud damage, and the simulator smoke build runs it automatically. Developer-facing only; no app runtime change. `[evidence_level: build_verified+code_verified, confidence: exact]`

---

## v4.6 - July 2026

*   **Ingestion Queue Stop Means Stop:** Closing an active ingestion queue now records a deletion-wins marker that participates in iCloud Drive reconciliation, preventing the same discarded queue item from returning after reload or from another device's stale snapshot. Automatic empty-index repair is serialized, can be persistently suppressed for that library on the current device from the queue, and yields only at a safe document boundary; a later explicit import or manual rebuild re-enables local repair. `[evidence_level: code_verified, confidence: high_pending_runtime_validation, evidence_source: RAGService.swift, WorkspaceSyncService.swift, IngestionQueueOverlay.swift]`
*   **PCC Dynamic Routing Phases 0–8:** Added a deterministic post-retrieval `ModelExecutionPlan` and durable `ModelExecutionReceipt`. Retrieval/planning and verification remain local; evidence-sufficient long-context or multi-document synthesis may use native PCC after live capability/quota checks and consent for the exact minimized envelope. Receipts separate intended, attempted, actual, fallback, and completed targets. `[evidence_level: code_verified, confidence: high, evidence_source: ModelExecutionPlan.swift, ModelExecutionPlanner.swift, RAGService.swift, LLMService.swift]`
*   **A Model Picker That Means What It Says:** `Hybrid`, `On-Device`, and `PCC` are now persistent user policies. The picker no longer changes itself to PCC after a Hybrid-routed answer. Each answer shows the route that actually completed it: green for on-device, blue for PCC, or amber when a requested PCC answer finished through the on-device fallback. `[evidence_level: build_verified+code_verified, confidence: high_pending_ui_runtime_validation, evidence_source: ModelStatusIndicator.swift, MessageBubbleV2.swift, ChatScreen.swift and generic iOS 27 simulator build 2026-07-16]`
*   **Scene-Correct Silicon HUD:** The floating iOS HUD now derives its bounds exclusively from its owning `UIWindowScene`, removing the deprecated global-screen fallback and keeping restored positions tied to the correct display. `[evidence_level: build_verified+code_verified, confidence: exact_for_build, evidence_source: MotherboardHUDView.swift and generic iOS 27 simulator build 2026-07-16]`
*   **Privacy-Safe Consent and Fallbacks:** PCC consent now occurs only after the cloud payload is final. The sheet shows context size, bytes, and route reason; background and App Intent work never waits for foreground UI. Hybrid and explicit PCC requests fall back locally before meaningful streaming when consent, network, entitlement, availability, or quota prevents PCC; quota is not retried on PCC, and partial cloud/local streams are never combined. `[evidence_level: code_verified, confidence: high_pending_physical_device_validation, evidence_source: CloudConsentPromptView.swift, ModelExecutionPlanner.swift, RAGService.swift, AgenticOrchestrator.swift]`
*   **Remembered PCC Means Remembered:** `Always Allow` and `Never Allow` now survive relaunches even if the older PCC picker contains stale state. Choosing Ask clears the remembered decision, and OpenIntelligence no longer opens a generic PCC consent sheet at startup; the sheet appears only when a real finalized evidence package needs permission. `[evidence_level: code_verified+test_verified, confidence: high_pending_physical_device_validation, evidence_source: SettingsStore.swift, RAGService.swift, PCCConsentPreferenceMigrationTests.swift]`
*   **Honest GPU Execution Profiles:** The old percentage slider is now four discrete profiles, Efficiency, Balanced, Performance, and Maximum. PDF rendering, Core ML preferences, large Metal vector/MMR work, and background GPU eligibility consult the same persisted profile, while Settings clearly states that Apple frameworks retain final hardware scheduling control. `[evidence_level: code_verified+test_verified, confidence: high_pending_device_thermal_validation, evidence_source: DeviceCapabilityService.swift, SettingsView.swift, RAGEngine.swift, BNNSVectorDatabase.swift]`
*   **Managed Entitlement Enabled:** Apple approval was confirmed on July 15 and the source entitlement now includes `com.apple.developer.private-cloud-compute`. Native macOS can inspect the signed process through Security.framework; iOS/Catalyst development and ad-hoc builds inspect the signed provisioning profile; profile-less App Store/TestFlight builds use Apple's PCC availability and quota APIs before session construction. This is generic-iPhoneOS compile-verified, not yet signed-installation/TestFlight runtime-verified. `[evidence_level: build_verified+user_confirmed, confidence: high_for_source_unverified_for_distribution, evidence_source: OpenIntelligence.entitlements, EngineSDKCompatibility.swift, FoundationModelCapabilityProvider.swift, FoundationModelSessionFactory.swift]`
*   **Physical-iPhone Entitlement-Check Compatibility:** Removed iOS calls to Security symbols that are exported by the binary but not declared by the iPhoneOS SDK. The platform-specific checker now compiles for generic arm64 iPhoneOS and retains development/ad-hoc entitlement verification without relying on unavailable Swift symbols. `[evidence_level: build_verified+sdk_verified, confidence: exact_for_compilation, evidence_source: EngineSDKCompatibility.swift and generic/platform=iOS build 2026-07-15]`
*   **Swift 6 PCC Quota Compatibility:** Future quota-status cases added by Apple are handled through `@unknown default` and map to the fail-closed `.unknown` state, keeping v4.6 source compatible with non-frozen SDK enums. `[evidence_level: code_verified, confidence: exact, evidence_source: FoundationModelCapabilityProvider.swift]`
*   **Public Model Truth:** Active UI and telemetry no longer advertise separate 3B/20B/Advanced models. On-device execution uses the public `SystemLanguageModel.default`; PCC uses the public `PrivateCloudComputeLanguageModel` only on iOS/macOS 27+. Legacy preferences migrate without breaking saved settings. `[evidence_level: code_verified, confidence: high, evidence_source: LLMModel.swift, SettingsStore.swift, ModelResolutionService.swift]`
*   **RepoOS Workspace-Native Codex Routing:** Added a repository-local skill and deterministic task preflight that map every Codex request to the owning subsystem, required evidence, permitted and forbidden paths, tests, documentation updates, and Notion-roadmap relevance. Each preflight derives the active release from current repository documentation and names the exact `[Unreleased]` changelog, active-version release-notes, and Notion release targets for durable implementations. This developer-governance layer does not change Apple app runtime behavior. `[evidence: code_verified, exact, .codex/skills/route-openintelligence-work/scripts/repoos_router.py]`
*   **Zero-Regression PR Audit & Consolidation:** Completed a full evidence-gated audit of all 68 repository pull requests (43 open). Valuable changes were reimplemented cleanly on a consolidation branch (no bot branch was merged directly); duplicates, contaminated branches, and false-premise PRs were documented and closed. Full ledger in the consolidation PR description.
*   **Model-Route Telemetry Correction (MAIN-1):** `FoundationModelSessionFactory` now sets `selectedRoute = .onDevice` in the `.onDeviceAdvanced` OS-27+ branch, telemetry no longer reports an "advanced" tier that never executed. `SystemLanguageModel.advanced` does not exist in the installed SDK (compiler-probe verified).
*   **PCC Entitlement Fail-Closed (historical, superseded):** The earlier profile-only fail-closed implementation predated Apple approval. v4.6 now checks native macOS signatures, iOS/Catalyst development/ad-hoc provisioning entitlements, then Apple Foundation Models availability and quota for profile-less distribution builds.
*   **FTS5 Migration Hardening:** `ensureColumnExists` now consumes a closed, compiler-owned `ColumnMigration` enum (consolidating PRs #27/#55) with identifier validation and identifier/PRAGMA quoting as defense in depth, no runtime strings reach schema DDL.
*   **Unit-Test Target Restored:** The `OpenIntelligenceTests` target (removed by PR #3) is back, with regression suites for fallback embeddings, normalization bounds, RAG eval metrics, markdown horizontal rules, structured-answer citation parsing, launch arguments, `WorkspaceTier`, and `LLMModelType`.
*   **Deterministic Micro-Optimizations:** Bit-identical single-pass rewrites of embedding magnitude, variance, and 3D-coordinate bounds computations (PRs #28/#31/#35), each with pinned-behavior tests.

## v4.5 - July 2026

*   **Ingestion Pipeline Stability & Correctness:** Resolved critical FTS5 index truncation, page offset mapping errors, parallel ingestion concurrency race conditions/CoreImage deadlocks on Apple Silicon (by introducing `NSRecursiveLock` serialization around CGImage rendering), and an ingestion deletion race condition during batch-based streaming ingestion.
*   **FTS5 Append Capability:** Added optional `append` support to `store(...)`, `storePages(...)`, and `storeChunks(...)` methods in `SQLiteFullTextService`, preventing index deletion during streamed PDF page range processing.
*   **Streaming Ingestion Race Protection:** Modified `WorkspaceSyncService` with a 15-minute file modification window filter, and propagated `storageRelativePath` to queued `IngestionItem` records to prevent background sweeps from purging active ingestion files.
*   **Ingestion File Sync-Sweep Protection:** Fixed a rare ingestion file sync-sweep race condition where background cleanups deleted recently uploaded files. Resolved by touching the modification date of newly copied workspace files to current date, ensuring they are protected by the 15-minute sweep guard before metadata registration finishes.
*   **Streaming Chunk Search Integration:** Fully integrated `storeChunks` inside the `importLargePDFStreamed` batch loop in `RAGService+Streaming.swift`, making large documents fully searchable across all lexical and semantic indexes.
*   **Core AI Selection and Diagnostics:** Resolved a critical Core AI embedding provider selection race condition by caching provider instances and introducing an awaitable model readiness check. Added clear compile-time and runtime diagnostics inside the settings picker.
*   **PCC Entitlement Crash Prevention:** Implemented runtime signature checking using `EntitlementChecker` to verify the presence of the `com.apple.developer.private-cloud-compute` entitlement. Dynamically routes requests away from native PCC to on-device fallback models when running on unauthorized developer builds instead of triggering a fatal crash. Removed the Private Cloud Compute entitlement from the `.entitlements` file to resolve Xcode Cloud export validation errors while waiting for App Store Small Business Program entitlement approval, routing queries transparently to local on-device models.
*   **PCC Fallback UI & Subsystem Diagnostics:** Restored and fixed the iCloud/PCC settings sheet views on iOS 27, ensuring robust `self.settings` scope lookup within SwiftUI sheet extensions to prevent routing crashes. Added an **AI Subsystem Diagnostics** card inside the Library settings, providing real-time "x-ray vision" of model load status, Neural Engine/GPU hardware acceleration targets, Rust-backed tokenizer parser, vocabulary details, byte-level citation offsets, and latency profiles.
*   **Rust-Backed Tokenizer Integration:** Replaced the legacy pure-Swift `BertTokenizer` with a highly optimized Rust-backed `swift-tokenizers` (DePasqualeOrg) package loaded asynchronously from the local resource bundle, yielding a large tokenization speedup and exact byte-level character offsets for citations *(the "100x" originally quoted was never measured and was withdrawn 2026-08-06)*. Excluded `tokenizer.json` files from Xcode's synchronized root group via `project.pbxproj` exceptions to prevent build conflicts.

---

## v4.4 - June 2026

*   **Ingestion Pipeline Acceleration:** Migrated from expensive UIImage-to-PNG data serialization to zero-copy `CGImage` direct processing in `StructuredDocumentParser.swift`, accelerating Vision OCR and structured parsing by 30%+ while reducing peak memory allocation.
*   **Page-Level JSON Checkpointing:** Integrated a robust checkpointing mechanism in `DocumentProcessor.swift` using local-only non-synced JSON files under `localCacheDir()/IngestionCheckpoints/<fingerprint>/`. If ingestion is interrupted (due to memory pressure, crash, or manual pause), the queue resumes from the exact page where it stopped rather than reprocessing from page 1.
*   **Ingestion Cache Management:** Wired automatic checkpoint cleanup in `RAGService.swift` on successful indexing completion and user-discard events.
*   **Apple Watch Smart Stack Layout:** Replaced the crowded Lock Screen view with a tailored compact layout when rendering in the `.small` activity family on watchOS (Smart Stack), utilizing a circular progress ring, doc badge, and high-legibility telemetry text.
*   **Evidence Threads Core:** Replaced dynamic, ephemeral chat persistence with robust, durable research threads stored under `Application Support/EvidenceThreads/<containerId>/` and bidirectionally synchronized across devices via iCloud Drive.
*   **Production Sidebar UI:** Built an elegant, slide-out `ThreadSidebarView` conforming to standard Design System tokens (`DSColors`, `DSSpacing`, `DSTypography`). Users can manage, switch between, and delete research threads via a new leading toolbar button.
*   **Billing Quota Gates**: Thread creation is gated by monetization tier quotas (5 for Free, 20 for Pro, unlimited for Lifetime) via `QuotaPolicy.swift` with localized error displays.
*   **Siri App Intents**: Registered `ListEvidenceThreadsIntent` and `CreateNewEvidenceThreadIntent` to expose threads to Siri and Shortcuts, refactoring them to execute directly on the active presented `RAGService.activePresentedInstance` to instantly populate the user interface and support library entity parameter filtering.
*   **RAG System Integration:** Configured `RAGService` to load the most recent thread automatically on preload, persist RAG responses (including rich citations and reasoning) to the active thread, and handle thread deletions cleanly.
*   **Legacy Preservation:** Retained the immutability of `ChatMessage` while utilizing it inside `EvidenceThread` to prevent breaking existing sync and database schemas.
*   **Diagnostics View:** Retained engineering diagnostic tools (`EvidenceThreadDebugView` and `EvidenceThreadDebugService`) for isolated persistence boundary testing.
*   **Native Private Cloud Compute:** Integrated native `FoundationModels.PrivateCloudComputeLanguageModel` execution when running on iOS 27 / macOS 27+. Older OS versions use real local `SystemLanguageModel` execution; PCC is never simulated or mislabeled.

---

## v4.3 - June 20, 2026

*   **RAG Gate UI Accuracy**: Fixed a bug where verification gates in Standard Mode would falsely appear as "failed" due to asynchronous UI state arrays missing intermediate contextual flags.
*   **Abstention Transparency**: Updated the confidence calibration pipeline to gracefully output the drafted source-answer along with a prominent `[Needs Verification]` warning when strict evidence thresholds are not met, rather than fully discarding the answer.
*   **Confidence Calculation**: Resolved a bug that caused the pipeline to report 100% confidence on abstained queries where the only supported claim had 100% fidelity but critical claims were completely missing.
*   **O(N) RAG Deduplication**: Removed $O(N^2)$ array-based deduplication loops during context packing, replacing them with $O(1)$ Hash Set lookups so evidence aggregation no longer degrades as the library grows. *(The "1000x" originally quoted here was never measured and was removed 2026-08-06; the complexity change is real.)*
*   **Database Dashboard Scrolling**: Implemented a dynamic UUID dictionary cache to eliminate constant UUID string re-computation on row render, keeping scrolling smooth on large libraries. *(The "240x" originally quoted here was never measured and was removed 2026-08-06.)*
*   **Historical Advanced Preference (Superseded in v4.6):** Earlier UI exposed an “Advanced” preference, but the installed public SDK never exposed a distinct selectable 20B runtime. v4.6 migrates that saved value to the public on-device `SystemLanguageModel.default` target.
*   **Architectural Pruning**: Completely removed the legacy `OnDeviceAnalysisService` to simplify LLM routing and reduce overhead, relying entirely on the native Apple Foundation Models integration.
*   **Strict RAG Budget Enforcement**: Hardened the prompt compiler to ensure strict token budget obedience against the 4K local context window constraints.

---

## v4.2 - June 2026

*   **Modernized UI for macOS/iOS**: Completely rebuilt the live telemetry HUD utilizing iOS 26/macOS 26/WWDC26+ APIs. Integrated `.ultraThinMaterial` for premium glassmorphism, hardware `.sensoryFeedback` for interactive haptics, and smooth `.symbolEffect` animations.
*   **Dynamic Verification Gates**: The visual HUD for RAG telemetry now adapts its pipeline dynamically based on your active `RAGQualityMode` (Standard = 4 gates, Deep Think = 8 gates, or Maximum = 12 gates).
*   **Fixed Chat History Persistence**: Resolved an issue that sometimes skipped loading your previous chat history during a cold boot after force-closing the app.
*   **Granular Hardware Telemetry**: The Execution Badge now dynamically fetches and displays exact onboard RAM allocations alongside TOPS processing power.
*   **Accuracy in Retrieval Metrics**: Corrected UI labels to differentiate between semantic Database Matching (Vector Similarity) and active LLM reasoning thresholds (Total Confidence).

---

## v4.0 & v4.1 - WWDC26 Apple Intelligence Update

OpenIntelligence version 4.0 & v4.1 is a milestone release that modernizes the application into an **Apple Intelligence-native evidence system**, incorporating the latest OS-level APIs and capabilities introduced at WWDC26. 

This release notes document details the complete picture of this major release cycle currently live on the App Store, covering modular foundation models, Private Cloud Compute, local sentence embeddings acceleration, live reasoning telemetry, robust data persistence, and sandboxed system integrations.

---

### 1. Modularization of Apple Foundation Models Architecture

The massive, monolithic `AppleFoundationLLMService` class was decomposed into discrete, single-responsibility helper modules under `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/` to ensure stability, ease of testing, and modular scaling:

*   **`FoundationModelSessionFactory`**: Standardizes `LanguageModelSession` creation. Handles the mapping of system instructions, session-specific tool registers, and pending transcript restorations.
*   **`FoundationModelToolRegistry`**: Manages the available RAG tool interface. It registers and wraps core system tools (e.g., `retrieve_corpus_evidence`, `inspect_document`, `compare_topic_across_documents`, and `get_library_overview`) conforming to Apple's native model tools schema.
*   **`FoundationModelPromptCompiler`**: Compiles context-aware prompts by combining user queries, retrieved RAG context, and system instructions, optimizing tokens for on-device context boundaries.
*   **`FoundationModelStructuredGenerator`**: Implements guided/structured JSON schema generation using the framework's native structured generation tools for factual, parseable lookup outputs.
*   **`FoundationModelErrorMapper`**: Maps OS-level generation errors (e.g., safety guardrail violations, unsupported locales, context limits) into localized, user-actionable diagnostics.
*   **`FoundationModelTranscriptStore`**: Manages conversation history, providing intelligent context trimming (moving window) to preserve token budget.
*   **`FoundationModelTokenBudget`**: Computes token usage dynamically using official character-to-token mappings (and a robust 1.4 characters-per-token fallback estimate).
*   **`FoundationModelRoute` & `FoundationModelRoutePolicy`**: Encapsulates dynamic execution route selection (On-Device vs. Private Cloud Compute). Standard queries execute locally, while eligible synthesis can route to PCC using the live SDK-reported context budget.
*   **`FoundationModelDynamicProfileRegistry`**: Standardizes runtime profile swaps for model behavior, tools, and instructions. Supports profiles for direct chat, grounded RAG, extractive RAG, tool-calling RAG, source-only verification, summarization, query planning, and visual evidence QA.

---

### 2. Core AI Framework & Production Core ML Embeddings

To support local-first AI on Apple Silicon, the Core AI framework layer has been fully enabled and integrated:

*   **Production Local Embeddings (`CoreMLSentenceEmbeddingProvider`)**: The live local vector processing pipeline is powered by the highly optimized Core ML engine (`CoreMLSentenceEmbeddingProvider`) on older OS targets.
*   **Core AI Integration (`CoreAISentenceEmbeddingProvider`)**: Fully integrated and enabled Silicon-native zero-copy sentence embeddings on iOS 27+ / macOS 27+. It is registered as a selectable option in library settings, with dynamic auto-tuning automatically upgrading compatible containers to this high-performance backend.
*   ~~**`CoreAIModelRegistry` / Backends**: Staged registries and execution/embedding backend scaffolding (`CoreAIExecutionBackend`, `CoreAIEmbeddingBackend` under `OpenIntelligence/Services/AIPlatform/CoreAI/`) to support running custom models directly on Apple Silicon.~~ **Withdrawn 2026-08-07 and deleted.** These three files never imported Apple's `CoreAI` framework and never had a caller. `generateEmbedding` returned `[]`, `execute` returned `[:]`, and the registry's `registerModel` was never invoked, so it was permanently empty. Listing them beside the working `CoreAISentenceEmbeddingProvider` under a heading reading "fully enabled and integrated" implied a capability that did not exist. The real Core AI integration is the provider entry directly above this one, which is unaffected.

---

### 3. Real-Time Telemetry & Liquid Glass UI Design System

To make the underlying reasoning loops of on-device LLMs transparent and ensure a premium user experience, a state-of-the-art UI trust layer was implemented:

*   **`ThinkingStreamView`**: Displays live, animated indicators during LLM thinking and reasoning phases.
*   **`UnifiedMetricsBar` Integration**: Integrates the thinking stream view directly into the metrics bar at the bottom of the chat interface, providing immediate telemetry feedback on active tokens, duration, and routing.
*   **`GroundedAnswerView`**: Renders verified, source-locked responses clearly with integrated citation mapping.
*   **`VisualEvidenceCard`**: Renders visual evidence context (Vision OCR text, page regions, barcodes, and QR codes) inside message bubbles, promoting camera/photo captures to first-class citations.
*   **`SourceFidelityStatus`**: Visually represents verification checks, showing if an answer is *Source-locked*, *Partially supported*, or *Lacking sufficient evidence*.
*   **`IngestionQueueOverlay` Transition**: Replaced CPU-bound layout dynamic hierarchy rendering with GPU-accelerated opacity, scale, and offset transitions to eliminate layout stutter.
*   **Theme Updates (Liquid Glass Theme)**:
    *   *DSTypography*: Replaced default system fonts with tight, modern headline sizes and monospaced code blocks.
    *   *DSSpacing & DSCorners*: Standardized smaller gaps (e.g., 14pt margin) and tighter corner radii (e.g., 12pt card, 16pt message bubble) for a sleek, premium look.
    *   *`glassCardEffectHelper`*: View modifier that leverages iOS 26+ `.glassEffect` system styling natively, adding an interactive, responsive frosted-glass layer over cards.

---

### 4. Real-Time Routing Badge & Popover

Routing is updated dynamically, ensuring the user understands exactly how the hybrid engine resolves:

*   **`ModelResolutionService` & `ModelStatusIndicator`**:
    *   Refactored the header pill to display the active execution route (e.g., On-Device vs. Private Cloud Compute) dynamically.
    *   Introduced a pulsing scaling animation for the status dot during active query execution.
    *   Transitioned the pill background dynamically based on routing (e.g., green for local, blue for PCC) with smooth state animations.
    *   Replaced the TTFT (time-to-first-token) latency heuristic in `ChatScreen` with the actual route resolved from `FoundationModelRoutePolicy`.
    *   Enriched the indicator detail popover to explain the hybrid engine mechanics "under the hood" (4K token context boundary, PCC cloud enclaves, and cryptographic privacy guarantees).

---

### 5. Suggested Questions & Grammar Safeguards

The query planning and question suggestions pipeline was refined to guarantee clean, high-quality follow-up questions:

*   **Two-Pass Diversity Selector**: Prevents duplicated categories or narrow section topics by running a section-isolation pass, falling back round-robin to ensure the target 12 diverse chunks are surfaced.
*   **POS Grammar Filters**: Integrates `NLTagger` Part-of-Speech analysis to filter out adverb suffixes (e.g., `simply`, `merely`), layout noise, and verbs from generated conceptual topics, ensuring suggested follow-up questions are grammatically clean and topic-grounded.

---

### 6. GPU-Accelerated Vector Search & Ingestion Optimization

The ingestion and retrieval phases were optimized to leverage Apple Silicon hardware:

*   **Metal Cosine Similarity Pipeline**: Replaced CPU-bound vector similarity calculations in `GPUComputeService` with threadgroup-level Metal shaders and SIMD4 batch pipelines, achieving a 4x reduction in query-time retrieval latency.
*   **Adaptive Preprocessing & Page Pre-Scan**: Integrated `PageComplexityAnalyzer` to pre-scan document structures. Digital PDF pages with validated text skip Vision OCR execution automatically (averaging a 20% skip rate), and the system dynamically scales rendering resolution (360-432 DPI) based on page density risk.
*   **Haptic & Ingestion Telemetry**: Coupled execution stages to native telemetry haptic indicators (`HardwareTelemetry` haptic pulses), providing real-time feedback during OCR scanning, embedding math, and LLM inference.

---

### 7. Atomic Vector Store Writes & Cascading Deletions

Storage, indexing, and sync layers were hardened to eliminate file corruption and orphaned database artifacts:

*   **Atomic Database Writes**: Replaced inline `FileHandle` appending in `BNNSVectorDatabase` with thread-safe atomic data replacement on disk, resolving size mismatches and mmap crashes.
*   **Cascading Deletions**: Deleting or discarding interrupted/paused ingestion items now triggers a clean cascade that removes document metadata, purges FTS5 indexes, wipes partial vectors from disk, and removes physical files from storage.
*   **Orphaned Chunk & File Cleanup**: Scans and garbage-collects physical files and vector databases to purge orphaned chunks whose parent documents are no longer active.
*   **Sync Tombstones**: Leverages `deleted_documents.json` tombstones to prevent bi-directional sync from resurrecting deleted files.

---

### 8. Empty Response, Retry, and Partial-Draft Preservation

Stricter generation safeguards ensure answer delivery remains stable under network or API strain:

*   **Abstentions & Retries**: Rate-limited or concurrent Foundation Model request failures get a short retry path. Empty model responses route to a reliability fallback rather than failing silently.
*   **Partial Answers**: Stream captures preserve valid partial answers if the model fails late in execution. Stricter repair pathways handle context overflow and missing citations.

---

### 9. Siri, Shortcuts, Spotlight, and Visual Intelligence

Siri, Spotlight, and system-wide indexing are promoted to first-class retrieval and discoverability layers:

*   **Granular Spotlight Indexing (`SpotlightIndexService.swift`)**: Updated the indexing layer to index not just general documents, but specific chunks, sections, figures, and citation anchors. This turns Core Spotlight into an active semantic retrieval plane.
*   **Entity-Native App Intents (`RAGAppIntents.swift` & `VisualIntelligenceIntents.swift`)**:
    *   Introduced native schemas: `OIDocumentEntity`, `OILibraryEntity`, `OIChunkEntity`, and `OICitationEntity`.
    *   Exposed entity-native Siri shortcuts including: *"Ask OpenIntelligence about current document"*, *"Summarize document in OpenIntelligence"*, and *"Find documents about topic"*.
    *   Replaced ephemeral, unbacked RAGService initializations inside intents with persistent storage-backed entity resolution.
*   **Visual Intelligence Integration**: Extracts OCR text from camera or image inputs and passes it as external evidence, elevating visual documents into first-class citations in the answer pipeline.

---

### 10. App-Wide UI, Onboarding, and Ingestion Queue Improvements

*   **Onboarding Progress**: Updated the onboardingchecklist and imports dashboard to display live stages, extraction progress, vector generation counts, and a timer publisher for smooth elapsed-time tracking.
*   **Live Activities**: Integrated Live Activity support to show background import status directly on the lock screen and Dynamic Island.
*   **Sample Document**: Renamed the sample document to "OpenIntelligence Product Guide" to align with onboarding instructions.

---

### 11. RAG Pipeline Evaluations Framework

The older ad-hoc benchmark script was replaced with a comprehensive, first-class evaluations suite under `OpenIntelligence/Services/Evaluation/` to validate model quality against the strict targets defined in the technical spec:

*   **`RAGEvalCase` & `RAGEvalDataset`**: Models represent test datasets containing queries, expected outputs, ground-truth chunks, and expected citations in a robust `.jsonl` dataset format.
*   **`RAGEvalRunner`**: Runs full evaluation sets against the RAG retrieval and generation engine asynchronously.
*   **`RAGEvalMetrics`**: Analyzes results to compute performance metrics including:
    *   *Retrieval Recall@5* (Target: $\ge 0.85$)
    *   *Citation Precision* (Target: $\ge 0.90$)
    *   *Exact-value Accuracy* (Target: $\ge 0.95$)
    *   *Unsupported-claim (Hallucination) Rate* (Target: $\le 0.05$)
    *   *Correct Abstention Rate* (Target: $\ge 0.85$)
    *   *Context Overflow Rate* (Target: $\le 0.02$)
*   **`RAGEvalReportWriter`**: Formats evaluation runs into readable Markdown reports and structured JSON files for CI/CD tracking.
*   **`AppleEvaluationsBridge`**: Interfaces the local evaluation runner with Apple's command-line evaluation tooling (`fm CLI`).
*   **Documentation (`Docs/EVALS.md` & `Docs/AI_AGENT_MAP.md`)**: Comprehensive documentation detailing quality gate target metrics, dataset schemas, and the full 29-step RAG query execution graph.

---

### 12. App Icon Assets & Build Compatibility

*   **Universal AppIcon**: Integrated a unified universal AppIcon configuration across iOS and macOS targets, resolving catalog build warnings.
*   **SDK Compatibility**: Added compatibility wrappers for iOS 26+ SDK symbols, keeping compile-time behaviors protected while supporting modern APIs.

## Model Override Selector
- Added the original model-preference UI. Its historical 3B/20B labels are superseded in v4.6 by truthful Hybrid, On-Device, and PCC policies because the public SDK exposes no selectable parameter-count model identities.
