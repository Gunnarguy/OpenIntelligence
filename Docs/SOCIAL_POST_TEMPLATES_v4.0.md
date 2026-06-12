# Social Media Post Templates: OpenIntelligence v4.0

Changes covered: commit `1702aef7dae510bafe7e28ffa7a53683aff61bc1` through `a4c70383ad60c22faab6a44135d289a15488396f`.

WWDC26 should be the lead angle. This release is an implementation pass on the things Apple changed, updated, or unlocked for app-level intelligence: Foundation Models, Private Cloud Compute, Evaluations, App Intents/App Entities, Visual Intelligence, Core Spotlight, Core AI, and Liquid Glass.

Project link: https://github.com/Gunnarguy/OpenIntelligence

---

## Full Pick-and-Choose Change Inventory

Use this as the raw menu. The posts below pull from it, but this is the broadest list of what changed.

### WWDC26 Platform Work

- Foundation Models moved from one large service toward a modular app runtime.
- `LanguageModelSession` creation is now separated from prompt compilation, tool registration, token budgeting, transcript handling, structured generation, error mapping, and route policy.
- Dynamic profile groundwork was added for direct chat, grounded RAG, extractive RAG, tool-calling RAG, source-only verification, summarization, query planning, and visual evidence QA.
- Private Cloud Compute is now represented as an explicit route, not a vague background possibility.
- `ContextOptions(reasoningLevel:)` is wired into the Foundation Models path for PCC reasoning levels.
- Core AI scaffolding was added for future local model work: model registry, execution backend, and embedding backend.
- SDK compatibility layers were added so newer iOS 26/WWDC26 APIs have safer compile-time fallbacks.

### Model Routing and Status

- Standard and exact lookup queries prefer the on-device path when possible.
- Deep Think, Maximum, and large-context requests can route to PCC when allowed, available, and within quota.
- Model route resolution now posts explicit active-route events.
- The model status pill now reflects real route state instead of relying on latency guessing.
- The Under the Hood popover explains active/last route, resolved model, and token-budget boundaries.
- PCC diagnostics scaffolding was added for route behavior, quota fallback, unavailable fallback, and Deep Think routing checks.

### Answer Quality and Source Support

- `GroundedAnswerView` was added for source-backed answer presentation.
- `SourceFidelityStatus` was added with Source-Locked, Partially Supported, and Not Enough Evidence states.
- Structured answer metadata now tracks claims, evidence IDs, citations, missing support, and abstention behavior.
- Visual evidence cards were added for OCR/image-derived context.
- Source-only verification can refine or abstain when generated text is not supported well enough.
- Response details and answer intelligence surfaces were updated around the new grounded answer model.
- Citation and evidence rendering was expanded so users can see the support behind an answer when they need to.

### Reliability and Recovery

- Empty model responses now route to reliability fallback instead of surfacing as a dead answer.
- Useful streamed partial answers can be preserved if generation fails late.
- The partial-output preservation threshold was lowered so shorter useful drafts can survive.
- Rate-limited and concurrent Foundation Models failures get a short retry path.
- Missing-citation, context-overflow, and malformed-response paths gained stricter repair, fallback, and abstention behavior.
- Thinking events were moved so session resets do not wipe useful processing feedback.

### Retrieval and RAG Runtime

- `QueryRuntimeCoordinator` was added to pull query mode, route policy, PCC eligibility, adaptive optimization, and response metadata out of the larger RAG flow.
- `RAGService` was updated around the coordinator while preserving the existing ingestion, retrieval, verification, and response finalization responsibilities.
- RAPTOR-lite summary routing was added for overview-style retrieval.
- Hybrid search now applies summary filtering for overview queries.
- Query enhancement, iterative retrieval, context packing, and confidence calibration were adjusted around the new runtime flow.
- RAG query metadata now carries execution route information.

### Evaluations and Diagnostics

