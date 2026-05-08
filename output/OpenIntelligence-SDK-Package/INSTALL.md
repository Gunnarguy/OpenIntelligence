# Install

## Current Status

This document describes how to work with the staged evaluation packet.

It does not turn the current packet into a finished enterprise SDK story.

There is now also a root source-SDK package path in the private engine repo, but that path is still in productization and validation work rather than buyer-ready no-guidance completion.

## Intended Evaluation Path

If the staged XCFramework artifact is present, the current packet can support a same-toolchain evaluation flow:

1. Drag `OpenIntelligenceEngine.xcframework` into the evaluator project.
2. Link required Apple frameworks if needed.
3. Use the sample host materials in this packet as a reference.
4. Test on a physical Apple Intelligence-capable device for live Foundation Models behavior.

## Source SDK Path Inside The Private Repo

The private engine repo now includes:

- a root `Package.swift`
- a source-distributed `OpenIntelligenceEngine` package target
- a validation script: `scripts/validate_source_sdk_package.sh`
- a package consumer sample app template: `Samples/SourceSDKHost/`
- a full consumer-flow validator: `scripts/validate_source_sdk_consumer_flow.sh`
- a committed consumer sample project: `Samples/SourceSDKHost/SourceSDKHost.xcodeproj`

That path currently proves:

- the source SDK manifest resolves
- the package builds for iOS Simulator
- engine resources are bundled through the package path
- a separate host app can compile against the package path
- the committed sample project can be built directly without regenerating it first
- those two steps can be re-run through one repo-level validation script

That path does **not** yet prove:

- docs-only buyer installation without founder help
- final consumer sample app integration
- finished no-guidance SDK productization

## Fastest Source SDK Validation Path

From the private engine repo root:

1. Run `./scripts/validate_source_sdk_package.sh`.
2. Run `Samples/SourceSDKHost/build_sample_app.sh`.
3. Or run `./scripts/validate_source_sdk_consumer_flow.sh` to perform both steps in sequence.

The committed sample project should build directly. `xcodegen` is only needed if you deliberately regenerate `Samples/SourceSDKHost/SourceSDKHost.xcodeproj` from `project.yml`.
If you do not provide `DESTINATION`, the sample build script will auto-detect an available iPhone simulator.

## Manual Source SDK Integration Into Another App

If you want to integrate the source SDK into your own app instead of only running the sample:

1. Clone the private engine repo locally.
2. Add the repo root as a Swift package dependency in Xcode, or point Xcode at the private Git URL for this repo.
3. Add the `OpenIntelligenceEngine` product to your app target.
4. Import `OpenIntelligenceEngine` in a `@MainActor` integration point.
5. Create an `OIEngine` with your preferred `OIEngineConfiguration`.
6. Create or select a library.
7. Ingest document URLs into that library.
8. Query that library and inspect the returned answer, warnings, and citations.

Use `Samples/SourceSDKHost/` as the reference integration shape for:

- package wiring
- library creation and selection
- ingest flow
- grounded query flow
- citation rendering

The minimum practical runtime contract is still:

- Xcode 26+
- iOS 26+
- a `@MainActor` caller for the current public engine facade
- physical-device validation for live Apple Foundation Models behavior

## Runtime Prerequisites

- Xcode 26 or later
- Apple Intelligence-capable iPhone, iPad, or Mac for live Apple FM behavior
- physical-device validation for actual generation behavior

## Evaluation Limits

Treat the current packet as:

- guided evaluation collateral
- technical-review support
- same-toolchain testing material

Do not treat it as:

- a full source-code transfer
- a toolchain-agnostic binary SDK
- a finished self-serve enterprise package

## Practical Rule

If the conversation is about serious licensing or code transfer, this packet should support that conversation, not replace the deeper repo and codebase review.

If the conversation is specifically about the fastest route to a polished SDK product, use the source package path as the lead productization lane and treat the XCFramework packet as the evaluation lane.
