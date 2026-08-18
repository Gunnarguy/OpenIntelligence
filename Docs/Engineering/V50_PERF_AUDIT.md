# v5.0 Performance Audit — launch and render path

Produced 2026-08-18 by a read-only 15-agent pass: one probe per dimension, each then refuted by an
independent agent. No source was edited. Raw output: `Docs/AuditArtifacts/DefectDiagnosis/perf_audit.json`.

A companion flow/responsiveness audit was **stopped early** to conserve session budget; its five
completed probes are in `flow_audit_partial.json` and are **unverified** — the refutation stage
never ran. Do not act on those without re-running verification.

---

# OpenIntelligence performance audit: work plan

Read-only pass over `Startup.txt` (1213 lines, one boot plus light navigation) and the source. Nothing was built, run, or profiled. Tags below: `[measured]` = present in the capture or derivable from it by arithmetic; `[source]` = established by reading code, not by measurement; `[inferred]` = neither, stated as a hypothesis.

Two framing corrections before the list, because three of the six dimensions were built on them:

- **The 432 loads / 210 persists are `WorkspaceSyncService.synchronizeVectorStore` (`WorkspaceSyncService.swift:2316`), not `mergeVectorStoresIfNeeded` and not `VectorStoreRouter.clearAll()`.** The repeating log unit is `L L L B P L B P`, which is 4 store opens + 2 rewrites per container per pass; `mergeVectorStoresIfNeeded` would emit `L L L B P` and `clearAll()` emits bare `L`. `[measured]` Arithmetic closes exactly: 22 passes over {26, 182, 182, 182, 1451} chunk stores gives 432 loads and 210 persists to the line.
- **`mergeVectorStoresIfNeeded` (`WorkspaceSyncService.swift:1795`) is unreachable.** Its only caller `migrateCanonicalWorkspaceIfNeeded` (`:1557`) has zero call sites repo-wide. `[source]` The instrumentation currently in your working tree (the `storeOpens`/`storeWrites` counters and "Vector merge pass starting/complete" at `:1820`, `:1825`) can never fire on a device. Move it to `synchronizeVectorStore` (`:2316`) before the next capture, or the next log will be as blind as this one.

---

## 1. Ranked by expected benefit per unit of risk

**1. Stop re-parsing the streaming answer on every pump tick.** `MessageListV2.swift:232` passes the whole accumulated `streamingText` into `MarkdownText` each tick; `MarkdownText.body` calls `MarkdownParser.parse` as its first statement (`MarkdownRenderer.swift:703`), which runs 14 whole-string ICU substitutions (13 with lookbehind, `MarkdownRenderer.swift:78`–`:169`), roughly 2 regex evaluations per line (`:223`, `:365` via `:333`), and one `AttributedString(markdown:)` per paragraph (`:456`). The pump runs at 80 ms, tightening to 60/40/20 ms under backlog (`ChatScreen.swift:3062-3070`), so 12.5 to 50 Hz, O(length × ticks), on the main actor. `[source]` For short answers the whole normalize pass is discarded: the fast path at `MarkdownRenderer.swift:705-707` hands the original `text` downstream. `[source]`

   I rank this first because it is the only work in this audit that is provably on the main actor, provably re-executed at a high fixed cadence, and on the interaction a user watches most closely. It needs no assumption about SwiftUI's view comparison (the input string genuinely differs every tick), touches no hard-boundary file, and the smallest version, rendering the streaming bubble as plain `Text` until the stream closes and parsing once on completion, is a few lines and trivially revertible. **The per-parse cost itself is unmeasured** and could be 1 ms or 30 ms depending on answer length; that is what makes it a gate item, not a certainty.

**2. Move `reconfigureIfNeeded()` inside the guard at `ContentView.swift:382-383`.** The expensive sync pass is awaited *before* the cheap-exit guard, so the guard protects only `reloadWorkspaceData()`. `[source]` This is the only non-boundary lever on the single largest measured waste in the capture, and it is a reorder, not new logic. Risk is real but bounded: if `reconfigureIfNeeded` under-reports, a synced library could show stale until the next scene change, so it needs a two-device iCloud check.

