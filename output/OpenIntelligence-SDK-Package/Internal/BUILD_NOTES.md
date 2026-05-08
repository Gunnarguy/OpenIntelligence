# Build Notes

## Current State

The workspace currently contains:

- app target: `OpenIntelligence`
- framework target: `OpenIntelligenceEngine`
- shared engine scheme for fresh framework and archive builds
- staged evaluation `OpenIntelligenceEngine.xcframework` artifact in the deliverable folder
- a generated evaluation host project that now acts as a room-ready pitch demo

Current validation completed:

- `OpenIntelligenceEngine` framework builds from current source for `generic/platform=iOS Simulator`
- root `Package.swift` source SDK manifest resolves from current source
- source SDK package build succeeds for iOS Simulator via `scripts/validate_source_sdk_package.sh`
- package consumer sample app template under `Samples/SourceSDKHost/` builds against the local package path
- package consumer sample app script auto-detects an available iPhone simulator when one is not explicitly provided
- repo-level source SDK consumer flow succeeds via `scripts/validate_source_sdk_consumer_flow.sh`
- evaluation device and simulator archives succeed with isolated per-platform DerivedData paths
- evaluation XCFramework rebuild succeeds from current source
- buyer packet staging and rebuild succeed from the fresh evaluation artifact
- evaluation host app builds for `iPhone 17 Pro` simulator
- the self-contained `output/OpenIntelligence-SDK-Package/SampleApp/` build path also succeeds for `iPhone 17 Pro` simulator
- evaluation host app has a configured on-device path for Apple Intelligence-capable iPhone validation once signing and hardware are available
- evaluation `OpenIntelligenceEngine.xcframework` remains usable for same-toolchain evaluation

Still not completed:

- module-stable commercial archive path with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`
- final module-stable `OpenIntelligenceEngine.xcframework`
- sealed stable buyer handoff with no evaluation-support shims

## Current Packaging Blocker

The current blocker is not the engine target itself.
The blocker is XCFramework archive with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`, where the upstream local package dependency `swift-transformers` fails Swift module-interface verification inside `Hub.swiftinterface` during archive.

Observed behavior:

- the repo now exposes a buildable/shared `OpenIntelligenceEngine` scheme again
- the evaluation artifact can now be rebuilt and staged directly from current source
- the evaluation archive path needed per-platform DerivedData roots to avoid simulator/device archive intermediate collisions
- module-stable binary packaging is still blocked before a final stable XCFramework path exists

Practical implication:

- the engine is demoable now
- an evaluation XCFramework is available now
- a source SDK packaging path is now real and buildable
- a source-SDK consumer app path is now real and buildable
- a clean-machine source-SDK consumer validation path is now scriptable and CI-friendly
- a buyer-safe ZIP with a packet-local sample app is available now
- the pitch demo can be compiled locally now and taken to Apple Intelligence-capable iPhone hardware for live runtime validation
- the engine is not yet ready for sealed module-stable binary handoff

## Resources Required By The Engine

- `EmbeddingModel.mlpackage`
- `ReRankerModel.mlpackage`
- `embedding_vocab.json`
- `reranker_vocab.json`

## Required Productization Changes Before Binary Packaging

1. Tighten framework target membership so app UI / billing / diagnostics are excluded
2. Finish narrowing the public API to configuration, ingestion, query, and availability
3. Audit remaining app-owned storage assumptions
4. Archive device and simulator slices with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`
5. Create the final XCFramework
6. Validate the pitch-demo host against the packaged binary

## Evaluation Packaging Path

For founder or design-partner sharing, a practical interim path exists:

- archive device and simulator slices with `BUILD_LIBRARY_FOR_DISTRIBUTION=NO`
- archive with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
- create an evaluation XCFramework with `-allow-internal-distribution`

This is appropriate for:

- early technical evaluation
- founder testing
- guided pilot integration
- in-room pitch demos on Apple Intelligence-capable devices

This is not the final packaging answer for a stable commercial SDK.

## Tomorrow-Safe Commercial Framing

Until the archive blocker is fixed, sell this as:

- early-access engine
- design-partner integration
- private demo plus assisted integration

Do not sell it as:

- finished stable drag-and-drop XCFramework
- same-day binary SDK handoff

## Scripts Added

- `scripts/build_engine_xcframework.sh`
- `scripts/build_engine_evaluation_xcframework.sh`
- `scripts/prepare_engine_buyer_packet.sh`
- `scripts/validate_sdk_package.sh`
- `scripts/build_sdk_buyer_bundle.sh`
- `scripts/validate_source_sdk_package.sh`
- `scripts/validate_source_sdk_consumer_flow.sh`

These scripts are real and currently support:

- a source-backed evaluation handoff path
- an initial source-SDK package validation path
- a combined source-SDK consumer validation path

The stable commercial binary path is still blocked by upstream package interface verification.

Additional packet-local sample staging script:

- `scripts/stage_sdk_sample_app.sh`

## Validation Limits

- compile-and-link validation can be done in simulator
- Apple Intelligence runtime validation requires Apple Intelligence-capable physical hardware
- performance validation must be done on real device
