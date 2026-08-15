# Current State

Updated: 2026-08-15
Branch/worktree: main, primary checkout
Last verified commit: e3fc0ee

<!-- Keep the line above as the bare short SHA and nothing else. The SessionStart hook parses it
     with `sed` then strips all whitespace, so prose appended after the SHA is swallowed into it and
     the hook reports the commit as missing from the repository. -->

## Objective

None active. The objective changed once during the session and both halves are finished: it began as
benchmark and fusion-weight work, then became **make Deep Think stop failing on device**, which it
now does. Pick from the recommendations below, or ask the owner.

## Status

Tree clean at `e3fc0ee`. Only `main` exists.

Deep Think produces answers on device. The last device capture returned a 3360 character answer with
a citation map over 20 sources, `Query failed` count 0, and `SmartReply` failure count 0.

## Completed

**Ten services built their session with the bare `LanguageModelSession()` initialiser and failed
deterministically.** That initialiser supplies no model and no instructions; every working path goes
through `FoundationModelSessionFactory`, which supplies `model: SystemLanguageModel.default`,
`tools:` and `instructions:`. Fixed at all ten. `SmartReply` had failed on **every run since
2026-07-30** and is now clean. The experiment that isolated it was an empty library with the
one-word query "Test" and zero retrieved chunks: the main answer generated normally and SmartReply
still failed, which ruled out content, guardrails, context size and token caps in a single run.

**A failure inside recursive research destroyed the answer the chain had already produced.**
`executeRecursiveResearch` has two call sites, and only the one passing `maxIterations: 5` was
guarded first. The one that actually fires in Deep Think passes `3`, which every device log states
plainly as `[RecursiveResearch] Iteration 1/3`. Both are guarded now.

**Citations resolved to the wrong document on any query with four or more chunks.**
`assembleContext` numbers sources *after* Lost-in-the-Middle reordering, while five call sites
rebuilt the citation list as `prefix(used)` of the pre-reordering array. It now returns `sources` in
label order and callers use it.

**Every citation tap was inert.** `GroundedAnswerView` built links with an ICU template of `$$1`,
which emits a literal `$` plus capture group 1, producing `citation://$3`.

**Deep Think reasoned over section headings instead of document text**, fixed by stemming the
keyword match and reading `chunk.metadata.sectionTitle`. Confirmed on device: session contexts went
from 67 characters to 855.

Also landed: disjoint session windows, a structured "still unanswered" line carried between
sessions, a title-routing turn, an evidence-driven research gate, and telemetry for the fusion
weights, the per-arm unique hit counts, and the citation map.

## Active Constraints

- **No em-dashes anywhere**, including Swift string literals.
- **`[Unreleased]` in `CHANGELOG.md` stays empty. New entries go under `## 5.0`.** v5.0 has **not**
  shipped; the App Store is on 4.9. `Docs/SHIPPED_VERSION.json` is the authority, and the preflight
  router reports this wrong.
- **A session instruction outranks prompt text.** Adding one to a service whose prompt already
  specifies a format will fight it. This regressed suggested questions within hours on 2026-08-14.
- **Do not do heavy file work while a benchmark is measuring, and do not profile heavily while
  reproducing a bug.** An instrumented run produced 10 memory warnings and 4 drops into efficient
  mode where a comparable un-instrumented run produced none.
- **Commits must not carry a `Co-Authored-By: Claude` trailer.**
- The pre-commit hook blocks a `.swift` change with no doc update. It is installed and active.
- Hard-boundary files still need the owner to name them. None were touched.

## Working Set

- `OpenIntelligence/Services/AIPlatform/AppleFoundationModels/FoundationModelSessionFactory.swift`,
  the only correct way to build a session. Read only, hard boundary.
- `OpenIntelligence/Services/LLM/LLMService.swift`, `generate` at line 537. Its generic `catch` logs
  Apple's real error case and the partial streamed text.
- `OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift`, both `executeRecursiveResearch`
  call sites and `getResearchDecision`.
- `Docs/EVALS.md`, the single entry point for measurement. Read it before quoting any number.
- `~/Desktop/Sigh.trace`, three runs of the Foundation Models Instruments template on device. Export
  with `xcrun xctrace export --input <trace> --xpath '/trace-toc/run[@number="N"]/data/table[@schema="ModelInferenceTable"]'`.

## Verification

- `xcodebuild test` -> **236 tests, 0 failures, `** TEST SUCCEEDED **`**, run after every commit this
  session, from `/private/tmp/oi-test-src`. `xcodebuild` deadlocks on this repository's own path; see
  `RUNBOOK.md` item 1b.
- Device capture 2026-08-15 -> Deep Think answered: 3360 characters, 2616 tokens, citation map over
  20 sources, zero failed queries, zero SmartReply failures.
- Instruments, Foundation Models template, run 3 -> 21 model inferences succeeded; 4 returned an
  empty `Response` with `assets: ""` and `deltasCount: 2`; `SessionTable` reports `Error Count: 0`
  for every one of them.

## Blockers / Unknowns

1. **`getResearchDecision` and the title-routing turn still return empty responses, cause unknown.**
   Contained, not fixed: both log a warning and keep the existing answer, so no query is lost. Apple
   reports no error, a `generatedTokenCount` of 21 to 49, `deltasCount: 2`, and an empty `Response`.
   Five hypotheses were tested and disproved: rate limiting, `@Generable` schema, prompt size, empty
   context, and the output token cap. **Verification path:** commit `2016394` logs the partial
   streamed text, so run one Deep Think query and read
   `grep -A7 "Non-GenerationError escaped" <device-log>`. Those 21 to 49 tokens are the last unknown.
2. **Two of the ten repaired services had never run their LLM path in production.** Repairing the
   call exposed untested generation, which is what degraded suggested questions.
   `ImageUnderstandingService`, `ClusterLabelService` and `QueryRewriterService` are in the same
   position and their output has not been reviewed on device.
3. **`doc_pack_addon` does not load from StoreKit.** `Missing products: doc_pack_addon` appears in
   every device capture while the other three products load. Revenue affecting, untouched.
4. **The fusion weight must not be set to one global value.** The offline sweep favours 0.00 on
   `qasper_external_v1`, but device telemetry shows the arms inverting between libraries: one query
   returned 137 vector-only against 3 lexical-only, another 58 against 28. See
   `Docs/RETRIEVAL_PIPELINE.md` item 16.

## Exact Next Action

**Read the partial streamed text from a fresh device capture.** It is the only unanswered question
left and is now one grep away:

```bash
grep -A7 "Non-GenerationError escaped generation" <device-log>
```

Run one Deep Think query against a library that reproduces it (the neuroscience corpus does), using
the Foundation Models Instruments template **alone**, or no profiling at all. The `partialText` line
shows what the model emitted before the response resolved to empty. That decides whether this is a
refusal, a stop-token artefact, or something else, and replaces five disproved hypotheses with an
observation.

### If the owner wants product work instead

- **Delete the structure and keyword boost stage.** Measured over 72 cases: 22 better, 21 worse,
  p = 1.0. It reorders 43 of them and buys nothing. See `Docs/EVALS.md`.
- **Review the on-device output of `ImageUnderstandingService`, `ClusterLabelService` and
  `QueryRewriterService`.** See Blockers 2.
- **Fix `doc_pack_addon`.** See Blockers 3.