**3. Lazy-load the 43 MiB Core ML model out of `ContentView.init`.** `ContentView.swift:41` → `RAGService.swift:1542` → the default argument at `EmbeddingService.swift:53` → `CoreMLSentenceEmbeddingProvider.swift:93` → synchronous `MLModel(contentsOf:configuration:)` at `:168` with `.cpuAndNeuralEngine`. `[source]` The capture places it inside the `ContentView.init` window and before the hang report (`Startup.txt:1` is the `#if DEBUG` harness log from `ContentView.swift:34`, `:2` is the model load, `:47` is the hang). `[measured]` Nothing embeds in the entire session (one tokenizer line at `:34`, no embed calls), so deferring removes the work rather than moving it. `[measured]` Ranked third only because the fix has a landmine, see Conflicts, and its magnitude is unmeasured.

**4. Delete the duplicate Atlas analysis task.** `AdaptiveVisualizationsView.swift:205` (bare `.task`) and `:208` (`.task(id:)`) both call `refreshAnalysis()`, so every Atlas entry runs `allChunksForActiveContainer()` and a full profile build twice. `[source]` `analysisTask?.cancel()` (`LibraryVisualizationEngine.swift:356`) cannot stop the in-flight duplicate: neither `buildProfile` (`:390`) nor `analyzeTopics` (`:447`) checks `Task.isCancelled`, and the class is `@MainActor` with no `nonisolated`/`Task.detached`/`DispatchQueue` anywhere in the file, so full-text tokenization of every chunk holds the main actor. `[source]` Deleting one modifier is near-zero risk. The Atlas tab was never opened in this capture, so the cost is entirely unmeasured.

**5. Make `LibraryVisualizationEngine.profileCache` actually read.** It is written at `:381` and read nowhere; the only other references are the declaration (`:304`) and two invalidators (`:332`, `:341`). `[source]` Higher risk than #4 because a stale Atlas after ingestion is worse than a slow one, and the no-argument `invalidateCache()` at `:329` has zero call sites, so eviction coverage is thinner than it looks.

**6. Eliminate the no-op vector-store writes in `synchronizeVectorStore`.** Largest measured waste by a wide margin: ~15 MB written per pass across two destinations, ~320 MB per session, roughly half of it queued to iCloud as replacement uploads, for zero content change. `[measured, from FPItem byte sizes]` Ranked sixth despite that, because the work is off the main thread (`BNNSVectorDatabase` is an `actor`, `:50`; `loadFromDisk`/`saveToDisk` run on its executor), so the payoff is battery, thermals, I/O bandwidth and iCloud queue depth rather than frame time; because it needs `WorkspaceSyncService.swift` named in an approval; and because a wrong "unchanged" predicate leaves two devices silently divergent in the subsystem whose own comments (`:2380-2400`) record a past incident of exactly that shape.

**7. `coordinatedMergeData` byte-equality guard (`WorkspaceSyncService.swift:3445`, write at `:3461`).** All four transforms already set `.prettyPrinted, .sortedKeys`, so identical content really does produce identical bytes and the guard will fire rather than merely exist. `[source]` Small, but it also gates the `.localWorkspaceDidChange` post at `:3472`, which feeds the 2 s debounced reconfigure at `:295`, so it is one of the two candidate self-trigger channels.

**8. `DatabaseDashboardView.swift:180` freshness guard.** Six FTS5 queries per tab entry, plus a double-load on first entry because `:191` seeds `databaseScope` into the `onChange` at `:188`. `[source]` Off-main (`SQLiteFullTextService` is an actor), unmeasured, tab never opened in the capture.

**9. Publisher-surface hygiene.** 24 `ObservableObject` conformances, 157 `@Published`, one `@Observable` (`HardwareTelemetryState.swift:122`). Last, because nothing here measures a cost. The one credible hot path is `RAGService.updateIngestionItem` (`:4904`) writing `processingStatus` (`:4914`) and `ingestionItems` per progress tick, observed by the root view through `ContentView.swift:16`. `[source]` Note the earlier "per streamed token invalidates the whole TabView" claim is wrong: `deepThinkLiveTokens`/`deepThinkLiveSteps` are per *step* (`RAGService.swift:8147`, `:8162`) and the actual streaming text is `ChatScreen`-local `@State` (`ChatScreen.swift:203`), which `ContentView` does not observe.

---

## 2. What is measured versus what is inferred

**Measured (in the capture, or exact arithmetic on it):**

