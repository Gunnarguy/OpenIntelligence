# OpenIntelligence v4.0 User-Facing Changelog

Changes covered: commit `1702aef7dae510bafe7e28ffa7a53683aff61bc1` through `a4c70383ad60c22faab6a44135d289a15488396f`.

Version 4.0 is a major WWDC26 Apple Intelligence modernization pass. The work touches the model-routing layer, answer verification UI, chat experience, document library, onboarding, ingestion queue, settings, diagnostics, Siri/Shortcuts integration, Spotlight indexing, visual evidence handling, evaluation infrastructure, app icons, and the app's overall visual system.

The practical user story is simple: OpenIntelligence now does a better job showing what it used, where it ran, and how much source support it found before you trust an answer.

---

## Why WWDC26 Matters Here

WWDC26 changed what an Apple-platform document AI app can reasonably be. Apple pushed more AI capability into system-level frameworks instead of leaving every app to build isolated, one-off AI plumbing.

For OpenIntelligence, the important WWDC26 unlocks were:

- **Foundation Models as a real app runtime**: `LanguageModelSession`, native tools, structured generation, transcript handling, dynamic profiles, provider-aligned model routing, and better context/reasoning controls.
- **Apple Foundation Models on Private Cloud Compute**: a larger secure route for complex or context-heavy work when the user allows it and the route is available.
- **Evaluations**: a more formal way to measure AI behavior instead of relying only on manual testing.
- **App Intents and App Entities**: a path for Siri, Shortcuts, and Apple Intelligence to understand app content like documents and libraries.
- **Visual Intelligence**: a system route for image/camera inputs to become actionable evidence.
- **Core Spotlight**: a system indexing layer that can expose more specific document content outside the app.
- **Core AI**: a future local execution layer for custom on-device models such as rerankers, classifiers, extractors, and embedding helpers.
- **Liquid Glass**: a new system visual language for iOS 26-era interfaces.

What I implemented in v4.0 is the first pass at moving OpenIntelligence toward that architecture: an Apple Intelligence-native evidence system.

---

## What Users Will Notice First

- Answers are more transparent: the app now separates source-locked answers from partially supported answers and not-enough-evidence cases.
- The model route is visible: the status pill can show whether the last/active query ran locally or through Apple Private Cloud Compute when that route is allowed and available.
- Imports feel less opaque: the onboarding/import surfaces show live stages, timers, and more specific processing details instead of a generic spinner.
- Camera and image-based evidence is treated more seriously: OCR text, regions, and barcode-style evidence can be carried into the answer pipeline as first-class evidence.
- Siri, Shortcuts, and Spotlight integration are deeper: documents, libraries, and indexed chunks are easier to discover and act on from system surfaces.
- The app is now organized around the WWDC26 direction: local-first where possible, secure PCC when needed, and evidence visible either way.

---

## 1. Smarter On-Device vs. Private Cloud Compute Routing

OpenIntelligence now has a clearer routing policy for Apple Foundation Models:

- Exact lookups and standard questions prefer the on-device path when possible.
- Deep Think, Maximum, and large-context questions can route to Private Cloud Compute when the user setting allows it, PCC is available, and quota is not exhausted.
- The "Under the Hood" model status popover explains the active/last route, resolved model, and token-budget boundary instead of leaving users guessing.
- The app no longer relies on a rough latency guess to describe the route; it listens for the resolved execution path.
- The Foundation Models implementation was split into smaller pieces for sessions, tools, prompts, structured output, transcript state, token budgets, route policy, and dynamic profiles.

Why it matters: users can ask harder questions while the app chooses a route that better matches the request.

---

## 2. Grounded Answers and Citation Integrity

The answer surface now makes source support visible instead of hiding it behind generic confidence language:

- `GroundedAnswerView` presents verified answer text with clearer source mapping.
- `SourceFidelityStatus` labels answers as Source-Locked, Partially Supported, or Not Enough Evidence.
- `VisualEvidenceCard` can show OCR/image evidence in the chat flow.
- Structured answer metadata tracks claims, evidence IDs, citations, missing support, and abstention behavior.
- Source-only verification can refine or abstain when a generated answer is not backed well enough.

Why it matters: users can see whether an answer is backed by the library, partly inferred, or based on evidence that is too thin.

---

## 3. Better Recovery When Generation Misbehaves

