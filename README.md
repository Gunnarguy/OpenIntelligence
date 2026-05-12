# OpenIntelligence

OpenIntelligence is an experimental Apple-native document intelligence prototype for working with user-controlled files.

It explores local-first document ingestion, library-based organization, retrieval, source-backed answers, citations, confidence signals, and AI-assisted reasoning on Apple platforms.

This repository is meant to show the engineering work directly: the SwiftUI app, document ingestion services, retrieval stack, answer grounding logic, benchmark harness, local model resources, and technical notes are all linked from this front page.

OpenIntelligence is a proof-of-concept and portfolio project. It is not a finished enterprise SDK, regulated healthcare system, clinical decision-support tool, diagnostic system, production-ready commercial product, company, or product for sale.

## Start Here

- [Architecture](Docs/ARCHITECTURE.md): app structure, service boundaries, data flow, and package boundary.
- [Retrieval pipeline](Docs/RETRIEVAL_PIPELINE.md): ingestion, chunking, retrieval, context packing, grounded answer generation, and diagnostics.
- [RAG technical specifications](Docs/Engineering/RAG_TECHNICAL.md): deeper implementation notes for HyDE, parent retrieval, compression, verification, reranking, and retrieval policy.
- [Storage and pipeline trace](Docs/Engineering/STORAGE_AND_PIPELINE_TRACE.md): current storage reality, SQLite/vector traces, container isolation, and benchmark hooks.
- [Benchmarks](Benchmarks/README.md): manifest format, local RAG validation runner, document studio, outputs, and fixture guidance.
- [Demo guide](Docs/DEMO.md): suggested public demo flow and safe demo-document guidance.
- [Limitations](Docs/LIMITATIONS.md): product, safety, technical, and demo limits.
- [Roadmap](Docs/ROADMAP.md): near-term engineering direction.

## What It Demonstrates

- AI product engineering in a native Apple app.
- Local-first document workflows built around user-controlled files.
- Document ingestion, OCR-oriented extraction, chunking, enrichment, and indexing.
- Retrieval-oriented answer generation with citations and evidence review.
- Library/workspace isolation so questions stay scoped to the selected material.
- Confidence, warning, and verification surfaces instead of pretending every answer is final.
- Benchmarking and diagnostics for inspecting retrieval quality.
- A Swift/SwiftUI implementation with a developing engine boundary.

## Repository Map

| Area | What to look at |
| --- | --- |
| App shell | [`OpenIntelligence/App`](OpenIntelligence/App) |
| Core models and protocols | [`OpenIntelligence/Core`](OpenIntelligence/Core) |
| Document library UI | [`OpenIntelligence/Features/Documents`](OpenIntelligence/Features/Documents) |
| Chat and answer surfaces | [`OpenIntelligence/Features/Chat`](OpenIntelligence/Features/Chat) |
| Diagnostics and validation UI | [`OpenIntelligence/Features/Diagnostics`](OpenIntelligence/Features/Diagnostics) |
| Telemetry and visualizations | [`OpenIntelligence/Features/Telemetry`](OpenIntelligence/Features/Telemetry) |
| Document processing services | [`OpenIntelligence/Services/Document`](OpenIntelligence/Services/Document) |
| Embedding providers | [`OpenIntelligence/Services/Embedding`](OpenIntelligence/Services/Embedding) |
| Query analysis and rewriting | [`OpenIntelligence/Services/Query`](OpenIntelligence/Services/Query) |
| RAG orchestration, retrieval, and safety | [`OpenIntelligence/Services/RAG`](OpenIntelligence/Services/RAG) |
| Storage and vector search | [`OpenIntelligence/Services/Storage`](OpenIntelligence/Services/Storage), [`OpenIntelligence/Services/VectorStore`](OpenIntelligence/Services/VectorStore) |
| Experimental engine API boundary | [`OpenIntelligence/SDK/OpenIntelligenceEngine.swift`](OpenIntelligence/SDK/OpenIntelligenceEngine.swift) |
| Local model resources | [`OpenIntelligence/Resources/MLModels`](OpenIntelligence/Resources/MLModels) |
| Benchmark and audit scripts | [`scripts`](scripts) |
| Benchmark manifests and studio | [`Benchmarks`](Benchmarks) |

## Engineering Highlights

The main app flow runs through a native SwiftUI shell and a document intelligence service layer:

- [`OpenIntelligence/App/OpenIntelligenceApp.swift`](OpenIntelligence/App/OpenIntelligenceApp.swift): app entry point.
- [`OpenIntelligence/App/ContentView.swift`](OpenIntelligence/App/ContentView.swift): top-level app composition.
- [`OpenIntelligence/App/DebugRAGValidationHarness.swift`](OpenIntelligence/App/DebugRAGValidationHarness.swift): debug validation entry point for scripted RAG runs.
- [`OpenIntelligence/Features/Documents/Library/DocumentLibraryView.swift`](OpenIntelligence/Features/Documents/Library/DocumentLibraryView.swift): document/library management surface.
- [`OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift`](OpenIntelligence/Features/Chat/Conversation/ChatScreen.swift): main question-answering experience.
- [`OpenIntelligence/Features/Chat/Response/RetrievalSourcesTray.swift`](OpenIntelligence/Features/Chat/Response/RetrievalSourcesTray.swift): source review UI.
- [`OpenIntelligence/Features/Chat/Response/RetrievalQualityView.swift`](OpenIntelligence/Features/Chat/Response/RetrievalQualityView.swift): retrieval-quality feedback surface.
- [`OpenIntelligence/Features/Diagnostics/Validation/RAGAccuracyView.swift`](OpenIntelligence/Features/Diagnostics/Validation/RAGAccuracyView.swift): validation dashboard.

