# Quality-Mode Verification — Standard, Deep Think, Maximum

> **Purpose:** settle whether the three quality modes work, and what they buy.
> **Date:** 2026-07-30 · **Surface:** native macOS build, Apple Foundation Models available on host
> **Corpus:** `Benchmarks/rag_eval_v1.jsonl` (20 ground-truthed cases) · **Runner:** `scripts/run_quality_matrix.py`
> **Raw data:** `BenchmarkRuns/20260730-091821-matrix/` (60 runs, 21.5 min)

---

## 0. RESOLVED — 2026-07-30, commit `665da0a`

> **The cause was found. Everything from Section 1 down is the investigation trail that led there; it is preserved because two of its conclusions were wrong in instructive ways, and because the symptom data is still diagnostic.**

**Root cause.** `RAGService.generateWithProperConsent` declares `sourceChunks: [RetrievedChunk] = []`, and 13 of its 14 call sites rely on that default because they pass evidence as an already-rendered `context` string. `executeReasoningChain` goes further and passes `context: ""` deliberately — `buildChainPrompt` already embeds the documents in the prompt text, and passing them again double-rendered into 4521-token overflows against a 4096 budget. So `makePostRetrievalModelPlan` computed `chunkCount == 0`, `PostRetrievalEvidence.isSufficient` returned false, the planner set `.abstain`, and `.abstain` threw `RAGServiceError.modelNotAvailable`.

That error string is what the user saw. The evidence was real and on-target the entire time; it was inside `prompt`, where the planner could not see it. Only Deep Think and Maximum route through this path, which is exactly why Standard was unaffected.

**A third wrong conclusion, corrected.** This document states the failure is macOS-specific and that scope beyond macOS is unknown. That is wrong. iPhone (A18 Pro) device logs show the identical `RAGServiceError.modelNotAvailable`. The defect was always cross-platform. The earlier belief came from testing macOS rigorously through the UI while iPhone was only checked casually.

**A second failure was hiding behind the first.** Replacing the bogus error with a grounded abstention was not sufficient: all eight sessions then returned the abstention text *as their insight*, which was condensed and fed to the final PCC synthesis — telling the synthesizer there was no evidence while twenty chunks sat beside it. Self-RAG accepted that at 85% confidence. The mode did not crash; it silently degraded to Standard-with-PCC while reporting success.

**Fixes** (all in `665da0a`): thread real chunks into the planner; pin chain sessions on-device via `forceOnDevice`; return a grounded abstention instead of an availability error; cut `PRIOR FINDINGS` at sentence boundaries in both truncation paths; strip fabricated structured output from insights and stop the prompt wording from priming it.

**Verification** — four physical-device runs, final run A/B'd against the prior run on an identical corpus:

| Metric | Before | After |
| :--- | ---: | ---: |
| Sessions emitting fabricated JSON | 3 of 8 | **0 of 8** |
| Citations verified | 13/16 | **14/17** |
| Total tokens | 3562 | **3342** |
| Wall clock | 111.6s | **99.4s** |

The qualitative signal: session 6 corrected session 2, writing *"Neither documents nor the prior findings mention that PCC is triggered specifically when the context exceeds 32,000 tokens"* after session 2 had asserted exactly that. Cross-session self-correction against the sources is the behaviour the mode exists to produce.

**Still open.** Deep Think has no `rag_eval_v1.jsonl` score — it was verified against a personal library, not the dataset. The central question this document set out to answer, *does more compute buy more correctness*, remains unanswered, because until this fix the extra compute produced nothing. Two follow-ups are tracked separately: the confidence ceiling that makes early exit unreachable, and the unmeasured figures circulating in the app's own corpus.

`[evidence_level: device_verified, confidence: high_for_iOS_unverified_for_macOS, evidence_source: four iPhone A18 Pro runs 2026-07-30, commit 665da0a]`

---

## 1. Verdict

| Mode | Status | Evidence |
| :--- | :--- | :--- |
| **Standard** | ✅ **Verified working** | 20/20 runs completed, 80% accuracy, zero hallucinations |
| **Deep Think** | ✅ **Fixed in `665da0a`** — was broken as described below | Root cause in §0. Verified on four iPhone device runs |
| **Maximum** | ⚠️ **Same root cause, fix not separately verified** | Shares `executeReasoningChain`, so the fix applies; no device run yet |
| **iOS** | ✅ **Tested and fixed** — and it was *also* broken | The "macOS-specific" claim below is wrong; see §0 |

> ### Confirmed through the normal chat interface, not the harness
>
> An earlier version of this document hedged that the failure might be a benchmark artifact. **It is not.** The macOS app was launched normally — no launch arguments, no validation harness — and the question was typed into the chat box with documents already in the library:
>
> - **Deep Think** → *"The selected model isn't available right now. Please try again."*
> - **Standard**, same question, same library, immediately after → answered in 8.2s at 99% confidence, badged `On-device · Standard · Verified`
>
> Back-to-back control in one session. Standard works; Deep Think does not. This is what a macOS user experiences today.

