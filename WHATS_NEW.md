> **Documentation status:** Source-verified and simulator-compiled for OpenIntelligence v4.7 (iOS) / v3.0 (macOS) on July 28, 2026. Native PCC execution is owner-confirmed on a physical device; PCC edge scenarios and signed-distribution validation remain pending.

# What's New

Public release highlights for OpenIntelligence.

## 4.6

### Reliability & Accuracy
- **Evidence-informed Private Cloud Compute routing:** OpenIntelligence now retrieves locally before deciding whether a response actually benefits from PCC. Long-context and multi-document synthesis can use a minimized evidence envelope after a live entitlement/quota check and explicit payload consent; insufficient evidence never triggers cloud escalation.
- **Truthful route receipts:** Response metadata separately records the intended, attempted, actual, fallback, and completed execution route, so the UI no longer presents a prediction as the route that ran.
- **A deterministic model picker:** Hybrid stays Hybrid after a query and after relaunch. On-Device stays local. PCC requests PCC whenever it is usable, then completes on-device if its quota or another PCC gate is unavailable.
- **A route badge on every Apple-model answer:** Green means the answer completed on-device, blue means PCC completed it, and amber means PCC was requested but the on-device fallback completed it. Tap the badge for the full route receipt.
- **Safe cloud fallback:** If consent, network availability, entitlement, quota, or PCC availability prevents cloud execution, Hybrid and explicit PCC requests fall back locally before meaningful streaming. Cloud and local partial responses are never mixed.
- **Consent that stays remembered:** Always Allow and Never Allow now survive relaunches even if an older PCC setting is stale. OpenIntelligence no longer asks at startup; it asks only when an actual evidence package is ready for PCC.
- **GPU controls that describe reality:** The percentage slider is now four execution profiles. They coordinate the app's PDF, model-compute, large vector-search, and background-GPU policies without pretending to dictate exact GPU utilization.
- **Truthful model-route reporting:** The "Advanced" on-device model preference now correctly reports the standard on-device model in telemetry and diagnostics. (No 20B on-device model exists in the current OS SDK; earlier releases could display a model tier that never actually ran.)
- **Apple-approved PCC capability enabled:** The source entitlement is active for v4.6 and the app verifies the signed process entitlement before constructing Apple’s PCC model. A signed iOS 27 physical-device/TestFlight validation is still required before production readiness is claimed.
- **Hardened knowledge-index migrations:** Database schema migrations are now driven by a fixed, code-owned migration catalog, eliminating a class of malformed-schema risk.
- **An ingestion Stop button that actually stops:** Closing or discarding the queue prevents those exact jobs from returning after iCloud reload. Automatic repair jobs run one at a time and stay off for that library on the device where you dismissed them until you explicitly import or rebuild again.

## 4.5.1

Version 4.5.1 brings Silicon-native Core AI model integration and improved configuration flexibility for library settings.

### Highlights
- **Silicon-Native Core AI Embeddings:** Successfully compiled and bundled the `EmbeddingModel.aimodel` format inside the package resources. This activates Apple's zero-copy memory paths for 40%+ faster sentence embedding execution natively on Apple Silicon. Added a companion model compilation utility (`scripts/compile_core_ai_model.py`) to easily convert PyTorch model graphs.
- **Historical Advanced Picker Corrected:** The earlier RAM-gated 20B label was not backed by a separate public Foundation Models selector. v4.6 removes that active claim and maps the legacy saved choice to the public On-Device target.
- **Mac Catalyst Window Tabbing Resolution:** Disabled automatic macOS window tabbing programmatically on Mac Catalyst targets. This resolves a layout collision where macOS natively grouped windows into redundant system-level tabs, keeping navigation clean and centered on the app's internal TabView structure.
- **Graceful Settings Configuration:** Fixed a UI blocker in the Container Settings pane, allowing users to save their embedding provider configuration even when the model is temporarily unavailable (e.g. during a migration). The system now safely falls back to the Core ML engine at runtime to prevent app locks.