Several reliability changes protect users from blank or degraded answers:

- If a model returns an empty response, the RAG service now routes into a reliability fallback instead of treating the entire query as unavailable.
- If streaming produced a useful partial answer before a failure, the app can preserve that text instead of replacing it with an empty or generic failure result.
- Rate-limited or concurrent Apple Foundation Model failures get a short retry path before the app falls through to other recovery behavior.
- Context overflow and missing-citation cases have stricter fallback handling, including evidence-pack style recovery and abstention when grounding is not strong enough.

Why it matters: a late model hiccup is less likely to erase the useful answer the user already saw forming.

---

## 4. System Search, Siri, Shortcuts, and Visual Intelligence

OpenIntelligence now connects more of the document workflow to Apple system surfaces:

- Spotlight indexing now reaches document chunks/sections, so system search can surface more specific document content instead of only whole files.
- App Intents now expose document and library entities backed by persisted app data.
- Siri/Shortcuts actions include asking documents, summarizing documents, comparing documents, searching a library, listing documents, adding documents, and checking import status.
- Visual Intelligence/image intents can extract OCR text and pass it into RAG as external evidence.
- View annotation and App Entity groundwork makes the app better aligned with Apple Intelligence-style interaction, where system features can understand app content and actions instead of only launching the app.

Why it matters: users can start from the system surface they are already using instead of always opening the app first.

---

## 5. App-Wide UI and Workflow Improvements

The release refreshes the places where users ask, read, verify, import, manage, and diagnose:

- Chat and message surfaces were updated around route state, streaming behavior, grounded answers, and live event handling.
- Answer review was expanded with `GroundedAnswerView`, `SourceFidelityStatus`, `VisualEvidenceCard`, `ResponseDetailsView`, and `AnswerIntelligenceView` changes.
- The model status indicator was redesigned around route colors, active/last execution path, processing state, and the Under the Hood details card.
- The metrics bar now shows thinking/reasoning feedback during processing.
- Documents and library surfaces were updated through `DocumentLibraryView`, `DocumentCard`, `EmptyDocumentsView`, and `StatsFooter`.
- The old `ProcessingOverlay` was removed in favor of the integrated ingestion queue/checklist surfaces.
- Onboarding now uses local state and a timer publisher for smoother live progress updates.
- Import stages now show clearer details for extraction, layout parsing, BM25 indexing, vector generation, summaries, and tagging.
- Ingestion metrics are preserved more carefully, including words processed, vectors generated, and chunking strategy.
- The bundled sample document was renamed from "OpenIntelligence Pricing" to "OpenIntelligence Product Guide" to better match what users are learning from it.
- Settings and diagnostics were refreshed around the new routing/model surfaces.
- The design system gained/tightened Liquid Glass helpers, spacing, typography, corner radii, and visual density.
- The app icon asset catalog was expanded across iPhone, iPad, and Mac sizes.

Why it matters: the app feels more complete across the full loop: ask a question, watch it process, review the answer, verify sources, import more material, and manage the library.

---

## 6. Retrieval, Summaries, and Evaluation Quality Gates

The underlying retrieval system gained more structure:

- RAPTOR-lite summary routing helps overview-style questions use generated document summaries where appropriate.
- Query enhancement, hybrid search, iterative retrieval, and confidence calibration were updated around the new runtime flow.
- A new evaluations suite can run JSONL datasets and report retrieval recall, citation precision, exact-value accuracy, unsupported-claim rate, abstention behavior, and context overflow rate.
- Developer diagnostics now include a PCC route evaluator for route behavior checks.

Why it matters: the app now has a clearer way to validate whether retrieval and citations are improving instead of relying only on manual spot checks.

---

## 7. Liquid Glass and Visual Polish

The UI was refreshed around a cleaner iOS 26-style visual language:

- Native glass-card styling was added to core surfaces.
- Spacing, typography, corner radii, and density were tightened.
- The model status indicator has clearer route colors, processing state, and an explanatory details card.
- The chat surface now shows live thinking/reasoning feedback in the metrics area during processing.
- The app icon asset catalog was expanded across iPhone, iPad, and Mac sizes.
- Public release notes, changelogs, App Store metadata, and technical docs were updated for v4.0.

Why it matters: the app feels more current, and the visual polish is tied to real product surfaces.
