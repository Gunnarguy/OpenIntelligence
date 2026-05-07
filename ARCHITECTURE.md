# OpenIntelligence Architecture

Version 2.0

This is the public architecture summary for OpenIntelligence. It documents the major product layers and their responsibilities without exposing private engine internals.

This document is about the shipped app and public product architecture.

It is not the same thing as the engine boundary. The engine is a narrower reusable subset inside the same source tree, not a synonym for the whole app.

For internal/source-grounded analysis, use:

- [Docs/CURRENT_STATE_AND_GAPS.md](./Docs/CURRENT_STATE_AND_GAPS.md)
- [Docs/IMPLEMENTATION_ANALYSIS_2026_04_24.md](./Docs/IMPLEMENTATION_ANALYSIS_2026_04_24.md)
- [Docs/STORAGE_AND_PIPELINE_TRACE.md](./Docs/STORAGE_AND_PIPELINE_TRACE.md)
- [Docs/BUYER_READINESS_AND_EVALUATION.md](./Docs/BUYER_READINESS_AND_EVALUATION.md)

If you need the repo split rather than the app architecture, start with:

- [README.md](./README.md)
- [ENGINE_CAPABILITIES.md](./ENGINE_CAPABILITIES.md)
- [SDK_BOUNDARY_AUDIT.md](./SDK_BOUNDARY_AUDIT.md)
- [EngineSale/ENGINE_INVENTORY.md](./EngineSale/ENGINE_INVENTORY.md)

## High-Level View

```text
User Interface
    -> Feature Modules
        -> Local Document Processing and Storage
            -> Answering Engine
                -> Apple Platform Services
```

## Public Component Map

| Layer             | Responsibility                                                                                |
| ----------------- | --------------------------------------------------------------------------------------------- |
| User interface    | SwiftUI screens, navigation, answer presentation, onboarding, settings                        |
| Feature modules   | Chat, document management, billing, diagnostics, onboarding, telemetry                        |
| Local processing  | File import, adaptive text and visual extraction, storage, indexing, app-owned data lifecycle |
| Answering engine  | Evidence retrieval, answer synthesis, citation packaging                                      |
| Platform services | Apple Intelligence, OCR, speech, PDF, Metal, StoreKit, system privacy controls                |

## Code Organization

The app source is organized to separate product experience, shared domain types, and the answering engine stack:

- `App/` contains entry points and top-level routing.
- `Core/` contains shared models, protocols, and extensions used across the app.
- `Features/` contains user-facing modules such as chat, documents, billing, settings, onboarding, diagnostics, and telemetry.
  Chat is grouped into conversation, response, and pipeline support.
  Documents is grouped into library, search, detail, settings, and reusable components.
  Telemetry is grouped into dashboard, visualizations, and diagnostics.
- `Services/Document/` is grouped by pipeline stage: processing, extraction, chunking, analysis, classification, and configuration.
  The document stack includes adaptive OCR/detail recovery and figure-aware visual understanding for PDFs and standalone images.
- `Services/Embedding/` separates embedding orchestration from concrete provider implementations.
- `Services/Infrastructure/` groups cross-cutting app services by concern, including configuration, monitoring, background work, compute, integrations, and presentation support.
- `Services/Query/` groups query enhancement, rewriting, routing, analysis, and user-assist behavior.
- `Services/RAG/` is grouped into orchestration, retrieval, extraction, safety, and tuning.
- `Services/LLM/`, `Services/Storage/`, and `Services/VectorStore/` hold the remaining core answering engine layers.
- `Resources/` contains assets, ML models, privacy metadata, and StoreKit content.
- `UI/` contains reusable design system components shared across features.

## Public Principles

- Native iOS-first architecture
- Local-first data handling
- Clear separation between app experience and engine internals
- Platform integrations routed through Apple frameworks whenever possible
- Product features shipped only when they are supportable in code and UI
- Conservative claims around Apple Foundation Models, PCC, and regulated use cases

## Publicly Documented Areas

- App structure and user-facing modules
- Apple framework usage at a category level
- Privacy posture and platform assumptions
- Build and distribution context for the public app
- Internal benchmarking includes a Mac Catalyst validation path; that should not be read as a separately shipped native macOS product

## Intentionally Private Areas

The following remain out of scope for the public documentation set:

- Retrieval and ranking formulas
- Engine thresholds, verification criteria, and confidence logic
- Multi-pass orchestration details and decision policies
- Internal performance tuning and hardware-specific optimization rules
- Commercial strategy, roadmap detail beyond public themes, and partner materials

## Public Repository Boundary

The public repository is designed to communicate product quality and platform depth. If deeper engine review is needed for partnership, diligence, or private collaboration, that material should be shared outside the public repo.
