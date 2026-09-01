# Current State

Updated: 2026-09-01
Branch/worktree: main (primary checkout)
Last verified commit: 845c7b9

## Objective

**Make macOS ingestion usable, then close the one open defect that loses user data.**

The first half is written and unverified: five code changes landed 2026-08-29 to 09-01, all
build- and suite-verified, **none device-verified**. The second half — iCloud sync without
`NSFileCoordinator` — has not been started and needs the owner to name a hard-boundary file.

## Status

**Live on the App Store:** iOS **5.0** (approved 2026-08-27), macOS **5.0.2** (approved 2026-08-28).
Nothing in review.

**v5.1 has metadata but no binary.** Release notes, promotional text and app name were pushed to
both platform records on 2026-08-31 and verified in the `deliver` logs. Cutting a build is an open
task nobody has done.

**The platforms have diverged and it is the most load-bearing fact in this repository.** macOS
carries 5.0.1 and 5.0.2; iOS never received either. Most of 5.0.1's seventeen entries are
cross-platform fixes that only reached the Mac, so an iPhone user installing 5.1 gets roughly twenty
fixes a Mac user already has. This is why App Store copy is per-platform and why the Notion
`Shipped On` property exists alongside `Status`.

**Notion v5.1**, read 2026-09-01: 6 rows — 3 `Completed`, 1 `In Progress`, 2 `To Do`. Future Backlog
is 70 rows, all `To Do`. v5.0 closed at 57 rows, every one with `Shipped On` recorded.

## Completed this cycle

All five are **build-verified and suite-verified only**. Treat every one as unconfirmed on hardware.

1. **macOS PDF rendering** (`961f446`). `renderPDFPageAsImage` used deprecated `NSImage.lockFocus`
   plus a TIFF encode/decode round-trip. Measured with a standalone AppKit probe: 4.0× oversize
   (3060×3960 requested, 6120×7920 produced) and 370 MB per page. Now a `CGBitmapContext`.
   **Render was never the bottleneck** — it measures 12–16 ms/page on a live trace, so a five-hour
   ingest is Vision recognition, not rasterisation. Do not re-derive this.
2. **Restored progress** (`7e717a1`). A paused import showed zero although it always resumed
   correctly, steering users toward removal, which is the one action that discards the checkpoint.
3. **OCR settings on the live path** (`209a045`, then `d610183`). Language narrowed to the detected
   language; `minimumTextHeightFraction` 0.0 → 0.004. **The first commit fixed the wrong file** —
   see Active Constraints.
4. **Idle vector churn** (`46aa57e`). `VectorStoreRouter.clearAll()` reloaded every store on a
   1.68 s timer. Measured: 162,712 reload tasks spawned against 76,391 completed, a 53% backlog that
   grew without bound until the app hung after 169 minutes. Now compares on-disk signatures first.
5. **macOS app icon** (`0a90bfe`). All 20 mac slots were full-bleed opaque squares where macOS needs
   824-of-1024 inset behind a superellipse; the dark variant carried the light icon's blue on its
   antialiased edges. Regenerated. iOS slots were correct and untouched.

Plus `scripts/verify_doc_claims.py` (`845c7b9`), wired into `scripts/enforce_docs_hook.sh`.

## Active Constraints

- **`OCRConfiguration.configureRequest` is NOT the live OCR path.** `extractStructuredPDFContent`
  routes every OS 26+ device to `StructuredDocumentParser`, which builds `RecognizeDocumentsRequest`
  directly. Two commits fixed settings in the wrong file before this was noticed. **Trace the
  request the app actually builds before editing any OCR setting.**
- **The cross-encoder reranker exists** at `RAGEngine.swift:82` (model load) and `:331`
  (`rerankWithCrossEncoder`). A search scoped to `Services/RAG/Retrieval/` finds only heuristic
  scoring and reads as absence. That error reached a published document.
- **Three assertions of absence were wrong this cycle**, each from a too-narrow grep, and in all
  three the repository's own documentation was already correct. Read the owning document for a
  subsystem before concluding something does not exist; `repoos_router.py preflight` names it.
- **`minimumTextHeightFraction` is conservative on purpose.** Text below the floor is not recognised
  and nothing downstream can tell it was there. Lower it if wrong; never raise it casually.
- **Do not remove the `unreleased` HTML comment from the `## 5.1` heading** in `CHANGELOG.md`.
  `repoos_router.py` reads it from that line and nowhere else.
- **Benchmark runs are archived, not on disk.** 90 directories, 474 MB, in
  `~/OpenIntelligence-BenchmarkArchive/BenchmarkRuns-2026-09-01.tar.gz`, verified byte-identical
  before deletion. `BenchmarkRuns/LEDGER.md` still indexes them.

