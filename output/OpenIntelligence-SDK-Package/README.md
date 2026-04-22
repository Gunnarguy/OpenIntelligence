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

- Apple Intelligence-capable iPhone
- Apple Intelligence-capable iPad
- Apple Intelligence-capable Mac

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
- a start-here evaluation guide
- API design
- buyer-safe packet documents
- build and validation scripts
- an evaluation `OpenIntelligenceEngine.xcframework` handoff artifact
- a self-contained evaluation sample app

Current validation state:

- evaluation `OpenIntelligenceEngine.xcframework` is present in this folder for founder and design-partner use on the same Xcode toolchain
- evaluation support modules can be staged alongside the XCFramework for simulator import validation
- device compatibility modules can be staged alongside the XCFramework for evaluation-host iPhone builds
- the current repo no longer exposes a buildable/shared `OpenIntelligenceEngine` scheme, so the evaluation handoff may need to be restored from the existing buyer packet plus archived simulator support on disk
- module-stable XCFramework packaging is still blocked by upstream `swift-transformers` module-interface verification during `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`
- sample host-app validation exists for the evaluation path, including a real SwiftUI pitch demo that builds in simulator and has a prepared Apple Intelligence-capable iPhone path, but a fully standalone stable SDK handoff is not yet complete
- the sample host now includes a bundled four-document demo pack plus an operator script for room-ready demos from a clean app install

## Send This Today

If you need a buyer-safe artifact today, send only:

- `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`

That ZIP is the current commercial handoff.
It contains the evaluation XCFramework, evaluation support modules, the self-contained sample app, and the buyer-safe docs.

Do not lead with SPM today.
Do not zip the full folder manually.
Lead with the curated buyer packet and describe it as a same-toolchain evaluation SDK handoff.

## Sharing Model

Buyer-safe files stay at the root of `output/OpenIntelligence-SDK-Package/`.

Internal-only sales and demo materials live under:

- `output/OpenIntelligence-SDK-Package/Internal/`

Do not zip the whole folder manually for external sharing.
Instead, generate the buyer-safe artifact with:

- `./scripts/build_sdk_buyer_bundle.sh`
- `./scripts/prepare_engine_buyer_packet.sh`

The first script assumes the evaluation artifact is already staged.
The second script stages or restores the evaluation artifact, validates the package, and then creates the curated buyer zip.

## Cofounder Quick Path

If David opens this repo and wants the shortest useful route, use this order:

1. Start in `output/OpenIntelligence-SDK-Package/README.md`.
2. Read `output/OpenIntelligence-SDK-Package/START_HERE.md` for the fastest evaluator path.
3. Read `output/OpenIntelligence-SDK-Package/PACKAGE_SUMMARY.md` for the honest readiness snapshot.
4. Read `output/OpenIntelligence-SDK-Package/INSTALL.md` for the actual integration path.
5. Open `output/OpenIntelligence-SDK-Package/OpenIntelligenceEngine.xcframework` to see the evaluation artifact that is being handed off.
6. If you want proof that it can be imported without the full repo, go to `output/OpenIntelligence-SDK-Package/SampleApp/` and run `./build_sample_app.sh`.
7. For the live room flow, read `output/OpenIntelligence-SDK-Package/SampleApp/DEMO_SCRIPT.md` and use the in-app `Load Demo Pack` action before indexing.

What this means operationally:

- the private repo is the source of truth for founder trials
- the buyer-safe packet lives under `output/OpenIntelligence-SDK-Package/`
- the partner-facing commercial copy lives under `output/OpenIntelligence-Partner-Packet/`
- the sample import app lives under `Samples/EngineEvaluationHost/`
- that sample app is now a real SwiftUI pitch demo for private-doc ingestion and grounded QA, with a bundled room-demo dataset and operator script, not the final production product UI

## Honest Tomorrow-Morning Status

If you are speaking with buyers tomorrow, the truthful framing is:

- the engine logic is real
- the public evaluation artifact imports and builds cleanly in the sample host path
- the public SDK surface is defined
- an evaluation XCFramework can be handed off now for same-toolchain integration
- the evaluation handoff can include support modules for simulator import validation
- the evaluation host app builds in simulator today and has a prepared Apple Intelligence-capable iPhone path using the staged support artifacts
- the fully module-stable binary SDK handoff is still being finalized

That is strong enough for a design-partner or early-access conversation.
It is strong enough to support a drag-and-drop evaluation handoff.
It is not yet strong enough to promise a fully stable, toolchain-agnostic binary SDK handoff.