The document and retrieval stack is split across focused services:

- [`DocumentProcessor.swift`](OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift): document ingestion and processing coordinator.
- [`SemanticChunker.swift`](OpenIntelligence/Services/Document/Chunking/SemanticChunker.swift): semantic chunking experiments.
- [`EmbeddingService.swift`](OpenIntelligence/Services/Embedding/EmbeddingService.swift): embedding abstraction.
- [`SQLiteFullTextService.swift`](OpenIntelligence/Services/Storage/SQLiteFullTextService.swift): full-text storage path.
- [`VectorStoreRouter.swift`](OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift): vector store routing.
- [`RAGService.swift`](OpenIntelligence/Services/RAG/Orchestration/RAGService.swift): retrieval-augmented answer orchestration.
- [`HybridSearchService.swift`](OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift): hybrid retrieval.
- [`ContextPackingService.swift`](OpenIntelligence/Services/RAG/Retrieval/ContextPackingService.swift): context budget and evidence packing.
- [`SourceOnlyAnswerService.swift`](OpenIntelligence/Services/RAG/Safety/SourceOnlyAnswerService.swift): source-backed answer checks.
- [`VerificationGateService.swift`](OpenIntelligence/Services/RAG/Safety/VerificationGateService.swift): answer verification gates.

## Retrieval Pipeline

At a high level:

1. A user imports files into a selected library/workspace.
2. The app extracts text and document structure where available.
3. The document processor chunks and enriches content.
4. Text and vector indexes are updated for scoped retrieval.
5. A query is analyzed, rewritten, or routed depending on quality mode.
6. Candidate chunks are retrieved, reranked, compressed, and packed into context.
7. The answer layer produces a response grounded in retrieved evidence.
8. Citations, confidence signals, warnings, and diagnostics are exposed in the UI.

See [Retrieval Pipeline](Docs/RETRIEVAL_PIPELINE.md), [RAG Technical Specifications](Docs/Engineering/RAG_TECHNICAL.md), and [Storage and Pipeline Trace](Docs/Engineering/STORAGE_AND_PIPELINE_TRACE.md) for the detailed flow.

## Technical References

- [Apple Document Intelligence Reference](Docs/Engineering/APPLE_DOCUMENT_INTELLIGENCE.md): Vision, VisionKit, Natural Language, PDFKit, Speech, and related Apple document APIs.
- [Apple Intelligence Foundation Language Models Tech Report Notes](Docs/Engineering/APPLE_FM_TECH_REPORT_2025.md): model architecture and platform constraints relevant to the prototype.
- [Apple Intelligence Models and Specs](Docs/Engineering/APPLE_MODELS.md): context-window, token-budget, `LanguageModelSession`, tool-calling, and guided-generation notes.
- [Private Cloud Compute Reference](Docs/Engineering/PRIVATE_CLOUD_COMPUTE.md): PCC architecture notes and conservative wording for what it does and does not imply.

## Benchmarks And Diagnostics

The repo includes a local benchmark harness for testing RAG behavior against controlled manifests:

- [`Benchmarks/rag_validation_sample.json`](Benchmarks/rag_validation_sample.json): sample manifest.
- [`Benchmarks/studio.html`](Benchmarks/studio.html): lightweight ad hoc document studio.
- [`scripts/run_rag_benchmarks.py`](scripts/run_rag_benchmarks.py): benchmark runner.
- [`scripts/rag_benchmark_studio.py`](scripts/rag_benchmark_studio.py): local benchmark-studio helper.
- [`scripts/prepare_rag_research_fixtures.py`](scripts/prepare_rag_research_fixtures.py): fixture preparation helper.
- [`scripts/secret_scan.py`](scripts/secret_scan.py): lightweight local secret scan.

The benchmark path exists to make retrieval failures inspectable: source mismatches, weak answers, abstention behavior, missing evidence, and context-packing issues should be visible rather than hidden behind a polished answer.

## Setup

Requirements:

- macOS with Xcode installed.
- iOS 26.0+ SDK/toolchain support.
- Developer familiarity with Xcode, SwiftPM, and local simulator builds.

Build the app target:

```bash
xcodebuild \
  -project OpenIntelligence.xcodeproj \
  -scheme OpenIntelligence \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Run the simulator smoke script:

```bash
./scripts/build_simulator_smoke.sh
```

Inspect the experimental package boundary:

```bash
swift package describe
```

Run the lightweight secret scan:

```bash
python3 scripts/secret_scan.py .
```

## Limits And Non-Goals

OpenIntelligence is intentionally honest about what it is:

- Experimental prototype.
- Not validated for regulated workflows.
- Not intended for clinical, legal, financial, or safety-critical decision-making.
- Not guaranteed to produce complete or correct answers.
- Some paths may depend on device-specific Apple Intelligence availability.
- Packaging and setup may require developer familiarity.
- The engine boundary is exploratory and should not be treated as a finished public SDK contract.

See [Limitations](Docs/LIMITATIONS.md) for the full version.

## Relationship To OpenClinic

OpenClinic and OpenIntelligence are separate projects. OpenIntelligence is a general document intelligence prototype and is not a clinical tool. Any healthcare-adjacent examples should be treated as generic document workflows, not medical guidance or regulated functionality.

## License

See [`LICENSE`](LICENSE).
