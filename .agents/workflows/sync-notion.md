# /sync-notion — Sync the Notion roadmap to the current work

Update the OpenIntelligence Roadmap in Notion. Runs standalone or called from /finalize.

Hardcoded target — do NOT search for it:
- Database ID: `37f49a74-d54f-81b7-9424-dae1288c0043`
- Data source: `collection://37f49a74-d54f-81b0-92d9-000bce5e05fa`

1. Determine the feature/fix summary and its architectural tag from the current diff (or from /update-docs output).
2. Query the data source for an existing row whose `Name` matches the feature (fuzzy match on keywords).
3. If a row exists: update `Status` → `Completed` (or `In Progress` if work is ongoing) and set the `Completed` date to today when completing.
4. If no row exists: create one with `Name` = the CHANGELOG bullet text, `Status` = `Completed`, `Component` = the architectural tag, `Priority` = Medium unless obvious, `Target Release` = current release (check `Docs/USER_CHANGELOG.md` heading), `Added` = today.
5. Schema guard — the ONLY valid select values are:
   - Status: `To Do`, `In Progress`, `Completed` (never "Shipped" — it does not exist)
   - Component: `Ingestion`, `Chunking`, `Indexing`, `Retrieval`, `Orchestration`, `Shortcuts`, `General`, `UI`
   - Priority: `High`, `Medium`, `Low`
   - Target Release: `v4.0`, `v4.1`, `v4.2`, `v4.3`, `v4.3.1`, `v4.4`, `v4.5 (Phase 2B)`, `v4.6`, `Future Backlog`
   If a needed option doesn't exist, use the closest valid one and note it — never invent select options.
6. Report the exact row(s) touched with their URLs.
