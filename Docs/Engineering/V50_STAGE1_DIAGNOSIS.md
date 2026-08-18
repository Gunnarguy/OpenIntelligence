# v5.0 Stage 1 — Defect Diagnosis

Produced 2026-08-17 by a read-only 21-agent pass: one diagnosis per defect row, each then handed to
an independent agent whose only instruction was to refute it. No source was edited.

Raw structured output, including every file:line citation and every refutation in full:
`Docs/AuditArtifacts/DefectDiagnosis/v50_stage1_diagnoses.json`.

**Read the verdict column before acting on anything here.** Three diagnoses were refuted outright
and two roadmap rows turned out to rest on false premises. The refutations are the most valuable
part of this document, because each one is a day that does not get spent.

## Verdicts

| Row | Cause established | Verifiable by | Effort | Note |
|---|---|---|---|---|
| `unregistered-tools` | **yes** | static count | small | Six `Tool` structs never registered |
| `iwork` | **yes** | unit test | small | Tier 1 shippable; Tier 2 needs IWA reading |
| `embedding-fingerprint` | **yes** | unit test | medium | Merge with `selfheal-noop`, same edit |
| `selfheal-noop` | **yes** | unit test | medium | Merge with `embedding-fingerprint` |
| `chunk-boundaries` | **yes** | unit test | medium | Probe counts must be re-measured |
| `candidate-cutoff` | mechanism only | static count | medium | **Cannot fire on any corpus in this repo** |
| `transcription-tests` | **yes** | device only | medium | One sub-claim is inference |
| `nondeterminism` | **NO** | — | large | Standard-mode cause unestablished; split the row |
| `pdf-columns` | bug yes, link **NO** | unit test | small | Fix as written does not compile |
| `fts5-bm25` | premise **false** | not today | large | Weighting already done 2026-08-06 |

## Four things worth knowing before reading the plan

1. **Two roadmap rows are partly or wholly already done.** BM25 column weighting was fixed on
   2026-08-06; all four call sites pass nine correctly aligned weights. The `candidate-cutoff`
   defect as stated does not exist. Both rows need correcting rather than working.
2. **The 21% reproducibility figure predates commit `24d3b54`** and has never been re-measured. One
   possible outcome of Batch 0 is that the row is already closed.
3. **`embedding-fingerprint` and `selfheal-noop` are the same edit**, not two rows that happen to be
   adjacent. Implementing them separately means the second overwrites the first.
4. **The proposed fingerprint does not cover the chunker.** Batch 4 changes stored chunk text, which
   invalidates every vector while the fingerprint continues to read healthy. That is precisely the
   failure mode the fingerprint row exists to prevent, reproduced inside its own fix.

---

# OpenIntelligence v5.0 — Defect Work Plan

Ten diagnoses, six verified, four not. This orders them, groups them by what actually verifies them, and names the collisions.

---

## 1. Dependency order

```
Batch 0  Attribution runs (no code)          ← gates every retrieval measurement
   │
   ├── Batch 1  Make the silent discards audible (no behavior change)
   │
   ├── Batch 2  Container / rebuild lifecycle   [fingerprint + self-heal, MERGED]
   │       │
   │       └── Batch 4  Ingested-text correctness  [pdf-columns + chunk-boundaries]
   │               │
   │               └── Mean-pooling re-export     ← hard constraint satisfied here
   │
   ├── Batch 3  Retrieval ordering correctness   (after Batch 0 only)
   │
   ├── Batch 5  Claims and copy         ┐
   ├── Batch 6  Test-suite honesty      ├ independent, parallelizable
   └── Batch 7  Dead code cleanups      ┘

Batch 8  Gated: FTS5 trigram, iWork Tier 2, transcription Tier 3
```

**On the stated gate.** "The nondeterminism fix gates trustworthy measurement" is correct as a *constraint* but cannot be discharged by shipping the nondeterminism fix, because that row's cause is not established (§6). Only Batch 0 discharges it — and one possible outcome is that commit `24d3b54` already closed it and there is nothing to fix.

**On the stated constraint.** Fingerprint and self-heal before re-export is not just sequencing — they are the *same edit* (§3a). Treat them as one batch, not two rows.

---

## 2. Batches, grouped by what verifies them

### Batch 0 — Attribution runs. No code. Do this first.
Freeze inputs before starting (`VersionHistoryTests` makes `USER_CHANGELOG.md` a build input).
1. Re-baseline the 21% figure on **current HEAD**, post-`24d3b54`. The figure predates that fix.
2. Two runs Standard mode, two with `SWIFT_DETERMINISTIC_HASHING=1` exported, two Deep Think. `run_quality_matrix.py:238` records the variable automatically.
3. Embed one fixed chunk twice in one process and across two processes; compare bytes. Cheapest discriminator between "ordering" and "floats", and it is missing from every diagnosis.

