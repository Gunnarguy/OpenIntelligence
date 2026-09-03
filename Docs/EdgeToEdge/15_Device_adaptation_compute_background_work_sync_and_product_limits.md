# Module 15. Device adaptation, compute, background work, sync, and product limits

Forty-four concepts. The power manager and the janitor: how hard the device may work, what runs in the background, how libraries sync, and what the tiers limit.

## The ladder

**Like you're five.** The phone checks what kind of phone it is and how hot it is, and decides how hard to work. When it's too hot, it slows down. Some chores wait until the phone is plugged in. If you have two devices, the library can be the same on both, carefully, so nothing gets deleted by accident.

**Like an idiot.** One configuration can't serve a fanless MacBook Air and an iPhone in a hot car. So the app detects the chip, memory and GPU limits once and hands every subsystem an envelope: batch sizes, concurrency, agentic depth, cooldowns. You get a GPU profile lever on top: Efficiency, Balanced, Performance, Maximum. Thermal and memory pressure dial the pipeline down. Background tasks let ingestion and index maintenance continue when iOS allows. iCloud sync exists so a library is the same on every device, with guards so a not-yet-downloaded file never looks like an empty library.

**Like less of an idiot.** Five device tiers from the chip: baseline (A17 Pro), enhanced (A18), advanced (A19), ultra-advanced (M-series), unsupported. From tier and memory come agentic step concurrency, step cooldown, vector batch, embedding batch, the matrix-multiply threshold, Vision concurrency, render concurrency and embedding concurrency. The GPU profile sets Core ML compute units, whether Metal may be used for the MMR matrix, and concurrency ceilings. An adaptive optimiser picks full, balanced, efficient or minimal per query from thermal state, memory pressure and complexity. Five background task identifiers are registered on iOS only. Sync is per-library, local-only or iCloud-shared, with tombstones, deletion-wins, a materialisation guard, a write-in-progress guard, and a signature cache so an unchanged store isn't re-read.

**Average Joe.** Why does the GPU profile exist as a user choice at all? Because the app cannot promise a utilisation percentage; it can promise a policy. Efficiency keeps models on CPU plus Neural Engine and avoids GPU vector work; Maximum removes internal limits. Why did Maximum get slower than Performance once? Because it requested CPU plus GPU, which excludes the Neural Engine. Why is "38 TOPS" on screen a lookup? Because Apple exposes no live Neural Engine measurement; the number is a per-chip table.

**Dot-connector.** The two guards that came from real data loss. The materialisation guard: iCloud reports a vector store exists but the bytes aren't downloaded; without the guard, that read as an empty library and triggered a destructive overwrite. Deletion-wins plus tombstones: a device that still has the last full copy would otherwise resurrect what you deleted. And the open defect lives here: a 1.68-second idle timer in `WorkspaceSyncService` that fires because a container's orphaned state never resolves. It used to reload every vector store per tick, 2,848 loads in 164 idle seconds; the router's on-disk signature check made it cheap; the timer is still there.

**Expert.** `DeviceCapabilityService`: `utsname` for the device model, `sysctlbyname("machdep.cpu.brand_string")` on Mac, physical memory, a Metal device query for GPU limits; TOPS lookup per chip (35 A17 Pro, 35/38 A18/A18 Pro, 38 every M4, 45 every M5; a new Mac was once tiered as M3-era because M5 was unknown, fixed late August). Ladder: agentic step concurrency 3 to 32, step cooldown 100 ms to 0, vector batch 128 to 16,384, embedding batch 8 to 512, Vision concurrency 2 to 64, PDF render concurrency 1 to 64 capped by a per-page memory estimate, embedding concurrency 2 to 64. GPU profile to compute units: query-side models Efficiency and Balanced `.cpuAndNeuralEngine`, Performance and Maximum `.all`; ingestion embedder Efficiency `.cpuAndNeuralEngine`, the rest `.all`. `AdaptivePipelineOptimizer`: thermal critical forces minimal; memory pressure critical forces efficient; serious thermal no longer throttles; battery alone no longer degrades; on Mac only thermal and memory matter; query timeout and step cooldown per level. `BackgroundTaskService` and `OpenIntelligenceApp`: continued ingestion, continued query (system-scheduled), index maintenance no earlier than 4 h and `requiresExternalPower`, Spotlight reindex no earlier than 2 h, app refresh no earlier than 30 min; iOS only. `IngestionLiveActivityService` updates within 0.5 s. `WorkspaceSyncService` (3,866 lines): debounce 2 s, bootstrap conflict detection, merge plan, tombstones, deletion-wins, materialisation guard, write-in-progress guard, vector sync signature cache. `QuotaPolicy` for document and library limits and the free-tier Maximum daily allowance; `EntitlementStore` and `MonetizationPolicy` from StoreKit; `MaximumModeQuotaStore`. `SettingsStore` snapshotted at query start. `LoggingConfiguration` for levels, categories, buffering and redaction. `GPUComputeService` kernels: batch cosine similarity (plus SIMD and threadgroup variants), batch normalise, MMR diversity; buffer pool; residency set. `BNNSGraphService` for normalisation, matrix cosine, softmax, RRF arithmetic and pairwise similarity on Accelerate.

