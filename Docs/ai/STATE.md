# Current State

Updated: 2026-08-16
Branch/worktree: main, primary checkout
Last verified commit: e8fbd6e

<!-- Keep the line above as the bare short SHA and nothing else. The SessionStart hook parses it
     with `sed` then strips all whitespace, so prose appended after the SHA is swallowed into it and
     the hook reports the commit as missing from the repository. -->

## Objective

None active. The 2026-08-15/16 objective was "make Deep Think measurably better than 4.9". Seven
defects were found and fixed, every one present in `v4.9.0` and none a 5.0 regression. **The
comparison itself was never made and cannot be until Blocker 1 is resolved.** Pick from the
recommendations below, or ask the owner.

## Status

Tree clean at `e8fbd6e`. Everything pushed. Nothing running.

The answer collapse is fixed, and it is the one quality result that is not noise-limited: on a fixed
6-case set the pre-fix baseline stubbed 3 of 6 into 136 to 443 character answers and the current
build stubs 0 of 6, every answer between 2993 and 3415 characters. It is defensible because the
mechanism is understood and guarded at both call sites, not because a number moved.

**Two housekeeping facts a new session must know:**

1. **Six of the owner's documents were deleted by benchmark runs on 2026-08-16 and restored** from
   `/private/tmp/oi-library-backup-20260815-0109`. The library holds its original 14 files plus
   `1911.10742.md`, a benchmark fixture left in place rather than deleted. That backup is the only
   copy and lives in `/private/tmp`, which does not survive a reboot.
2. **The FTS5 index holds 4077 distinct document ids for roughly 15 documents.** Runs re-ingest
   under fresh UUIDs and `--reset-shared-library` does not clean the index, so pollution
   accumulates. Not shown to affect app behaviour, and not investigated.

## Completed

**Deep Think graded its citations against the wrong array, for the reasoning chain's entire life.**
Labels are built over `routeChunksByTitle`'s output, which reorders, and relabelled from `[S1]` in
every rotating 4-chunk window, while verification resolved them against the pre-routing array. Two
independent mismatches. Every citation tap resolved to a wrong source, and the verification loop
made keep-or-discard decisions from grounding scores computed against unrelated chunks.

**Recursive research searched for the literal word "query" in 83% of its invocations.** The prompt
read `[SEARCH: query]` and the on-device model copied the placeholder back: 49 of 59 searches across
16 of the 17 cases that reached the loop. It fires when Deep Think is least confident, so it failed
hardest where it was needed most.

**The verification loop replaced grounded answers with ungrounded ones**, and preferred them because
`AgenticPolicyService:180` retries on `groundingScore < 0.3 && totalCitations > 0` while an uncited
answer has grounding forced to 0.5 and skips the check entirely. Caught with both sides logged:
`2647 chars with 4 citations -> 53 chars with 0 citations`. Guarded at **both** call sites.

**Recursive research had no wall-clock bound.** Now 180 seconds, after a case blew a 1500s budget.

**Every Deep Think answer showed a fabricated 70% match score.** `topSim` and its neighbours were
hardcoded on the agentic audit snapshot and reached the UI. Now measured.

**Suggested questions** no longer come from bibliographies or running headers (validated against
5,425 real library chunks, 99.2% clean), no longer repeat a single sentence frame, no longer assume
every document is a research paper, and no longer ask "why" about rules a document states without
justifying. Verified end to end against a residential lease: 6 of 6 grounded, 0 reason-seeking.

**iOS 27 error taxonomy.** `LanguageModelSession.GenerationError` is deprecated wholesale and splits
into four types the app caught none of, so every Foundation Models error fell to a generic handler.
`GeneratedContent.ParsingError` carries `rawContent`, the raw model output, which is the evidence
that kept "Session ended without producing a response" undiagnosable for three days.

## Active Constraints

- **No em-dashes anywhere**, including Swift string literals.
- **`[Unreleased]` stays empty. New entries go under `## 5.0`.** v5.0 has not shipped; the App Store
  is on 4.9. `Docs/SHIPPED_VERSION.json` is authoritative and the preflight router reports it wrong.
- **Never build or test while a benchmark is measuring.** It starved a case into a 600s timeout.
- **One benchmark at a time**, and know that any run with `--reset-shared-library` writes into, and
  deletes from, the owner's real document library. Back it up first.
- Commits must not carry a `Co-Authored-By: Claude` trailer. The pre-commit hook blocks a `.swift`
  change with no doc update and is active.

## Working Set

