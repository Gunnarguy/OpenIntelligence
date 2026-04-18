---
applyTo: "**/*.swift"
---

# Swift Conventions

Follow existing code patterns. These clarify non-obvious project-specific choices.

## Concurrency

- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` — every type is MainActor by default
- Use `actor` for background compute (RAGEngine, VerificationGateService)
- Use `nonisolated` to opt out of MainActor when needed
- `[weak self]` in ALL `Task` / closure captures
- Store tasks as `Task<Void, Never>?`, cancel in `deinit`
- `Task.checkCancellation()` in LLM session loops
- `nonisolated` on `init` when required by strict concurrency

## Logging

- Use `Log.info/error/debug/verbose("message", category: .retrieval)` — never `print()`, `os_log`, or `Logger`
- Categories: `.initialization`, `.ingestion`, `.embedding`, `.vectorDB`, `.retrieval`, `.llm`, `.pipeline`, `.performance`, `.streaming`, `.telemetry`, `.ui`, `.billing`, `.pipelineTrace`
- All `print()` must be wrapped in `#if DEBUG`

## Error Handling

- `do/catch` with `Log.error(...)` — never silently swallow errors
- `decodeIfPresent ?? defaultValue` for all Codable fields added after v1 (migration safety)
- Custom `init(from:)` with backward-compatible decoding for any persisted model
- No `fatalError()` (except `required init?(coder:)`)
- No force unwraps (`!`) — use `guard let`, `if let`, `??`
- Fallback chains: Apple FM → OnDeviceAnalysis → graceful "unavailable" message

## SDK Productization

- For engine-owned resources, do not use `Bundle.main`; use `OpenIntelligenceResourceBundle`
- For framework-owned storage, do not add fresh `.applicationSupportDirectory` lookups when `AppSupportPaths.baseDir()` or `OpenIntelligenceRuntimePaths` should own the path
- Keep the public SDK surface in `OpenIntelligence/SDK/*`; internal services stay internal unless they are intentionally part of the commercial API
- Engine-facing code should not import or depend on app-only layers in `App/`, `Features/`, or `UI/`
- If a file is shared by app and SDK, prefer abstractions that work in both instead of app-only shortcuts

## SwiftUI

- `@State` is always `private`
- `@EnvironmentObject` is always `private`
- `@ObservedObject` is NOT private (injected from parent)
- DI happens in `ContentView`, not at `App` level
- Design System tokens: `DSColors`, `DSSpacing`, `DSTypography`, `SurfaceCard`
- No `GeometryReader` in navigation stacks — use `.frame(maxWidth: .infinity)`

## Anti-Patterns

- No third-party AI SDKs (no OpenAI, no HuggingFace Hub, no LangChain)
- No bare `print()` outside `#if DEBUG`
- No `os_log` or `Logger` — use `Log`
- No `/** */` doc comments — use `///`
- No `fileprivate` — use `private`
- No explicit `internal` — it's the default
- Don't import `UIKit` when `Foundation` or `SwiftUI` suffices
- Don't modify `swift-transformers/` — it's upstream
