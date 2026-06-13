# Post-Vik Alignment Validation Report - OpenIntelligence v4.1

This document registers the build and documentation validation checks performed after updating the RAG reliability and reranking audit materials.

---

## Validation Matrix

| Check | Result | Notes |
|---|---|---|
| **Markdown Link Integrity** | `PASS` | All new absolute links (with the `file://` scheme) to local codebase files exist and correspond to active symbols and directories. |
| **Accuracy Guarantees Sweep** | `PASS` | Grep scans confirm that "guarantee" or "guaranteed" are only used under context-limits or in Apple's PCC context, and not as accuracy promises. |
| **Hallucination-Free Claims** | `PASS` | Scanned for "no hallucinations". Only occurrences are in safety lists of unsafe claims in deep-dive documents. |
| **Core AI Reranking Claims** | `PASS` | Scanned for "Core AI reranking" and "fully integrated Core AI". All references are qualified as `VERIFIED_SCAFFOLD` (scaffolded stubs). |
| **ANE Routing Claims** | `PASS` | Scanned for "runs on ANE". Statements are qualified to note that Core ML schedules dynamically across ANE/GPU/CPU based on `computeUnits = .all`. |
| **Pro Tier Unlimited Claims** | `PASS` | Scanned for "unlimited Pro". No active claims remain. Feature claim register correctly maps Pro tier limit to the 1,000-document limit in `QuotaPolicy.swift`. |
| **Candidate Pool Discrepancy** | `WARNING` | Inline comment claims small corpora (<200 chunks) use all chunks, but `adaptiveCeiling` formula applies a floor cutoff at `max(100, topK * 5)`, truncating chunks when `topK < 20`. |
| **PCC Routing Integrity** | `WARNING` | While route planning is fully active, PCC execution maps back to the local `SystemLanguageModel.default` due to compatibility stubs. |
