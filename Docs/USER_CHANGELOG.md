> **Documentation status:** Source-verified for OpenIntelligence v4.8 on July 30, 2026. Deep Think's reasoning chain, the model picker, and early stopping are device-verified; the remaining v4.8 fixes are build- and test-verified only.


# OpenIntelligence User-Facing Changelog

This document provides a chronological history of user-facing changes, highlighting how OpenIntelligence continuously improves transparency, speed, and reliability.

---

## v4.8 - July 31, 2026

*   **Deep Think and Maximum Now Reason Over Retrieved Evidence:** Both modes run several reasoning passes across your documents, each building on the one before it. The handoff between retrieval and the reasoning step was never connected, so every pass concluded there was nothing to work with. Maximum needed a second, separate fix for the same defect in its own loop.
*   **Retrieval Was Never the Problem:** Documents were being found, ranked, and prepared correctly the entire time. The evidence simply never reached the step that decides how to answer.
*   **Answers Cite Their Sources in Every Mode:** Maximum previously produced answers carrying no citations at all, because source markers were lost while findings were compressed between passes. Attribution now survives that compression.
*   **Resolved "The selected model isn't available right now":** That message appeared when the reasoning step found nothing to plan against. It was never a model or hardware problem.
*   **Model Picker Now Governs Every Mode:** On-Device, Hybrid, and Private Cloud Compute reached Standard correctly but were dropped in Deep Think and Maximum, which fell back to a default. On-Device now applies to the entire query, including the final answer.
*   **Deep Think and Maximum Stop When Finished:** Both had internal confidence targets that could not mathematically be reached, so every query ran the maximum number of passes whether or not it was still learning anything. Maximum now ends once it stops finding new material, typically halving the time it takes.
*   **Reasoning Output Stays Readable:** Reasoning passes sometimes emitted raw model markup instead of prose, and that text could reach the final answer. It is now removed before being used or shown.
*   **The Pipeline Shows What Is Actually Running:** Reasoning passes were labeled "Re-ranking", and several stages were grouped under one name, so the live view did not match the work. Each stage now reports itself, including verification and query rewriting, which were never shown at all. Passes skipped for having no relevant text say so instead of leaving gaps in the sequence.
*   **Reasoning Detail Is No Longer Cut Off:** Live reasoning text was truncated to a single line, removing the part that explained what a step had found. It now wraps.
*   **Follow-Up Suggestions Are Drawn From the Answer:** Suggestions were built from stray words and often read as nonsense. They now come from the phrases the answer quotes, the sections it defines, and the gaps it reports.
*   **Grounded Answers Are No Longer Discarded:** An answer correctly reporting that the documents did not cover something was being replaced with generic help text. That answer is now kept, because it is the honest one and it cites its sources.
*   **A Failed Pass No Longer Ends the Query:** A single transient model error used to discard an entire query. Passes now retry, the run continues across its remaining evidence, and a pass returning something unusable no longer counts as the model being unavailable.
*   **Document Import on Mac:** The macOS file picker was a placeholder. It is now a native picker supporting the same formats as iOS, including PDFs, Office and iWork files, text, code, images, audio, and video.
*   **What Changed, After Every Update:** Opening the app after an update now shows a short summary of what is new.

## v4.7 - July 28, 2026