- A RAG evaluation framework was added with JSONL-backed cases and datasets.
- Eval metrics now cover retrieval recall@5, citation precision, exact-value accuracy, unsupported-claim rate, correct abstention rate, and context overflow rate.
- Markdown and JSON report generation were added for eval runs.
- An Apple Evaluations bridge shape was added for future Apple/fm CLI-style workflows.
- Developer diagnostics gained route/evaluation-facing entry points.
- Deep Think trace and console artifacts were added for debugging/release analysis.

### Siri, Shortcuts, Spotlight, and Visual Intelligence

- Document and library App Entities were added.
- Entity queries now resolve persisted documents and libraries.
- Siri/Shortcuts workflows were expanded for asking documents, summarizing, comparing, searching libraries, listing documents, adding documents, and checking import status.
- Visual Intelligence image intents now OCR camera/photo inputs and pass extracted text into RAG as external evidence.
- Spotlight indexing now covers containers, documents, and document chunks/sections.
- Spotlight deindexing is tied into document/library removal paths.
- View annotation groundwork was added for richer system-facing UI context.

### App-Wide UI and UX Work

- ChatScreen was updated for route state, streaming behavior, and model status representation.
- Message bubbles and message lists were updated for the new grounded answer and event handling model.
- Live pipeline preview handling was simplified.
- UnifiedMetricsBar now includes thinking/reasoning feedback during processing.
- ResponseDetailsView, AnswerIntelligenceView, WritingToolsResultSheet, GroundedAnswerView, SourceFidelityStatus, and VisualEvidenceCard were added or updated around answer review.
- ModelStatusIndicator was redesigned around route colors, processing state, and the Under the Hood details card.
- DocumentLibraryView was refreshed around queue integration, empty states, layout, and library workflow polish.
- DocumentCard, EmptyDocumentsView, and StatsFooter were updated.
- OnboardingChecklistView now mirrors ingestion locally, uses a timer publisher, and shows more specific live pipeline stages.
- IngestionQueueOverlay was heavily refactored into a denser integrated queue/stats surface.
- ProcessingOverlay was removed.
- SettingsView was refreshed around the updated model/settings surfaces.
- DeveloperDiagnosticsHubView was expanded.
- Theme gained/tightened Liquid Glass helpers, spacing, typography, corner radii, and visual density.
- The app icon asset catalog was expanded across iPhone, iPad, and Mac sizes.

### Ingestion, Library, and Background Work

- Ingestion items now carry richer metrics and state.
- Ingestion queue persistence/restoration was improved.
- Ingestion metrics such as words processed, vectors generated, and chunking strategy are preserved more carefully.
- Import stages now show extraction, layout parsing, BM25 indexing, vector generation, summary generation, and tagging details.
- Live Activity attributes/services were updated for richer import progress state.
- The sample document was renamed from "OpenIntelligence Pricing" to "OpenIntelligence Product Guide."
- Workspace sync received queue/sync-related updates.

### Release, Docs, and Build Work

- Version/release metadata was updated for v4.0.
- Fastlane release automation and App Store release notes were updated.
- App Store release notes were trimmed to fit App Store Connect limits.
- Public changelog, What's New, release notes, architecture docs, retrieval pipeline docs, hard-limit docs, Apple model docs, and PCC docs were updated.
- WWDC26 implementation planning/reference documentation was added.
- Build settings and project metadata were updated for the v4.0/iOS 26 direction.

---

## 1. Best Default Launch Post

WWDC26 changed the technical direction for OpenIntelligence.

Apple gave app developers clearer primitives for system-level intelligence: Foundation Models, Private Cloud Compute, App Intents, Visual Intelligence, Core Spotlight, Evaluations, Core AI, and the new iOS 26 visual system.

I spent the last two days applying that direction to OpenIntelligence v4.0.

What I implemented:

- Split the Apple Foundation Models layer into smaller modules for sessions, tools, prompts, structured output, transcripts, token budgeting, errors, route policy, and dynamic profiles.
- Added explicit on-device vs. Private Cloud Compute routing for standard, Deep Think, Maximum, and large-context questions.
- Added an Under the Hood model route popover so users can see where the answer ran.
- Added grounded answer states: Source-Locked, Partially Supported, and Not Enough Evidence.
- Added visual evidence support so OCR/image-derived evidence can flow into RAG instead of sitting outside the answer.
- Added document/library App Entities and deeper Siri/Shortcuts workflows.
- Expanded Spotlight indexing down toward chunks and sections.
- Added a RAG evaluation framework for recall, citation precision, exact-value accuracy, unsupported claims, abstention, and context overflow.
- Reworked UI across chat, answer review, model status, Documents, onboarding, ingestion queue, settings, diagnostics, the design system, and app icons.

The goal is a stronger document workflow: clearer answers, clearer source support, clearer model routing, and less ambiguity when the app handles harder questions.

Open source:
https://github.com/Gunnarguy/OpenIntelligence

#WWDC26 #AppleIntelligence #SwiftUI #RAG #OpenSource

---

## 2. Apple Unlocked X, I Built Y

The best way to explain OpenIntelligence v4.0 is:

WWDC26 set the architecture. I implemented the first OpenIntelligence pass.

- Foundation Models became the runtime target, so I split the model layer into session, prompt, tool, transcript, structured generation, token budget, and route-policy modules.
- Private Cloud Compute became a real route for complex work, so I added explicit routing and UI transparency around on-device vs. PCC execution.
- Evaluations became a serious AI development path, so I added a RAG eval suite for retrieval, citations, exact values, abstention, unsupported claims, and context overflow.
- App Intents and App Entities became the system bridge, so I modeled documents and libraries as native entities for Siri and Shortcuts.
- Visual Intelligence became an input surface, so I started routing image/OCR evidence into the answer pipeline.
- Core Spotlight became more important, so I expanded indexing toward chunks and sections.
- Core AI became the future local-model layer, so I added the registry/backend scaffolding.
- Liquid Glass became the system design direction, so I updated the app's visual components around native iOS 26 glass effects.

This release moves OpenIntelligence toward an Apple Intelligence-native evidence system.

Code:
https://github.com/Gunnarguy/OpenIntelligence

#WWDC26 #AppleIntelligence #iOSDevelopment #Swift #RAG

---

## 3. User-Focused LinkedIn Post

OpenIntelligence v4.0 is built around the WWDC26 Apple Intelligence shift.

The user-facing result is simple: the app now explains itself better.

Users can see:

- whether an answer is fully source-backed, partially supported, or not supported well enough
- whether the model route stayed on device or used Apple Private Cloud Compute
- what sources and visual evidence were used
- what the import pipeline is doing while documents are being processed
- when the app should preserve a useful partial answer instead of replacing it with an empty failure

Behind that is a lot of WWDC26 integration work: Foundation Models modularization, route policy, App Entities, Siri/Shortcuts support, Visual Intelligence OCR evidence, chunk/section Spotlight indexing, a RAG eval framework, Core AI scaffolding, and Liquid Glass UI updates.

This keeps the core workflow simple while making the answer trail stronger when users need to verify something.

OpenIntelligence is open source here:
https://github.com/Gunnarguy/OpenIntelligence

#AIUX #AppleIntelligence #WWDC26 #SwiftUI #OpenSource

---

## 4. Technical LinkedIn Post

I just finished a two-day WWDC26 implementation pass on OpenIntelligence v4.0.

This was not a small UI refresh. The audited range covered 18 commits, 126 files, about 9.5k insertions, and 3.1k deletions.

The main work:

- Decomposed the Apple Foundation Models layer into focused modules for session creation, prompt compilation, structured generation, tool registration, transcript trimming, token budgeting, error mapping, route policy, and dynamic profile mapping.
- Added explicit on-device vs. Private Cloud Compute routing based on query type, estimated context size, PCC permission, availability, and quota state.
- Moved model route state into a real resolution service so the UI can show the actual route instead of guessing.
- Added grounded answer UI: source fidelity states, visual evidence cards, structured answer metadata, and clearer citation rendering.
- Hardened RAG generation against empty responses, rate limits, interrupted streams, missing citations, and context overflow.
- Added RAPTOR-lite summary routing for overview-style retrieval.
- Added a RAG evaluation framework for JSONL test cases, recall@5, citation precision, exact-value accuracy, unsupported-claim rate, abstention rate, and context overflow tracking.
- Expanded Siri/Shortcuts/App Intents with persisted document and library entities.
- Expanded Spotlight indexing around documents, chunks, and sections.
- Added Core AI backend scaffolding for future local model work.
- Reworked UI across chat, message rendering, answer review, model status, Documents, onboarding, ingestion queue, settings, diagnostics, the design system, and app icon assets.

The release direction is Apple Intelligence-native evidence: route-aware, source-aware, system-integrated, and cleaner across the app.

Code:
https://github.com/Gunnarguy/OpenIntelligence

#Swift #SwiftUI #WWDC26 #AppleIntelligence #RAG #OpenSource

---

## 5. Trust and Evidence Angle

WWDC26 gave Apple-platform apps a stronger AI foundation.

For OpenIntelligence, the priority was trust.

The product goal is stronger trust without making the workflow heavier.

So v4.0 adds:

- explicit on-device vs. Private Cloud Compute routing
- route transparency in the UI
- Source-Locked, Partially Supported, and Not Enough Evidence answer states
- visual/OCR evidence cards
- safer recovery when generation fails late or returns empty text
- evaluations for retrieval, citation, exact-value, abstention, and unsupported-claim behavior
- deeper Siri, Shortcuts, Spotlight, and Visual Intelligence integration
- app-wide UI updates across chat, answer review, Documents, onboarding, settings, diagnostics, and model status

OpenIntelligence should make the answer, the route, and the supporting evidence feel clear without adding friction.

Open source:
https://github.com/Gunnarguy/OpenIntelligence

#AIUX #WWDC26 #RAG #AppleIntelligence #ProductEngineering

---

## 6. Builder Story Post

I spent two days on OpenIntelligence v4.0, and the core question was:

What did WWDC26 make possible that the app should actually use?

The answer was:

- use Foundation Models as the runtime boundary
- route complex work through PCC when allowed and available
- turn documents and libraries into App Entities
- let Visual Intelligence/OCR inputs become evidence
- index more specific document content with Spotlight
- measure RAG quality with evals
- prepare for Core AI local model execution
- update the app-wide interface around chat, answer review, Documents, onboarding, ingestion, settings, diagnostics, model status, and iOS 26 visual patterns

OpenIntelligence v4.0 is the first pass at that: stronger answers, clearer routing, broader system integration, and a cleaner app-wide UI.

Code:
https://github.com/Gunnarguy/OpenIntelligence

#IndieDev #WWDC26 #SwiftUI #AppleIntelligence #OpenSource

---

## 7. X / Threads Single Post

OpenIntelligence v4.0 is my WWDC26 implementation pass.

I mapped Apple's new AI direction into the app: Foundation Models modularization, on-device/PCC routing, App Entities, Visual Intelligence OCR evidence, Spotlight chunk indexing, RAG evals, Core AI scaffolding, app-wide UI updates, and Liquid Glass styling.

https://github.com/Gunnarguy/OpenIntelligence

---

## 8. X / Threads User Single Post

OpenIntelligence v4.0 makes document answers clearer and easier to trust.

WWDC26 gave the app better Apple-native primitives. I used them to improve source support, model routing, visual evidence, answer recovery, system integration, and the UI across chat, answers, Documents, onboarding, settings, and diagnostics.