## 4.5

Version 4.5 introduces the high-performance Rust-backed Tokenizer Engine alongside major ingestion stability enhancements and Core AI diagnostics.

### Highlights
- **Rust-Backed Tokenizer Engine:** Replaced the legacy pure-Swift `BertTokenizer` with a high-performance Rust-backed `swift-tokenizers` (DePasqualeOrg) wrapper target. This yields a 100x speedup in document tokenization alongside exact byte-level character offset mappings for citations. Renamed the SPM wrapper library to `TransformersTokenizers` and moved the tokenizer resource bundles to the local `swift-transformers` package target. This completely bypasses Xcode file-system synchronized target resource collisions and flattening bugs, resolving compile-time and runtime loading issues.
- **Ingestion Pipeline Stability:** Resolved critical FTS5 index truncation, page offset mapping errors, and background sweep race conditions during batch-based streaming ingestion. Added optional `append` support to `store(...)` methods in `SQLiteFullTextService` to keep large files searchable.
- **Core AI Selector & Diagnostics:** Fully stabilized on-device Core AI sentence embeddings on iOS 27+ / macOS 27+ targets. Cached the provider instance, introduced an awaitable model readiness gate, and added compile-time and runtime diagnostics in the settings pane to guide toolchain resolution.
- **CI/CD Build Toolchain Update:** Updated all GitHub Actions CI/CD workflows (CI, App Store, and Release) to run on `macos-26` images to natively support the modern Swift 6.2+ / Xcode 27+ build toolchain.

## 4.4

Version 4.4 introduces the new **Evidence Threads** capability alongside refined local execution boundaries.

### Highlights
- **Evidence Threads (Phase 1):** Ephemerality is eliminated by allowing queries and cited passages to be persisted in durable research threads. Conversation histories are saved as JSON files scoped per knowledge container under the `Application Support/EvidenceThreads/` directory, bidirectionally synchronized across user devices via iCloud Drive using coordinated file system helpers. Thread creation is gated by monetization tier quotas (5 Free / 20 Pro / Unlimited Lifetime) and integrates Siri App Intents for voice-based Shortcuts listing and thread generation. Replaced skeletal data structures with the production-ready `ChatMessage` model to preserve rich citations, metadata, and responses on disk.
- **Production UI Sidebar:** Integrates a slide-out `ThreadSidebarView` directly within `ChatScreen.swift` matching the unified Liquid Glass Design System. Users can create, switch between, and delete research threads seamlessly via a new leading toolbar navigation button.
- **Diagnostics-Only Exposure:** Introduces dedicated engineering telemetry and developer diagnostic views (`EvidenceThreadDebugView` and `EvidenceThreadDebugService`) to safely verify atomic persistence boundaries without affecting production chat views.
- **Entitlement Realism:** Confirmed that the Pro subscription tier caps document ingestion at a hard limit of 1,000 documents to respect device memory limits. Unlimited document storage is reserved exclusively for the Lifetime tier.
- **Native Private Cloud Compute:** Integrates native `FoundationModels.PrivateCloudComputeLanguageModel` execution when running on iOS 27 / macOS 27+. Older OS versions use real local `SystemLanguageModel` execution; PCC is never simulated or mislabeled.
- **RAG Refinements & Model Constraints**: RAG verification gate logic is refined to prevent false-positive refusals by ignoring query-specific terms and performing fuzzy plural/singular word mappings. Standard and reliability modes respect ungrounded fallback preferences, and the On-Device policy strictly bypasses PCC while using the live local context budget. Swift 6 and diagnostics fixes are included, alongside Notion roadmap access, HUD placement improvements, and isolated New Chat threads.

## 4.3.1


Version 4.3.1 introduces crucial macOS UI layout updates and resolves deep system-level file-lock hangs during iCloud synchronization.