**Expert's expert.** Correction to the bank's GPU-profile entry: it does not gate the vector-search GPU path; module 06 has the two real conditions. The bank's "Performance profile moves sufficiently large searches to GPU" is the same error from the other side; large searches go to the GPU under any profile if a Metal device exists. "Metal Performance Shaders" appears as a concept; the kernels in `GPUComputeService` are custom Metal functions, so treat MPS as infrastructure vocabulary rather than a distinct code path. Unified memory is why the mmap-to-Metal handoff is near-zero-copy and also why Vision, Core ML and the vector store compete inside one process budget, which is what the throttle, the buffer pool and the memory-warning listener are for.

## Every concept

### AdaptivePipelineOptimizer (Core, verified) and Full, Balanced, Efficient, Minimal optimization levels (Core/Conditional, verified)
- **Idiot:** the dimmer switch, with four positions.
- **Dot-connector:** full is everything permitted; balanced disables some repeated work; efficient drops HyDE, compression and iteration and shrinks batches; minimal keeps only essential retrieval and generation with no agentic steps. Critical heat picks minimal, critical memory picks efficient.
- **Expert:** resolved per query after complexity and device state; adjusts features, candidate limits, context, rerank batch, agentic steps, cooldowns, timeout, thresholds and MMR.

### Balanced profile (Core, verified), Efficiency profile (Core, verified), Performance profile (Core, verified), Maximum GPU profile (Core, verified), GPU execution profile (Core, verified)
- **Idiot:** the user's four-position lever for how much silicon to use.
- **Dot-connector:** Efficiency keeps models on CPU plus Neural Engine; Balanced allows GPU for indexing and rendering; Performance allows all units; Maximum removes internal limits. It governs Core ML units, the MMR matrix and concurrency, not the vector-search GPU switch.
- **Expert:** `DeviceCapabilityService`; the `.cpuAndGPU` Maximum bug fixed 2026-08-26.

### BGTaskScheduler maintenance (Conditional, verified), Continued ingestion task (Conditional, verified), Continued query task (Conditional, verified)
- **Idiot:** chores that run when you're not looking.
- **Dot-connector:** continued tasks carry user-started work through backgrounding; maintenance waits for power and hours.
- **Expert:** five identifiers registered in `OpenIntelligenceApp` on iOS; index maintenance 4 h and external power; Spotlight 2 h; refresh 30 min.

### BNNSGraphService (Core, verified) and vDSP (Core, verified) and Unified memory (Core, verified)
- **Idiot:** the fast-maths library on the CPU, and the reason the GPU can read the same memory.
- **Dot-connector:** normalisation, matrix cosine, softmax, RRF arithmetic and pairwise similarity on Accelerate; unified memory enables near-zero-copy handoffs and means everything competes for one budget.
- **Expert:** `BNNSGraphService`; `vDSP_dotpr`, `vDSP_mmul`; `MTLResourceOptions.storageModeShared`.

### Core ML compute units (Core, verified) and Neural Engine (Core as a request, not a placement)
- **Idiot:** the list of chips the model is allowed to use; Apple picks.
- **Dot-connector:** `.cpuAndNeuralEngine` or `.all` from the profile; five lines in the app set them; no line places work on the Neural Engine; no API measures it.
- **Expert:** `MLModelConfiguration.computeUnits` in the embedding provider, reranker, YOLO, region detector, document classifier and the dormant QA model.

