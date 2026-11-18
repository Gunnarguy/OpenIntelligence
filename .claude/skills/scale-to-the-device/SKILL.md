---
name: scale-to-the-device
description: Make OpenIntelligence use the hardware it runs on, from an iPhone 15 Pro to an M6 Ultra, by reading Apple's documentation and the SDK first and the device at runtime, never a chip list or a remembered figure. Use before writing or changing any code, copy or claim that depends on the device, the chip, the on-device model, its context window, memory, cores, GPU or Neural Engine; before adding any constant that sizes work (a character cap, a token budget, a concurrency limit, a cache size); and whenever the owner asks whether the app "uses the full power" of a device, says "scale with better devices", "best hardware", "M6", "20B", "Core Advanced", or reports a device showing a wrong figure.
---

# Scale to the device

Using the best Apple hardware fully is the owner's biggest selling point (his words, 2026-11-17) and rule 8 in
`Docs/ai/PURPOSE.md`. On 2026-11-17 he found out, by asking, that the app sized work with fixed numbers and chip
lists, and that one page of Apple's documentation would have shown what to read instead. His words: "could all of
this have been solved had you just looked at the damn documentation". This skill is that lookup, done first.

## 1. Read these before writing a line

Fetch them fresh (`mcp__sosumi__fetchAppleDocumentation`, or the JSON endpoint in the `apple-api-truth` skill) and
write the fetch date next to anything you take from them.

| Read | What it settles |
|---|---|
| `/documentation/foundationmodels/detecting-available-apple-foundation-models` | Which device runs which on-device model, the window per model, that the app cannot pick a variant, the device table |
| `/documentation/foundationmodels/managing-the-context-window` | How to count tokens and budget a session |
| `/documentation/foundationmodels/systemlanguagemodel` (`contextSize`, `variant`, `capabilities`, `tokenCount(for:)`) | The live numbers to read instead of assuming |
| `/documentation/foundationmodels/languagemodelerror` (`rateLimited`, `contextSizeExceeded`) | What fails, with what payload (`resetDate`, `contextSize`, `tokenCount`) |
| `/documentation/updates/foundationmodels`, `/documentation/updates/coreml`, `/documentation/updates/vision`, `/documentation/updates/metal` | What changed this year that the app does not use yet |
| `support.apple.com/121115` | Apple Intelligence device eligibility |

Then the SDK on disk, which is what compiles (`apple-api-truth` has the commands): grep the FoundationModels
`.swiftinterface` for `variant`, `contextSize`, `capabilities`, `tokenCount`, `LanguageModelError`.

## 2. Facts read so far (re-read when the OS or Xcode changes)

| Fact | Source |
|---|---|
| Two on-device models on 27: AFM 3 Core (3B, 4 to 8K window) and AFM 3 Core Advanced (20B, 8K). Each device has exactly one; the system downloads the best it can run; the app cannot choose. PCC (AFM Cloud) is 32K. | Apple, "Detecting available Apple Foundation Models", fetched 2026-11-17 |
| Core Advanced runs on: iPhone Air, iPhone 17 Pro models, iPhone 18 Pro models, iPhone Duo; iPads with M4 or later; Macs with M3 or later; Vision Pro (M5). Everything else eligible runs Core. | same page |
| The owner's M3 Pro Mac: `AFM 3 Core Advanced`, `contextSize` 8,192, capabilities vision, guided generation and tool calling, **not reasoning**; 11 cores (5 performance, 6 efficiency), 18 GB. | measured 2026-11-17, a Swift probe of `SystemLanguageModel.default` on macOS 27.0 |
| The owner's iPhone 16 Pro Max: `AFM 3 Core`, window 4,096 through 2026-11-16 and 8,192 from 2026-11-17 (iOS 27.2.1); a Deep Think call of about 4,900 input tokens ran on device with no error. | measured, `pipeline_trace.log` on the phone, 2026-11-17 |
| `rateLimited` means too many requests in a short window or system load; recover by spacing requests or reducing load. It carries an optional `resetDate`. | Apple, `LanguageModelError.rateLimited(_:)`, fetched 2026-11-17 |
| `SystemLanguageModel.tokenCount(for:)` counts prompts, instructions, tools, schemas and transcript entries (iOS and macOS 26.4). | SDK, Xcode 27A266a |

## 3. The rules

1. **Read the device, never a table of devices.** Window: `SystemLanguageModel.default.contextSize`. Model:
   `.variant` (compare with `.core3`, `.coreAdvanced3`). Abilities: `.capabilities.contains(...)`. Tokens:
   `tokenCount(for:)`. Cores: `sysctl hw.perflevel0.physicalcpu` / `ProcessInfo.activeProcessorCount`. Memory:
   `ProcessInfo.physicalMemory`. GPU budget: `MTLDevice.recommendedMaxWorkingSetSize`. A chip list
   (`contains("m5") || contains("m4")`) silently drops every chip released after it was written; that is how A20 and
   M6 fell to the smallest GPU cache until 2026-11-17.
2. **No fixed size where the device reports one.** A character cap, a token budget or a page count that is the same
   on a 3B model with 4,096 tokens and a 20B model with 8,192 is a defect on one of them. Derive it from the live
   window or the hardware, and keep a floor so a small device still works.
3. **A floor, not a ceiling, from what was measured.** When a known chip had a measured good value, keep it as the
   minimum and let bigger hardware go higher.
4. **Accuracy first.** More context is not automatically more accurate (`accuracy-first-speed-second` memory).
   A change that lets Deep Think or an answer carry more evidence is measured on every benchmark set before it
   ships (`running-the-retrieval-benchmark` memory, `BenchmarkRuns/LEDGER.md`). A change that only removes a
   truncation (an answer cut mid-sentence) needs the trace, not a benchmark.
5. **Say what the hardware does in the words Apple uses.** Name the model the device reports ("AFM 3 Core
   Advanced"), never a size the app assumed. No TOPS or Neural Engine claim Apple did not publish.
6. **Prove it on the device.** Pull `pipeline_trace.log` (phone) or run the Mac build and read the `[FM] usage in=`
   and `Context budget: base=` lines. A claim about M4, M5 or M6 that was not measured there says so.

## 4. Where the app sizes work (check each when this skill runs)

- `AppleFoundationLLMService.continueGeneration`: continuation room from the window (was a fixed 1,600 characters).
- `FoundationModelTokenBudget`: `contextSize`, `reportedOnDeviceModelName`, `tokenBudget`.
- `AgenticOrchestrator+ReasoningChain`: Deep Think session context and the synthesis prompt ("prompt N of WINDOW"
  in the trace).
- `DeviceCapabilityService`: `visionOperationConcurrency`, tiers, `coreMLComputeUnits(for:)`.
- `GPUComputeService` (`MetalBufferPool` cache size), `BNNSVectorDatabase` (worker threads, GPU threshold).
- `DocumentSummaryService`, `ResponseTransformService`: budgets that may still assume 4,096.

Grep for new literals before closing a change: `grep -rn "4096\|4_096\|1600\|contains(\"m[0-9]\|contains(\"a[0-9]" OpenIntelligence`.