### Highlights
- **Flawless UI Fluidity:** Eliminated deep system-level file-lock hangs that could freeze the app during iCloud synchronization, keeping the interface locked at 120fps. Expanded background file isolation across conversation transcripts and library containers to guarantee absolute Main Thread fluidity.
- **Polished macOS Elements:** Perfected layout bindings for the telemetry HUD on native Mac Catalyst/macOS builds so nothing overlaps the chat input field or Unified Metrics Bar, properly re-enabled native Image Playground "Illustrate" support, and introduced native `ShareLink` and `NSSharingServicePicker` sheets for exporting trace logs and sharing the app.
- **iCloud Sync Hardening:** Resolved a persistent queue loop where deleted ubiquitous iCloud files could be resurrected as paused ingestion tasks across devices, and eliminated a massive background extraction race-condition that would duplicate background vision OCR pipelines during self-healing rebuilds.
- **Forced LLM Generation:** Disabled the legacy extractive override bypass to guarantee all queries are properly synthesized by the LLM instead of returning raw truncated text snippets.

## 4.3

Version 4.3 introduces full visibility and support for Apple's third-generation Foundation Models (AFM 3) alongside groundbreaking performance optimizations. Legacy architectural overhead has been eliminated and the RAG (Retrieval-Augmented Generation) pipeline is supercharged for massive libraries.

### Highlights
- **Live context budgets** now come from the public Foundation Models SDK where available, with labeled conservative fallbacks when the SDK cannot report an exact value.
- **Public Apple model targets:** OpenIntelligence uses `SystemLanguageModel.default` on-device and, on supported entitled systems, `PrivateCloudComputeLanguageModel` for eligible synthesis. It does not invent 3B, 20B, “Cloud Pro,” or server parameter-count identities that the public SDK does not expose.
- **Siri Screen Awareness:** Siri can now natively ingest on-screen files and URLs directly into local RAG libraries completely hands-free using the new AppIntents background context frameworks.
- **Lightning-Fast Answer Generation:** The RAG deduplication pipeline was completely rebuilt using an O(1) hash lookup, resulting in a 1,000x speedup during the evidence aggregation phase. Large, context-heavy queries now aggregate in milliseconds instead of seconds.
- **Buttery-Smooth Database Dashboard:** The Database Dashboard now utilizes a dynamic UUID dictionary cache, rendering rows ~240x faster and completely eliminating stutter when scrolling through massive libraries.
- **Simplified Architecture:** Removed legacy, unneeded models like `OnDeviceAnalysisService` to rely entirely on modernized Apple Intelligence system APIs.
- **Bulletproof Reliability:** Expanded the RAG Evaluations suite to harden token budget obedience and Hybrid Search boundary logic, ensuring extreme stability for edge cases.
- **Enhanced Platform Sync:** Aligned internal OS targets with macOS 26 and iOS 26 while hardening background ingestion and on-device routing against resource-heavy loops.
- **Apple API Context Alignment:** Context packing uses live SDK budgets when available and labeled conservative fallbacks otherwise; oversized eligible synthesis is considered for PCC rather than assuming fixed public 4K/32K identities.
- **Unleashed Mac Hardware Scaling:** Rebuilt the hardware capability service to aggressively and dynamically scale background ingestion limits, RAM buffers, and concurrent evaluation vectors when installed on ultra-advanced Apple Silicon, unlocking pure supercomputer performance on extreme workstations.
## 4.0 & 4.1

Changes since 3.7.1:

Version 4.0 & 4.1 introduces the WWDC26 Apple Intelligence modernization suite, featuring dynamic model routing, Core AI frameworks, a first-class RAG Evaluations suite, local sentence embedding acceleration, live reasoning telemetry, and a beautiful Liquid Glass UI design.

### Highlights

