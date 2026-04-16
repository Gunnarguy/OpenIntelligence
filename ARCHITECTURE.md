# OpenIntelligence Architecture

Version 2.0

This is the public architecture summary for OpenIntelligence. It documents the major product layers and their responsibilities without exposing private engine internals.

## High-Level View

```text
User Interface
    -> Feature Modules
        -> Local Document Processing and Storage
            -> Answering Engine
                -> Apple Platform Services
```

## Public Component Map

| Layer | Responsibility |
| --- | --- |
| User interface | SwiftUI screens, navigation, answer presentation, onboarding, settings |
| Feature modules | Chat, document management, billing, diagnostics, onboarding, telemetry |
| Local processing | File import, extraction, storage, indexing, app-owned data lifecycle |
| Answering engine | Evidence retrieval, answer synthesis, citation packaging |
| Platform services | Apple Intelligence, OCR, speech, PDF, Metal, StoreKit, system privacy controls |

## Public Principles

- Native iOS-first architecture
- Local-first data handling
- Clear separation between app experience and engine internals
- Platform integrations routed through Apple frameworks whenever possible
- Product features shipped only when they are supportable in code and UI

## Publicly Documented Areas

- App structure and user-facing modules
- Apple framework usage at a category level
- Privacy posture and platform assumptions
- Build and distribution context for the public app

## Intentionally Private Areas

The following remain out of scope for the public documentation set:

- Retrieval and ranking formulas
- Engine thresholds, verification criteria, and confidence logic
- Multi-pass orchestration details and decision policies
- Internal performance tuning and hardware-specific optimization rules
- Commercial strategy, roadmap detail beyond public themes, and partner materials

## Public Repository Boundary

The public repository is designed to communicate product quality and platform depth. If deeper engine review is needed for partnership, diligence, or private collaboration, that material should be shared outside the public repo.