**Verifies:** which of layers A/B/C, or the untested float hypothesis, survives. **Nothing downstream is trustworthy until this runs.**

### Batch 1 — Instrumentation only, no behavior change
Verified by grep + one device trace. Nothing here can confound anything else.
- `FoundationModelToolRegistry.swift:422` — warn before `return []`. Highest-value single line in this whole plan.
- `RAGEngine.swift:319` — warn when `adaptiveCeiling < chunks.count`, with the supplementary-origin count. Warning, not info.
- Add `.ceiling` stage to `RetrievalTraceCollector`; update `save_benchmark_summary.py:36` `STAGE_ORDER`; correct the false diagnostic at `RetrievalTraceCollector.swift:85-86` **and** its duplicate at `run_quality_matrix.py:804`.
- `DocumentProcessor.swift` spatial extraction — drift log (`wordIndex` vs `pageString.utf16.count`), unresolved-word count, and a warning on the `spatialLines.count > 3` bail. Log **before** fixing the arithmetic, or you cannot attribute.
- Self-heal: warn when a rebuild is vetoed to empty (precedes the throw in Batch 2).

⚠️ Inserting `.ceiling` makes every prior benchmark artifact non-comparable. Land Batch 1 *after* Batch 0's runs, then re-baseline once and treat that artifact as the new reference.

### Batch 2 — Container / rebuild lifecycle (fingerprint + self-heal merged)
Verified by: pure-function unit tests (fingerprint computation, `KnowledgeContainer` Codable round-trip to nil, extracted `documentsEligibleForRebuild`) plus one device pass. Order inside the batch:
1. Extract the rebuild-selection logic at `RAGService.swift:7079-7096` into a `nonisolated static func` returning `.rebuild / .libraryEmpty / .blockedByQueue`. This is the only part of either row testable without hardware.
2. Stage-aware veto (`!$0.stage.isTerminal`) + throw on blocked. Note the everyday trigger the diagnosis missed: `pruneCompletedIngestionItems()` at `:4817` defers 4s, `kickPendingReembedIfNeeded()` fires at `:4818`, so freshly-imported documents veto their own re-embed.
3. Flag-**before**-wipe at `RAGService.swift:4304-4312` and `ContainerSettingsSheet.swift:823`.
4. Fingerprint field + computation + "flag, don't wipe" response for recipe-only changes.
5. `rebuildSemanticIndex` `:6616-6623` — clears the banner then silently returns at `:6648`/`:6652`. Same defect, not in either fix plan.

Add a **chunker-recipe term** to the fingerprint here (see §3d).

### Batch 3 — Retrieval ordering correctness
One batch because these four overwrite each other. Verified by unit tests on extracted comparators + one frozen-corpus re-baseline. Be honest: at ~300 chunks no quality delta is attributable.
- `HybridSearchService.swift:417/:504` — stop re-sorting by `similarityScore`; preserve the fused score `RAGEngine.swift:1027` currently discards.
- `HybridSearchService.swift:993` — the `allChunkLookup` gate. Fixing it un-inerts structured-row rescue *today* and is a precondition for any future trigram arm.
- `HybridSearchService.swift:1091` — `vectorResults` → `vectorResultsFiltered`.
- `RAGEngine.swift:1487-1546` — indexed write instead of completion-order append; stable tiebreaks at `:1501`/`:1544`.
- Ceiling formula (`RAGEngine.swift:318`) **last** — meaningless until the ordering above is right, and the proposed `min(poolSize, max(topK, latencyBudget))` still discards 100% of supplementary chunks in the large-corpus case (§3c).

### Batch 4 — Ingested-text correctness
`pdf-columns` + `chunk-boundaries`. Both change stored chunk text, so they are one reindex event. Verified by **pure-string unit tests** (UTF-16 offset arithmetic; word-alignment on constructed ties) and **reading extracted text by eye**, never by retrieval metrics.
- The pdf-columns fix as written does not compile: `NSRange(_:in:)` for `StringProtocol` is non-failable in this SDK. Use a plain expression, `in: pageString` (the base).
- The chunk-boundaries fix omits `buildParentContent` `:1453-1454`, which has the identical defect and is what the *model* reads.
- Do not close the pdf-columns row on the offset fix (§6).