- `Hang detected: 2.94s (overlaps extended launch)` at `Startup.txt:47`. Reported at *recovery*, so it bounds nothing after that line.
- 432 `[BNNS] Loaded` / 210 `[BNNS] Persisted`, split 250/88/91 loads and 122/44/44 persists by store. Decomposes exactly into 22 passes (17 over five containers, 5 over four after a document deletion at `:878-887` empties one 182-chunk store) plus 12 stray single loads.
- The repeating token sequence `L L L B P L B P`, with 105 runs of exactly 1 and 100 runs of exactly 3 consecutive loads. Five anomalous runs out of 205.
- Burst quantization at exactly 20 and 40 loads, never in between.
- All five 40-load bursts (starting `Startup.txt:212, 366, 456, 587, 720`) are immediately preceded by `Scene became inactive` (`:210, 364, 452, 580, 713`). Five for five. Four 20-load bursts occur while the Documents tab is on screen.
- Exactly one tab switch in the whole session (`Startup.txt:90`), one `ContentView.init`, one `Loaded EmbeddingModel.mlmodelc`, one `[RAGService] Loaded 10 documents`, zero `[DatabaseDash]` lines, zero scroll events, transcript held one entry throughout.
- FileProvider item sizes are exact matches for the app's own vector artifacts: 104 B = 26×4, 728 B = 182×4, 6 KB = 1451×4, 40 KB = 26×384×4, 280 KB = 182×384×4, 2.2 MB = 1451×384×4, plus `_meta.json` at 531 KB (182) and 2.8 MB (1451). Each carries `(replacing:…)` and `ul:uploading(?%)`, and at least five distinct fresh `mt:` values appear inside one 293-second session.
- It is a DEBUG build with a debugger attached (`Startup.txt:1` can only be emitted from inside `#if DEBUG`).

**Inferred, not measured:**

- Every per-unit cost. Nothing in the capture times a single store load, a single markdown parse, a single JSON decode, or the MLModel load. The log has no timestamps.
- Whether the 2.94 s is one continuous main-thread block or a launch-to-first-frame measure. The whole launch argument turns on this and the log does not say.
- That the sync pass re-triggers itself through `coordinatedMergeData` → content-date change → `handleMetadataQueryResults` (`:3252`, `observedWorkspaceChangeCount += 1` at `:3273`, no `isSyncWriteInProgress` guard) → `ContentView.swift:237`. The code path is provable; the loop closing is not observed, because no FPItem in the log is identifiable as the shared `containers.json` or `documents_metadata.json`.
- That the scene-phase `.active` branch (`ContentView.swift:353-357`) is what doubles the passes. Correlation is 5/5 but that branch logs nothing, so it is correlation plus a read code path.
- Anything about scrolling or list rendering. The capture contains no scrolling and a one-entry transcript.
- Anything about the Atlas or Database tabs. Never opened.
- That the markdown parse or the observation fan-out costs frame time.

**Refuted, so nobody spends time on it:**

- The aux-file "ping-pong" (`WorkspaceSyncService.swift:2470`) does not re-trigger the sync. `FileManager.copyItem` preserves the source's modification date; this was tested on this machine (APFS, Darwin 27) and the destination came out with an identical timestamp, not a newer one. The capture corroborates: the `transcript_*`/`chat_history_*` JSON items keep pre-session `mt:` values while only the vector artifacts get fresh ones. The redundant copy at `:2515` is still wasted I/O, but fixing it will not slow the loop.
- `restorePersistedIngestionQueueIfNeeded` (`RAGService.swift:1045`) opens no vector store; it reads `Document.totalChunks` by design (`:1108-1118`). The `Dropping persisted ingestion item` lines are the tail of a refresh cycle, not its cause.
- `VectorStoreRouter.clearAll()` accounts for roughly 5 of the 432 loads and 0 of the 210 writes. Renaming it is hygiene (it does not clear, it reloads), not perf.
- The 182-chunk store is not "processed three times". There are three distinct 182-chunk containers, confirmed by three separate 531 KB `_meta.json` FPItems in one block.

---

## 3. What needs Instruments before anyone writes code

