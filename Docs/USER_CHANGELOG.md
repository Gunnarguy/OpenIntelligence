> **Documentation status:** Source-verified for OpenIntelligence v5.0 on August 11, 2026. The v5.0 entries below were each checked against the code that implements them. Anything device-only, including Private Cloud Compute behaviour and the library management screens added late in v5.0, is build-verified rather than device-verified and is called out where it matters.


# OpenIntelligence User-Facing Changelog

This document provides a chronological history of user-facing changes, highlighting how OpenIntelligence continuously improves transparency, speed, and reliability.

---

## v5.0 - August 10, 2026
Importing a document was quietly losing parts of it. This release finds the places that happened.

### Speed
- **The source chips under an answer scroll properly now.** They used a custom press handler that fought the sideways scroll, so swiping across them sometimes registered as a tap instead. They look and respond exactly the same, they just no longer argue with the scroll.
- **Leaving the chat tab no longer kills the answer you were waiting for.** Switching to Documents mid-answer and coming back used to cancel it and discard everything written so far, with nothing to tell you why. The answer now keeps going while you look at something else.
- **The chat no longer loses your place.** Scrolling up to re-read an older answer and switching tabs used to slam you back to the newest message on return. It now stays where you left it, and still follows along automatically when you are reading the latest.
- **Atlas keeps showing what it already worked out.** Re-opening the tab replaced the whole page with a loading spinner while it recalculated the same result. It now leaves the existing view up until the new one is ready.
- **Answers stream more smoothly.** While an answer was arriving, the app re-formatted the entire text from scratch up to fifty times a second, on the same thread that draws the screen. Formatting now happens once, when the answer finishes. The finished answer looks exactly the same, and text stops flickering as half-finished bold and code blocks resolve.
- **Opening the Atlas tab did its work twice.** Two separate triggers were both starting the same analysis. Now one does.

### Libraries
- **Every action above your documents is now one tap.** Add, search, library settings, emptying a library and deleting one were two buttons and a three-dot menu hiding the rest. They are now five icons on a single row, nothing hidden. VoiceOver still reads each one's full name, including which library a delete would affect, and both delete actions still ask you to confirm and still tell you exactly what will go.
- **Press and hold on a library now behaves like the rest of iOS.** It was using a custom gesture that competed with sideways scrolling, so holding a library sometimes scrolled the row instead and nothing told you which one was about to happen. It now uses the standard press-and-hold menu, with the usual preview and haptic.
- **Creating a library no longer suggests a name you already have.** The suggested name was based on how many libraries you had rather than what they were called, so after deleting one, the next suggestion could collide with a library still on screen. Accepting it left you with two libraries sharing a name.

### Your Documents

*   **Tables in Word documents were being thrown away.** Each one was read into rows and then dropped, so a document could import looking fine with all of its numbers missing.
*   **Images keep their layout.** Every image became one unbroken line of text before anything downstream could read it.
*   **Photographing a page now matches importing it.** Camera captures came out as flat text where the same page imported as table cells.
*   **Scanned pages report their scanning honestly.** A fully scanned PDF used to tell you it had scanned zero pages.
*   **A page the parser knew it had read badly is no longer repaired and then discarded.**
*   **PDFs with figures but no tables keep their figures.**
*   **Pages, Numbers and Keynote files now fail clearly.** They were never actually readable; importing one no longer looks like it worked.

### Answers

*   **Search ranks section headings again.** A weighting mistake had dropped section paths out of ranking entirely.
*   **Evidence that retrieval had already found is no longer discarded** when sentence extraction matches nothing.
*   **Long questions can now reach Private Cloud Compute.** They were being kept on device precisely when they were too big for it.

### Your Sample Documents

*   **The three sample documents described things the app cannot do.** They claimed Pages, Numbers and Keynote support, credited the wrong framework, and documented a screen that does not exist. The app answers questions out of those documents, so a wrong sentence became a wrong answer.
*   **If you already had them, they update themselves once.** You will see a short re-import the first time you open Documents, and a notice explaining it. Nothing you imported yourself is touched, and samples you deleted stay deleted.

### Settings

*   **Settings is a searchable list instead of one long scroll.** Fifteen stacked panels became about ten rows in sections. Nothing was removed. Type "temperature" and you land on it.
*   **The generation controls are reachable.** Temperature and response length were built with no way into them. Settings → Advanced, one tap. Both work on device and on Private Cloud Compute.
*   **You can choose how the model picks its words.** Top-K, Top-P or Greedy. The app used to decide for you and always picked the same one, so the Top-P slider did nothing. Unchanged unless you change it.
*   **Answers can be made reproducible.** Turn on "Reproducible answers" and the same question against the same library returns the same answer every time. Useful if you are checking work, or comparing two libraries fairly.
*   **Controls that never affected Apple Intelligence now say so.** The three penalty sliders apply to a self-hosted model, not to on-device or Private Cloud Compute answers.
*   **Five switches that did nothing are no longer switches.** Writing Tools, Speech Analysis, Translation, Screen Awareness and Image Playground are real and always on. The toggles never controlled them.

