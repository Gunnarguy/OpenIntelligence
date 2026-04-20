# Install

## Intended Installation Paths

### XCFramework

1. Drag `OpenIntelligenceEngine.xcframework` into the client Xcode project.
2. Add it under Frameworks, Libraries, and Embedded Content.
3. Link required Apple frameworks if the binary package does not re-export them automatically.
4. Add the bundled model resources if the final framework package uses a separate resource bundle.

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

That bundle excludes internal-only sales and demo playbooks.
