# Install

## Intended Installation Paths

### XCFramework

1. Drag `OpenIntelligenceEngine.xcframework` into the client Xcode project.
2. Add it under Frameworks, Libraries, and Embedded Content.
3. Link required Apple frameworks if the binary package does not re-export them automatically.
4. Add the bundled model resources if the final framework package uses a separate resource bundle.

## Current Evaluation Delivery Mode

The current fastest founder-share artifact is an evaluation XCFramework.

Today’s actual sendable package is:

- `output/OpenIntelligence-SDK-Package/build/OpenIntelligenceEngine-Buyer-Packet.zip`

That packet now includes a self-contained `SampleApp/` folder for import validation without the full private repo.

Use it when:

- the buyer is testing on the same Xcode generation and Swift toolchain you used to build it
- the goal is an early technical evaluation or design-partner pilot

Do not describe the current package as a long-term module-stable binary SDK yet.

For the current evaluation path, the XCFramework is paired with:

- `EvaluationSupport/iphonesimulator`, which contains the compiler support modules needed for the simulator import flow
- `EvaluationSupport/iphoneos`, which contains device-compile compatibility modules when native `iphoneos` support artifacts are not available from the original Engine build

Current artifact location:

- `output/OpenIntelligence-SDK-Package/OpenIntelligenceEngine.xcframework`
- `output/OpenIntelligence-SDK-Package/EvaluationSupport/iphonesimulator`
- `output/OpenIntelligence-SDK-Package/EvaluationSupport/iphoneos`

Commercially, describe this as:

- guided evaluation XCFramework handoff
- same-toolchain technical evaluation package

Do not describe it as:

- finished SPM package
- toolchain-agnostic binary SDK
- fully self-serve production SDK

### Swift Package Binary Target

If a binary package wrapper is produced later:

1. Add the package URL in Xcode.
2. Pin the package version or binary checksum.
3. Import `OpenIntelligenceEngine`.

## Runtime Prerequisites

- Xcode 26 or later
- an Apple Intelligence-capable iPhone, iPad, or Mac for live Foundation Models runtime behavior
- Real device validation for Foundation Models behavior

## Important Validation Note

Simulator is valid for compile-and-link checks.
Simulator is not a full runtime validation environment for Apple Intelligence behavior.

## External Sharing Note

If you are sending the current SDK packet to a founder or buyer, generate the curated bundle with:

- `./scripts/build_sdk_buyer_bundle.sh`

If you want the shortest buyer-share path, run:

- `./scripts/prepare_engine_buyer_packet.sh`

If you need the evaluation XCFramework and simulator support included in that bundle, stage or restore them first with:

- `./scripts/build_engine_evaluation_xcframework.sh`

That bundle excludes internal-only sales and demo playbooks.
The fastest evaluator entrypoint inside the packet is `START_HERE.md`.

## Sample Host App

The SDK packet includes a self-contained pitch-demo evaluation host app at:

- `output/OpenIntelligence-SDK-Package/SampleApp/`

The private engine repo also retains the source-of-truth host app at:

- `Samples/EngineEvaluationHost/`

Inside the packet, you can validate the standalone sample app with:

- `cd output/OpenIntelligence-SDK-Package/SampleApp && ./build_sample_app.sh`

Inside the private repo, you can regenerate and build the source-of-truth host app with:

- `./scripts/build_engine_evaluation_host.sh`

This is meant to prove XCFramework import, ingestion, grounded query, and citation rendering in a room-ready demo flow.
The sample includes a real SwiftUI pitch-demo UI for evaluation, a bundled four-document demo pack, and an operator script at `output/OpenIntelligence-SDK-Package/SampleApp/DEMO_SCRIPT.md` when using the packet.
It is not the final production product UX.

## Cofounder Quickstart

If you need the fastest “what do I click and run?” path:

1. Open `output/OpenIntelligence-SDK-Package/OpenIntelligenceEngine.xcframework` to verify the evaluation artifact exists.
2. Read `output/OpenIntelligence-SDK-Package/INSTALL.md` and `output/OpenIntelligence-SDK-Package/PACKAGE_SUMMARY.md`.
3. Verify `output/OpenIntelligence-SDK-Package/EvaluationSupport/iphonesimulator` exists.
4. Verify `output/OpenIntelligence-SDK-Package/EvaluationSupport/iphoneos` exists.
5. Open `output/OpenIntelligence-SDK-Package/SampleApp/` if you want a concrete local validation target.
6. Run `./build_sample_app.sh` inside `output/OpenIntelligence-SDK-Package/SampleApp/`.
7. Read `output/OpenIntelligence-SDK-Package/SampleApp/DEMO_SCRIPT.md`.
8. Open the included Xcode project and choose an Apple Intelligence-capable iPhone for the live answer-generation step.
9. Launch the app, tap `Load Demo Pack`, index the library, then run the risk question first.

That gives you:

- the evaluation support modules if missing
- the generated sample Xcode project
- a simulator build that proves the import path works in the current environment
- a bundled sample dataset so the pitch demo works from a clean install without file-picking
- a live on-device pitch-demo path when signing and Apple Intelligence-capable hardware are available

Important:

- if the `OpenIntelligenceEngine` target and shared scheme still exist, the script rebuilds the evaluation XCFramework
- if that build path is gone, the script restores the evaluation artifact from the existing buyer packet and archived simulator support already on disk
- when native `iphoneos` support artifacts are unavailable, the script generates device compatibility modules for the evaluation host path
