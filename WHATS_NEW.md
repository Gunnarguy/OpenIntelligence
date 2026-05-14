# What's New

Public release highlights for OpenIntelligence.

## 3.6

Changes since 3.5:

Version 3.6 adds optional iCloud reuse for the libraries you choose, without giving up the app's local-first default.

If you've been building one library on iPad and wishing that exact processed library could show up on iPhone or your other devices without starting over, this is the update aimed at that problem - but now it works per library instead of as an all-or-nothing cloud mode.

Shoutout to Tim for asking for this.

## Highlights

- Every library can now be set to **Local Only** or **iCloud Drive** individually.
- New libraries now ask where they should live when you create them, and existing libraries can be switched later.
- **Local Only** libraries stay fully on-device unless you explicitly change them.
- Libraries you mark **iCloud Drive** can reuse imported files and processed state across your own Apple devices on the same iCloud account.
- If a long-running import is interrupted on one device, another device can pick up queued work for that iCloud library instead of forcing you to restart from scratch.
- The iCloud controls in Documents and Settings are cleaner, shorter, and easier to understand, with clearer status, Sync Now actions, and direct library storage controls.

This release is about making cross-device reuse practical without compromising the app's privacy-first, local-by-default model.

## 3.5

Changes since 3.2.5:

Sorry for the rough edges in the last few updates. Version 3.5 is the cleanup release that should have landed sooner.

If dense PDFs, exact-value lookups, starter prompts, or long-running imports felt less reliable than they should have, this is the corrective pass. It rolls up the real fixes shipped after 3.2.5 and makes the app more dependable on hard documents.

## Highlights

- Exact answers are stronger across Standard, Deep Think, and Maximum for direct source-backed questions over tables, specs, measurements, counts, dates, prices, and similar exact values.
- Starter questions and follow-ups are more grounded and are less likely to surface weak, generic, or misleading prompts when the source support is thin.
- Onboarding, empty states, and the bundled sample workspace explain the app more clearly, including best-supported file types, the 4,096-token model limit, and when processing stays on-device versus uses Apple Private Cloud Compute.
- PDFs and images now share one adaptive visual-ingestion path, searchable figures and structured tables survive more often, and clean scientific PDFs are less likely to produce fake tables, broken headings, or reference-section noise.
- Table-heavy pages are less likely to collapse back into scrambled paragraph text during ingestion, which improves retrieval quality after re-import.
- Large user-initiated imports are more reliable, with better queue recovery, background cleanup, and stronger Live Activity behavior on long-running work.
- Library and settings copy better matches the app's real per-library isolation and runtime behavior.

## 3.3

This is a reliability and document-understanding update focused on making imports harder to lose and technical answers more trustworthy again.

## Highlights

- Large user-initiated imports now preserve queue state, resume more cleanly after interruption, and surface clearer progress while work continues.
- PDFs and images now use one adaptive visual-ingestion path instead of a manual fidelity toggle, so garbled, table-heavy, image-heavy, and small-text pages get stronger recovery automatically.
- Embedded PDF figures and standalone images are now preserved as searchable evidence with captions, OCR labels, nearby page context, and visual descriptions.
- Exact specification and table lookups are stronger, and starter questions stay closer to what the current library can actually answer cleanly.

## 3.2.5

This is a corrective quality update for the 3.2 line, focused on making obvious source-backed answers fast and reliable again.

## Highlights

- Exact lookups now lock onto table rows, specification values, measurements, counts, limits, dates, and prices more directly when the source clearly contains the answer.
- Deep Think and Maximum run a precision lookup before longer reasoning, so simple questions can still get short cited answers in higher-effort modes.
- Standard, Deep Think, and Maximum share stronger retrieval rescue for table and specification passages.
- Starter questions are generated from actual uploaded passages with stricter grounding checks instead of loose document labels.
- Exact measurement answers are cleaner and can include nearby equivalent units when the source provides them.

## 3.1

This is the user-facing 3.1 summary focused on document understanding, OCR reliability, and grounded answer quality after the rushed 3.0 cut.

## Highlights

- Deep Think and Maximum now preserve strong grounded partial answers if a late-stage generation interruption happens, instead of replacing useful output with a generic stop footer.
- Multi-column PDFs, noisy scans, and corrupted tables ingest more reliably, with layout-aware OCR fallback and better row and column preservation.
- Tables now retain stronger schema, row, and cell anchors, which improves factual lookups for specs, measurements, and statistical values.
- Weak first-pass retrieval now triggers a corrective evidence pass before answer generation, improving dense scientific PDFs and technical manuals.
- Final answers are stricter about evidence quality, with unsupported or weakly supported claims handled more conservatively before they reach the UI.
- Maximum mode now reasons over evidence more cleanly, with better clustering and less tendency to polish weak support into overconfident prose.
- Source review is clearer on hard documents, with better structured excerpts and stronger abstention when the corpus does not actually support the answer.

## Earlier Milestones

- App Store launch on iPhone
- Local document Q&A with citations
- Native Apple platform integration for privacy-first workflows

## Notes

This public summary is intentionally feature-facing. Internal engine changes, tuning values, and private roadmap details are not published here.
