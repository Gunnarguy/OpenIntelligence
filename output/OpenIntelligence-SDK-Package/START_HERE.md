# Start Here

This packet is the current source-first diligence slice of the OpenIntelligence engine story.

## What It Is

- a staged evaluation packet
- a technical-review aid
- a same-toolchain testing path when the staged artifact is present
- a buyer-facing explanation of the real source-SDK path inside the private engine repo

## What It Is Not

- a full source-code handoff
- a finished enterprise SDK
- a docs-only self-serve SDK
- a regulated-use artifact

## Delivery Lanes

There are currently two lanes:

- Source SDK lane: the primary commercial lane today. This lives in the private engine repo, where the root `Package.swift`, `Samples/SourceSDKHost/`, and the repo-level validation scripts prove the engine can be integrated as a source-distributed SDK.
- Packet-local evaluation lane: the fallback evaluation lane. This uses the staged XCFramework and packet-local sample app for same-toolchain technical review and room demos.

## Current Release Alignment

The app target and engine target are currently on the 3.5 release line.

Treat this staged packet as a 3.5-aligned evaluation artifact and rebuild it from current source after every public release before sending it to a buyer or partner.

## Hard Status

- Built from current source and staged into this packet: yes, when generated through `scripts/prepare_engine_buyer_packet.sh`.
- Root source SDK package present in the private engine repo: yes.
- Repo-side source consumer sample present in the private engine repo: yes (`Samples/SourceSDKHost/`).
- Repo-side source consumer validator present in the private engine repo: yes (`scripts/validate_source_sdk_consumer_flow.sh`).
- Required engine model and vocabulary assets are expected inside the staged XCFramework, not as separate loose files.
- Same-toolchain technical evaluation path: yes.
- Source SDK package validation script present in the private engine repo: yes (`scripts/validate_source_sdk_package.sh`).
- Source-distributed design-partner SDK lane: yes, with private repo access and assisted integration.
- Module-stable commercial binary SDK: no.
- Self-serve no-guidance buyer handoff: no.

The blocking reason is still the same: stable `BUILD_LIBRARY_FOR_DISTRIBUTION=YES` packaging is blocked by upstream `swift-transformers` interface verification.

The fastest productization path is now the source SDK lane, not the sealed binary lane.

## Fastest Review Path

1. Read `PACKAGE_SUMMARY.md`.
2. Read `API.md` for the simple explanation of how another app would use the engine.
3. Read `INSTALL.md`.
4. Open `SampleApp/` if you want to inspect the packet-local host path.

## Fastest Source SDK Repo Path

Inside the private engine repo, the fastest source-SDK check is now:

1. `./scripts/validate_source_sdk_package.sh`
2. `Samples/SourceSDKHost/build_sample_app.sh`
3. `Samples/SourceSDKHost/run_smoke_tests.sh`
4. or `./scripts/validate_source_sdk_consumer_flow.sh` to run all three

The committed `Samples/SourceSDKHost/SourceSDKHost.xcodeproj` should build directly. Regenerating it with XcodeGen is optional, not required for the default validation path.

If you want to wire the SDK into another app instead of only validating the sample, go next to `INSTALL.md` for the manual package-integration steps and `API.md` for the minimum integration contract.

## Commercial Framing

Use this packet for:

- source-SDK diligence conversations
- design-partner and technical-evaluation conversations
- explaining why the source lane is the honest commercial lane today

Current commercial wording is:

- private source-distributed SDK
- assisted integration
- design-partner evaluation

Do not use this packet by itself to claim:

- sealed stable binary SDK
- docs-only no-guidance self-serve SDK
- finished enterprise SDK productization
