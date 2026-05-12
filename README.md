# OpenIntelligence

OpenIntelligence is an experimental Apple-native document intelligence prototype for working with user-controlled files.

It explores local-first document ingestion, library-based organization, retrieval, source-backed answers, citations, confidence signals, and AI-assisted reasoning on Apple platforms.

This is a proof-of-concept and portfolio project. It is not a finished enterprise SDK, regulated healthcare system, clinical decision-support tool, production-ready commercial product, or clinical decision-support system.

## Why It Exists

OpenIntelligence was built to explore what a document intelligence system feels like when the product is organized around evidence instead of generic chat. The central idea is simple: users should be able to import their own files, ask questions, and inspect the sources behind an answer.

The project demonstrates practical AI product engineering across ingestion, chunking, retrieval, answer generation, citations, and uncertainty handling in a native Apple app.

## What It Does Today

- Imports user-selected documents and supporting files into local app workflows.
- Organizes material into libraries or workspaces so retrieval stays scoped.
- Chunks and indexes content for retrieval-oriented question answering.
- Retrieves source material before producing grounded answers.
- Displays citations, evidence review surfaces, confidence signals, and warnings.
- Includes diagnostics and validation surfaces for inspecting retrieval quality.
- Carries an experimental Swift package boundary for the document intelligence engine.

## Core Concepts

- local-first document workflows
- user-controlled files
- document ingestion
- chunking and retrieval
- library or workspace isolation
- source-backed answers
- citations and evidence review
- confidence and warning signals
- Apple-native app architecture
- Swift and SwiftUI implementation

## Architecture Overview

The app is structured around a native SwiftUI shell and a document intelligence core:

- `OpenIntelligence/App`: app entry points and composition.
- `OpenIntelligence/Features`: document, chat, settings, diagnostics, telemetry, onboarding, and related user-facing features.
- `OpenIntelligence/Services`: ingestion, extraction, chunking, embedding, storage, retrieval, RAG orchestration, answer safety, and platform integration services.
- `OpenIntelligence/SDK`: experimental package-facing API surface for the engine boundary.
- `OpenIntelligence/Resources`: assets, privacy metadata, and local model resources.

See `Docs/ARCHITECTURE.md` and `Docs/RETRIEVAL_PIPELINE.md` for the technical overview.

## What This Demonstrates

- AI product engineering
- retrieval-oriented system design
- Apple-platform development
- practical handling of context constraints
- source-grounded answer design
- iterative prototype development

## Tech Stack

- Swift
- SwiftUI
- Xcode projects and Swift Package Manager
- Apple document and text processing APIs
- Local storage, full-text search, vector retrieval, and reranking experiments
- On-device model resources for embedding and ranking experiments

## Limitations

- Experimental prototype.
- Not validated for regulated workflows.
- Not intended for clinical, legal, financial, or safety-critical decision-making.
- Not guaranteed to produce complete or correct answers.
- May require device-specific Apple Intelligence availability for some paths.
- Packaging and setup may require developer familiarity.

## What It Is Not

OpenIntelligence is not:

- a finished enterprise SDK
- a sealed binary SDK
- a production enterprise product
- a regulated healthcare tool
- a clinical decision-support system
- a diagnostic system
- a buyer-ready handoff
- a company
- a product for sale

## Setup

Requirements:

- macOS with Xcode installed
- iOS 26.0+ SDK/toolchain support

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

## Documentation

- `Docs/ARCHITECTURE.md`: app and engine architecture.
- `Docs/RETRIEVAL_PIPELINE.md`: ingestion, chunking, retrieval, and answer flow.
- `Docs/LIMITATIONS.md`: known limitations and non-goals.
- `Docs/ROADMAP.md`: near-term technical direction.
- `Docs/DEMO.md`: suggested demo flow and screenshots guidance.

## Relationship To OpenClinic

OpenClinic and OpenIntelligence are separate projects. OpenIntelligence is a general document intelligence prototype and is not a clinical tool. Any healthcare-adjacent examples should be treated as generic document workflows, not medical guidance or regulated functionality.

## License

See `LICENSE`.