| Question | Instrument / setup | What it decides |
|---|---|---|
| Is the 2.94 s one continuous main-thread block? | **Time Profiler** with *Record Waiting Threads*, filtered to the main thread, on a **Release** device launch. Xcode Organizer hang reports as a cross-check. | Whether the launch dimension is one item or five. Everything downstream of it is guesswork until this is answered. |
| How is pre-first-frame time split? | `os_signpost` intervals around `CoreMLSentenceEmbeddingProvider.setup()` (`:152`), `ContainerService.loadContainers()` (`:225`), `RAGService.loadDocumentsSnapshotFromDisk()` (`:3646`), and the `.task` body from `ContentView.swift:161` to `:223`. One device run. | Whether the 43 MiB MLModel load is 40 ms (warm ANE cache) or 1.5 s (cold). Single highest-leverage unknown, one signpost. |
| What does one markdown parse cost, and does it run for finished messages? | **SwiftUI instrument**, *Long View Body Updates* lane (orange >500 µs, red >1000 µs) plus *Show Causes*, during a streamed long answer. Plus `let _ = Self._printChanges()` on `MarkdownText.body` and `MessageBubbleV2.body`. | Whether item 1 is worth doing, and whether only the streaming bubble re-parses or every visible row does. Note the grounded path is the likely offender: `StructuredAnswer` and `[RetrievedChunk]` are not `Equatable`, and `GroundedAnswerView.swift:31` hands `MarkdownText` a freshly allocated buffer each body. |
| Does the sync pass trigger itself? | Cheaper than Instruments: one `Log` line at each of the four trigger sites (`ContentView.swift:223`, `:232`, `:237`, `:356` and `DocumentLibraryView.swift:1309`), plus the merge-pass counter moved from the dead `mergeVectorStoresIfNeeded` to `synchronizeVectorStore` (`:2316`). One fresh device capture. If that is inconclusive, **File Activity**. | Which of the four triggers produces the 22 passes, and whether channel (a) closes. |
| Does the observation fan-out cost anything? | **SwiftUI instrument** *Show Causes* on an update group, during an ingestion and during a large-library scroll. | Whether item 9 is worth its blast radius. |
| Is the Atlas profile build actually expensive? | `os_signpost` around `buildProfile`/`analyzeTopics`, main-thread Time Profiler while entering the tab. | Whether items 4 and 5 matter at 1451 chunks. |

Apple is explicit that all of this must be on device: "Never profile your code using the iOS simulator. Always use real devices for performance testing." Also profile Release, not the DEBUG build this capture came from.

---

## 4. Batches, grouped by what verifies them

**Batch A, verified by a fresh device capture counting `[BNNS] Loaded`/`Persisted` lines on an idle boot with the same libraries present.** All of these move the same counter, so they cannot land together without confounding each other. Land them one at a time with a capture between each:

- A0: move the working-tree instrumentation from `mergeVectorStoresIfNeeded` to `synchronizeVectorStore`, add the four trigger log lines. Capture. This is a prerequisite, not an optimization.
- A1: `ContentView.swift:382-383` reorder (item 2). Capture.
- A2: `coordinatedMergeData` byte guard (item 7). Capture.
- A3: `synchronizeVectorStore` persist short-circuit (item 6). Capture. Do not accept a simulator run as proof; the ubiquity container is what drives the loop.
- A4 (separate commit, separate capture): routing the local store through `VectorStoreRouter`. This one changes actor identity and ordering between sync and live retrieval.

**Batch B, verified by the SwiftUI instrument on a streamed long answer plus a parse-count signpost.** Independent of Batch A, different metric, different files.

- B1: streaming bubble stops re-parsing (item 1).
- B2: hoist the 14 patterns plus `:223`, `:365`, `:369`, `:406` into `static let NSRegularExpression`. Separate commit from B1, because it changes String→NSString/UTF-16 range semantics and could shift a replacement boundary on emoji or non-BMP text. Re-run the markdown tests; `GroundedAnswerView.swift:25-30` documents a prior ICU template-escaping regression in this exact area.
- B3: bounded `NSCache` in front of `MarkdownParser.parse` and `AttributedString(markdown:)`, keyed on text only (blocks depend on nothing else; font and color are applied downstream at `:463-466`). Helps scroll-back only, never the streaming bubble, since every tick is a distinct string.
- Also in scope for B's trace, unexamined by anyone: `MessageListV2.swift:136-145` fires an animated `proxy.scrollTo` roughly every 80 characters of stream, and the whole list body sits inside a `GeometryReader` (`:71`). Both are plausibly larger than the parse.

**Batch C, verified by the launch signpost trace on a Release build.** Independent of A and B.

