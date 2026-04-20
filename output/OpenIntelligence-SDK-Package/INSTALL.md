# Install

## Intended Installation Paths

### XCFramework

1. Drag `OpenIntelligenceEngine.xcframework` into the client Xcode project.
2. Add it under Frameworks, Libraries, and Embedded Content.
3. Link required Apple frameworks if the binary package does not re-export them automatically.
4. Add the bundled model resources if the final framework package uses a separate resource bundle.

## Current Evaluation Delivery Mode

The current fastest founder-share artifact is an evaluation XCFramework.

Use it when:

- the buyer is testing on the same Xcode generation and Swift toolchain you used to build it
- the goal is an early technical evaluation or design-partner pilot

Do not describe the current package as a long-term module-stable binary SDK yet.

Current artifact location:

- `output/OpenIntelligence-SDK-Package/OpenIntelligenceEngine.xcframework`

### Swift Package Binary Target

If a binary package wrapper is produced later:

1. Add the package URL in Xcode.
2. Pin the package version or binary checksum.
3. Import `OpenIntelligenceEngine`.

## Runtime Prerequisites

- Xcode 26 or later
- Apple Intelligence-supported hardware for Foundation Models runtime behavior
- Real device validation for Foundation Models behavior

## Important Validation Note

Simulator is valid for compile-and-link checks.
Simulator is not a full runtime validation environment for Apple Intelligence behavior.

## External Sharing Note

If you are sending the current SDK packet to a founder or buyer, generate the curated bundle with:

- `./scripts/build_sdk_buyer_bundle.sh`

If you need the XCFramework included in that bundle, generate it first with:

- `./scripts/build_engine_evaluation_xcframework.sh`

That bundle excludes internal-only sales and demo playbooks.
