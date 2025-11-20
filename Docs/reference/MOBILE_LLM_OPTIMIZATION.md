# Mobile LLM Optimization Guide

**Last Updated**: 2025-11-12  
**Target Platform**: iOS 17+ (iPhone 15 Pro and newer recommended for optimal performance)

## Overview

This guide documents best practices for optimizing GGUF local model inference on iOS devices to ensure fast, privacy-preserving LLM responses while conserving battery and memory.

---

## 0. Local Model Preview Funnel

Starter and Free workspaces now receive a **3-run preview** so they can feel the difference of on-device GGUF/Core ML inference before upgrading.

### Preview Allowances

- `EntitlementStore` seeds `localModelPreviewRemaining` with **3 tickets** for Free, **0 for paid tiers**.
- Tickets are issued via `issueLocalModelPreviewTicket()` whenever a GGUF/Core ML backend spins up; Pro/Lifetime get non-consuming tickets.
- Consumption is recorded in `previewRunsConsumed` so telemetry and conversions remain accurate even after upgrades/downgrades.

### Gating & Fallback Behavior

- When previews remain, Settings lets users select GGUF/Core ML models and `RAGService` consumes one ticket per successful local generation.
- Once previews hit zero, `LocalModelAccessState` flips to `.blocked` and Settings surfaces the `PlanUpgradeEntryPoint.localModelGated` paywall CTA.
- `RAGService` automatically falls back to `OnDeviceAnalysis` after exhausting previews and raises `LocalModelAccessError.previewsExhausted` so UI copy stays consistent.

### Telemetry Events

- `preview_model_used` — Fired on each successful local run, includes backend + remaining allotment.
- `preview_exhausted` — Emitted when the final preview ticket is consumed.
- `preview_gate_triggered` — Logs when a user without tickets tries to activate local models.
- `preview_to_paid` — **New** conversion pulse emitted when a user who consumed previews upgrades to Pro/Lifetime (`preview_runs` metadata captures cumulative preview usage).

Keep these events enabled in release builds; the paywall team watches them for conversion funnels.

## 1. Model Selection & Quantization

### Recommended Model Sizes

- **iPhone 15 Pro / 16 Pro** (8GB RAM): 2–3B parameter models
- **iPhone 16 Pro Max** (8GB+ RAM): 3–7B parameter models
- **Future devices** (12GB+ RAM): 7–13B parameter models

### Quantization Strategy

| Quantization | Size (3B model) | Quality | Speed | Recommendation |
|--------------|----------------|---------|-------|----------------|
| **Q4_K_M** | ~2.0 GB | Excellent | Fast | ✅ **Recommended** – Best balance for iPhone |
| **Q5_K_M** | ~2.4 GB | Better | Moderate | Good for Pro Max or when quality critical |
| **Q8_0** | ~3.2 GB | Near-fp16 | Slower | Avoid on mobile (high memory pressure) |
| **Q2_K** | ~1.2 GB | Poor | Very fast | Too lossy; only for testing |

**Current Implementation**: `LlamaCPPiOSLLMService` accepts any `.gguf` file. Recommend **Q4_K_M** or **Q5_K_M** in user-facing documentation (Model Manager, import flows).

**Suggested Starter Models**:

- **Qwen2.5-3B-Instruct-Q4_K_M** (1.9 GB) – Strong reasoning, 32K context
- **Gemma-2-2B-It-Q4_K_M** (1.6 GB) – Google model, efficient on-device
- **Llama-3.2-1B-Instruct-Q4_K_M** (730 MB) – Ultra-light, 128K context

---

## 2. Metal GPU Acceleration

### Configuration

llama.cpp's Metal backend is automatically enabled when building for iOS device targets. Key parameters in `LlamaCPPiOSLLMService`:

```swift
// Current implementation uses defaults; future tuning:
let ngl: Int = 99  // Offload all layers to GPU (Metal)
let computePref: LocalComputePreference = .automatic  // User-configurable
```

**Compute Preferences** (exposed in Settings → Local Compute):

- **Automatic** (default): Metal GPU + Neural Engine when available
- **CPU Only**: Fallback for testing or extreme battery conservation
- **GPU Prioritized**: Force Metal acceleration (future enhancement)

**Metal Performance Tips**:

1. Always use Metal-compatible quantizations (Q4_K_M, Q5_K_M work optimally)
2. Avoid hybrid CPU/GPU splits on mobile (increases memory traffic)
3. Monitor GPU utilization via Instruments (Metal System Trace) during development

---

## 3. Context Window Management

### Context Limits

| Model | Max Context | Recommended Mobile Context |
|-------|-------------|----------------------------|
| Qwen2.5-3B | 32,768 | 8,192 (performance) / 16,384 (quality) |
| Gemma-2-2B | 8,192 | 4,096–8,192 |
| Llama-3.2-1B | 131,072 | 8,192 (massive window impractical on mobile) |

**Current Implementation**:

- RAG context assembly targets ~3,000 tokens (see `assembleContext()` in `RAGService`)
- User queries + retrieval typically fit within 4K–8K context
- `AutoTuneService` adjusts context caps based on model registry metadata

**Optimization Strategy**:

1. Keep RAG context compact (3–4 chunks @ 400 words ≈ 1,600 tokens)
2. Use `SemanticChunker` overlap (75 words) to maintain coherence without bloat
3. Monitor `HybridSearchService` MMR diversity to avoid redundant context

### Dynamic Context Scaling

```swift
// Future enhancement: Scale context based on battery state
let contextCap: Int = {
    guard let batteryLevel = UIDevice.current.batteryLevel else { return 8192 }
    if batteryLevel < 0.2 { return 4096 }  // Low Power Mode
    return 8192  // Normal
}()
```

---

