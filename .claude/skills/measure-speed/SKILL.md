---
name: measure-speed
description: Use before and after any change meant to make OpenIntelligence faster (Deep Think, answers, import, launch, Chat open, library switch, sync), and before claiming anything is slow, faster, or "lightning speed". Gives the measured time budget to start from, the commands that read timings off the iPhone, the Simulator and the Mac, and the accuracy checks a speed change must pass. Triggers on "make it faster", "speed", "slow", "lag", "stall", "hang", "how long does X take", "where does the time go", and on any change to embedding, retrieval, reranking, model calls or main-thread work.
---

# Measure speed, keep accuracy

The owner's standing goal (2026-11-04): every process much faster, with no loss of accuracy, quality
or citations. A speed change here is two numbers and a check: the time before, the time after, and
proof the output did not get worse. Any one of the three missing means the change is not done.

## Start from the measured budget, not from a guess

Measured on his iPhone 16 Pro Max on 2026-11-04 (two uncontended Deep Think runs, 270.7 s and 236.2 s;
`~/Library/Developer/OpenIntelligence-evidence/2026-11-04_141602` and `_145216`):

| Stage | Mean | Share |
|---|---|---|
| Five evidence sessions (model) | 113 s | 44% |
| Synthesis (model) | 56 s | 22% |
| SourceOnly pass that was then declined (run 1 only) | 46.7 s | 18% of run 1 |
| Multi-query search, 5 sub-queries at about 3.6 s each | 17 s | 7% |
| Chain setup (model) | 12 s | 5% |
| Unlogged gaps before the first model call | 6 to 9 s each | |

Model calls are 59% to 78% of a Deep Think answer. Decode is about 19 tok/s, so every 100 output
tokens is about 5.5 s, and time to first token is 1.4 to 6.4 s per call. The cheapest seconds are
model calls that never happen and output tokens that are never generated. Elsewhere: chat-open
main-thread stalls (93 at or above 250 ms, longest 57 s), library analysis recomputed 55 times
(median 2.8 s), PDF extraction 65% of PDF import time, background-task embedding 5.6 times slower than
foreground. The full budget, its sources and the research behind this skill are in
`BenchmarkRuns/2026-11-04-speed-research/` (local and gitignored, like every run folder: never delete it).

## Read timings, in this order

1. **The iPhone, after he has used the build:** `python3 scripts/phone_evidence.py --since <install time>`
   pulls the journal (`verification_events.jsonl`) and `pipeline_trace.log`. Stage lines in the trace
   carry millisecond timestamps; diff consecutive lines. The trace holds his questions and file names:
   grep for what you need, never print it whole, never commit it.
2. **Model calls on the device:** the Instruments "Foundation Models" template (Xcode 27 ships it;
   `xcrun xctrace list templates`). It splits each call into prefill, decode and token counts, which
   the trace cannot. The trace file stores his documents unencrypted; keep it out of the repo.
3. **Main-thread work in the Simulator:** launch the Debug build, then
   `sample <pid> 4 -file <out>` and read the `com.apple.main-thread` subtree. Count samples in app
   frames against `__CFRunLoopServiceMachPort` (idle). The module's default isolation is the main
   actor, so plain classes run there unless marked `nonisolated` or `@concurrent`; this is how the
   embedding provider was caught doing tokenizing and pooling on the main thread.
4. **Embedding throughput:** launch with `-embeddingBenchProviders` (`OpenIntelligence/App/DebugEmbeddingBench.swift`);
   it writes `Documents/embedding_bench_providers.json` with passages per second per round. Compare
   rounds of the same build before comparing builds; the Simulator runs Core ML on the CPU, so use it
   for before-and-after, never for absolute figures.

Run experiments on the build copy (`/private/tmp/oi58-src`), not the repository, when the code is
out of bounds (`.claude/rules/ingestion-and-indexing.md` puts provider internals there): patch the
copy, measure, save the diff, and hand him the patch with its numbers.

## Accuracy checks a speed change must pass

- **Same inputs, same outputs, when the change claims to change nothing.** Executor or caching
  changes must give bit-identical vectors and identical retrieval order. Write the comparison as a
  test (240 passages, one at a time against the concurrent batch, `maxAbsDiff == 0` is the bar; see
  the 2026-11-04 off-main embedding experiment).
- **Retrieval changes** (rerank depth, candidate counts, fusion weights, quantized vectors) need the
  retrieval benchmark before and after, flag-for-flag (auto memory `running-the-retrieval-benchmark.md`),
  and the metric pitfalls in `retrieval-metric-pitfalls.md`. Literature says a strong first stage needs
  a rerank depth of about 20; that is a hypothesis to measure here, not a setting to copy.
- **Model-call changes** (fewer calls, shorter outputs, merged sessions, prewarm) need the same
  questions answered before and after with citations compared, because greedy decoding still words
  answers differently between a cached and a cold session.
- Never use abstractive or token-pruned context compression: it measured 0.12 citation precision
  against source spans (arXiv 2609.14245). Extractive selection of whole passages keeps citations checkable.

## Contamination

A timing taken while another job used the model or the CPU is not a timing. Side jobs (suggested
questions, enrichment, analysis) halved decode speed on 2026-11-04 before they were made to yield.
A rebuild loop, a background grant, rate limiting (iOS limits the on-device model in the background)
or a game in front (timers run about 14 times slow) each void a run. Say which runs were clean.

## Report

Every speed claim gets `[evidence_level: measured, confidence: ...]`, the device, the build and the
evidence folder. "Faster in the Simulator" and "faster on his iPhone" are different claims; a roadmap
row about speed closes only on the device where the slowness was seen.