*   **Honest Route Labels:** Labels now say exactly where each answer ran: on your device, or Apple Private Cloud Compute with your permission. Nothing claims more than the system can verify.
*   **Steadier Document Understanding:** The key ideas pulled from your documents now come out the same every time, for more consistent search and more reliable connections across files.
*   **Route Verification:** New internal checks confirm that every answer's recorded route matches what actually ran.
*   **Removed Unsupported Model Claims:** Settings no longer advertises selectable 3B or 20B on-device models, or a parameter-count based capability chip. (Correction to earlier releases: the public SDK exposes no such selector. Apple's larger on-device model is real and managed by the operating system, but no app can choose or observe it.)

## v4.6 - July 15, 2026

*   **Smarter Private Cloud Compute Decisions:** Queries now retrieve evidence locally before choosing a model route. PCC is used only when the final evidence and context budget justify secure cloud synthesis; missing evidence never causes escalation.
*   **Exact Cloud Consent:** The confirmation sheet describes why PCC was selected and shows the size of the minimized evidence payload that would be transmitted. Background actions never wait on a hidden consent prompt.
*   **Model Choice That Stays Put:** Hybrid, On-Device, and PCC now describe the policy you selected—not whichever route happened to run last. Hybrid remains selected after a PCC answer and after relaunch.
*   **Route Badges on Answers:** Every Apple-model answer identifies the route that completed it: on-device, PCC, or on-device fallback. The badge opens the existing detailed route receipt.
*   **Reliable Local Fallback:** Hybrid and explicit PCC requests fall back on-device when consent, network, entitlement, quota, or PCC availability blocks cloud execution, provided streaming has not meaningfully begun. The answer is labeled as a fallback instead of silently changing routes.
*   **Remembered PCC Choice:** Always Allow and Never Allow persist across relaunches. The app no longer opens a generic PCC sheet on startup; permission is requested only for a real finalized evidence package.
*   **Clear GPU Execution Profiles:** Efficiency, Balanced, Performance, and Maximum replace the misleading percentage control and align Settings with the work the app can actually route to GPU-capable paths.
*   **Accurate Route History:** Saved response metadata distinguishes intended, attempted, actual, fallback, and completed execution paths.
*   **Truthful Model Reporting:** The "Advanced" on-device model preference now reports the actually executed model route in telemetry and diagnostics. (Correction to earlier releases: the current OS SDK exposes no separate 20B on-device model API; the Advanced preference executes the standard on-device model.)
*   **Apple-Approved PCC Capability Enabled:** The v4.6 source entitlement is enabled and the app verifies the signed process entitlement before constructing Apple’s native PCC model. Signed iOS 27 physical-device and TestFlight validation remains pending.
*   **Hardened Knowledge-Index Migrations:** Database schema migrations are driven by a fixed, code-owned migration catalog, eliminating a class of malformed-schema risk.
*   **Ingestion Stop Now Persists:** Closing or discarding an ingestion queue prevents those exact jobs from returning after iCloud reload. Automatic empty-index repair runs one library at a time and remains disabled for that library on the device where you dismissed it until you explicitly import or rebuild again.
*   **Restored Test Coverage:** The unit-test target removed in an earlier release is restored, with regression suites pinning embedding, parsing, citation, and launch-argument behavior.
*   **PR Backlog Consolidation:** All 43 open automated pull requests were audited end-to-end; the valuable changes were reimplemented cleanly in this release and the remainder documented and closed.

## v4.5.1 - July 2, 2026

*   **Parallel PDF Ingestion Concurrency Fix:** Resolved concurrency race conditions and deadlocks on Apple Silicon by introducing thread-safe `NSRecursiveLock` serialization around CoreImage image generation, preventing concurrent Metal context crashes during multi-page parallel processing.
*   **Silicon-Native Core AI Embeddings:** Compiled and bundled the `EmbeddingModel.aimodel` format inside the package resources. This activates Apple's zero-copy memory paths for 40%+ faster sentence embedding execution natively on Apple Silicon. Included a companion model compilation utility (`scripts/compile_core_ai_model.py`) to easily convert PyTorch model graphs.
*   **Flexible Settings Saving:** Enabled saving of embedding configuration options when a provider is unavailable at save-time, allowing runtime fallback routing (e.g. Core AI falling back to Core ML) to resolve and execute cleanly.
*   **Silicon HUD Layout Correction:** Restored the iOS Silicon HUD position back to its original layout coordinates (x: 45, y: safeAreaInsets.top + 85), and configured the HUD legend to dynamically shift to the right (x: 345) when the conversation history sidebar is visible to prevent overlap.
*   **Private Cloud Compute Fallback & UI Safeguard:** Configured dynamic Hybrid (Automatic) model routing to check for active developer entitlements before selecting Private Cloud Compute, ensuring seamless fallbacks to local models and eliminating routing delays. Greyed out and disabled the PCC option in the header model preference selection menu until the official developer entitlement is active.
*   **Historical Advanced Picker Correction:** The earlier RAM-gated “20B Advanced” label was not backed by a distinct public SDK model selector. v4.6 removes that active claim and migrates the saved preference to the public On-Device target.

## v4.5 - July 2026

*   **Rust-Backed Tokenizer Engine:** Replaced the legacy pure-Swift tokenizer with a highly optimized Rust-backed `swift-tokenizers` engine. This delivers microsecond-level document tokenization (a 100x speedup) and exact byte-level character offset tracking for citations.
*   **Ingestion Pipeline Stability:** Fixed FTS5 index corruption and page offset mapping bugs during streamed ingestion of large documents. Large files are now fully searchable.
*   **Core AI Diagnostic Options**: Stabilized Silicon-native Core AI sentence embeddings on iOS 27+ / macOS 27+ with robust model readiness indicators and detailed build/OS error diagnostics in settings.
*   **CI/CD Pipeline Upgrades**: Updated cloud build environments to `macos-26` to natively support Xcode 27+ and Swift 6.2+.

## v4.4 - June 2026

*   **Evidence Threads:** Introduced durable conversational threads. Chat sessions and their active citations, metadata, and responses are now persisted on disk, eliminating dynamic ephemerality.
*   **Slide-Out Thread Sidebar:** Added a premium, spring-animated slide-out menu to view, create, switch, and delete research threads. Features full swipe-to-delete support and active-selection highlighting.
*   **Design System Parity:** Structured the new sidebar using the app's native visual tokens (`DSColors`, `DSSpacing`, `DSTypography`), rendering a visually integrated, sleek interface on both iOS and macOS.
*   **Thread Storage:** Threads initially shipped in isolated local-only storage. *(Updated July 2026: thread storage has since moved into the app's workspace storage and now syncs across your devices via iCloud Drive using safe, coordinated file writes. If you edit the same thread on two devices at nearly the same time, the most recent change wins.)*
*   **Engineering Diagnostics View:** Retained the debug view and mocked thread triggers inside the Developer Diagnostics Hub to inspect and verify thread persistence.
*   **Native Private Cloud Compute Support:** Integrates route-policy support and diagnostics to escalate complex queries to Apple's secure Private Cloud Compute server enclaves on iOS 27 / macOS 27+ for supported and entitled builds, with graceful automatic fallback to local on-device execution when unavailable.
*   **Pro Annual Pricing & Free Trial:** Calibrated the Pro Annual subscription to $29.99/year (representing a 58% savings vs monthly) and introduced a 7-day free trial.
*   **Discontinued Document Pack Add-on:** Discontinued the consumable Document Pack add-on, removing related UI cards, quick-refill views, and purchase flows.
*   **Direct Review Prompts:** Streamlined the app-rating experience by triggering Apple's native review prompt directly at key "happy moments" (like tapping Thumbs Up), eliminating the intermediate alert dialog.

---

## v4.3 - June 20, 2026

*   **Transparent Verification Engine**: When the AI abstains from answering due to lack of evidence, it will now gracefully provide its drafted reasoning with a prominent `[Needs Verification]` warning, rather than hiding the drafted answer entirely.
*   **Accurate Telemetry Status**: Fixed a minor UI bug that caused the Verification Gates status panel to incorrectly light up red (as "Failed") during perfectly healthy standard queries.
*   **Instant Library Scrolling**: Fixed a massive scroll-lag issue when browsing large libraries. Scrolling through your documents is now 240x smoother.
*   **Faster Answer Generation**: Rebuilt the context aggregation math, reducing the time it takes the app to deduplicate massive datasets by 1000x. Answers generate substantially faster.
*   **Enhanced Reliability**: Simplified the underlying AI routing engine to be exclusively reliant on native Apple Intelligence, resulting in fewer context errors.

---

## v4.2 - June 2026

*   **Modernized UI**: Completely rebuilt the live telemetry dashboard with premium frosted glass and interactive haptic feedback.
*   **Dynamic Verification Gates**: The visual HUD for RAG telemetry now adapts its pipeline dynamically based on your active `RAGQualityMode`.
*   **Fixed Chat History Persistence**: Resolved an issue that sometimes skipped loading your previous chat history during a cold boot.
*   **Granular Hardware Telemetry**: The Execution Badge now dynamically fetches and displays exact onboard RAM allocations alongside TOPS processing power.
*   **Accuracy in Retrieval Metrics**: Corrected UI labels to differentiate between semantic Database Matching (Vector Similarity) and active LLM reasoning thresholds.

---

## v4.0 & v4.1 - WWDC26 Apple Intelligence Update

OpenIntelligence version 4.0 & v4.1 is a major Apple Intelligence modernization and refinement pass currently live on the App Store. The release touches every major component of the user experience—from the local-first execution model to transparent citation details, visual evidence cards, and Siri/Shortcuts system integration.

This document consolidates this major release cycle into a single, cohesive user-facing log—highlighting the Apple Intelligence native foundation alongside a GPU-accelerated ingestion pipeline, Metal vector search performance, live reasoning telemetry, and database protection.

The practical user story is simple: **OpenIntelligence now does a better job showing what evidence it used, where it ran, and how much source support it found before you trust an answer.**

---

#### Why WWDC26 Matters Here

WWDC26 shifted the platform architecture by pushing core AI capabilities into system-level frameworks. For OpenIntelligence, this unlocked several important system resources:

*   **Apple Foundation Models**: Native `LanguageModelSession` instances, structured generation, token budgeting, and route-policy layers.
*   **Apple Private Cloud Compute (PCC)**: A secure cloud route for complex or context-heavy work, ensuring cryptographic privacy.
*   **App Intents & App Entities**: Integration with Siri, Shortcuts, and system services for reading, listing, and indexing documents.
*   **Visual Intelligence**: A platform route to import OCR and camera captures as active RAG evidence.
*   **Core Spotlight**: Deep system-level indexing of document chunks and sections.
*   **Core AI**: Execution pathways for local custom models.
*   **Liquid Glass**: A modern visual design system featuring responsive glass effects.

---

#### What Users Will Notice First

*   **Transparent Verification UI**: Responses are explicitly labeled so you can see if they are **Source-Locked** (fully supported by your documents), **Partially Supported**, or **Lacking Sufficient Evidence**.
*   **Model Routing Visibility:** The status pill in the header shows you exactly where your query is targeted to run: **On-Device** (standard questions) or **Private Cloud Compute** (complex or long-context questions, falling back locally if the build lacks the required cloud entitlement).
*   **Live Reasoning Telemetry**: You can watch the model's active thinking loop in real-time inside the bottom metrics bar as it organizes thoughts, resolves routing, and writes answers.
*   **Lag-Free Visual Transitions**: The processing dashboard and overlays transition smoothly using GPU-accelerated effects, eliminating visual stutter during document imports.
*   **4x Faster Local Vector Search**: Local vector similarity calculations run on Apple Silicon hardware accelerators using custom Metal pipelines, reducing RAG search latency by 4x.
*   **Clean Discarding & Deletion**: Canceling or deleting an in-progress import now triggers a cascading purge that completely removes file fragments, database records, and Spotlight search indexes, ensuring no orphaned data is left behind.
*   **Grammatically Correct Suggested Questions**: Suggested follow-up questions are grammatically clean and diverse across different sections of your library.

---

#### Key Improvements

#### 1. Smarter On-Device vs. Private Cloud Compute Routing
*   **Dynamic Policy:** Local execution is preferred for standard queries to protect battery life and latency. Heavy reasoning queries or large files are dynamically targeted to route to secure Private Cloud Compute, with automatic local fallback if the entitlement is not present.
*   **Under the Hood Details**: Tap the header status pill to open a popover detailing the active model name, token budget usage, and explanations of Apple's PCC privacy guarantees.
*   **Direct Route Metrics**: The status bar displays telemetry from the actual resolved routing engine rather than an estimation based on response latency.

#### 2. Grounded Answers and Citation Integrity
*   **GroundedAnswerView**: Presents cited answers clearly, making it easy to map each statement back to its specific source document.
*   **Visual Evidence Cards**: Image imports, camera scans, and PDF figures render inside the chat bubbles as OCR-derived evidence.
*   **Fidelity Status**: Clearly displays the verification level of every response, helping you decide how much to rely on the generated answer.

#### 3. Better Recovery When Generation Misbehaves
*   **Empty Response Fallback**: If a model returns an empty response, the RAG service now routes into a reliability fallback instead of treating the entire query as unavailable.
*   **Partial-Draft Preservation**: If streaming produced a useful partial answer before a failure, the app preserves that text instead of replacing it with an empty or generic failure result.
*   **Rate Limit Safeguards**: Rate-limited or concurrent Apple Foundation Model failures get a short retry path before falling through to recovery behavior.
*   **Stricter Grounding Repair**: Stricter repair pathways handle context overflow and missing citations, prompting abstention when grounding support is too weak.

#### 4. UI Telemetry & Render Optimizations
*   **Thinking Stream**: The `ThinkingStreamView` shows live feedback during reasoning phases so you are never left wondering if the app is frozen.
*   **GPU-Driven Overlay**: Ingestion overlay animations utilize hardware-accelerated opacity and scale transitions, preventing frames from dropping during heavy background indexing.
*   **Massive Document Stability**: Resolved a critical bug where opening the app after ingesting massive documents (e.g., HOA docs) caused an instant crash or UI freeze. Ingestion logs are now lazily loaded and capped to prevent unbounded memory allocation and excessive view generation on launch.

#### 5. Suggested Questions & Grammar Safeguards
*   **Diverse Suggestions**: The query planner isolates unique sections of your documents to guarantee follow-up questions cover a variety of topics.
*   **Grammar Filter**: Uses Apple's native language taggers (`NLTagger`) to analyze parts of speech and filter out OCR layout noise, verbs, or incomplete phrases from suggested prompts.

#### 6. GPU & Neural Engine (ANE) Pipeline Optimizations
*   **Adaptive Pre-Scan**: Automatically pre-scans documents before ingestion. Clean digital PDF pages bypass expensive Vision OCR pipelines completely, achieving up to a 20% processing speedup.
*   **GPU Resolution Scaling**: Scales document rendering resolution dynamically based on font size risk, reducing document parsing memory requirements on device silicon.
*   **Hardware Telemetry**: Integrates haptic and visual metrics feedback for Vision OCR, vector embedding generation, and LLM inference.

#### 7. Database Safety & Zero-Remnant Discarding
*   **Anti-Corruption Writes**: Vector database disk saves write to a contiguous memory buffer and replace database files atomically, preventing corruption if the app reloads during ingestion.
*   **Zero-Remnant Purge**: Deleting or discarding a document cleanly deletes all corresponding vector data, FTS5 database indices, Spotlight entries, and local files.
*   **Sync Tombstones**: Leverages deletion logs (`deleted_documents.json`) to prevent deleted documents from being revived during cross-device syncing.

#### 8. System Integrations: Spotlight, Siri, and Shortcuts
*   **Deep Spotlight Indexing**: System Spotlight search can search and index down to specific document chunks, sections, and figures.
*   **App Intents**: Persisted document and library entities are exposed to Siri and Shortcuts. You can ask Siri to summarize, compare, or search documents directly.
*   **Visual Intelligence OCR**: Captures image inputs and extracts their text as active evidence in the RAG pipeline.

#### 9. App-Wide UI, Onboarding, and Workflow Improvements
*   **Onboarding Progress**: Updated the checklist and imports dashboard to display live stages, extraction progress, vector generation counts, and a timer publisher for smooth elapsed-time tracking.
*   **Live Activities**: Integrated Live Activity support to show background import status directly on the lock screen and Dynamic Island.
*   **Sample Document**: Renamed the sample document to "OpenIntelligence Product Guide" to align with onboarding instructions.

#### 10. Retrieval, Summaries, and Evaluation Quality Gates
*   **Evaluations Framework**: Built a suite to measure retrieval recall, citation precision, exact-value accuracy, and hallucination rates against strict quality gates before updates are shipped.
*   **RAPTOR-Lite Routing**: Added summary routing to handle high-level document overviews by querying generated document summaries.

#### 11. Liquid Glass and Visual Polish
*   **Universal AppIcon**: Added a unified universal AppIcon configuration across iOS and macOS targets, resolving catalog build warnings.
*   **Visual density**: Standardized margins (14pt) and tighter corner radii for message bubbles (16pt) and cards (12pt) to create a denser, more cohesive Liquid Glass UI.

- **Model Preference Selector:** The original selector is superseded by v4.6’s persistent Hybrid, On-Device, and PCC policies. PCC fallback is now explicitly labeled rather than represented as PCC running locally.
