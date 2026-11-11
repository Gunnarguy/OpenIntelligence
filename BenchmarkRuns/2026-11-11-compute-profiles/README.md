# Compute profiles on one build, 2026-11-11

Commit ee2ce21b (the build `scripts/bench_compute_profiles.sh` ran on is the one
`build_test.sh` built for that commit's tests). iOS 27.0 Simulator FD71D24F, erased before the set. Each run records
what an import stored with `ExtractionFidelityRecorder` under `TEST_RUNNER_OI_COMPUTE_PROFILE=<profile>`
(`DeviceCapabilityService.selectedProfile`), scored with `scripts/extraction_fidelity.py`.

## Extraction-fidelity set (8 PDFs, 141 pages, the owner's; not kept here)

| Run | Order | num rec | body num | word rec | body wrd | inv num/k | inv word/k | seconds |
|---|---|---|---|---|---|---|---|---|
| prof-balanced | 1st | 0.944 | 0.966 | 0.966 | 0.975 | 22.7 | 20.4 | 953.8 |
| prof-performance | 2nd | 0.944 | 0.966 | 0.966 | 0.975 | 22.7 | 20.4 | 964.5 |
| prof-maximum | 3rd | 0.944 | 0.966 | 0.966 | 0.975 | 22.7 | 20.4 | 596.3 |

The stored passages are the same text in all three (BL999: 148 of 148 identical; every score equal). On these
table-rich PDFs Balanced already draws all 123 recognised pages at 432 DPI (the page analysis marks them hard), so
Maximum's full-detail pages change nothing here, and Performance's extra rescue regions found nothing to rescue.
Maximum's shorter time came from the third run; the reversed pass below separates the profile from run order.
`[evidence_level: measured, confidence: high for "no change on this set", low for the time difference]`

## olmOCR-Bench, 160 public text pages (`run160.txt`)

| Run | headers_footers | multi_column | tables | long_tiny_text | mean |
|---|---|---|---|---|---|
| prof160-balanced | 79/126 | 86/153 | 128/226 | 172/250 | 0.611 |
| prof160-performance | 79/126 | 86/153 | 128/226 | 172/250 | 0.611 |
| prof160-maximum | 79/126 | 86/153 | 128/226 | 172/250 | 0.611 |

Seconds: 1562.6, 1493.4, 1509.2 (ladder order).

## Was Maximum really on?

The page resolutions were the same in every run (olmOCR: 56 pages at 144 DPI, 141 at 360, 136 at 432), which looked like
Maximum not engaging. A probe added to `ExtractionFidelityRecorder` (it writes `profile-start.json` and
`profile-end.json` beside the passages) ran one PDF under `TEST_RUNNER_OI_COMPUTE_PROFILE=maximum` on the same setup:
selected maximum, `isMaximumFidelityActive` true, full-detail pages, 24 rescue regions, rerank ceiling 400, thermal
nominal, no Low Power Mode, not the background CPU-safe profile. The resolutions match because a clean digital page is
read from its text layer and never drawn, the pages that are drawn for text recognition are the hard ones Balanced
already draws at 432 DPI, and the 360 DPI renders are the text-layer check on each file, the same in every profile.

## What this says

On these two sets (8 table-rich PDFs and 160 single pages of headers, columns, tables and small print) Performance's
and Maximum's import depth stores exactly what Balanced stores: no gain, no loss. Neither set exercises what Maximum
adds on easy pages (they are not drawn) or the reranker and keyword depth (import only). Time is not settled: each
profile ran once, in ladder order. Still to measure: retrieval (QASPER, tables 158) per profile, which is where
Performance's and Maximum's rerank and keyword depth act, and a reversed-order timing pass.
`[evidence_level: measured, confidence: high for "same stored text on these sets"]`