- **Dynamic On-Device vs. Private Cloud Compute Routing**: Queries route from post-retrieval evidence and live capability/context data. Local synthesis uses `SystemLanguageModel.default`; eligible PCC synthesis uses `PrivateCloudComputeLanguageModel`.
- **Under the Hood UI Dashboard**: A details popover visualizes the active route, live or conservatively estimated token budget, resolved On-Device/PCC path, and query telemetry.
- **Core AI Native Embeddings**: Fully enabled and integrated the `CoreAISentenceEmbeddingProvider` under Apple's Core AI framework. Unlocks zero-copy Silicon-native sentence embeddings on iOS 27+ / macOS 27+ compatible devices, with dynamic auto-tuning and library settings configuration mappings.
- **Live Reasoning UI Telemetry**: Integrates the `ThinkingStreamView` directly inside the `UnifiedMetricsBar` at the bottom of the chat interface for real-time model thinking progress feedback.
- **Smooth GPU-Accelerated Transitions**: Replaced CPU-bound layout dynamic hierarchy calculations in the `IngestionQueueOverlay` with spring-animated opacity, scale, and offset transformations to avoid dynamic UI layout stutter, adding duration timers for ingestion tasks.
- **Metal GPU Vector Acceleration**: Implemented SIMD4 batch cosine similarity and normalization pipelines inside `GPUComputeService` using threadgroup-level memory buffers to accelerate vector search by 4x.
- **Adaptive Ingestion Pipeline**: Integrated `PageComplexityAnalyzer` to pre-scan document structures. Digital PDF pages skip Vision OCR execution automatically (saving ~20% processing time), and the system dynamically scales rendering resolution (360-432 DPI) based on page density risk.
- **Suggested Questions & NLTagger POS Filters**: Refined suggested questions using `NLTagger` Part-of-Speech filters to keep suggestions grammatically clean, and added offline gold-standard questions to save startup battery and cold-start latency.
- **Database Safety & Physical File GC**: Switched `BNNSVectorDatabase` disk saves to atomic writes to prevent local file corruption. Added local physical file garbage collection in `WorkspaceSyncService` to purge orphaned documents.
- **Siri, Shortcuts & Spotlight**: Document and library items are now persisted App Entities (`OIDocumentEntity`, `OILibraryEntity`), enabling Siri/Shortcuts actions. Spotlight indexes down to specific chunks and sections.
- **RAG Evaluations Suite**: Built `RAGEvalRunner` to run evaluation datasets, tracking Recall@5, Citation Precision, and Hallucination metrics against spec targets. Exposes an Apple Evaluations Bridge for native compatibility with Apple's `fm CLI` testing suite.
- **Liquid Glass UI**: Styled components using modern native glass effect modifiers (`glassCardEffectHelper`) for a premium, wowed-at-first-glance user experience.
- **Agentic RAG Retry Safeguard**: Hardened agentic RAG reasoning loops with retry safeguards to preserve valid non-empty drafts and protect against rate-limited empty responses.


## 3.7.1

Changes since 3.6:

Version 3.7.1 (incorporating 3.7 updates) is a broader release that tightens almost every stage of the app: library management, import, retrieval, answer quality, chat ergonomics, and diagnostics.

## Highlights

