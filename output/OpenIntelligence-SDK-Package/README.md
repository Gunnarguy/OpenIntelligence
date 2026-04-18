# OpenIntelligence Engine SDK

Closed-source Apple-native document intelligence SDK for grounded question answering over private document libraries.

## What It Is

OpenIntelligence Engine is intended to let a client application:

- ingest private documents locally
- build an answerable on-device knowledge layer
- query that material in natural language
- receive source-backed answers with trust metadata

## Who It Is For

Teams building Apple-native products that need private document QA without exposing implementation details or shipping a server-side retrieval stack first.

## Supported Platforms

Target packaging scope:

- iPhone on supported Apple Intelligence hardware
- iPad on supported Apple Silicon hardware
- Apple Silicon Mac where framework/runtime support is valid

## What It Includes

- document ingestion pipeline
- embeddings, indexing, and retrieval
- grounded answer orchestration
- source-only verification behavior
- availability and capability handling

## What It Does Not Include

- app UI
- billing
- onboarding
- diagnostics dashboards
- source code for the engine internals

## Status

This deliverable folder currently contains:

- packaging specification
- API design
- build and validation scripts
- a real `OpenIntelligenceEngine` framework target in the main Xcode project

Current validation state:

- framework target build succeeds for iOS Simulator integration
- final `OpenIntelligenceEngine.xcframework` is not yet present in this folder
- demo integration packaging is not yet complete
