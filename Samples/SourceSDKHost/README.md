# Source SDK Host

This sample app consumes the root `OpenIntelligenceEngine` Swift package directly.

What it proves:

- the source-distributed SDK resolves into a separate app target
- the package builds through normal Xcode package dependency flow
- a host app can create libraries, ingest bundled or imported documents, and run grounded queries
- a package consumer test target can exercise the public SDK facade on simulator without a founder walkthrough

Fastest path:

1. Run `./build_sample_app.sh`.
2. Open the committed `SourceSDKHost.xcodeproj` in Xcode.
3. Select an Apple Intelligence-capable device for live Foundation Models behavior.
4. Use `Load Bundled Demo Pack`, then `Index Documents`, then ask a question.

Smoke-test path:

1. Run `./run_smoke_tests.sh`.
2. This uses the committed sample project and validates the public SDK facade on an iOS simulator.

Notes about tooling:

- the committed `SourceSDKHost.xcodeproj` should build directly through `./build_sample_app.sh`
- the build script auto-detects an available iPhone simulator if you do not provide `DESTINATION`
- the smoke-test script also auto-detects an available iPhone simulator if you do not provide `DESTINATION`
- `xcodegen` is only required if you intentionally want to regenerate the sample project from `project.yml`
- to force regeneration, run `REGENERATE_PROJECT=1 ./build_sample_app.sh`

Important:

- this is the source-SDK consumer path, not the XCFramework evaluation path
- it is a productization milestone, not the final no-guidance SDK claim by itself
- live generation behavior still needs Apple Intelligence-capable hardware