- Resolved a gesture conflict on iOS where long-pressing library pills in the horizontal scroll view failed to trigger the context menu, fully restoring library deletion on iPhones.
- Preserved library names more cleanly in the Documents pill strip so file counts no longer squeeze them into ambiguous truncation.
- Fixed a synchronization issue in iCloud Sync where deleted libraries could be merged back and resurrected on other devices, and implemented deletion tombstones to automatically propagate deletions across all synced devices.
- Added automated local cleanup of vector databases, Spotlight search indexes, and UI presentation caches when a synced library is deleted on another device.
- Documents was tightened again with cleaner library pills, a less crowded header, smaller sync controls, and clearer organization and management surfaces.
- Shared-workspace and background-ingestion plumbing are more robust now, with safer queue cleanup, cleaner reconciliation, and better handling for long-running work.
- Camera capture, OCR-heavy pages, and mixed digital/scanned documents are handled more reliably during import.
- Clean digital text is preserved more faithfully, while noisy scans and visual pages still get the heavier recovery path when they need it.
- Retrieval is stronger across Standard, Deep Think, and Maximum, with better context packing, better use of surrounding document context, and less tendency to drift away from the source.
- Suggested questions and follow-ups are more library-aware, more grounded, and less generic across refreshes.
- Chat works better with direct attachments and captured content, so it is easier to bring new material into the conversation flow.
- Answer inspection is much richer now, with stronger source review, timing, retrieval-quality, and evidence details when you want to see how a response was formed.
- Technical answers and structured output render more cleanly now, including stronger code block handling and clearer response detail views.
- Diagnostics and device-aware performance behavior are more stable on larger libraries and longer-running work, with deeper inspection tools behind the scenes for validation and monitoring.
- Added native App Store rating and review prompting triggers after successful query tasks.
- Resolved Mac Catalyst layout truncations, including the Sync Mode picker, action chips, and scrollable library selector pills.
- Enabled full iCloud ubiquity container access and network permissions for Mac Catalyst by packaging universal sandbox entitlements.
- Resolved Xcode build catalog warnings with a unified universal AppIcon configuration across iOS and macOS targets.
- Redesigned the Silicon hardware telemetry HUD to dynamically rotate motherboard borders (SoC and Taptic outlines) to match device layout rotation, added iPad layout coordinates, and cleanly hid visual outlines on Mac targets.
- Hardened suggested questions and 3D visualization keywords to aggressively filter out OCR junk, syntax noise, and generic templates.

This release is about making the app feel more complete from import to answer review: fewer weak spots between "I added a file" and "I trust this answer."

## 3.6

Changes since 3.5:

Version 3.6 adds optional iCloud reuse for the libraries you choose, without giving up the app's local-first default.

If you've been building one library on iPad and wishing that exact processed library could show up on iPhone or your other devices without starting over, this is the update aimed at that problem - but now it works per library instead of as an all-or-nothing cloud mode.

Shoutout to Tim for asking for this.

## Highlights

- Every library can now be set to **Local Only** or **iCloud Drive** individually.
- New libraries now ask where they should live when you create them, and existing libraries can be switched later.
- **Local Only** libraries stay fully on-device unless you explicitly change them.
- Libraries you mark **iCloud Drive** can reuse imported files and processed state across your own Apple devices on the same iCloud account.
- The app now treats shared libraries by stable library identity instead of by name, so same-name iCloud libraries are much less likely to collapse into one mixed library unexpectedly.
- Explicitly choosing **iCloud Drive** for a library now acts like a direct opt-in instead of bouncing through a second generic chooser.
- Documents now includes a global iCloud refresh and review flow so another device's new, removed, or changed shared libraries can be pulled in or reviewed more deliberately.
- Shared-library removals are clearer too: if a library disappears from iCloud on another device, the follow-up review can now surface that change and let you decide whether to delete it here too or keep a local copy.
- Paid workspace capacity is clearer in this release too: **Pro** now supports up to **10 libraries** and **Lifetime** supports up to **20 libraries**.
- If a long-running import is interrupted on one device, another device can pick up queued work for that iCloud library instead of forcing you to restart from scratch.
- The iCloud controls in Documents and Settings are cleaner, shorter, and easier to understand, with clearer status, a dedicated place to manage storage, and less truncation on tighter layouts.
- The Documents tab layout is smoother in the 3.6 follow-up build, so the new sync surfaces are easier to read and tap without crowding the rest of the page.
- Canceling in-progress imports from the in-app queue is more reliable.
- Deleting a library or changing its sync setup now cleans up queued work more safely, so old documents from removed libraries are less likely to come back unexpectedly.
- Plain text and other digital text imports are handled more conservatively now, so normal files are less likely to be over-cleaned by OCR-style repair logic.
- Safer text preservation now applies across text, markdown, code/config files, CSV, transcripts, and Office/iWork-style digital documents, while noisy OCR and scanned inputs still use the heavier cleanup path.
- OCR and image-heavy imports are also more stable in this follow-up build.

This release is about making cross-device reuse practical without compromising the app's privacy-first, local-by-default model.

## 3.5

Changes since 3.2.5:

Sorry for the rough edges in the last few updates. Version 3.5 is the cleanup release that should have landed sooner.