### Every Word, Explained Where You Read It

*   **Tap any figure the app shows you and it tells you what it means.** "38 TOPS", "32/batch", "768 search", "Chunks", "Vectors". Where they already are, without leaving the screen.
*   **Two explanations for each, not one.** A plain one first, and the mechanism underneath if you want it. Turn the technical version on once and it stays on everywhere.
*   **The four import stages explain themselves while they run.** Extract, Chunk, Embed and Index are all tappable during the import you watch on first launch.
*   **Nothing is buried.** Settings has the full list under Plain English, searchable, including by the technical name if that happens to be the word you know.

### Your Libraries

*   **"Remove Local Copies" is now "Remove All Documents", because that is what it did.** It never only removed local copies. It deleted those documents from iCloud and from your other devices too, while telling you Sync Now could bring them back. It could not. The wording now says what happens, and names the library it applies to.
*   **Deleting one document said the same untrue thing,** and its button is now just "Delete".
*   **Emptying a library used to leave things behind.** The documents stayed in Spotlight search, and their files stayed on disk taking up space. Both are cleaned up now.
*   **Moving a library off iCloud asks first.** One tap used to remove that library's copy from iCloud with no warning at all.
*   **The Documents toolbar no longer hides half its buttons off the edge of the screen.** Library Settings, and the two destructive actions, now live in one menu you can see. Visualize is gone from that row, because it only switched you to the Atlas tab that is already at the bottom of the screen.
*   **Two libraries with the same name can be told apart** by a short code on the chip.
*   **Library chips in Semantic Search no longer show storage buttons that did nothing.**

### Your Database Tab

*   **You can look at any library from here.** It used to offer only "All Libraries" or whichever library happened to be active, so seeing a different one meant going to Documents, switching, and coming back. Every library is now in one menu.
*   **"All Libraries" actually shows all of them.** The document list underneath used to show only the active library no matter what you picked, and never said which library you were looking at. It says now.

### Library Settings

*   **Changing the embedding model no longer wipes your vectors before you agree to rebuild them.** It deleted them at Save, then asked, and choosing "Later" left the library holding documents it could not search.
*   **The chunk size sliders now stop where the app actually stops.** They went up to 600 words and 200 overlap while importing quietly capped them at 260 and 50, so over half of each slider did nothing. If you had set 400, you were already getting 260.
*   **The chunk size controls now say you should not touch them.** The app already picks a chunk size from the kind of file you imported, smaller for code, larger for reports and transcripts. Setting these by hand replaces that with one size for everything in the library.
*   **Two descriptions on that screen were not true.** One said chunks are split by comparing meaning between sentences; that never runs. It splits on section headings and a fixed list of ten English phrases, and the screen says so now, including that the list is English only. The other described the storage format the app stopped using.

*   **Deleting a library from its settings screen no longer half-works.** If iCloud refused the delete, that screen used to remove the library from this device anyway, so the next sync brought it back and you were left thinking it was gone. It now stops, keeps the library, and tells you why.

*   **The two destructive actions no longer look like the same button.** They sat next to each other, both red, both a bin icon, and one empties a library while the other removes it. They are now "Remove All Documents from X" and "Delete the X Library", with different icons and a divider between them.
*   **"Cached Documents" is hidden until there is something in it.** It was always empty, because the feature that would fill it has not been built yet.

*   **On a Mac, a Shortcut running in the background could send a question to Apple's Private Cloud Compute with nobody there to approve it.** The check that requires you to be looking at the app was only ever running on iPhone and iPad. It runs on Mac now.
*   **A question is no longer sent to the cloud when the app cannot tell how much cloud quota is left.** It now answers on this device instead of guessing.

### Things The App Was Claiming That Weren't True

Settings describes what the app is doing while it answers you. Several of those lines described
things the code does not do, so they are gone or corrected.

*   **Settings listed eight agentic tools, and all eight were the wrong ones.** Four tools are actually wired up. Those four are now what it names.
*   **Two advertised features did not exist,** and are no longer advertised.
*   **The model picker listed a tier the app cannot select.**
*   **Speed figures that were never measured have been removed,** including from the sample documents the app reads back to you as fact. Where the underlying work was real, it is now described by what it does instead of by a number.
*   **Every remaining capability line was checked against the code that would have to run it.**

### The App Itself

*   **Your device is identified correctly.** iPhone 17 and M5 hardware reported itself as "A12 or Older" with limited performance.
*   **The first screen no longer cuts off its own text.** Half the headline and all three example questions were being truncated.
*   **The chat controls match each other, and the mode menu explains itself.** It also shows which mode is active, and how many Maximum runs you have left before you pick it.
*   **The hardware readout follows a live answer** and no longer stays lit after you stop one.
*   **The screen readers can reach the hardware panel properly.** Its figures used to be read as one long block; each one is now its own element with its own definition.
*   **Answers that ended in bold or italic text no longer come out broken.** The last two characters were being cut off, which left the formatting unclosed and bled it into the rest of the screen. The clearest case was the notice you get when an answer could not be verified: its closing bracket was always missing.
*   **The embedding view no longer claims your vectors have 512 numbers when they have 384.** It reads the real number from the library you are looking at, which differs depending on which embedding model that library was built with.

