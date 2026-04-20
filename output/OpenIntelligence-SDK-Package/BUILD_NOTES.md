# Build Notes

## Current State

The workspace currently contains:

- app target: `OpenIntelligence`
- framework target: `OpenIntelligenceEngine`
- no existing XCFramework artifact in the deliverable folder

Current validation completed:

- `OpenIntelligenceEngine` framework target builds successfully for `generic/platform=iOS Simulator`
- latest engine-target compile drift from billing shims has been repaired

Still not completed:

- device archive
- simulator archive suitable for XCFramework packaging
- final `OpenIntelligenceEngine.xcframework`
- demo app that links only against the packaged binary

## Current Packaging Blocker

The current blocker is not the engine target itself.
The blocker is XCFramework archive with `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`, where the upstream local package dependency `swift-transformers` fails Swift module-interface verification for its `Generation` module during archive.

Observed behavior:

- direct `OpenIntelligenceEngine` framework builds can succeed
- archive for binary distribution fails before final XCFramework creation
- package validation therefore still reports the binary artifact as missing

Practical implication:

- the engine is demoable
- the engine is not yet ready for sealed binary handoff

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
6. Validate a demo integration target against the packaged binary

## Tomorrow-Safe Commercial Framing

Until the archive blocker is fixed, sell this as:

- early-access engine
- design-partner integration
- private demo plus assisted integration

Do not sell it as:

- finished drag-and-drop XCFramework
- same-day binary SDK handoff

## Scripts Added

- `scripts/build_engine_xcframework.sh`
- `scripts/validate_sdk_package.sh`

These scripts are real and intended to become the packaging path once the framework target exists.

## Validation Limits

- compile-and-link validation can be done in simulator
- Apple Intelligence runtime validation requires supported physical hardware
- performance validation must be done on real device