## 4. Batch Size & Threading

### Batch Configuration

llama.cpp defaults to **batch_size = 512** for prompt processing and **batch_size = 1** for token generation (streaming).

**Mobile Tuning** (implemented in `GGUFClientRuntime`):

```swift
let batchSize: Int = 512  // Prompt processing (one-time cost)
let ubatch: Int = 256     // Micro-batch for generation (reduces latency spikes)
```

**Threading**:

- llama.cpp auto-detects CPU cores (iPhone 16 Pro: 6 performance + 2 efficiency cores)
- Use **4–6 threads** for inference (avoid saturating all cores to preserve UI responsiveness)
- `Task.isCancelled` checks in `RAGService` ensure cancellable queries

---

## 5. Memory Management

### Memory Footprint Estimates

| Component | Size (Q4_K_M 3B model) |
|-----------|------------------------|
| Model weights | ~2.0 GB |
| KV cache (8K context) | ~500 MB |
| OS + app overhead | ~1.0 GB |
| **Total** | **~3.5 GB** |

**Available RAM**:

- iPhone 15 Pro: 8 GB total, ~5–6 GB available for apps
- iPhone 16 Pro Max: 8 GB total, ~6 GB available (more aggressive memory compression)

**Best Practices**:

1. **Avoid multiple concurrent GGUF loads**: Use `GGUFClientRuntime` actor serialization
2. **Cache loaded models**: Current implementation caches `LlamaClient` instances by parameter set
3. **Monitor memory warnings**: Implement `didReceiveMemoryWarning` observer to flush caches

```swift
// Future enhancement in LlamaCPPiOSLLMService
NotificationCenter.default.addObserver(
    forName: UIApplication.didReceiveMemoryWarningNotification,
    object: nil,
    queue: .main
) { [weak self] _ in
    await self?.runtime.clearCache()
}
```

---

## 6. Streaming & Token Generation

### Current Implementation

`LlamaCPPiOSLLMService.generate()` uses **streaming mode** to emit tokens incrementally:

```swift
let stream = try client.textStream(from: input)
for try await chunk in stream {
    aggregated += chunk.content
    if firstToken == nil { firstToken = Date().timeIntervalSince(start) }
}
```

**Performance Targets**:

- **Time to First Token (TTFT)**: <2 seconds for 3B Q4_K_M on iPhone 15 Pro
- **Tokens per Second (TPS)**: 15–25 tokens/sec (device-dependent)

**Optimization Checklist**:

- ✅ Use streaming (non-blocking UI, user sees progress)
- ✅ Log TTFT + TPS telemetry (`TelemetryCenter.emit`)
- ⚠️ Avoid blocking main thread during generation (already handled via actor isolation)

---

## 7. Battery & Thermal Considerations

### Energy Efficiency

1. **Inference Cost**: GGUF generation draws ~3–5W on iPhone (vs. <1W for on-device NLEmbedding)
2. **Thermal Throttling**: Sustained inference (>60 sec) may trigger GPU throttling on older devices
3. **User Experience**: Prefer short bursts (3–5 sec generations) over long monologues

**Low Power Mode Detection** (future enhancement):

```swift
if ProcessInfo.processInfo.isLowPowerModeEnabled {
    // Switch to On-Device Analysis or reduce context window
    contextCap = 4096
}
```

---

## 8. Diagnostics & Troubleshooting

### Backend Health Checks

**Settings → Developer & Diagnostics → Backend Health → GGUF Local (iOS)**:

- **Verify Model File**: Confirms `.gguf` path exists and is readable
- **Run Smoke Test**: Generates 10-token sample to validate runtime

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| "GGUF model missing" error | File deleted or moved | Re-import from Model Gallery |
| Slow inference (<5 TPS) | Quantization too high (Q8_0) or overheating | Use Q4_K_M; wait for device to cool |
| Out-of-memory crash | Model >3B or context >16K | Use smaller model; reduce context cap |
| High battery drain | Continuous inference loop | Add `Task.isCancelled` checks; limit generation length |

### Telemetry Badges

Chat UI shows execution metadata:

- **TTFT**: Time to first token (ms)
- **TPS**: Tokens per second (real-time average)
- **Backend**: `GGUF Local` or fallback to `Apple Intelligence`

---

## 9. Future Enhancements

### Planned Optimizations

1. **Prompt Caching**: Cache system prompts to reduce TTFT for repeated queries
2. **Speculative Decoding**: Use smaller draft model + larger verifier (future llama.cpp feature)
3. **Quantization Autopilot**: Auto-select Q4_K_M vs. Q5_K_M based on available RAM
4. **Device Capability Gating**: Warn users on iPhone <15 Pro that GGUF inference may be slow

### Research Areas

- **Flash Attention**: llama.cpp support for Flash Attention 2 (reduces memory overhead)
- **Mixed Precision**: FP16 KV cache + Q4_K_M weights (future Metal optimization)
- **Core ML Hybrid**: Use Core ML for encoder + GGUF for decoder (experimental)

---

## 10. References

- **llama.cpp iOS Build Guide**: [Vendor/LocalLLMClient/README.md](../../Vendor/LocalLLMClient/README.md)
- **Model Registry**: [OpenIntelligence/Services/ModelRegistry.swift](../../OpenIntelligence/Services/ModelRegistry.swift)
- **GGUF Service Implementation**: [OpenIntelligence/Services/LlamaCPPiOSLLMService.swift](../../OpenIntelligence/Services/LlamaCPPiOSLLMService.swift)
- **User Documentation**: [userInstructions/ios-gguf-local-setup.md](../../userInstructions/ios-gguf-local-setup.md)

---

## Change Log

- **2025-11-12**: Initial version documenting Metal GPU, quantization, and context management best practices.