### Batch 5 — Claims and copy
Run `oi-claim-audit` first. `fastlane/metadata/en-US/description.txt:19`, `README.md:55`, `Docs/ai/PROJECT.md:22`, `DocumentPicker.swift:144`, `DocumentProcessor.swift:9281`, `SettingsView.swift:2305` (4 → 6). Roadmap corrections for `candidate-cutoff` (the stated defect does not exist) and `fts5-bm25` (weighting is done). **The description edit does not change the live listing** — the ASC push is part of the fix, not a follow-up.

### Batch 6 — Test-suite honesty
`IngestionFormatCoverageTests` + `IngestionFixtureFactory`. Transcription Tier 1 must match on the **message substring**, not the error case: `DocumentProcessor.swift:8494` rewraps `authorizationDenied` into `audioTranscriptionFailed`, so case-matching reproduces the vacuity. Tier 2b needs `XCTExpectFailure` or it lands permanently red. Replace the fake Pages fixtures (`IngestionFixtureFactory.swift:256-276` writes zero-filled bytes, so any iWork work would test nothing).

### Batch 7 — Dead code
Six unregistered `Tool` structs, dead `storeChunk` (zero callers), dead `disableTools` parameter in `FoundationModelPromptCompiler.compilePrompt`. Build + grep. Keep out of Batch 1 so that diff stays readable.

---

## 3. Conflicts and contradictions

**a. Same lines, two rows — MUST merge.** `embedding-fingerprint` and `selfheal-noop` both rewrite `RAGService.swift:4304-4312` (wipe/enqueue), `:6684` (banner clear), and `reembedDocuments` `:7080-7113`. Implementing them separately means the second overwrites the first.

**b. Direct contradiction inside Batch 2.** Fingerprint says "`:6684` becomes the single place that clears `librariesNeedingIndexRebuild`." Self-heal's verifier shows `:6571` and `:6605` also clear it, and both are *evidence-based reads of the actual store*. **Resolution: keep `:6571`/`:6605`; only the no-evidence clear at `:6684` changes.**

**c. Same function, opposite readings — `HybridSearchService.swift:417/:504`.** `nondeterminism` calls these variance-propagating and wants a tiebreak. `candidate-cutoff` Part D shows the sort *key itself* is wrong (RRF ordering already destroyed at `RAGEngine.swift:1027`). **Resolution: candidate-cutoff supersedes. Fix the key, then add the tiebreak. One change.**

**d. Coverage gap between two fixes.** The embedding fingerprint covers tokenizer/model/pooling. It does **not** cover the chunker — so Batch 4 silently invalidates every stored vector with the fingerprint reading healthy. Exactly this row's own failure mode. Add a chunker-recipe term in Batch 2.

**e. Same file, adjacent regions.** `DocumentProcessor.swift` is edited by pdf-columns (`~7671-7760`, `4207`), iWork Tier 1 (`8527`, `9281`), and transcription (`8490`). Low risk, but one writer per checkout — use separate worktrees outside `~/Documents`.

**f. Hard-boundary hosting trap, twice.** Both `nondeterminism` layer A and `unregistered-tools` want a new shared helper for Foundation Models config. Do **not** host it in `FoundationModelSessionFactory.swift` or `FoundationModelRoutePolicy.swift`. Also: a new type under `OpenIntelligence/Services/` joins the engine framework target — the app builds, the test build fails with a fake-looking scope error.

**g. Mechanism disagreements worth recording, not resolving now.** pdf-columns internal (offset drift vs. empty column boundaries at `:7743-7746`); FTS5 contentless DELETE (fails loudly vs. succeeds silently with `changes()=0` — the silent version is the dangerous one).

---

## 4. Cannot be verified without a device

| What | What you have to do |
|---|---|
| Zero tools attach on the agentic fresh-session path | Land the Batch 1 warning at `FoundationModelToolRegistry:422`, run one Deep Think query on device, read the trace |
| `DocumentSummaryService.swift:286-306` attaches all six tools during **ingestion** (not in any diagnosis) | Same trace, during a document import |
| Self-heal: banner reappears on blocked rebuild; vector count goes 0 → non-zero | Device pass with a library that has a stuck queue item |
| Fingerprint migration flags rather than wipes; library stays searchable during in-place re-embed | Install the new build over an existing library, watch the banner and search |
| Fingerprint survives the iCloud round trip | **Two devices, one on an older build** — otherwise unfalsifiable |
| Two-column PDF reads down-column | A fixture PDF + read the extracted text by eye. Unit tests prove the arithmetic only |
| Candidate ceiling ever binds | A library **≥2,500 chunks on a mid/high device tier**. Benchmark corpus is ~300; all recorded traces are 181-420 |
| iWork: picker greys out package form; new error reaches the ingestion row; chat toast | Manual import attempt of `.pages` from both pickers |
| Real-speech transcription | First: `xcrun simctl privacy <dev> grant all <bundle>` (untested — `simctl privacy` has no speech-recognition service). Then boot, import audio, tap the TCC alert, report whether `supportsOnDeviceRecognition` is true |
| FTS5 trigram benefit | Benchmark item 2A + a large corpus. Not measurable today at any price |
| End-to-end reproducibility | Two harness runs, frozen corpus, macOS Debug build. Note PCC is silently unavailable from agent shells |