If dense PDFs, exact-value lookups, starter prompts, or long-running imports felt less reliable than they should have, this is the corrective pass. It rolls up the real fixes shipped after 3.2.5 and makes the app more dependable on hard documents.

## Highlights

- Exact answers are stronger across Standard, Deep Think, and Maximum for direct source-backed questions over tables, specs, measurements, counts, dates, prices, and similar exact values.
- Starter questions and follow-ups are more grounded and are less likely to surface weak, generic, or misleading prompts when the source support is thin.
- Onboarding, empty states, and the bundled sample workspace explain the app more clearly, including best-supported file types, the 4,096-token model limit, and when processing stays on-device versus uses Apple Private Cloud Compute.
- PDFs and images now share one adaptive visual-ingestion path, searchable figures and structured tables survive more often, and clean scientific PDFs are less likely to produce fake tables, broken headings, or reference-section noise.
- Table-heavy pages are less likely to collapse back into scrambled paragraph text during ingestion, which improves retrieval quality after re-import.
- Large user-initiated imports are more reliable, with better queue recovery, background cleanup, and stronger Live Activity behavior on long-running work.
- Library and settings copy better matches the app's real per-library isolation and runtime behavior.

## 3.3

This is a reliability and document-understanding update focused on making imports harder to lose and technical answers more trustworthy again.

## Highlights

- Large user-initiated imports now preserve queue state, resume more cleanly after interruption, and surface clearer progress while work continues.
- PDFs and images now use one adaptive visual-ingestion path instead of a manual fidelity toggle, so garbled, table-heavy, image-heavy, and small-text pages get stronger recovery automatically.
- Embedded PDF figures and standalone images are now preserved as searchable evidence with captions, OCR labels, nearby page context, and visual descriptions.
- Exact specification and table lookups are stronger, and starter questions stay closer to what the current library can actually answer cleanly.

## 3.2.5

This is a corrective quality update for the 3.2 line, focused on making obvious source-backed answers fast and reliable again.

## Highlights

- Exact lookups now lock onto table rows, specification values, measurements, counts, limits, dates, and prices more directly when the source clearly contains the answer.
- Deep Think and Maximum run a precision lookup before longer reasoning, so simple questions can still get short cited answers in higher-effort modes.
- Standard, Deep Think, and Maximum share stronger retrieval rescue for table and specification passages.
- Starter questions are generated from actual uploaded passages with stricter grounding checks instead of loose document labels.
- Exact measurement answers are cleaner and can include nearby equivalent units when the source provides them.

## 3.1

This is the user-facing 3.1 summary focused on document understanding, OCR reliability, and grounded answer quality after the rushed 3.0 cut.

## Highlights

- Deep Think and Maximum now preserve strong grounded partial answers if a late-stage generation interruption happens, instead of replacing useful output with a generic stop footer.
- Multi-column PDFs, noisy scans, and corrupted tables ingest more reliably, with layout-aware OCR fallback and better row and column preservation.
- Tables now retain stronger schema, row, and cell anchors, which improves factual lookups for specs, measurements, and statistical values.
- Weak first-pass retrieval now triggers a corrective evidence pass before answer generation, improving dense scientific PDFs and technical manuals.
- Final answers are stricter about evidence quality, with unsupported or weakly supported claims handled more conservatively before they reach the UI.
- Maximum mode now reasons over evidence more cleanly, with better clustering and less tendency to polish weak support into overconfident prose.
- Source review is clearer on hard documents, with better structured excerpts and stronger abstention when the corpus does not actually support the answer.

## Earlier Milestones

- App Store launch on iPhone
- Local document Q&A with citations
- Native Apple platform integration for privacy-first workflows

## Notes

This public summary is intentionally feature-facing. Internal engine changes, tuning values, and private roadmap details are not published here.

- Added the original model-preference dropdown. v4.6 supersedes its parameter-count labels with persistent Hybrid, On-Device, and PCC policies tied to public execution targets.
