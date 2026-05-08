# Evaluation Sample App

This folder is the packet-local XCFramework host app for validating the OpenIntelligence evaluation handoff.

It is not the canonical source-distributed SDK sample.
That canonical source-SDK consumer lives in the private engine repo at `Samples/SourceSDKHost/`.

What it proves:

- the XCFramework imports into a separate app
- the evaluation support modules are wired correctly for same-toolchain testing
- the bundled demo documents can be indexed and queried locally
- a buyer can inspect the engine flow without guessing where to start

What it does not prove:

- private-repo source SDK installation
- docs-only no-guidance integration
- sealed module-stable binary packaging

Fastest path:

1. Run `./build_sample_app.sh` for a simulator compile check.
2. Open `EngineEvaluationHost.xcodeproj` in Xcode.
3. Read `DEMO_SCRIPT.md`.
4. For a live runtime demo, select an Apple Intelligence-capable iPhone and your own signing team.

Important:

- This is the packet-local evaluation host, not the primary commercial delivery lane.
- The primary commercial lane today is the source-distributed SDK in the private engine repo.
- The project is configured to look for `../OpenIntelligenceEngine.xcframework` and `../EvaluationSupport/` in this packet.
- For device runs, choose your own development team in Xcode if required.