- C1: fix `isAvailable` semantics first (see Conflicts), then lazy-load the MLModel with a single-flight `Task<MLModel, Error>`. Do not ship the lazy load without the single flight: the provider is a non-`Sendable` `final class` (`CoreMLSentenceEmbeddingProvider.swift:61`) whose `model` is already reassigned at runtime by `enableIngestionMode()` (`:107`) / `disableIngestionMode()` (`:135`), and `embed` runs at `embeddingConcurrency > 1`, so N callers could race N 43 MiB loads. Swift 5 mode will not diagnose it.

**Batch D, verified by a main-thread trace on Atlas tab entry.** Independent.

- D1: delete `AdaptiveVisualizationsView.swift:205`.
- D2: make `profileCache` read, keyed on containerId + chunkCount + documentCount.

**Batch E, verified by an FTS5 query count on Database tab entry.** Independent. `DatabaseDashboardView.swift:180` guard.

**Batch F, verified by SwiftUI *Show Causes*.** Do last, only if the trace justifies it. Drop `@Published` from the seven zero-reader properties; migrate `RAGService` to `@Observable` incrementally (Apple explicitly blesses one object at a time). `SettingsStore` is not worth it: `setupPipelines` (`:631`) drives persistence off 45 merged `$` projected publishers (`:644-690`), which `@Observable` removes.

---

## 5. Conflicts

**Same code, two fixes:**

