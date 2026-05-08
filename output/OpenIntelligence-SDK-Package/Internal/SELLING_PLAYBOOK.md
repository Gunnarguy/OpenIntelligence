# Selling Playbook

## Core Pitch

OpenIntelligence Engine is a private document-intelligence engine for Apple platforms.
It lets a product ingest customer documents locally, build a grounded knowledge layer, and answer questions with source-backed citations and trust signals.

What buyers are actually buying:

- ingestion and OCR cleanup
- chunking and indexing
- embeddings and retrieval
- reranking and grounded answer generation
- citation and evidence handling
- Apple Intelligence runtime handling on supported hardware

What they are not buying:

- a chat app
- consumer UI
- onboarding
- billing
- settings panels

## Best Buyer Profile

Best-fit teams:

- vertical SaaS companies with document-heavy workflows
- support and field-service tools with manuals and installation guides
- healthcare, legal, compliance, or operations apps with private knowledge bases
- teams that want Apple-native on-device document QA without building retrieval from scratch

Bad-fit buyers:

- teams that need a finished cross-platform web SDK immediately
- teams that require same-day drag-and-drop binary handoff today
- teams that want a hosted API instead of embedded Apple-native logic

## Positioning

Do say:

- private document intelligence engine
- grounded answers over private libraries
- workspace-isolated retrieval
- Apple-native and on-device first
- early-access engine with real working logic

Do not say:

- polished off-the-shelf SDK ready for immediate self-serve install today
- generic AI chatbot
- cloud RAG platform

## Library Feature Framing

Do not sell the concept as “library” unless the buyer already uses that word.
Sell it as workspace isolation.

Examples:

- one workspace per customer account
- one workspace per case or matter
- one workspace per product line
- one workspace per department
- one workspace per project

## Current Offer

Best commercial framing right now:

- private capability demo
- technical evaluation
- design-partner or pilot integration
- early access to the engine surface while binary packaging is finalized

What you send in that motion:

- `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`

This is the honest version of “we can start now” without overpromising the current XCFramework status.

## Exact Reference Map

Keep these exact paths ready during buyer conversations:

- buyer packet zip:
  - `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`
- packet root:
  - `output/OpenIntelligence-SDK-Package/`
- packet-local demo app:
  - `output/OpenIntelligence-SDK-Package/SampleApp/EngineEvaluationHost.xcodeproj`
- packet-local demo script:
  - `output/OpenIntelligence-SDK-Package/SampleApp/DEMO_SCRIPT.md`
- source-of-truth demo app in repo:
  - `Samples/EngineEvaluationHost/EngineEvaluationHost.xcodeproj`
- current engine entry-point code file:
  - `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
- engine inventory:
  - `EngineSale/ENGINE_INVENTORY.md`
- pipeline trace:
  - `Docs/STORAGE_AND_PIPELINE_TRACE.md`
- packaging blocker/status note:
  - `output/OpenIntelligence-SDK-Package/Internal/BUILD_NOTES.md`

If the buyer asks "what exactly is in the package?" point them first to:

- `output/OpenIntelligence-SDK-Package/START_HERE.md`
- `output/OpenIntelligence-SDK-Package/PACKAGE_SUMMARY.md`
- `output/OpenIntelligence-SDK-Package/API.md` for the simple explanation of how another app would use the engine
- `output/OpenIntelligence-SDK-Package/INSTALL.md`

## 60-Second Pitch

OpenIntelligence Engine is the Apple-native logic behind grounded document QA.
It ingests private files on-device, builds a workspace-scoped knowledge layer, and answers with citations and evidence-aware behavior instead of generic chat output.
If your app needs document intelligence on iPhone, iPad, or Apple Silicon without building the retrieval stack yourself, this is the engine layer.
Today, we can send a guided evaluation XCFramework packet, demo the real behavior, and start a guided integration. The sealed binary SDK handoff is still being finalized.

## 15-Minute Buyer Call Structure

1. Open with the problem: most teams do not want to build ingestion, chunking, retrieval, reranking, and grounded answer logic from scratch.
2. Position the engine: private document QA embedded inside their app.
3. Show the demo: ingest, query, citations, workspace isolation.
4. Translate to their product: explain what their users would see in their own branded UI.
5. Close on next step: pilot, technical evaluation, or early-access integration.

## Likely Buyer Questions

### What will users see?

Their own app UI.
The engine is embedded and powers document import plus question answering behind the scenes.

### Is this a full app?

No.
It is the engine layer behind the app behavior.

### Can it isolate multiple customer knowledge bases?

Yes.
That is the practical value of the current library or workspace concept.

### Is it ready as a binary SDK today?

Not fully.
A working evaluation XCFramework exists, the curated buyer packet can be generated today, and the sample host imports and builds against that artifact.
The final reproducible module-stable packaging path is still being finalized.

### So what can we do right now?

Send the buyer-safe evaluation packet, demo the real capability, scope a pilot, and prepare an early integration path while stable binary packaging is completed.

### What file should I show if they ask for proof?

Show the thing closest to the question:

- how another app would use the engine:
  - `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
- pipeline:
  - `Docs/STORAGE_AND_PIPELINE_TRACE.md`
- subsystem map:
  - `EngineSale/ENGINE_INVENTORY.md`
- packaging status:
  - `output/OpenIntelligence-SDK-Package/Internal/BUILD_NOTES.md`
- actual sendable artifact:
  - `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`

## What You Should Ask The Buyer

1. What kind of documents do your users actually upload?
2. Do you need one shared knowledge base or workspace isolation per tenant or case?
3. Do you need citations and trust review in the UI, or only answer text?
4. Is your target runtime iPhone, iPad, Apple Silicon Mac, or all three?
5. Are you evaluating this as a feature, a pilot, or a licensable engine?

## Next-Step Options

1. Live demo against their sample files
2. Pilot integration against a tiny host app
3. Early-access SDK conversation with guided support