## Working Set

| File | Why it matters |
|---|---|
| `OpenIntelligence/Services/Infrastructure/Storage/WorkspaceSyncService.swift` | Holds the `NSFileCoordinator` data-loss row **and** the orphan guard behind the idle churn. Tier-2 hard boundary; needs the owner to name it. |
| `OpenIntelligence/Services/Document/Processing/StructuredDocumentParser.swift` | Builds the live `RecognizeDocumentsRequest`. Any OCR change goes here, not `OCRConfiguration`. |
| `OpenIntelligence/Services/VectorStore/VectorStoreRouter.swift` | `clearAll()` now signature-gated. Never evict: `BNNSVectorDatabase` is memory-mapped and two instances must not map one file. |
| `OpenIntelligence/Services/Document/Processing/DocumentProcessor.swift` | `renderPDFPageAsImage`, the phase-1.6 language detection, `restoredIngestionProgress`. |
| `fastlane/metadata/` and `fastlane/metadata-ios/` | macOS and iOS App Store copy. iOS push is a documented swap-and-restore; see `Docs/ai/RUNBOOK.md`. |
| `scripts/verify_doc_claims.py` | New gate. Four checks; deliberately cannot verify prose. |

## Verification

Run 2026-08-31 to 09-01, output read:

- `xcodebuild test` (iOS 27 sim, full suite) → **392 tests, 3 skipped, 0 failures**. The 3 skips are
  in `EmbeddingProviderAgreementTests` and `LayoutReadingOrderTests` and are unrelated.
- macOS Debug build → **BUILD SUCCEEDED**, 0 errors.
- `bash scripts/build_simulator_smoke.sh` → **BUILD SUCCEEDED**.
- Device build on **Xcode 26.6** → SUCCEEDED, **zero PCC symbols across all six binaries**, installed
  on the owner's iPhone 16 Pro Max.
- `python3 scripts/verify_doc_claims.py` → **181 claims checked, all pass**.
- `python3 scripts/secret_scan.py` → clean.
- `fastlane push_metadata version:5.1` → ran for `platform:ios` and `platform:osx`, both
  `finished successfully`.

**Not verified:** every behavioural claim above, on any device. No ingestion has been run against
any of the five changes.

## Blockers / Unknowns

1. **Nothing from this cycle is device-confirmed.** Verification path: the Exact Next Action below.
2. **The idle-churn root cause is untouched.** The 1.68 s timer still fires and container
   `3CE9F7D5` is still detected as permanently orphaned — it is merely cheap now. The guard treats a
   permanent condition as transient ("an import may still be writing"). Fix is in
   `WorkspaceSyncService.swift`, which needs naming.
3. **Retrieval is nondeterministic.** Two runs of one build return different evidence for one
   question. This blocks every quality change in the RAG stack, including judging what already
   shipped. Verification path: run a fixed query set twice against one build and diff the retrieved
   chunk ids. Tracked at
   [determinism](https://app.notion.com/p/3cc49a74d54f81d7a88dffe679ce9bb1).
4. **`scripts/test_stop_handoff.sh` has a failing assertion.** It guards the hook that tells a
   session which documents it owes. Cheap, and worth fixing given this cycle was largely doc drift.

## Exact Next Action

**Rebuild the macOS app in Xcode, ingest one large PDF, and read the trace.** This is two minutes of
the owner's time and it closes three of the five changes at once.

Start a capture that survives the log's rotation first:

```bash
mkdir -p /private/tmp/oi-trace-archive && nohup tail -F -n +1 "$HOME/Library/Containers/Gunndamental.OpenIntelligence/Data/Documents/pipeline_trace.log" >> /private/tmp/oi-trace-archive/continuous.log &
```

Three lines decide three open questions:

| Look for | Decides |
|---|---|
| `OCR languages narrowed 13 -> N` | Whether the language work is finally on the live path. **This string has never appeared in any trace.** If it says `NOT narrowed`, detection is not firing. |
| `Rendered PDF page ... in N ms via CGBitmapContext` paired with `Page N: OCR extracted ... (N.NNs)` | The first render-versus-OCR cost split, at `minimumTextHeightFraction` 0.004. |
| `[VectorLoad]` frequency while idle | Was 13.3/s before `46aa57e`. Should be near zero. |

Then quit mid-ingest and reopen: the restored item must report its true page count rather than zero,
which closes `7e717a1`.

**After that**, the highest-value work is
[Six file families sync without NSFileCoordinator](https://app.notion.com/p/3ca49a74d54f8103b69be921f0335171)
— the only open row anywhere that loses user data, 599 conflict copies observed. It lives in
`WorkspaceSyncService.swift` along with blocker 2, so one naming unblocks both. **Ask the owner to
name that file before editing it.**