## v4.9 - August 2, 2026
Documents no longer disappear after importing, and libraries carry their work between devices instead of asking you to redo it.

### Your Libraries

*   Fixed documents disappearing shortly after import. A document that finished importing while the app was saving your library could be dropped from the list, even though it had imported correctly. This affected a single device as well as several, and it is what made the sample documents unreliable.
*   Documents processed on one device no longer need re-importing on another.
*   Libraries no longer appear to lose documents while iCloud is still catching up.

> iPhone and iPad are coming from v4.7, so everything under v4.8 below ships here too. On Mac, v4.8 was already released, so only this section is new.

## v4.8 - July 31, 2026
Deep Think and Maximum were not wired up correctly in previous releases. This release fixes that, and everything it uncovered.


### Deep Think And Maximum

*   Both modes now reason across your documents. Previously they returned Standard quality answers after a much longer wait.
*   Answers cite their sources in every mode. Maximum produced none at all.
*   Both stop once they stop finding new material, typically halving Maximum's run time.
*   A single failed pass no longer ends a query.
*   Resolved "The selected model isn't available right now."
### Privacy And Routing

*   On-Device now covers the entire query, including the final answer.
*   The model picker governs every mode. It previously reached Standard only, so Deep Think and Maximum fell back to a default.
### What You See

*   The live pipeline names each stage correctly, including verification and query rewriting.
*   Reasoning detail wraps instead of cutting off mid-sentence.
*   Follow-up suggestions come from the answer rather than stray words.
*   Raw model output no longer appears in answers.
*   Passes skipped for having no relevant text are shown instead of leaving gaps.
*   An answer reporting that your documents do not cover something is kept, not replaced with generic help text.
### Also

*   Document import works on Mac. The file picker there was a placeholder.
*   Opening the app after an update now shows what changed.

## v4.7 - July 28, 2026

*   **Honest Route Labels:** Labels now say exactly where each answer ran: on your device, or Apple Private Cloud Compute with your permission. Nothing claims more than the system can verify.
*   **Steadier Document Understanding:** The key ideas pulled from your documents now come out the same every time, for more consistent search and more reliable connections across files.
*   **Route Verification:** New internal checks confirm that every answer's recorded route matches what actually ran.
*   **Removed Unsupported Model Claims:** Settings no longer advertises selectable 3B or 20B on-device models, or a parameter-count based capability chip. (Correction to earlier releases: the public SDK exposes no such selector. Apple's larger on-device model is real and managed by the operating system, but no app can choose or observe it.)

## v4.6 - July 15, 2026

*   **Smarter Private Cloud Compute Decisions:** Queries now retrieve evidence locally before choosing a model route. PCC is used only when the final evidence and context budget justify secure cloud synthesis; missing evidence never causes escalation.
*   **Exact Cloud Consent:** The confirmation sheet describes why PCC was selected and shows the size of the minimized evidence payload that would be transmitted. Background actions never wait on a hidden consent prompt.
*   **Model Choice That Stays Put:** Hybrid, On-Device, and PCC now describe the policy you selected, not whichever route happened to run last. Hybrid remains selected after a PCC answer and after relaunch.
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

*   **Rust-Backed Tokenizer Engine:** Replaced the legacy pure-Swift tokenizer with a highly optimized Rust-backed `swift-tokenizers` engine. This delivers much faster document tokenization and exact byte-level character offset tracking for citations. *(A "100x speedup" was quoted here originally; it was never measured and was withdrawn 2026-08-06.)*
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
*   **Instant Library Scrolling**: Fixed a scroll-lag issue when browsing large libraries, by caching row identifiers instead of recomputing them on every row draw.
*   **Faster Answer Generation**: Rebuilt the context aggregation math so deduplicating large evidence sets no longer slows down as the library grows. Answers generate substantially faster.
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

OpenIntelligence version 4.0 & v4.1 is a major Apple Intelligence modernization and refinement pass currently live on the App Store. The release touches every major component of the user experience, from the local-first execution model to transparent citation details, visual evidence cards, and Siri/Shortcuts system integration.

This document consolidates this major release cycle into a single, cohesive user-facing log, highlighting the Apple Intelligence native foundation alongside a GPU-accelerated ingestion pipeline, Metal vector search performance, live reasoning telemetry, and database protection.

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
*   **GPU-Accelerated Local Vector Search**: Local vector similarity calculations run on Apple Silicon hardware accelerators using custom Metal pipelines. *(A "4x" figure was quoted here originally; it was never measured and was withdrawn 2026-08-06.)*
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
