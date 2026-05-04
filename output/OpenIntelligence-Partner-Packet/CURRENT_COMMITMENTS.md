# Current Commitments

This is the honesty sheet for partner conversations.

## Safe To Say Now

- there is a working Apple-native document-intelligence engine in the repo
- the engine supports private document ingestion and grounded question answering
- the repo includes a small engine entry-point file another Apple app can call
- the repo includes a benchmark harness and evaluation tooling
- the current strongest offer is a founder-led evaluation, pilot, diligence, or handoff discussion
- the codebase is a substantial head start for Apple-device document QA

## Say Carefully

- the SDK boundary exists, but it is still evaluation-stage
- staged evaluation packet materials exist, but they do not equal a finished enterprise SDK
- local-first behavior is a real design goal and often true in practice, but execution mode and Apple-managed routing still matter
- verification and citations improve behavior, but do not guarantee correctness
- regulated-adjacent document evaluation may be interesting, but the repo is not ready for regulated decision-making use as-is

## Do Not Say Yet

- it is a finished enterprise SDK today
- it is production-ready for every document type and workflow
- it guarantees correctness
- it is HIPAA compliant
- it is ready for clinical, legal, safety, or IFU use
- it has Apple Foundation Models embeddings
- it has a public 65K Foundation Models context path
- it is full GraphRAG

## Best Current Offer

The best current offer is:

- technical evaluation
- design-partner pilot
- source-code diligence
- licensing or handoff discussion

The weakest current offer is:

- broad self-serve SDK sale as if packaging and validation were complete

## Exact Things You Can Point To

When a serious buyer asks "what is the actual thing?" use exact repo artifacts:

- buyer-safe evaluation zip:
  - `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`
- staged evaluation packet folder:
  - `output/OpenIntelligence-SDK-Package/`
- current public engine facade source:
  - `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`
- canonical engine inventory:
  - `EngineSale/ENGINE_INVENTORY.md`
- canonical pipeline trace:
  - `Docs/STORAGE_AND_PIPELINE_TRACE.md`
- current SDK boundary map:
  - `SDK_BOUNDARY_AUDIT.md`
- packet-local demo app project:
  - `output/OpenIntelligence-SDK-Package/SampleApp/EngineEvaluationHost.xcodeproj`
- source-of-truth demo project in the repo:
  - `Samples/EngineEvaluationHost/EngineEvaluationHost.xcodeproj`
- current packaging-status note:
  - `output/OpenIntelligence-SDK-Package/Internal/BUILD_NOTES.md`

## Exact Buyer Language

If the buyer asks what they are paying for, the safest concrete answer is:

- the engine code in this repo
- the small engine entry-point file another Apple app can call
- the retrieval, verification, and benchmark infrastructure
- the evaluation packet and sample host app
- founder-guided diligence, pilot, or handoff support
