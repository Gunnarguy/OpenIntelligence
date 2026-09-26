# RAG architecture audit, 2026-09-26

> **Status:** working record of an audit, not live documentation. These are findings, not decisions: the
> owner decides what is scheduled. The owner approved the proposed extractor fix on 2026-09-26, and it is
> applied to the source; see "Open for the owner". The audit's own findings were never compiled. The fix
> was: `swift/` builds the extractor from source with Swift 6.4 on Linux and runs its tests. Nothing has
> been built in Xcode or tested on a device.

## Why it exists

On 2026-09-25, on the macOS Debug build of 5.4 in Deep Think, "How much notice do I have to give before I
move out?" returned "1 lb." from an air fryer manual, marked Verified, when the lease in the same library
says 60 days (roadmap row: https://app.notion.com/p/3e749a74d54f8115a76ad5b06b196956). The diagnosis found
two defects in `SpecificationExtractor` and proposed a roughly 10-line fix. The owner then asked whether
that fix is a band-aid on something larger, and how the app's ingestion, SQLite and vector storage,
retrieval, generation and verification compare with Apple's iOS 27 frameworks and with current practice.

**Short answer, from `REPORT.md`:** yes, a band-aid, but a correct one worth keeping. It changes 2 of the
11 decisions that produced the answer. The pipeline's shape is standard and matches Apple's TN3193
recipe. The larger problems sit around it:

- hand-written extraction can pre-empt or overwrite the model's answer at five places;
- verification checks presence rather than whether the question was answered, and never runs in Deep
  Think or Maximum;
- the "Verified" label defaults to Verified;
- ranking and storage plumbing discard or damage work the pipeline already did.

## What is here

| Path | Contents |
|---|---|
| [`REPORT.md`](REPORT.md) | The report. It covers:<ul><li>the verdict;</li><li>how the pipeline works in each quality mode;</li><li>fifteen defects;</li><li>the missing capabilities;</li><li>six conflicts between sources, settled against the code;</li><li>ten changes ranked by effect on answer correctness, mapped to roadmap rows and hard-boundary files;</li><li>the evidence limits.</li></ul> |
| [`notes/`](notes/) | The nine evidence notes the report was written from, every claim tagged. Three read the app's code at `b37ab4c`: ingestion, storage and the query path. Six read the web: Apple's iOS 27 frameworks, WWDC26 and Apple's model documentation, retrieval and generation practice, ingestion and storage practice, agentic and on-device RAG research, and reference architectures. They were written in a cloud session, so their absolute `/tmp/...` paths refer to that session's scratchpad. |
| [`port/`](port/) | A Python re-implementation of the extractor's decision path, `extractor_port.py`, with its fixture runs. `python3 run_fixture.py` writes `port_run_fixture.txt`, and `python3 validate_proposed_test.py` writes `port_validate_proposed_test.txt`, which predicts the outcome of the proposed tests. Run both from this folder with `PYTHONHASHSEED=0` to reproduce the saved files byte for byte; other seeds change only the order of printed keyword lists, not any score. Evidence level: inferred. The port shows what the Swift computes only if it is faithful. |
| [`proposed/extractor-fix.patch`](proposed/extractor-fix.patch) | The fix as proposed and approved. It edits `OpenIntelligence/Services/Query/Analysis/SpecificationExtractor.swift` and adds four regression tests in `OpenIntelligenceTests/Services/RAG/Tuning/PrecisionLockAnswerTypeTests.swift`. Applied on 2026-09-26 with one change: `@MainActor` on the test class. The engine module defaults to main-actor isolation, so reading an extraction's fields from a nonisolated test warned under Swift 5 and is an error under Swift 6. Other engine tests, `SourceOnlyStandardGateTests` among them, use the same annotation. Kept as the record of what was approved. |
| [`swift/`](swift/) | The extractor compiled and run as Swift, added 2026-09-26 when the fix was applied.<ul><li>`run.sh <label> [rev]` builds the extractor, detector, scoring policy, logging and chunk model from source in a SwiftPM package that mirrors the engine target's compiler settings.</li><li>It runs `PrecisionLockAnswerTypeTests` and `LockMatrixProbe.swift`, an 18-question before/after probe over fictional passages.</li><li>`tests_before.txt` and `probe_before.txt` come from `b37ab4c`; the `_after` files come from the fixed source.</li></ul>Toolchain: Swift 6.4 on x86_64 Linux. The outputs repeat byte for byte. Before the fix, 3 of the 4 tests fail; after it, 4 of 4 pass. That matches the Python port's prediction case for case, and the scores agree to two decimals ("1 lb" 0.8525 in the port, 0.85 in Swift). This is a Linux build of six source files, not an Xcode build of the app. |

## How it was produced

- **The incident diagnosis** read the source at `b37ab4c`. The app source there matches the shipped 5.4
  build: between `c276b9a` and `b37ab4c` only two screenshot scripts changed.
- **The research** used nine researchers; one writer then synthesized the report from their notes.
- **Coordinator re-read.** The coordinator re-read the headline code claims in the source a second time.
  The report marks those claims "confirmed twice".
- **The network policy limited the web research.** Reachable: developer.apple.com, raw.githubusercontent.com,
  www.anthropic.com and pypi.org. Blocked: arXiv, Hugging Face, sqlite.org, machinelearning.apple.com,
  support.apple.com and many vendor sites. Figures known only from search summaries are tagged
  `inferred (search summary)`.
- **No Swift toolchain was available.** Nothing was compiled; SQLite behaviour was checked with Python's
  `sqlite3`.

## Roadmap rows filed or updated on 2026-09-26

All new rows are To Do, Future Backlog.

| Row | Change |
|---|---|
| [Deep Think answered a lease-notice question with "1 lb" from an air fryer manual and marked it Verified](https://app.notion.com/p/3e749a74d54f8115a76ad5b06b196956) | New. The incident and its proposed fix |
| [Regex extraction can pre-empt or replace the model's answer at five places, with no check that it answers the question](https://app.notion.com/p/3e749a74d54f817083a6fbf197ff26db) | New. Change 1 |
| [The Verified badge shows for answers whose checks failed or never ran, and Deep Think and Maximum run no verification gates](https://app.notion.com/p/3e749a74d54f81b1ae8bc414159799ed) | New. Change 3 |
| [The semantic query cache is never cleared, so Standard can answer a repeated question from stale retrieval](https://app.notion.com/p/3e749a74d54f810c86fefac905fa1d6f) | New. Change 8 |
| [Opening a library deletes its vector index when the vector file's size does not match the chunk count](https://app.notion.com/p/3e749a74d54f81859f4dd44bc4c9e9b2) | New. Part of change 5 |
| [Chunks over 430 tokens are split at every period, so "4.5 L" is stored and embedded as "4. 5 L"](https://app.notion.com/p/3e749a74d54f8198b727fa124d5db474) | New. Part of change 6 |
| [Hybrid fusion ranks worse than the keyword arm it is fusing](https://app.notion.com/p/3bf49a74d54f81d593ddfe700f277f1e) | Dated note. The keyword boost discards the fused order, and per-batch rerank rescaling explains the scores of exactly 0.9000 |
| [Adopt Apple's Evaluations framework for answer-quality grading](https://app.notion.com/p/3b549a74d54f814cbb06fa629417b657) | Dated note. A golden set over the owner's document types is the precondition for every change |
| [Benchmark three embedders and replace MiniLM-L6-v2 if warranted](https://app.notion.com/p/3b149a74d54f81f0a1a0dc9f4d12614a) | Dated note. BEIR figures, and the code's real chunk limits |

## Open for the owner

- **Scheduling.** All new rows default to Future Backlog. Three rows name the case for test 2 (an
  advertised capability does not work): the incident, the answer-seat row and the label row. The case
  rests on `fastlane/metadata/en-US/description.txt:23` and `:25`.
- **The fix is applied, not closed.** The owner approved it with `PROCEED: IMPLEMENT` on 2026-09-26.
  It is on the branch `claude/determined-ritchie-7y60am` with the 5.5 changelog entry and item 22 of
  `Docs/RETRIEVAL_PIPELINE.md`.
  - Still to run on the Mac: `xcodebuild test` with an iOS 27 simulator (`Docs/ai/RUNBOOK.md`, Test)
    and the build smoke test.
  - Then re-ask the incident question on a device in Deep Think. In Standard, use a fresh phrasing,
    because the semantic query cache can replay old retrieval.
- **Found while verifying the fix, and not fixed by it.** When several volumes in one passage score the
  same, the extractor keeps the first. On a car manual's capacities list, "What is the fuel tank
  capacity?" locks the engine oil's 4.5 L, and "How much coolant does it need?" locks its 4.8 US qt,
  both before and after the fix (`swift/probe_*.txt`). The cause is at `SpecificationExtractor.swift:300-305`:
  - The check for competing answers treats same-category ties as "variants of the same spec".
  - It picks the first.

  This belongs to the answer-seat row.
- **A correction candidate for `.claude/skills/apple-api-truth/SKILL.md`.** Apple's documentation shows
  `ContextOptions` only on the 12 new iOS 27 `respond`/`streamResponse` overloads, not on every overload.
  Confirm against the iOS 27 SDK's `.swiftinterface` before editing that table: the SDK is authoritative
  on what exists.

`[evidence_level: artifact_derived, confidence: high, evidence_source: REPORT.md and notes/ in this folder; roadmap rows read back on 2026-09-26]`
`[evidence_level: measured, confidence: exact_for_these_runs, evidence_source: swift/tests_*.txt and swift/probe_*.txt, for the fix's test results and the same-category tie]`
