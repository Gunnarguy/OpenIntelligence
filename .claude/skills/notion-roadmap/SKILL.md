---
name: notion-roadmap
description: Read or update the OpenIntelligence roadmap in Notion, which is the source of truth for plans rather than Docs/ROADMAP.md. Use whenever the user asks what is planned, what is in progress, what the backlog or priorities are, or mentions the roadmap; and whenever a task starts or finishes work that a roadmap row tracks. Also use before answering any "what's next" or "is X on the roadmap" question, because answering those from memory has produced wrong answers.
---

# Notion roadmap

The Notion database is authoritative for plans. `Docs/ROADMAP.md` is a mirror and has been the stale
side before. Never answer a roadmap question from memory or from the markdown.

`.agents/workflows/sync-notion.md` describes the same job for Antigravity. Claude Code does not load
`.agents/`, which is why this skill exists. If the two disagree, whichever was verified more recently
wins, and fix the other in the same task.

## Identifiers, hardcoded on purpose

```text
database    37f49a74-d54f-81b7-9424-dae1288c0043
datasource  collection://37f49a74-d54f-81b0-92d9-000bce5e05fa
```

The two differ only in the middle segment. Query tools take the **data source** URL; `notion-fetch`
takes either.

**Never locate this database by workspace search.** Other databases in the workspace have
similar-looking rows and have already produced a wrong answer once. Theirs use emoji statuses
(`🔨 In Progress`); this one does not. If a result set contains an emoji status, you are reading the
wrong database. Discard it and say so.

## Reading

This server's `notion-query-data-sources` runs **SQLite against the data source URL as a table
name**. It does not take Notion filter objects.

```sql
SELECT url, "Name", "Status", "Component", "Priority", "Target Release",
       "date:Added:start" AS added, "date:Completed:start" AS completed
FROM "collection://37f49a74-d54f-81b0-92d9-000bce5e05fa"
WHERE "Status" != 'Completed'
ORDER BY "Status", "Name"
```

Pass it as `{"data": {"data_source_urls": ["collection://37f49a74-d54f-81b0-92d9-000bce5e05fa"], "query": "..."}}`.
Use `params` with `?` placeholders rather than interpolating strings.

Date properties are not queryable under their display name. Use the split columns
`date:Added:start`, `date:Completed:start`. Run `notion-fetch` on the database first if you need the
schema; it returns the full `CREATE TABLE` definition.

## Release scope is frozen; triage before you file

`CLAUDE.md` governs this and the rule is not advisory. **A new row defaults to `Future Backlog`.**
It gets the active release only if it passes one of three tests, and the row must name which:

1. **Data loss or corruption.** The user loses work, or the app silently damages what it stored.
2. **An advertised capability does not work.** Something the App Store listing, onboarding, Settings
   or the README claims, which does not do what it says.
3. **It blocks shipping.** The build cannot go out, or cannot go out honestly, until this is done.

Performance, retrieval quality, refactors, features, tooling and test coverage do **not** qualify,
however valuable. They are real work and they belong on the board — in `Future Backlog`, where they
do not inflate a release that is trying to close.

If a row is genuinely ambiguous, file it `Future Backlog` and say in the body why it might belong in
the release. Pulling a row forward is one property change; discovering three months later that the
release never converged because everything was tagged into it is not recoverable.

**State the closing condition in the body when you file.** "Closes when X is observed on device" is
the difference between a row that can end and a row that accumulates commentary. A row nobody can
close is a row that will still be open at the next release.

## Writing

**Starting** work a row tracks: set `Status` to `In Progress`.
**Finishing** it: set `Status` to `Completed` **and** `date:Completed:start` to today.
**No row exists** for durable work: create one.

Update with `notion-update-page`, `command: "update_properties"`. Create with
`notion-create-pages` and `parent: {"type": "data_source_id", "data_source_id": "37f49a74-d54f-81b0-92d9-000bce5e05fa"}`.
Put the detail in the page `content` as Notion-flavored Markdown; keep the title short.

Pure docs-only or refactor-only changes need no row unless they close one.

## Schema, verified 2026-08-28 off the live data source

Never invent an option. These are the complete lists.

| Property | Options |
|---|---|
| `Status` | `To Do`, `In Progress`, `Completed`. There is no "Shipped". |
| `Component` | `Ingestion`, `Chunking`, `Indexing`, `Retrieval`, `Orchestration`, `Shortcuts`, `General`, `UI`, `Infrastructure` |
| `Priority` | `High`, `Medium`, `Low` |
| `Target Release` | `v4.0`, `v4.1`, `v4.2`, `v4.3`, `v4.3.1`, `v4.4`, `v4.5 (Phase 2B)`, `v4.6`, `v4.7 (iOS) / v3.0 (macOS)`, `v4.8 (iOS)`, `v4.9`, `v5.0`, `v5.1`, `Future Backlog` |
| `Target OS` | `All (26.5 & 27)`, `iOS/macOS 26.5 Only`, `iOS/macOS 27+ Only`. Optional; leave unset rather than asserting one for dev tooling. |
| Dates | `Added`, `Completed`, ISO dates, set through `date:<name>:start` |

The two split-numbered `Target Release` options are historical. From 4.9 onward both platforms share
one version, so new rows use a single label such as `v5.1` and never a split one.

This table is a cache and has been the stale side before: it stopped at `v5.0` while `v5.1` had
already been added to the live database, which is how a session ends up filing new work against a
released version. Re-read the live data source with `notion-fetch` on the data source URL whenever
the active release changes, and re-date the heading above when you do.

## Getting `Target Release` right

Take it from the preflight's `active_release`:

```bash
python3 .codex/skills/route-openintelligence-work/scripts/repoos_router.py preflight --task "..."
```

Read `state`, not just `version`. `in_development` means the target is the next release and
`last_shipped` is already out; writing `last_shipped` onto new work is the error that got a build
rejected by App Store Connect on 2026-07-28. If it reports `unreleased` or
`unassigned`, the next version has not been named: stop and ask rather than picking the closest
option.

## Row titles are published

This database is the source for the public roadmap page, so a row title is public writing. Two
consequences:

- A title carrying an unmeasured figure publishes that figure. Describe the mechanism instead.
- Correct a wrong historical row in place with a dated note rather than deleting it, so the record
  shows what was claimed and when it was withdrawn. Use the `oi-claim-audit` skill before removing
  any specific technical name, figure, or capability from a row.

Blunt defect titles are the established voice here and are fine. Read a few existing rows before
writing one.

## Finish by reporting the exact rows you touched, with their URLs.
