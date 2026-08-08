# /sync-notion — Sync the Notion roadmap to the current work

Update the OpenIntelligence Roadmap in Notion. Runs standalone or called from /finalize.

Hardcoded target — do NOT search for it:
- Database ID: `37f49a74-d54f-81b7-9424-dae1288c0043` (use ONLY with retrieve-database calls)
- Data source ID: `37f49a74-d54f-81b0-92d9-000bce5e05fa` (use ONLY with query-data-source calls — note it differs from the database ID)

## Exact tool recipe — tiered, stop-on-failure
Try these in order. Move to the next tier ONLY on failure of the previous one. Which tier applies
depends on which Notion MCP server is connected, so check your available tool names first rather
than assuming.

0. **Tier 0 (hosted `mcp.notion.com`, the server connected as of 2026-08-07).** Different tool names
   *and* a different call shape from the tiers below. The tools are `notion-fetch`,
   `notion-query-data-sources`, `notion-update-page`, `notion-create-pages`, and querying is
   **SQLite against the data source URL used as a table name**, not a Notion filter object:

   ```sql
   SELECT url, "Name", "Status", "Component", "Target Release", "date:Completed:start"
   FROM "collection://37f49a74-d54f-81b0-92d9-000bce5e05fa"
   WHERE "Status" != 'Completed'
   ```

   Date properties are not queryable under their display name; use `date:Added:start` and
   `date:Completed:start`. Create rows with `notion-create-pages` and
   `parent: {"type": "data_source_id", ...}`; update with `notion-update-page`,
   `command: "update_properties"`.

   The `API-*` tiers below do not exist on this server and fail as unknown tools. They are kept for
   a self-hosted `notion-mcp-server`, which exposes them instead, and their filter-object bodies
   apply only there. `[verified 2026-08-07 by running the calls against the live database]`

   Claude Code does not load `.agents/`, so it reads this recipe from
   `.claude/skills/notion-roadmap/SKILL.md` instead. Change both or neither.
1. **Tier 1 (new API, REST-style server):** `API-query-data-source` with `data_source_id: "37f49a74-d54f-81b0-92d9-000bce5e05fa"`.
   - KNOWN FAILURE: if this returns `400 invalid_request_url`, the MCP server's Notion API version predates data-source endpoints. Do not retry with other IDs — go to Tier 2.
2. **Tier 2 (legacy API, self-hosted `notion-mcp-server` only — does NOT exist on the hosted server):** `API-post-database-query` with `database_id: "37f49a74-d54f-81b7-9424-dae1288c0043"` and body `{"filter": {"property": "Status", "select": {"does_not_equal": "Completed"}}}`.
3. **Tier 3 (ID discovery):** `API-retrieve-a-database` with `database_id: "37f49a74-d54f-81b7-9424-dae1288c0043"`; if the response exposes `data_sources[0].id`, retry Tier 1 with that exact value; otherwise retry Tier 2.
4. **If all tiers fail: STOP.** Report each tier's exact error to the user and ask how to proceed. NEVER answer a roadmap question from `API-post-search` or any workspace-wide search — those return rows from OTHER databases and have already produced wrong answers once.
5. Filter for open items: Status is not "Completed". On Tier 0 that is `WHERE "Status" != 'Completed'` in SQL; the `does_not_equal` filter object applies to the Tier 1–3 endpoints only.
6. Sanity check on ANY result set: this roadmap's Status values contain NO emojis (`To Do`, `In Progress`, `Completed`) and its Components are exactly `Ingestion/Chunking/Indexing/Retrieval/Orchestration/Shortcuts/General/UI/Infrastructure`. Emoji statuses (e.g. "🔨 In Progress") = WRONG database = discard the results and report. `Infrastructure` was missing from this list until 2026-08-07, which would have made a legitimate Infrastructure row look like evidence of the wrong database.

1. Determine the feature/fix summary and its architectural tag from the current diff (or from /update-docs output).
2. Query the data source for an existing row whose `Name` matches the feature (fuzzy match on keywords).
3. If a row exists: update `Status` → `Completed` (or `In Progress` if work is ongoing) and set the `Completed` date to today when completing.
4. If no row exists: create one with `Name` = the CHANGELOG bullet text, `Status` = `Completed`, `Component` = the architectural tag, `Priority` = Medium unless obvious, `Target Release` per the next line, `Added` = today.
   **`Target Release` comes from the preflight's `active_release`, read as three fields.** `version` is what new work targets, `state` is `shipped` or `in_development`, and `last_shipped` is already out. Never write `last_shipped` onto new work; that is what got a build rejected by App Store Connect on 2026-07-28. If `version` is `unreleased` or the Notion target reads `unassigned`, the next version has not been named: stop and ask rather than picking the closest option. This paragraph previously said the field was defective and told you to work around it; the defect was fixed on 2026-08-07 and the workaround is gone. One rule, stated once, in `.claude/skills/notion-roadmap/SKILL.md`. `[verified 2026-08-07: test_repoos_router.py 24/24]`
5. Schema guard — the ONLY valid select values are:
   - Status: `To Do`, `In Progress`, `Completed` (never "Shipped" — it does not exist)
   - Component: `Ingestion`, `Chunking`, `Indexing`, `Retrieval`, `Orchestration`, `Shortcuts`, `General`, `UI`, `Infrastructure`
   - Priority: `High`, `Medium`, `Low`
   - Target Release: `v4.0`, `v4.1`, `v4.2`, `v4.3`, `v4.3.1`, `v4.4`, `v4.5 (Phase 2B)`, `v4.6`, `v4.7 (iOS) / v3.0 (macOS)`, `v4.8 (iOS)`, `v4.9`, `v5.0`, `Future Backlog`
     This list previously stopped at `v4.6`, which combined with the rule below meant an agent
     targeting v5.0 work would "round down" to a two-release-old label. The two split-numbering
     options are historical: from 4.9 onward both platforms share one version, so new rows use
     `v4.9` or `v5.0` and never a split label. `[read off the live data source 2026-08-05; matches .agents/rules/01-docs-and-notion-sync.md]`
   If a needed option doesn't exist, use the closest valid one and note it — never invent select options. If the closest valid option is more than one release away from the truth, stop and ask instead.
6. Report the exact row(s) touched with their URLs.