- `ContentView.swift` is targeted by four dimensions. Ordering matters: passing `forceReload: false` at `:223` buys nothing until `reconfigureIfNeeded()` moves inside the guard at `:383`, because it runs before the guard today. Do A1 first, then reconsider `forceReload`.
- `WorkspaceSyncService.swift:2316` region is targeted by three dimensions with three differently-worded versions of the same skip predicate. One owner, one commit, the version in A3.
- `VectorStoreRouter`: A4 (route the sync's local opens through the router) and the "make `clearAll()` idempotent" proposal interact badly. A4 increases the number of cached stores, which increases `clearAll()`'s fan-out. If both land, do the in-flight dedupe first.
- `MessageBubbleV2` equatability: the proposed `.equatable()` needs `ChatMessage: Equatable`, and `ChatMessage.swift:10` is `Identifiable, Codable, Sendable`. Adding the conformance means editing a hard-boundary file. A custom `static func ==` on the view comparing `message.id` and `message.content` avoids that; the original fix did not say so.
- Three dimensions independently propose the same Core ML lazy load, and **two of them propose redefining `isAvailable` as a bundle-resource check, which the third refutes and I agree is a regression.** `isAvailable` is `model != nil` (`CoreMLSentenceEmbeddingProvider.swift:203-215`); `EmbeddingService.forProvider` branches on it at `:178` and `:197` and falls back to `NLEmbeddingProvider` at `:205` with `targetDimension: 512` against 384-dim stores. Bundle-presence makes it never false on a shipped build (kills the fallback, converts silent degradation into a query-time throw); a naive lazy provider makes it always false at construction (silently downgrades every container to 512 dims). Neither is acceptable. Use a tri-state (`.notAttempted` / `.loaded` / `.failed`) reported as available, or an async probe. Also note `EmbeddingService.swift:57-60` reads `provider.dimension` and `provider.isAvailable` in `init`, so the naive `@autoclosure` form is defeated on exactly the path it targets.
- Making `ContainerService.loadContainers()` async races the default-container creation at `ContainerService.swift:23-26`, which can write a duplicate library into `containers.json`. `activeContainerId` is non-optional and must be set in `init`.
- Making `EvidenceThreadStore.listThreads` async cascades into `RAGService.chatHistory(for:)` (`:602`, synchronous `@MainActor`, called from `ChatScreen.swift:1734`, `RAGService.swift:9078`, `:12471`) and `createNewThread(for:)` (`:775`, synchronous, throws). The per-container index is the better fix and keeps both signatures.
- Deleting `DocumentLibraryView.swift:1309` removes the only metadata-bump path to `presentSharedSyncReviewIfNeeded()` (`:1046`), and `ContentView`'s handler additionally invalidates visualization/cluster/suggested-question/Spotlight caches (`:394-400`) which the library's does not. Merge the two behaviours, do not delete one.

**Where two findings disagree, and how I resolved it:**

| Disagreement | Resolution |
|---|---|
| BNNS storm is `clearAll()` vs `mergeVectorStoresIfNeeded` vs `synchronizeVectorStore` | `synchronizeVectorStore`. Decided by log shape: `L L L B P L B P` matches only it, and the 432/210 arithmetic closes exactly at 22 passes. |
| Documents-tab entry vs scene phase drives the double passes | Scene phase. Only one tab switch exists in the capture; all five 40-load bursts follow `Scene became inactive`; four 20-load bursts occur while on Documents. Tab attribution is unproven. |
| The two launch JSON decodes are expensive vs negligible | Negligible. `Document` (`DocumentChunk.swift:430-444`) and `KnowledgeContainer` are metadata only, 10 documents, kilobyte-scale. Whatever they cost is the `NSFileCoordinator` round trip, unmeasured. |
| Root view invalidates per streamed token vs per step | Per step, and the token stream is `ChatScreen`-local `@State`. The "per token" claim is wrong. |
| Aux-file copy sustains the sync loop | Refuted empirically. Still wasted I/O, no longer a trigger. |
| Finished messages re-parse markdown during streaming | Unproven on the plain path (`MarkdownText`'s three stored properties are all `Equatable` and provably unchanged), plausible on the grounded path. The streaming bubble itself is certain. |

---

## 6. Hard-boundary files needed

Approve or decline each. Nothing in Batches B, D, E or item 4/5 needs any of these.

```
OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift
    Needed for: A2 coordinatedMergeData byte guard, A3 persist short-circuit,
    metadata-handler path-scoped suppression, aux-file equality check, and
    moving ubiquityIdentityToken (:430) / ensureDirectory (:446) off the main
    actor. Also needed to move the dead merge-pass instrumentation to :2316.
    No format or schema change. Unavoidable for the largest measured waste.

OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift
    Needed only if reload coalescing or the change digest lands inside the
    database rather than in VectorStoreRouter / WorkspaceSyncService.
    No on-disk format change intended. Avoidable.

OpenIntelligence/Features/Chat/ChatMessage.swift
    Needed only if MessageBubbleV2 is made Equatable via a ChatMessage
    conformance. Avoidable with a custom == on the view. Recommend declining.

OpenIntelligence.xcodeproj/project.pbxproj
    Needed only to add SWIFT_STRICT_CONCURRENCY = complete (absent today) and
    later to change SWIFT_VERSION (app target :797, :862). Zero direct
    performance gain; this is data-race correctness. Defer.

Package.swift
    Needed only to replace the .unsafeFlags block (:78-88) with
    SwiftSetting.defaultIsolation(MainActor.self) + .enableUpcomingFeature,
    which also requires raising tools-version from 6.0. Defer.

OpenIntelligence/Services/Billing/EntitlementStore.swift
    Would be a natural continuation of an @Observable migration.
    Explicitly NOT recommended this pass. Decline.
```

One compounding risk if the `@Observable` migration goes partial: `ContentView.swift:133-136` injects four services in one `.environmentObject` chain. If `RAGService` moves and the others do not, the injection sites diverge (`.environment` vs `.environmentObject`) and a missed consumer is a runtime crash, not a compile error. `ContentView.swift:144-147` carries a comment recording that this exact mistake already shipped once.

---

## 7. Apple guidance

**Applies here.** All quotes were pulled this session from the DocC JSON endpoints, because `developer.apple.com` HTML returns a JS shell and yields only page titles.

- Launch-time deferral, applies to the Core ML load in `ContentView.init`: "Do only the work necessary to prepare your app's initial display in these methods; defer other tasks to more appropriate times in the app's life cycle" and "Initialize nonview functionality, such as persistent storage and location services, on first use rather than on app launch." https://developer.apple.com/documentation/xcode/reducing-your-app-s-launch-time
- SwiftUI performance, applies to the view-initializer work, the body-time budget, and the instrument to use: "avoid performing complex, long-running tasks in your View initializer"; the excessive-updates cause list; the 500 µs orange / 1000 µs red Long View Body Updates thresholds and *Show Causes*. https://developer.apple.com/documentation/Xcode/understanding-and-improving-swiftui-performance
- Observation semantics, applies to item 9 and sets the migration order: "a view updates when any published property of an ObservableObject instance changes, even if the view doesn't read the property that changes" and "You don't need to make a wholesale replacement of the ObservableObject protocol throughout your app. Instead, you can make changes incrementally." https://developer.apple.com/documentation/swiftui/migrating-from-the-observable-object-protocol-to-the-observable-macro
- Profiling discipline: "Never profile your code using the iOS simulator. Always use real devices for performance testing." https://developer.apple.com/documentation/swiftui/creating-performant-scrollable-stacks
- Swift 6 adoption order (upcoming features, then Minimal→Complete checking, then language version): https://developer.apple.com/documentation/swift/adoptingswift6 and https://www.swift.org/migration/documentation/swift-6-concurrency-migration-guide/migrationstrategy/
- Supported replacement for the `unsafeFlags` block: https://developer.apple.com/documentation/packagedescription/swiftsetting/defaultisolation(_:_:)

**Does not apply, checked rather than assumed:**

- Reduce embedded third-party frameworks / mergeable libraries. `Package.resolved` lists exactly one external dependency (`swift-tokenizers`).
- Remove static initializers. Zero `.m`, `.mm`, `.c`, `.cpp` files in the target.
- Replace custom `draw(_:)` views. Zero `override func draw(` in the codebase.
- Adopt lazy stacks. Already 50 `Lazy*` containers, including both that matter (`MessageListV2.swift:74`, `DocumentLibraryView.swift:202`).
- Adopt Approachable Concurrency and default `MainActor` isolation, the two WWDC25 headline recommendations. **Already done** on the app target: `project.pbxproj:792-793` (Debug) and `:857-858` (Release), plus `Package.swift:79`. The earlier citation of `:970-971` was the widget extension. The remaining gap is narrow: `SWIFT_STRICT_CONCURRENCY` appears nowhere in the file, `SWIFT_VERSION = 5.0` at `:797`/`:862`, `swiftLanguageModes: [.v5]` at `Package.swift:97-99`.

**Could not be verified:** WWDC26 session 321, "Dive into lazy stacks and scrolling with SwiftUI," surfaced in search but was not fetched. It postdates the assistant knowledge cutoff and may supersede the scroll guidance above. Worth watching before acting on anything scroll-related.

---

## 8. Dimensions where no cause was established

- **The 2.94 s launch hang. No cause established.** Ruled out with reasons: the BNNS churn (actor executor, and the hang is logged one line *before* the first `[BNNS] Loaded`); iCloud and FileProvider blocking (there is not one FileProvider line in `Startup.txt:1-46`, the first is `:88`); `NSMapGet: map table argument is NULL` (zero `NSMapTable`/`NSMapGet` references in Swift source, so it comes from a system framework, and adjacency in an untimestamped multi-threaded console capture is not attribution); Metal/GPU setup (off-main); `WorkspaceSyncService.isSyncEnabled` (never read from a view body); repeated `ContentView.init` (ran exactly once). What is left is one 43 MiB synchronous MLModel load, two kilobyte-scale coordinated reads, a main-thread-required `SystemLanguageModel.availability` read, and a debugger-attached DEBUG build. The launch `.task` also awaits StoreKit at `ContentView.swift:217` (request at `Startup.txt:9`, response at `:35`), which releases the run loop, so a single continuous 2.94 s block cannot contain both `ContentView.init` and the later iCloud calls. At most one of them is in it, and the log does not say which.
- **Observation churn as an observation problem. No cause established.** The publisher surface is genuinely oversubscribed (24 conformances, 157 `@Published`, 7 zero-reader properties, 7 views subscribing to `RAGService` while reading none of its published fields), but nothing in the capture or the source shows it costing frame time, and reading source is the wrong instrument for that question.
- **Tab-switch cost. No cause established.** Entering Documents does reach the sync pass through `DocumentLibraryView.swift:1304`, but the capture contains one tab switch and cannot separate that from the scene-phase and metadata triggers firing on the same seconds. The Atlas and Database tabs were never opened, so their per-entry cost is entirely unmeasured.
- **List scrolling. No cause established.** The capture contains zero scrolling and a one-entry transcript. The streaming re-parse finding is real and is a *streaming* finding, not a scroll finding; do not sell it as one.
- **The 112 FileProvider "you don't have permission to view it" errors.** The item *sizes* are fully explained: they are the app's own vector artifacts being replaced and re-uploaded by the sync pass. The permission text itself is not explained by anything in this repository.
- **`NSMapGet: map table argument is NULL`.** Unexplained, and confirmed not to originate in app code.
