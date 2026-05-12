# Architecture

OpenIntelligence is an Apple-native document intelligence prototype built around a SwiftUI app shell and a retrieval-oriented document engine.

The app is intentionally organized as a prototype, not as a polished commercial framework. The codebase keeps the engineering substance visible: document ingestion, chunking, indexing, retrieval, grounded answer generation, citation handling, confidence surfaces, and diagnostics.

## Major Areas

- `OpenIntelligence/App`: application entry points and top-level composition.
- `OpenIntelligence/Features`: user-facing document, chat, settings, diagnostics, telemetry, camera, onboarding, and billing surfaces.
- `OpenIntelligence/Services/Document`: extraction, parsing, analysis, chunking, classification, and document processing.
- `OpenIntelligence/Services/RAG`: retrieval, context packing, orchestration, verification, source-only answering, confidence, and safety checks.
- `OpenIntelligence/Services/Embedding`: embedding providers and local embedding optimization experiments.
- `OpenIntelligence/Services/Storage`: full-text and local storage services.
- `OpenIntelligence/Services/VectorStore`: vector database abstractions and local vector search experiments.
- `OpenIntelligence/SDK`: experimental source package boundary for the engine-facing API.

## Data Flow

1. A user imports files into the app.
2. The document pipeline extracts text and structure where possible.
3. Content is chunked, tagged, and associated with a library or workspace scope.
4. Storage and retrieval indexes are updated.
5. A query is analyzed, rewritten or enhanced when appropriate, and routed through retrieval.
6. Retrieved evidence is packed into context for answer generation.
7. Verification and source-only checks remove or flag unsupported claims.
8. The UI presents the answer, citations, quality signals, and diagnostic detail.

## Design Goals

- Keep user files under user-controlled workflows.
- Keep library or workspace boundaries visible in retrieval.
- Prefer source-backed answers over unconstrained model output.
- Make uncertainty inspectable instead of hiding it behind polished prose.
- Preserve enough diagnostics for engineering iteration.

## Package Boundary

The repository includes `Package.swift` and an `OpenIntelligenceEngine` target. That package boundary is experimental. It is useful for understanding how the document intelligence core can be separated from the app shell, but it should not be described as a finished SDK or production-ready handoff.