### Debounced workspace change (Core, verified)
- **Idiot:** wait two seconds so a burst of changes becomes one sync.
- **Dot-connector:** ingestion writes many artefacts; each one should not launch a full merge.
- **Expert:** `WorkspaceSyncService`.

### Device capability tier (Core, verified), DeviceCapabilityService (Core, verified), Hardware execution envelope (Core, verified), TOPS lookup (Support, verified)
- **Idiot:** what phone is this, and what's it allowed to do.
- **Dot-connector:** baseline, enhanced, advanced, ultra-advanced, unsupported; the envelope is the concrete constraints every heavy stage reads; TOPS is a table, not a measurement.
- **Expert:** detection at first access; consumers listed in the ladder.

### GPUComputeService (Conditional, verified) and Metal Performance Shaders (Conditional, vocabulary)
- **Idiot:** the graphics-chip maths service.
- **Dot-connector:** batch cosine, normalise and MMR kernels with CPU fallback; buffer pool; residency set.
- **Expert:** custom Metal kernels, not MPS calls per se.

### iCloud-shared sync mode (Conditional, verified), Local-only sync mode (Core, verified), WorkspaceSyncService (Conditional, verified), Sync bootstrap conflict (Conditional, verified), Sync merge plan (Conditional, verified), Sync write-in-progress guard (Core, verified), Shared vector-store materialization guard (Core, verified), Vector sync signature cache (Support, verified)
- **Idiot:** the same library on every device, without anything getting eaten.
- **Dot-connector:** per-library choice; a conflict when both sides have real libraries is surfaced, not auto-resolved; a deterministic merge plan preserves identity and deletions; sync writes can't trigger another sync; an undownloaded shared file aborts rather than overwrites; a matching signature skips deserialising every vector.
- **Expert:** `KnowledgeContainer.syncMode`; `WorkspaceSyncService`; the 20 s wait in ingestion is the same guard's cousin.

### Ingestion Live Activity (Conditional, verified) and Spotlight indexing (Conditional, verified)
- **Idiot:** progress on the lock screen, and your documents in system search.
- **Dot-connector:** durable progress without reopening; OS-level discovery without a remote service.
- **Expert:** `IngestionLiveActivityService` and the widget target; `SpotlightIndexService`; both iOS.

### LoggingConfiguration (Support, verified)
- **Idiot:** what gets logged and what gets hidden.
- **Dot-connector:** useful diagnostics without leaking document content or flooding storage.
- **Expert:** levels, categories, file buffering, redaction, shareable trace inclusion.

### Maximum-mode quota (Conditional, verified), QuotaPolicy (Core, verified), StoreKit entitlement (Core, verified)
- **Idiot:** what your plan lets you do.
- **Dot-connector:** libraries, documents and Maximum runs per day by tier, enforced in one place so UI and engine agree.
- **Expert:** `QuotaPolicy.documentLimit()`, `freeMaximumModeDailyLimit`; `EntitlementStore`, `MonetizationPolicy`, `MaximumModeQuotaStore`. Hard-boundary files.

### Memory pressure (Core, verified) and Thermal state (Core, verified) and Query timeout (Core, verified) and Step cooldown (Conditional, verified)
- **Idiot:** too hot, too full, too long, take a breath.
- **Dot-connector:** nominal, warning, critical memory; nominal, fair, serious, critical thermal; a hard latency boundary; a pause between heavy steps.
- **Expert:** `AdaptivePipelineOptimizer`; cooldown 100 ms on baseline down to 0 on ultra-advanced; GPU cache cleared on memory warnings. The bank anchors a query timeout to the optimiser; no `queryTimeout` identifier matched a grep, so treat the exact allowance as unverified; the 180 s recursive-research budget in module 11 is the verified wall clock.

### SettingsStore (Core, verified)
- **Idiot:** your settings, snapshotted.
- **Dot-connector:** a query reads one coherent state at start rather than live UI values mid-run.
- **Expert:** read by `QueryRuntimeCoordinator`; also where the Core AI default on the 27 systems is decided.