> ## The failure is real on macOS. Scope beyond macOS is unknown.
>
> Two earlier conclusions in this investigation were **wrong** and are corrected here:
>
> 1. *"It's a headless-harness limitation."* Wrong — it reproduces in the app's own UI path.
> 2. *"It's an unsigned-build artifact; the entitlement fixes it."* Wrong — a build signed **with** `com.apple.developer.private-cloud-compute` fails identically. The signed+sandboxed run that appeared to succeed had retrieved **0 chunks** (sandbox blocked fixture access) and logged `HARD EXIT: Retrieved content is irrelevant` with `LLM Calls: 1` — it exited early and **never entered the reasoning chain**. It proved the early-exit path works, not the agentic path.
>
> **Confirmed failing across three distinct macOS build configurations:** unsigned/no entitlement, signed+sandboxed+entitled, and signed+unsandboxed+entitled.

### Exact failure point

```
[ReasoningChain] Starting dynamic 4-8-session chain
[ReasoningChain] Built 8 rotating contexts (662 chars, 4 chunks/session, stride 2)
[ReasoningChain] DEEP THINK MODE: Dynamic 4-8 sessions, targeting 95% confidence
[ReasoningChain] Session 1/4-8 (deep think, confidence: 10%)
[ReasoningChain] Session 1 context (662 chars): [S1] (case_1_part_b.md)
[Agentic] Failed: The selected LLM model is not available
```

Everything upstream is healthy: ingestion, retrieval (4 sources, 13 sentences), context rotation, and session planning all succeed. The **first generation call inside `executeReasoningChain`** throws. That call routes through `RAGService.generateWithProperConsent` → `makePostRetrievalModelPlan` → `FoundationModelSessionFactory`.

Notably, an **earlier generation in the same run succeeds** — the multi-query expansion logs `[GENERATION] Apple FM: Generation started – {execPref=onDeviceOnly, pccAllowed=false, route=onDevice}`. So the model is reachable in that process; something specific to the reasoning-chain call path is not.

**The failure is not random.** Deep Think and Maximum complete whenever the planner shortcuts to `Direct Source Extraction`, and fail whenever the multi-session reasoning chain engages:

| Category | Standard | Deep Think | Maximum |
| :--- | :---: | :---: | :---: |
| exact_value (shortcut-eligible) | 5/5 ran | 2/5 ran | 1/5 ran |
| lost_in_middle | 3/3 ran | 3/3 ran | 3/3 ran |
| retrieval_only | 5/5 ran | **0/5** | **0/5** |
| multi_hop | 5/5 ran | **0/5** | **0/5** |
| missing_evidence | 2/2 ran | **0/2** | **0/2** |

---

## 2. What is confirmed about the failure

Traced on the `multi_hop_project_m1` case through the UI path:

1. Retrieval succeeds **well** — 45 results fused into 9 unique chunks, lexical relevance 80%, reranker score 0.90, quality graded `Excellent`.
2. The orchestrator engages correctly: `[Agentic] Excellent retrieval → reasoning chain`, then `Using 5-session reasoning`.
3. Generation is requested on-device: `{execPref=onDeviceOnly, pccAllowed=false, route=onDevice}`.
4. The run then fails with `LLMError.modelUnavailable`.

So the pipeline is healthy right up to multi-session synthesis. **Retrieval, ranking, and routing are not implicated.**

### Ruled out

| Hypothesis | Test | Result |
| :--- | :--- | :--- |
| Harness/headless artifact | Re-ran through the app's own UI path | Same error |
| State contamination between runs | Isolated `HOME` per run | Same error |
| Ingestion failure | Reports show documents ingested | Not the cause |
| Timeout | Runs exit in ~14s against a 900s limit | Not the cause |
| Concurrent-session limit in Apple's SDK | Standalone probe created 6 `LanguageModelSession`s and generated on all 6 | All succeeded — **not the cause** |
| PCC consent leaking into the route | Log shows `pccAllowed=false, route=onDevice` | Not the cause |
| Missing PCC entitlement (unsigned build) | Rebuilt signed with the entitlement, sandbox off | **Fails identically — not the cause** |
| App Sandbox blocking something | Tested signed+sandboxed and signed+unsandboxed | Both fail once the chain is reached |
| Model unreachable in the process | An earlier generation in the same run succeeds on-device | Model **is** reachable — not the cause |

### Where the cause must lie

Given the above, the fault is inside the reasoning-chain generation path specifically:
`executeReasoningChain` → `RAGService.generateWithProperConsent` → `makePostRetrievalModelPlan` → `FoundationModelSessionFactory`.

Standard mode never enters this path, which is exactly why it is unaffected. The next diagnostic step is to log the resolved `ModelExecutionTarget` and factory branch at the moment of the throw — `RouteEvalMetrics` receipts would capture this if a receipt were produced, but the throw happens before one is written.

### Narrowed to a precise location

Instrumented every `LLMError.modelUnavailable` throw site and re-ran. Results:

- `FoundationModelSessionFactory` was called twice — `route=automatic`, then `route=onDevice` — and **threw at neither**. Session creation succeeds.
- The `ensureSession` main-thread guard (`LLMService.swift:490`) did **not** fire.

