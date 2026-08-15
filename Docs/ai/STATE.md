# Current State

Updated: 2026-08-15
Branch/worktree: main, primary checkout
Last verified commit: ccc0eeb

<!-- Keep the line above as the bare short SHA and nothing else. The SessionStart hook parses it
     with `sed` then strips all whitespace, so prose appended after the SHA is swallowed into it and
     the hook reports the commit as missing from the repository. -->

## Objective

Make Deep Think measurably better than 4.9. Four defects found and fixed today, all of them
long-standing rather than 5.0 regressions. **Whether the app is better than 4.9 is still unanswered,
and the reason it is unanswered is now understood.** See Blocker 1.

## Status

Tree clean at `ccc0eeb`. **Nine commits unpushed, deliberately.** Do not push without asking; the
owner asked to stop burning Xcode Cloud minutes until the device work settles.

A 6-case smoke is running against `ccc0eeb` in `BenchmarkRuns/smoke-deepthink-ccc0eeb`, verifying
the citation guard on the case that exposed it. A defect watcher is attached.

## Completed

**Deep Think graded its citations against the wrong array, for its entire existence.** The chain
labels `[S1]...[Sn]` over `routeChunksByTitle`'s output, which is a **reordering**, and it relabels
from `[S1]` in every rotating 4-chunk window. `runVerificationLoop` resolved those against
`allRetrievedChunks`, the pre-sort pre-routing order. Two independent mismatches. Across the 82-case
run the distinct cited numbers were S1..S4 plus two strays, never spanning the 20 sources.
`ReasoningChainResult` now carries `routedChunks`, verification uses it, and the window passes
`labelOffset`. `allRetrievedChunks -> sorted -> routed` were confirmed to be permutations of one set
with nothing dropped **before** the swap.

**Recursive research searched for the literal word "query" in 83% of its invocations.** The prompt
read `Reply with [ANSWER] (your answer) OR [SEARCH: query]` and the on-device model copied the
placeholder back: **49 of 59 searches, across 16 of the 17 cases that reached the loop.** Each
retrieved nothing, the loop burned every iteration, and forced synthesis replaced the chain's answer
with a stub. This is the mechanism behind the 49-to-195 character answers. Recursive research fires
when Deep Think is *least* confident, so it failed hardest where it was needed most.

**The verification loop traded grounded answers for ungrounded ones, and preferred them for the
reason it should have rejected them.** `AgenticPolicyService:180` retries on
`groundingScore < 0.3 && totalCitations > 0`, while an uncited answer has grounding forced to 0.5 and
skips the check, so the uncited replacement always verified cleaner. Instrumentation added first,
then the guard: the first case to hit the path logged `2647 chars with 4 citations -> 53 chars with
0 citations`. The guard forbids taking away an answer's last citation. It is **not** a rule about
length; that earlier assumption was wrong and was rejected.

**Every Deep Think and Maximum answer showed the user a fabricated 70% match score.** `topSim`,
`secondSim` and `avgTop5` were hardcoded on the agentic audit snapshot and reach the UI. Now
measured.

Also: suggested questions no longer generated from bibliographies and running headers, validated
against 5,425 real library chunks (99.2% clean, zero false hard-demotions).

## Active Constraints

- **Do not push.** Nine commits waiting. Xcode Cloud usage.
- **No em-dashes anywhere**, including Swift string literals.
- **`[Unreleased]` stays empty. New entries go under `## 5.0`.** v5.0 has not shipped; the App Store
  is on 4.9. `Docs/SHIPPED_VERSION.json` is authoritative and the preflight router reports it wrong.
- **Never run a build or test suite while a benchmark is measuring.** Doing so starved a case into a
  600s timeout; the same case later completed in 294.8s untouched.
- **One benchmark at a time.** Both modes ingest into the same
  `~/Library/Application Support/OpenIntelligence`, so concurrent runs corrupt each other.
- Commits must not carry a `Co-Authored-By: Claude` trailer. The pre-commit hook blocks a `.swift`
  change with no doc update, and it is active.

## Working Set

- `OpenIntelligence/Services/Agentic/AgenticOrchestrator.swift`. `shouldAcceptReplacement`,
  `logAnswerReplacement`, `parseResearchDecision`, `executeReasoningChain`, `runVerificationLoop`.
- `OpenIntelligence/Services/RAG/Tuning/AgenticPolicyService.swift:180`, the grounding gate whose
  asymmetry the guard closes. Not yet changed.
- `/private/tmp/defect_watch.sh`, the watcher. Takes `<results.jsonl> <harness log> <expected>` and
  emits per case **only on a defect signature**, plus terminal states. Validated against the
  2026-08-15 run, where it flags the placeholder bug on case 1.
- `BenchmarkRuns/qasper-deepthink-20260815/`, the 82-case pre-fix baseline.
- `/private/tmp/oi-mac-nosbx4/Build/Products/Debug/OpenIntelligence.app`, macOS build at `ccc0eeb`.

