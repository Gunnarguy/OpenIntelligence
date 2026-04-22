# Evaluation Sample App

This folder is a self-contained iOS host app for validating the OpenIntelligence evaluation SDK handoff.

What it proves:

- the XCFramework imports into a separate app
- the evaluation support modules are wired correctly for same-toolchain testing
- the bundled demo documents can be indexed and queried locally

Fastest path:

1. Run `./build_sample_app.sh` for a simulator compile check.
2. Open `EngineEvaluationHost.xcodeproj` in Xcode.
3. Read `DEMO_SCRIPT.md`.
4. For a live runtime demo, select an Apple Intelligence-capable iPhone and your own signing team.

Important:

- This is an evaluation host, not the final buyer UX.
- The project is configured to look for `../OpenIntelligenceEngine.xcframework` and `../EvaluationSupport/` in this packet.
- For device runs, choose your own development team in Xcode if required.