That leaves the `guard let session = session else { throw LLMError.modelUnavailable }` checks immediately after `ensureSession` (`LLMService.swift:579` for the streaming path, `:902` for the structured path). The factory reports creating a session, yet the service's `session` property is still `nil` when the reasoning chain reads it.

**This is the bug to fix.** It is a lifecycle/assignment problem in `AppleFoundationLLMService`, not a model-availability, entitlement, routing, sandbox, or threading problem — all of which were tested and excluded.

### iOS: cannot be tested in the Simulator

The iOS 27 Simulator has **no Apple Intelligence at all**. Running the same case there logs:

```
AppleFoundationLLMService unavailable on Simulator
Running in Simulator - Foundation Models unavailable
❌ No configured LLM available; Apple Intelligence is REQUIRED
```

The app detects this correctly and installs `AppleFoundationLLMServiceUnavailable`. This is an Apple platform limitation, not a defect — but it means **iOS verification requires a physical device**, and no amount of simulator work can substitute.

**The single highest-value next test:** on a physical iPhone running the shipped app, import two related documents and ask a Deep Think question that requires combining them.

- **It answers** → the bug is macOS-only. macOS 4.8 is in review and should be held; iOS ships safely.
- **It fails the same way** → cross-platform, and both submissions should be pulled.

Given that Deep Think has shipped since v4.4 and is the app's headline differentiator, prolonged total failure on iOS would likely have been noticed already — but that is inference, not evidence, and this document does not treat it as verified.

---

## 3. Standard baseline (fully verified)

20/20 runs completed. **16/20 correct (80%). Zero hallucinations.**

| Category | Score |
| :--- | :--- |
| retrieval_only | 5/5 |
| lost_in_middle | 3/3 |
| missing_evidence | 2/2 |
| multi_hop | 4/5 |
| exact_value | 2/5 |

**Both negative controls refused correctly** — the app declined to invent confidential pricing or unreleased battery-warranty terms. That is the verification-gate premise holding under measurement.

**Lost-in-the-middle is solved at this corpus size** — 3/3 regardless of whether the answer sat at the start, middle, or end of context.

### The four misses

Three of four are **over-conservatism, not fabrication** — the safe direction to fail, but it still costs the user an answer:

- `exact_capex` — abstained ("not available in the provided document context") when `$1,577 million` **is** in the document.
- `exact_temperature_limit` — abstained on a value present in the battery-limits table.
- `multi_hop_project_m2` — drafted a plausible answer, then self-flagged `⚠️ [Needs Verification] could not be strictly verified against the retrieved evidence`. The gate fired on its own work.

One is a **genuine false statement**: `exact_service_interval` returned *"The normal service interval is **30 minutes**"*, which is not a service interval. One confident error in 20.

---

## 4. Two scoring bugs found in the runner (corrected)

Recorded because the first version of this matrix produced a **false headline** — "Standard 75%, Deep Think 20%, Maximum 20%", i.e. *more compute makes it worse*:

1. **Empty runs were scored as wrong answers.** A mode that could not run is not a mode that answered badly. The report now separates `Measured` from `Unmeasured` and computes accuracy over measured runs only.
2. **Abstention detection was too narrow.** *"I do not have access to confidential pricing information"* is a correct refusal, but the pattern missed that phrasing and scored it a **hallucination** — defaming the exact behavior the gates exist to produce. Broadened, with the bias deliberately set toward under-reporting hallucinations.

Corrected results are the ones above. Fixed in commit `b1ff48c`.

---

## 5. What this does not yet answer

- **Does Deep Think / Maximum work in the shipped app?** Pending the signed-build test. The App Store builds carry the PCC entitlement, so they may be unaffected.
- **Does more compute buy more correctness?** Unanswerable until the modes run. Of the few Deep Think and Maximum runs that did complete, all were `Direct Source Extraction` shortcuts, which by definition do not exercise reasoning.
- **Per-stage timing.** The signposts landed in this session but the matrix does not yet consume them; `xcrun xctrace` on a physical device is Phase C.

---

## 6. Reproduce

```bash
# Full matrix (about 20 minutes)
python3 scripts/run_quality_matrix.py --app <path/to/OpenIntelligence.app>

# One mode
python3 scripts/run_quality_matrix.py --app <...> --modes standard

# One case through the app's UI path, which is what proved the failure is real
<App>/Contents/MacOS/OpenIntelligence --rag-validation --rag-validation-visual \
  --rag-validation-query "Who owns Project M1 and what is its reporting deadline?" \
  --rag-validation-files "<repo>/Benchmarks/ResearchFixtures/tiny_research_suite/fixtures/synthetic/multi_hop/case_1_part_a.md,...part_b.md" \
  --rag-validation-quality deep-think --rag-validation-storage /tmp/verify \
  --rag-validation-pcc-consent deny --rag-validation-entitlement lifetime
```

`[evidence_level: test_verified, confidence: exact_for_unsigned_macos_build_unknown_for_signed, evidence_source: BenchmarkRuns/20260730-091821-matrix, UI-path run 2026-07-30T17:06Z, multi-session SDK probe]`