Clearer answers. Stronger evidence. Better Apple system integration.

https://github.com/Gunnarguy/OpenIntelligence

---

## 9. X / Threads Technical Single Post

Two-day WWDC26 pass on OpenIntelligence v4.0:

- Foundation Models layer split into focused services
- dynamic on-device/PCC route policy
- grounded answer + citation UI
- Visual Intelligence OCR evidence
- chunk/section Spotlight indexing
- document/library App Entities
- RAG eval suite
- Core AI scaffolding
- partial-draft recovery
- app-wide UI refresh

https://github.com/Gunnarguy/OpenIntelligence

---

## 10. X Thread

1/ I spent the last two days applying WWDC26 Apple Intelligence changes to OpenIntelligence v4.0.

Most of the work was architectural.

2/ Apple unlocked a better app-level AI stack:

Foundation Models, Private Cloud Compute, Evaluations, App Intents/App Entities, Visual Intelligence, Core Spotlight, Core AI, and Liquid Glass.

3/ I started with Foundation Models.

The old model path was too monolithic, so I split it into session creation, tool registration, prompt compilation, structured generation, transcript storage, token budgeting, error mapping, route policy, and dynamic profile mapping.

4/ Then I made routing more explicit.

Standard/exact lookups prefer on-device execution when possible. Deep Think, Maximum, and large-context questions can route to Apple Private Cloud Compute when allowed and available.

5/ The UI now explains that route.

The model status surface can show whether the active/last query ran locally or through PCC, instead of making users guess.

6/ The answer UI also got more honest.

Answers can now be labeled:

- Source-Locked
- Partially Supported
- Not Enough Evidence

7/ Visual Intelligence now has a path into RAG.

Image/camera inputs can be OCR'd and passed into the answer pipeline as evidence instead of sitting outside the document workflow.

8/ Siri and Shortcuts got a better content model too.

Documents and libraries now have App Entity support, with workflows for asking, summarizing, comparing, searching, listing, adding, and checking import status.

9/ I also added eval infrastructure.

The app can now measure retrieval recall, citation precision, exact-value accuracy, unsupported-claim rate, abstention behavior, and context overflow.

10/ The UI work was broader than a single screen.

I updated chat, message rendering, answer review, model status, Documents, onboarding, ingestion queue, settings, diagnostics, design-system helpers, and app icons.

11/ The goal: OpenIntelligence should become an Apple Intelligence-native evidence system.

Local when possible. PCC when needed. Evidence visible either way.

https://github.com/Gunnarguy/OpenIntelligence

#WWDC26 #AppleIntelligence #SwiftUI #RAG #OpenSource

---

## 11. App Store / Product Copy Variant

OpenIntelligence 4.0 is a WWDC26 Apple Intelligence modernization release.

This update adds smarter on-device vs. Private Cloud Compute routing, clearer source fidelity states, visual evidence support for OCR/image inputs, deeper Spotlight/Siri/Shortcuts integration, better import and library progress surfaces, app-wide UI updates, a RAG evaluation framework, Core AI scaffolding, Liquid Glass styling, and safer recovery when model generation returns empty or interrupted output.

The result is a stronger document workflow from import to answer review, with clearer source support and better Apple system integration.

---

## 12. No-Hype Plain Version

I shipped OpenIntelligence v4.0.

This update is mostly about applying the WWDC26 Apple Intelligence direction to the app in a real way.

I split up the Foundation Models layer, added route-aware on-device/PCC behavior, made source support more visible, added visual evidence handling, expanded Spotlight/Siri/Shortcuts integration, added RAG evals, started Core AI scaffolding, improved answer recovery, and updated UI across chat, answer review, Documents, onboarding, ingestion, settings, diagnostics, model status, app icons, and the iOS 26 Liquid Glass design system.

This took two days of focused implementation and touched most of the core document-answering path.

Code:
https://github.com/Gunnarguy/OpenIntelligence
