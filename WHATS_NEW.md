# What's New

Public release highlights for OpenIntelligence.

## 3.0

This is the user-facing 3.0 summary focused on the reliability work shipped after 2.6.

## Highlights

- Deep Think and Maximum now fail softer on long answers: if a late-stage generation error happens after a strong grounded answer is already streaming, the app preserves the useful partial answer instead of replacing it with a generic stop footer.
- Corrupted and multi-column tables now ingest more reliably, with OCR/table reconstruction that preserves row alignment instead of flattening left-column data into garbage.
- Weak retrieval now triggers a corrective evidence pass before answer generation, using targeted full-text chunk and page recovery when the first pass is too thin or too generic.
- Fact-heavy answers are more resistant to table and spec misses through stronger extractive prioritization, table-aware evidence ordering, and page-level recovery.
- The answer pipeline is more willing to abstain when evidence is off-topic or structurally weak instead of synthesizing over bad matches.
- Dense technical PDFs and noisy scientific supplements hold up better during source review, with stronger evidence packs and clearer structured excerpts.
- Diagnostics now expose when corrective retrieval activated, making retrieval failures easier to inspect instead of hiding them behind a final answer.

## Earlier Milestones

- App Store launch on iPhone
- Local document Q&A with citations
- Native Apple platform integration for privacy-first workflows

## Notes

This public summary is intentionally feature-facing. Internal engine changes, tuning values, and private roadmap details are not published here.
