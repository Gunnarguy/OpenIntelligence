# Changelog

This is the public version history for OpenIntelligence. It focuses on user-visible product changes and intentionally omits private engine tuning, thresholds, and internal implementation details.

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