- `OpenIntelligence/Services/RAG/Retrieval/HybridSearchService.swift`, `stableTieBreakKey` and the
  keyword-boost scoring. Where Blocker 1 lives.
- `OpenIntelligence/Services/RAG/Tuning/RetrievalPolicyService.swift:107`, the `0.28` floor that
  amplifies a small scoring difference into 77 dropped chunks.
- `OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift:180`, the grounding gate that
  still prefers uncited answers. Guarded downstream, not fixed.
- `scripts/watch_benchmark_defects.sh`, the defect watcher. `RUNBOOK.md` item 7 explains it.
- `BenchmarkRuns/qasper-deepthink-20260815/`, the 82-case pre-fix baseline.
- `BenchmarkRuns/tiefix-1` and `tiefix-2`, the two runs that establish Blocker 1.

## Verification

- `xcodebuild test` -> **236 tests, 0 failures**, run once per commit from `/private/tmp/oi-test-src`.
  `xcodebuild` deadlocks on this repository's own path; see `RUNBOOK.md` 1b.
- Six 6-case smokes, one per fix. Final run: 6 of 6 completed, 0 collapses, 0 timeouts.
- Suggested questions verified headlessly against a lease via `--rag-validation-questions`.
- **Nothing in this session ran on a physical device.** Every fix is compile, suite, and macOS
  benchmark verified only.

## Blockers / Unknowns

1. **Retrieval is nondeterministic, and it blocks every quality claim.** Two runs of one build over
   byte-identical documents diverge: keyword hit rate 90% against 91%, the `< 0.28` filter dropping
   77 chunks in one run and none in the other, MMR selecting 30 against 14, answers 190 against 350
   characters. **This is a product defect, not only a measurement one:** re-ingesting a document
   changes its answers, and two users holding the identical file get different evidence, which
   contradicts the grounded-and-attributable promise the app exists for.
   **Ruled out:** ingestion is deterministic (268 chunks in both runs, across all ten documents).
   The random UUID tie-break was real, was fixed in `d3226de`, and **the divergence survived it.**
   **Where it is:** the keyword hit rate is `hitCount / results.count` over the *candidate set*,
   computed from chunk text, so identical documents yielding 90% against 91% means the candidate set
   differs in membership before any tie-break runs. That places the origin in embedding or vector
   search, amplified by the `0.28` floor.
   **The trap:** `--rag-validation-skip-ingest` gives byte-identical output and looks like proof. It
   is confounded, because a reused index holds chunk ids fixed **and** skips re-embedding.
   **Exact next measurement:** embed one chunk twice in the same process and compare the vectors bit
   for bit. Check Apple's own documentation for whether reproducible embeddings are offered at all;
   this assistant's knowledge cutoff predates the SDK, so do not answer that from memory. If they
   are not reproducible, the fix is removing the threshold cliff rather than chasing determinism.
2. **Nothing from this session is in the Notion roadmap.** Notion returned 503 on every call on
   2026-08-16, so none of the 21 commits have a row. Use the `notion-roadmap` skill; never answer a
   roadmap question from `Docs/ROADMAP.md` or from memory.
3. **The grounding gate at `AgenticPolicyService:180` is still asymmetric.** The destructive
   replacement it caused is guarded; the gate preferring uncited answers is not.
4. **Two dead question validators.** `isAnswerableSuggestedQuestion` and `isUsableGeneratedQuestion`
   have zero call sites, and a real fix placed in the first one silently did nothing. The first
   holds a full answer-intent switch that may be worth wiring up rather than deleting.
5. **`doc_pack_addon` does not load from StoreKit.** Revenue affecting, untouched all session.
6. **The QASPER fixture cannot measure answer quality.** 22 of 76 cases are graded by a bare
   `(?i)Yes` or `(?i)No` substring against a multi-thousand-character answer, matching inside "not"
   and "know".

## Exact Next Action

**Put the current build on a physical device and run one Deep Think query against a real document.**

Nothing from this session has run on hardware. Seven fixes are compile-and-benchmark verified only,
and one of them, the iOS 27 error taxonomy, exists specifically to capture evidence that has only
ever appeared on device. Capture the log and run:

```bash
grep -A6 "GeneratedContent.ParsingError" <device-log>
```

`rawContent` is the raw model output behind "Session ended without producing a response". That
either closes the three-day question outright or shows the failure is gone.

Then take Blocker 1. Do not run another A/B before it is resolved: a second uncomparable run costs
hours and settles nothing.
