# Start Here

This packet is the current buyer-safe evaluation handoff for OpenIntelligence Engine.

What you have:

- `OpenIntelligenceEngine.xcframework`
- `EvaluationSupport/` for same-toolchain evaluation imports
- `SampleApp/` as a self-contained validation host app
- `README.md`, `INSTALL.md`, `API.md`, and `PACKAGE_SUMMARY.md`

Fastest path for a founder or startup evaluator:

1. Read `PACKAGE_SUMMARY.md` for the honest readiness snapshot.
2. If you want proof that the SDK imports, go to `SampleApp/`.
3. Run `./build_sample_app.sh` inside `SampleApp/` for a simulator compile check.
4. Open `SampleApp/EngineEvaluationHost.xcodeproj` in Xcode.
5. Read `SampleApp/DEMO_SCRIPT.md` for the live evaluation flow.
6. For runtime evaluation, choose an Apple Intelligence-capable iPhone and your own signing team in Xcode if needed.

Commercial framing:

- This is a guided evaluation XCFramework packet.
- It is appropriate for design-partner conversations, pilot integration, and technical evaluation.
- It is not yet a toolchain-agnostic sealed binary SDK or finished SPM package.

If you are evaluating direct integration into your own app:

1. Start with `INSTALL.md`.
2. Use `SampleApp/` as the concrete reference for framework search paths and evaluation support wiring.
3. Expect same-toolchain evaluation, not final long-term binary stability.