## Verification

- `xcodebuild test` -> **236 tests, 0 failures**, run once per commit from `/private/tmp/oi-test-src`.
  `xcodebuild` deadlocks on this repository's own path; see `RUNBOOK.md` 1b.
- Placeholder fix confirmed in a 6-case smoke: zero placeholder searches, guard never had to fire.
- Citation and telemetry fixes are **code-verified, not quality-verified.** See Blocker 1.

## Blockers / Unknowns

1. **Benchmark runs are not comparable to each other, and this invalidates every before/after
   quality claim made today.** Generation runs at temperature 0.7 with nothing pinning sampling;
   `SWIFT_DETERMINISTIC_HASHING` seeds Swift hashes, not the model. One case moved 3613 -> 68 -> 3357
   chars across three runs whose code differences cannot explain it. The audit's "Deep Think is
   worse than standard" rests on one run per arm with no variance estimate and must not be quoted.
   **What is still solid** is anything derived from reading code or from aggregates *within* one run:
   the citation mismatch, the hardcoded 0.7, and 49-of-59 placeholder searches.
   **Verification path:** the app already models `GenerationOptions.SamplingMode` including `greedy`
   (`LLMService.swift:697`), but the agentic paths call `session.respond(to:)` with no options. Wire
   a benchmark-only greedy sampling flag, then re-run. This is the highest-value next task and it
   touches session construction, so treat `FoundationModelSessionFactory.swift` as the hard boundary
   it is.
2. **Yesterday's empty-response mystery is solved, and the fix is not yet made.** The app catches
   `LanguageModelSession.GenerationError` at 3 sites and `LanguageModelError` at **0**. Both are
   public enums in the iOS 27 SDK (verified in
   `Xcode-beta.app/.../FoundationModels.swiftinterface`, `LanguageModelError` at the top level and
   `LanguageModelSession.GenerationError` at line 1278), and the one actually thrown is
   `LanguageModelError`. So every Foundation Models error falls past its handler to the generic
   catch, which is why five hypotheses were disproved last session while Apple's own instrument
   reported `Error Count: 0`. Caught in the wild at `ccc0eeb`:
   `type: LanguageModelError / case: Response may contain sensitive or unsafe content /
   partialTextChars: 3588`, on a paper about scam detection. The content was not empty, it was
   generated and then refused by the guardrail. `LanguageModelError` carries `guardrailViolation`,
   `refusal`, `contextSizeExceeded`, `rateLimited`, `timeout`, `unsupportedCapability`,
   `unsupportedTranscriptContent`, `unsupportedGenerationGuide` and `unsupportedLanguageOrLocale`,
   so **every targeted recovery in this app is currently dead code**: no retry on `rateLimited`, no
   context reduction on `contextSizeExceeded`. The partial-text fallback does work and returned a
   3434-character answer, so this is degraded, not broken. **Verification path:** the 3 sites are
   `grep -rn "as LanguageModelSession.GenerationError" --include=*.swift`. Note the product
   consequence: documents about security, fraud, abuse or medicine will trip the guardrail
   legitimately, so guardrail handling needs a user-facing story, not just a log line.
3. **One case timed out at 1500s** (`qasper_1911.10742_f7662b11`) after completing in 294.8s the day
   before. Unexplained. Possibly the placeholder fix making searches real and therefore expensive,
   possibly noise. One sample. Watch whether it recurs.
4. **The grounding gate at `AgenticPolicyService:180` is still asymmetric.** The guard stops the bad
   replacement from being accepted but the gate still prefers uncited answers. Fixing the gate itself
   was deliberately deferred until runs are comparable.
5. **`doc_pack_addon` does not load from StoreKit.** Revenue affecting, untouched.
6. **The QASPER fixture cannot measure answer quality.** 22 of 76 cases are graded by a bare
   `(?i)Yes` or `(?i)No` substring against a multi-thousand-character essay, matching inside "not"
   and "know". A rubric-scored eval was scoped and not built.

## Exact Next Action

**Read the smoke result and confirm the guard fired.**

```bash
python3 -c "import json;[print(r['case_id'][-8:], len((r.get('run') or {}).get('answer') or ''), 'REJECTED' if 'Rejected replacement' in ((r.get('run') or {}).get('report') or '') else '') for r in [json.loads(l) for l in open('BenchmarkRuns/smoke-deepthink-ccc0eeb/results.jsonl')]]"
```

Case `85e41723` is the one to look at. At `f6bb4ca` it returned 53 characters after its 2647-character
4-citation answer was discarded. If the guard works it keeps the grounded answer and the
`Rejected replacement` warning appears in its report.

Then take Blocker 1. Until sampling is pinned, do not run another A/B, because a second
uncomparable run costs hours and settles nothing.