---

## 5. Hard-boundary files — your call, one per line

**Required (blocks the row entirely):**
- `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift` **(SCHEMA)** — `fts5-bm25` trigram. `CREATE VIRTUAL TABLE` inside `initializeDatabase()`. There is no query-side-only slice that delivers any value. Approve or the row does not start.

**Conditionally required:**
- `OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift` — only if the `deleted_documents.json` purge for the trigram table routes through sync. Trace it before you decide; the roadmap row names this wiring and no diagnosis traced it to the end.

**Declined by design, so you do not have to approve them:**
- `BNNSVectorDatabase.swift` **(FORMAT)** — the fingerprint deliberately lives on `KnowledgeContainer`, not stamped into `_meta.json`.
- `FoundationModelSessionFactory.swift` / `FoundationModelRoutePolicy.swift` — the tool-registry log goes in `createTools`, not the factory.
- `project.pbxproj` — new files land in synchronized groups. Confirm the target before writing `IWAReader.swift`.

**No other row touches a boundary file.** `ChatMessage.swift`, `EntitlementStore.swift`, `QuotaPolicy.swift`, `RAGAppIntents.swift`, `EngineSDKCompatibility.swift`, entitlements, storekit and Info.plist capabilities are all untouched by this plan.

---

## 6. Rows where no cause was established

**`nondeterminism` — Standard-mode cause NOT established.** The 21% figure was measured in Standard mode. `RAGQualityMode.swift:237-243` returns `false` for `usesQueryExpansion` in Standard, and `usesHyDE`/`usesIterativeRetrieval` are also off — so layers A and B are Deep Think/Maximum defects only and cannot explain the anchoring measurement. Layer C is in the circuit but its sufficiency is unproven (the ties it needs sit at the bottom of the list, far from the cut). The repo's own leading hypothesis, float variance in embedding/BNNS amplified by the `0.28` floor at `RetrievalPolicyService.swift:107-108`, was never tested. And `24d3b54` may have already closed it. **Split the row: "Deep Think/Maximum nondeterminism" is well supported and fixable; "Standard-mode nondeterminism" is open pending Batch 0.**

**`pdf-columns` — bug real, causal link NOT established.** The NSRange unit/separator bug is certain. That it produces the row's symptom is not: `wordIndex` covers ~85-100% of ordinary prose, so `spatialLines` lands well above the `> 3` guard. Getting to the nil return needs ~13-character average word gaps. The likelier across-columns mechanism is `:7743-7746` — when `detectColumnBoundaries` returns empty, the function sorts by Y alone and returns **non-nil**, interleaving columns with no log. Fix the offsets because they are unambiguously wrong; do not close the row on it.

**`fts5-bm25` — the row's premise is false and the remaining half is unmeasurable.** BM25 column weighting was fixed 2026-08-06; all four sites pass 9 aligned weights. Trigram is genuinely absent and the porter infix misses reproduce, but no benefit is provable at ~21% reproducibility, and the cost is +104% to +263% database growth, 2-4× what the plan assumes.

**`candidate-cutoff` — mechanism established statically, never observed.** It cannot fire on any corpus in this repository. It additionally requires a mid-or-high device tier, not just corpus size. The instrumentation half is worth landing now precisely because it is what would let the next large-library device run answer the question.

**`transcription-tests` — one sub-claim is inference.** That the recorded cold-start stall was the TCC alert is plausible and unmeasured. Whether a real-speech test can run in the simulator at all is unestablished pending the manual probe.

**Refuted sub-claims to drop from the record:** self-heal generator (b) — rebuild items *do* inherit `storageRelativePath` via `IngestionItem.swift:262`, so the cross-launch self-perpetuating veto does not exist. Trigram does not "lose `AB 1234`" — it produces a false positive by silently dropping the 2-char term. Every probe count in the chunk-boundaries diagnosis (33/40, 8/12, 1969 vs 2099) failed to reproduce; the mechanism holds, the numbers must be re-measured before any of them reaches a doc.

---

Every batch needs `PROCEED: IMPLEMENT`. Docs move in the same turn as code. Run `repoos_router.py preflight` **per path** — the iWork row already violates its own route's allowed-edit list.
