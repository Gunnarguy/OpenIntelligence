# Changelog

This is the public version history for OpenIntelligence. It focuses on user-visible product changes and intentionally omits private engine tuning, thresholds, and internal implementation details.

## 3.6 - May 2026

- Shoutout to Tim for asking for this.
- Added per-library storage choice so every library can be Local Only or iCloud Drive independently
- Kept the app local-first by default, with only iCloud-marked libraries entering the shared iCloud workspace
- Added cross-device reuse for iCloud libraries so imported files and processed library state can show up on the user's other Apple devices
- Added queue lease handling so another device can resume long-running work for an iCloud library if the first device drops out
- Cleaned up the Documents and Settings sync surfaces with clearer status, shorter copy, direct library storage controls, manual Sync Now actions, and less truncation on tighter layouts
- Smoothed out the Documents tab follow-up layout so the new sync UI is easier to read and tap without crowding the rest of the page
- Made in-app import cancellation work more reliably from the upload queue overlay
- Prevented deleted or reconfigured libraries from reviving old queued documents after sync or reload, and tightened cleanup when removing a library
- Improved OCR and image-analysis stability during document import

## 3.5 - May 2026

- Rolled up the corrective work since 3.2.5 into a more stable 3.5 release focused on trust, first-touch clarity, and harder real-world documents
- Strengthened exact answers across Standard, Deep Think, and Maximum for direct source-backed lookups over tables, specifications, measurements, counts, dates, prices, and similar exact values
- Tightened starter questions and follow-up suggestions so they stay grounded in actual passage support, fail closed more often on weak evidence, and avoid canned filler around procedures, requirements, and duration claims
- Reworked onboarding, empty states, and the bundled sample workspace so first-run guidance explains the real product story more clearly: model limits, best-supported file types, and when processing stays on-device versus uses Apple Private Cloud Compute
- Unified PDF and image visual ingestion behind one adaptive path, preserved searchable figures and structured tables more reliably, and reduced fake tables, broken headings, mixed table/prose contamination, and reference-section noise on scientific PDFs
- Improved long-running user-initiated imports with better queue recovery, background cleanup, and Live Activity lifecycle handling
- Cleaned up library and settings surfaces so per-library isolation and live runtime behavior are described more accurately

## 3.3 - April 2026

- Large user-initiated imports now preserve queue state, resume after interruption more cleanly, and surface clearer progress on supported devices
- Removed the old ingestion fidelity setting and replaced it with one adaptive visual-ingestion path that raises OCR/detail recovery only when a page actually needs it
- Preserved embedded PDF figures as searchable chunks with captions, OCR labels, page context, and visual descriptions instead of dropping them during structured chunking
- Grounded embedded-image analysis with real page text observations so figure captions and nearby instructions attach more reliably
- Preserved parsed table titles, headers, and rows in SQLite during ingestion so uploaded reference documents remain more inspectable and queryable instead of collapsing to flattened text only
- Added a structured table fallback path for retrieval when exact values sit under table headings, schemas, or row data that ordinary chunk search can miss
- Kept the exact-answer cleanup from the 3.2.5 corrective line in place so direct fact questions stay brief, grounded, and less citation-heavy across Standard, Deep Think, and Maximum
- Tightened starter-question quality so suggested questions stay closer to what a single grounded passage can actually answer cleanly

## 3.2.5 - April 2026

- Improved exact-value answers for table rows, specifications, measurements, counts, limits, dates, and prices when the source clearly contains the answer
- Added a precision lookup path before Deep Think and Maximum begin longer reasoning, so simple source-backed questions can still resolve quickly
- Shared stronger table/spec retrieval rescue across Standard, Deep Think, and Maximum
- Tightened generated starter questions so they are grounded in actual uploaded passages instead of loose document labels or generic topics
- Cleaned up exact measurement answers, including nearby equivalent units when present in the source

## 3.1 - April 2026

- Preserved grounded partial answers in Deep Think and Maximum when a late-stage generation interruption happens, instead of dropping generic stop text onto useful output
- Improved ingestion for noisy scans, multi-column PDFs, and corrupted tables so rows and columns survive extraction more reliably
- Strengthened table-aware retrieval and structured evidence packing for specification sheets, statistical tables, and dense scientific documents
- Tightened claim verification so unsupported statements are pruned or downgraded before final answers are shown
- Improved long-form reasoning with better evidence clustering, corrective retrieval, and more conservative abstention when support is weak

## 3.0 - April 2026

- Reworked noisy PDF and OCR table ingestion so structured rows survive extraction instead of collapsing into column-order garbage
- Added a corrective retrieval pass that runs before answer generation when first-pass evidence is weak, thin, or too generic
- Strengthened extractive handling for tables, specifications, and statistical outputs with better table-priority evidence selection and page recovery
- Tightened grounded abstention behavior when retrieved evidence is structurally weak or topically mismatched
- Improved diagnostics so retrieval hardening and corrective recovery are visible during pipeline review

## 2.5 - April 2026

- Starter questions now come from representative samples of the active library instead of generic prompts
- Refreshing starter questions surfaces more varied grounded prompts rather than repeating the same ideas
- Follow-up suggestions behave more reliably after answers and library switches, including deeper follow-up, clarification, and comparison flows
- Grounded answer routing is stronger before answers are shown, with a stricter path for fact-heavy questions and a more constrained synthesis path when needed
- Evidence verification is tighter before final answer presentation so weak support is handled more conservatively
- Weakly supported answers are surfaced more clearly through better answer review and source inspection
- Source cards, filenames, and scrollable excerpts are easier to inspect in response details
- Tables, lists, quotes, headings, separators, and other structured technical output render much better
- Malformed links in generated answers are repaired more aggressively
- PDF imports filter garbage text and noisy extraction more cleanly on messier files
- Maximum mode now has a real daily free-use quota path with clearer paid behavior
- Historical paid users are protected more generously in entitlement handling
- Settings, billing, and plan messaging were cleaned up to better match the actual entitlement model

## 2.0.x - March 2026

- Faster everyday document Q&A workflows
- Better handling for edge-case documents and long-running sessions
- Sharper source review, app responsiveness, and product polish

## 2.0.0 - February 2026

- Public App Store release of OpenIntelligence
- Native iPhone experience for asking questions about personal documents
- Multi-format import, local organization, and cited answers
- Subscription and purchase support for product access tiers

## Notes

Detailed internal algorithm changes and research-oriented engine updates are tracked privately rather than in the public changelog.
