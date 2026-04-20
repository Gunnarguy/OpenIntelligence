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
- buyer-safe packet documents
- build and validation scripts
- a real `OpenIntelligenceEngine` framework target in the main Xcode project

Current validation state:

- framework target build succeeds for iOS Simulator integration
- framework target compiles after the latest SDK compatibility shim updates
- final `OpenIntelligenceEngine.xcframework` is not yet present in this folder
- XCFramework archive is still blocked by upstream `swift-transformers` module-interface verification during `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`
- demo integration packaging is not yet complete

## Sharing Model

Buyer-safe files stay at the root of `output/OpenIntelligence-SDK-Package/`.

Internal-only sales and demo materials live under:

- `output/OpenIntelligence-SDK-Package/Internal/`

Do not zip the whole folder manually for external sharing.
Instead, generate the buyer-safe artifact with:

- `./scripts/build_sdk_buyer_bundle.sh`

That script creates a curated zip containing only the files intended for founder or buyer sharing.

## Honest Tomorrow-Morning Status

If you are speaking with buyers tomorrow, the truthful framing is:

- the engine logic is real
- the framework target compiles
- the public SDK surface is defined
- the sealed binary SDK handoff is still being finalized

That is strong enough for a design-partner or early-access conversation.
It is not yet strong enough to promise a finished drag-and-drop XCFramework handoff the same day.
