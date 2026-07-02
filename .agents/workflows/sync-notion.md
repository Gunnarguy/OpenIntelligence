# /sync-notion — Sync the Notion roadmap to the current work

Update the OpenIntelligence Roadmap in Notion. Runs standalone or called from /finalize.

Hardcoded target — do NOT search for it:
- Database ID: `37f49a74-d54f-81b7-9424-dae1288c0043` (use ONLY with retrieve-database calls)
- Data source ID: `37f49a74-d54f-81b0-92d9-000bce5e05fa` (use ONLY with query-data-source calls — note it differs from the database ID)

## Exact tool recipe (Notion REST-style MCP, e.g. `notion-mcp-server`) — tiered, stop-on-failure
Try these in order. Move to the next tier ONLY on failure of the previous one.

1. **Tier 1 (new API):** `API-query-data-source` with `data_source_id: "37f49a74-d54f-81b0-92d9-000bce5e05fa"`.
   - KNOWN FAILURE: if this returns `400 invalid_request_url`, the MCP server's Notion API version predates data-source endpoints. Do not retry with other IDs — go to Tier 2.
2. **Tier 2 (legacy API — expected to work on this server):** `API-post-database-query` with `database_id: "37f49a74-d54f-81b7-9424-dae1288c0043"` and body `{"filter": {"property": "Status", "select": {"does_not_equal": "Completed"}}}`.
3. **Tier 3 (ID discovery):** `API-retrieve-a-database` with `database_id: "37f49a74-d54f-81b7-9424-dae1288c0043"`; if the response exposes `data_sources[0].id`, retry Tier 1 with that exact value; otherwise retry Tier 2.
4. **If all tiers fail: STOP.** Report each tier's exact error to the user and ask how to proceed. NEVER answer a roadmap question from `API-post-search` or any workspace-wide search — those return rows from OTHER databases and have already produced wrong answers once.
5. Filter for open items: Status `does_not_equal` "Completed" (same filter shape works on both query endpoints).
6. Sanity check on ANY result set: this roadmap's Status values contain NO emojis (`To Do`, `In Progress`, `Completed`) and its Components are exactly `Ingestion/Chunking/Indexing/Retrieval/Orchestration/Shortcuts/General/UI`. Emoji statuses (e.g. "🔨 In Progress") = WRONG database = discard the results and report.

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
