# Current State

Updated: 2026-08-17
Branch/worktree: main, primary checkout
Last verified commit: acb86f5

<!-- Keep the line above as the bare short SHA and nothing else. The SessionStart hook parses it
     with `sed` then strips all whitespace, so prose appended after the SHA is swallowed into it and
     the hook reports the commit as missing from the repository. -->

## Objective

**Finish the embedding-quality arc.** Three defects were found on 2026-08-17, two fixed and one
diagnosed but not fixed. The open one is the largest.

**The Core AI embedding export reads the wrong output of the model.** `scripts/compile_core_ai_model.py`
wraps `all-MiniLM-L6-v2` and returns `last_hidden_state[:, 0, :]`, the CLS token, from a model trained
for **mean pooling**. It also takes only `input_ids`, so there is no attention mask and the CLS token
attends across padding. The Core ML provider, by contrast, mean-pools with a mask and is correct.

**Measured consequence, `BenchmarkRuns/coreml-provider` against `cmp-standard`: `vector r@1` moves
from 0.000 to 0.500 at n=4.** Early, but zero to half is not a subtle shift. **MiniLM is very likely
not the problem; the export is.**

**Worse: `EmbeddingService` routes iOS/macOS 27+ to the broken Core AI path and everything older to
the correct Core ML one**, calling the correct one a "fallback". Upgrading the OS silently degrades
retrieval.

**Next action:** finish the `coreml-provider` run (25 cases, started 12:47), then re-export the Core
AI model with mean pooling and an attention mask so iOS 27 keeps the new framework **and** correct
vectors. The owner was explicit that dropping iOS 27 back to Core ML is not acceptable. The toolchain
is installed at `/private/tmp/oi-export-venv` (torch 2.11, transformers 5.15, coreai-torch 0.4.1), so
no further downloading is needed; the owner is on a slow connection.

**Full instructions, written to be executed cold with no memory of this session:
`Docs/Engineering/EMBEDDING_MEAN_POOLING_REEXPORT.md`.** It explains what pooling is from first
principles, gives the exact before/after Python, names the Swift change the new two-input model
forces, lists four verification steps in order, and states what must not be done first. Read it
before touching the export; do not re-derive any of it.

**Do not evaluate bge-small until this is done.** Comparing a candidate against a misconfigured
incumbent is the confound this whole arc has been avoiding.

## Status

Tree clean at `fbd6dce`, everything pushed, **CI green**, nothing running.

**Do not push casually.** Every push triggers an Xcode Cloud build and the owner is near his usage
limit. Nine CI runs fired on 2026-08-16, three for docs-only commits, because `ci.yml` has no
`paths-ignore`. Commit locally and let the owner batch the push.

**v5.0 roadmap, verified against Notion 2026-08-16: 29 Completed, 5 In Progress, 23 To Do.** Nine
completed rows closed in the last three days and **seven of those nine did not exist as rows
beforehand**, having been found on device and written down afterwards. That is why the open count did
not fall while the work was happening. Of the 23 open, three are ship blockers and the rest are the
unbuilt overhaul.

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

**Benchmark runs can no longer damage the owner's library, proven live rather than argued.** Two
independent holes: `reset_shared_library` deleted anything outside a hardcoded four-entry allowlist,
which removed six real documents on 2026-08-16, and every write landed in the real library anyway
because `WorkspaceSyncService.init` calls `configureBaseDir(nil)` during ordinary activation and
silently voided the `--rag-validation-storage` override. The reset is now additive-only against a
snapshot and refuses to delete without one, and `pinOverrides` makes the override unclobberable,
covering the cache directory too. Verified with a full ingesting run: real listing, metadata md5 and
FTS5 database all byte-identical afterwards, 4 refused clobber attempts logged. **No hard-boundary
file was edited.**

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
2. **The App Store build pins Xcode 26.5, so no iOS 27 API can ship.** `.github/workflows/appstore.yml`
   selects 26.5, and every iOS 27 type added on 2026-08-16 sits behind `#if compiler(>=6.4)`, so the
   error-taxonomy work compiles out of the release binary and reaches no user. A decision, not a
   defect: move the release toolchain, or accept that iOS 27 adoption is deferred. Tracked in Notion.
3. **`iWork import is advertised but cannot read any file iWork produces`.** Roadmap row, High, not
   re-verified this session. The only open item with outside-facing risk, because the App Store
   listing claims a format the app may not open. Verify before shipping anything.
4. **The grounding gate at `AgenticPolicyService:180` is still asymmetric.** The destructive
   replacement it caused is guarded; the gate preferring uncited answers is not.
5. **Two dead question validators.** `isAnswerableSuggestedQuestion` and `isUsableGeneratedQuestion`
   have zero call sites, and a real fix placed in the first one silently did nothing. The first
   holds a full answer-intent switch that may be worth wiring rather than deleting.
6. **The real FTS5 index holds roughly 4077 document ids for about 15 documents**, residue from runs
   before the storage pin landed. New runs no longer add to it; the residue was not cleaned.
7. **`doc_pack_addon` does not load from StoreKit.** Revenue affecting, untouched all session.
8. **The QASPER fixture cannot measure answer quality.** 22 of 76 cases are graded by a bare
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
