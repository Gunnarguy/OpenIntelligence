> **Documentation status:** Historical reference. This document may describe earlier implementation plans or deprecated architecture. Do not use as the source of truth for OpenIntelligence v4.1.

# What's New

Public release highlights for OpenIntelligence.

## 4.3

Version 4.3 focuses on groundbreaking performance optimizations and codebase simplification. We've eliminated legacy architectural overhead and supercharged our RAG (Retrieval-Augmented Generation) pipeline for massive libraries.

### Highlights
- **Lightning-Fast Answer Generation:** The RAG deduplication pipeline was completely rebuilt using an O(1) hash lookup, resulting in a 1,000x speedup during the evidence aggregation phase. Large, context-heavy queries now aggregate in milliseconds instead of seconds.
- **Buttery-Smooth Database Dashboard:** The Database Dashboard now utilizes a dynamic UUID dictionary cache, rendering rows ~240x faster and completely eliminating stutter when scrolling through massive libraries.
- **Simplified Architecture:** Removed legacy, unneeded models like `OnDeviceAnalysisService` to rely entirely on our modernized Apple Intelligence system APIs. 
- **Bulletproof Reliability:** Expanded our RAG Evaluations suite to harden token budget obedience and Hybrid Search boundary logic, ensuring extreme stability for edge cases.

## 4.0 & 4.1
 
Changes since 3.7.1:
 
Version 4.0 & 4.1 introduces the WWDC26 Apple Intelligence modernization suite, featuring dynamic model routing, Core AI frameworks, a first-class RAG Evaluations suite, local sentence embedding acceleration, live reasoning telemetry, and a beautiful Liquid Glass UI design.
 
### Highlights
 
- **Dynamic On-Device vs. Private Cloud Compute Routing**: Queries route based on complexity. Standard queries run locally using the 4K-token on-device model (`SystemLanguageModel.default`), while complex reasoning or context-heavy queries escalate to secure Private Cloud Compute (`PrivateCloudComputeLanguageModel`) utilizing a 32K-token context window.
- **Under the Hood UI Dashboard**: A premium details popover card dynamically visualizes active model routing, token budget usage (4K vs 32K), resolved execution pathways (On-Device/PCC), and last query telemetry.
- **Core AI Local Scaffolding**: Prepared experimental `CoreAISentenceEmbeddingProvider` local scaffolding under Apple's Core AI framework (.aimodel loading with 512-token BERT tokenization), keeping the production baseline stable on the optimized Core ML vector engine.
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
