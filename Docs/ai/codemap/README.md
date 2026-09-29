# Codemap: feature index and knowledge graph

A fresh agent session should find a named feature, its purpose and the files to open without
re-reading the repository. The map has two levels:

1. [INDEX.md](INDEX.md): one row per feature, with the words a user might say, one sentence of
   purpose, the slice to open and the file to start at. It is small enough to read every time.
2. `features/<id>.json`: one slice per feature, read only when that feature is the task. A slice
   lists the feature's files, its nodes (views, view models, services, state, storage,
   integrations, configuration, tests) and typed edges between them, each with evidence.

[DRIFT.md](DRIFT.md) lists places where a document and the code disagree.
[UNMAPPED.md](UNMAPPED.md) lists source files no feature claims, with what was checked about each.
All three Markdown files are generated from the slices by `python3 .claude/codemap/codemap.py index`.

## Using it on a feature task

1. Read `INDEX.md`, or run `python3 .claude/codemap/codemap.py find <words>`.
2. Open only the matching slice.
3. Confirm the cited lines in the live code before trusting them. `python3 .claude/codemap/codemap.py check <id>`
   reports any citation that no longer matches, and `affected` lists slices whose files changed
   since they were stamped.
4. Edit. Then update the slice (below) in the same change.

`python3 .claude/codemap/codemap.py owner <path>` names the feature that owns a file, and
`python3 .claude/codemap/codemap.py refs <Symbol>` lists live declarations and mentions of a symbol,
which is the fallback when a slice is silent.

## Evidence and status

Every node and edge carries a status:

| Status | Meaning |
|---|---|
| VERIFIED | The Swift syntax on the cited line states the link on its own: it constructs a type declared once at top level (`Type(`), or calls a member through its type (`Type.member(`, `Type.shared.member(`). This repository's `code_verified`. Hand-written links are VERIFIED only when someone read the cited line. |
| INFERRED | A matching name was found (a call or mention by name, a test naming the symbol). This repository's `grep_verified`; it can point at the wrong symbol. |
| UNKNOWN | Expected but not found. The edge points to `?` and the note says what was looked for. |

Evidence is `{"path", "line", "match"}`. `match` is text copied from one line of that file,
compared without regard to whitespace; `line` is a hint that `stamp` keeps current. The checker
re-finds every `match`, so a renamed function or deleted call shows up as a broken citation rather
than a silently wrong map. Static reading misses relationships made at run time (protocol dispatch,
notifications, SwiftUI environment injection); those are recorded as INFERRED or UNKNOWN rather than
asserted.

## Slice schema (`codemap/1`)

```json
{
  "schema": "codemap/1",
  "id": "voice",
  "name": "Voice mode",
  "aliases": ["realtime", "live", "gpt-live-1"],
  "purpose": "One sentence: what the feature does for the user and where it runs.",
  "revision": "bd8027e",
  "verified_on": "2026-09-28",
  "entry_points": ["InlineVoiceView"],
  "files": [{"path": "OpenResponses/Core/Services/RealtimeService.swift", "role": "primary", "blob": "<set by stamp>"}],
  "nodes": [{"id": "RealtimeService", "kind": "service", "path": "...", "line": 12, "match": "final class RealtimeService", "status": "VERIFIED", "note": "..."}],
  "edges": [{"from": "InlineVoiceView", "type": "calls", "to": "RealtimeService", "status": "VERIFIED",
             "evidence": [{"path": "...", "line": 88, "match": "realtimeService.connect("}], "note": "..."}],
  "docs": [{"path": "ARCHITECTURE.md", "section": "Browser, voice and files", "quote": "text copied from one line",
            "claim": "what the document says", "status": "CONFIRMED", "evidence": {"path": "...", "line": 1, "match": "..."}, "note": "..."}],
  "unknowns": ["what could not be established"],
  "related": ["chat-turn"]
}
```

- `role`: `primary` (the feature owns the file), `shared` (a file several features use, such as
  `RAGService.swift`, shared by four slices here), `test`.
- Node `kind`: `view`, `view_model`, `service`, `model`, `function`, `state`, `persistence`,
  `integration`, `config`, `test`, `util`, `intent`, `resource`, `entry`. Large shared files get
  `function` nodes for the functions that implement this feature, so an agent can jump to them.
- Node ids are short and unique within the slice, usually the Swift symbol (`RAGService.createNewThread`
  in the `evidence-threads` slice). This repository has no `ChatViewModel`; the examples named one
  until 2026-09-29, carried over from the codemap skill's template, which was written for another app.
  State and storage use a prefix: `defaults:<key>`, `keychain:<service>`, `file:<name>`,
  `openai:<endpoint>`. An edge can point at another feature as `feature:<id>`, or at a node in
  another slice as `<feature-id>#<node-id>`.
- Edge `type`: `renders`, `calls`, `reads`, `writes`, `configures`, `depends_on`, `tested_by`.
- Doc `status`: `CONFIRMED`, `CONTRADICTED` (the code does something else), `STALE` (describes an
  earlier state: old paths, versions, removed features), `UNVERIFIED` (not checkable from code, such
  as live API behavior). Contradicted and stale claims are listed in DRIFT.md; the documents are not
  rewritten to hide them.
- A slice with `"index": false` holds repository-wide claims and stays out of the index.

## Keeping it current

After changing code:

```bash
python3 .claude/codemap/codemap.py affected        # stale slices, and new files no slice claims
python3 ~/.agents/codemap/build.py ID...           # regenerate those slices' links from the code
python3 .claude/codemap/codemap.py check
python3 .claude/codemap/codemap.py stamp ID...
python3 .claude/codemap/codemap.py index
```

Use the builder, not `refresh`: `refresh` runs the skill's own Swift derive, which marks every link
INFERRED and writes a separate `derived` block.

A slice is stale when a file it lists differs from the blob hash `stamp` recorded, or when one of
its citations no longer matches. Commits alone do not make a slice stale. For each stale slice:
re-read the changed code, fix, rename or remove what it invalidated, add what is new, then
rebuild, check and `stamp <id>`; `stamp` refuses while any citation is broken. A slice whose content is still
right only needs the refresh. A new source file either joins a slice's `files` or gets a note under
`unmapped_notes` in `config.json`.

### What runs on its own here

| When | What runs | Effect |
|---|---|---|
| Session start | `python3 "$HOME/.agents/codemap/hook.py" brief`, a SessionStart hook in `.claude/settings.json` | One line: features, cited lines, how many moved or broke since stamping. |
| Each prompt | `$HOME/.agents/codemap/hook.sh`, a UserPromptSubmit hook in `.claude/settings.json` | When the prompt names a feature, prints its slice with every cited line re-found in the live code; silent otherwise, and once per feature per session. |

Neither edits or stamps a slice: a stamp claims someone re-read the code, so it stays with the agent
that did. Both live on the owner's Mac; in a clone without them the hooks exit quietly.

`check` exits 1 on errors (broken citation, missing path, schema fault), so it can gate CI.
Warnings (changed files, unmapped files) and notes (moved lines, commits since stamping) do not fail it.

The checker is `.claude/codemap/codemap.py`, standard-library Python with no dependencies (not under
`scripts/`, because a push touching `scripts/` here starts an Xcode Cloud build). The method is packaged
for other repositories as the `codemap` skill in `~/.claude/skills/codemap/`.

## This repository's map

- 46 slices at the stamped revision; together their `primary` files cover every app Swift file under
  `OpenIntelligence/` (without the vendored `swift-transformers`) and `OpenIntelligenceLiveActivities/`
  exactly once. Tests are claimed by the source path they mirror, or by `test_owners` in
  `config.json` with the reason; the two app-wide resources nothing owns are in `unmapped_notes`.
- Names, aliases, purposes and file boundaries were drafted by Gemini 3.8 Flash from an inventory and
  `Docs/ai/ARCHITECTURE.md`, then corrected by hand. Entry points come first from the symbols
  ARCHITECTURE names, then from reading the code. Each slice's `traps` names the hard-boundary files
  it owns (`Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`) and code that is compiled out or unreachable.
- `derive.plumbing` in `config.json` lists the telemetry and resource types every feature calls;
  their links are left out except in the slice that owns them.
- Links are regenerated by `~/.agents/codemap/build.py` (its README has the Swift rules). On
  2026-09-28 an independent reader tried to refute 40 sampled links; the verdicts, the fixes they
  led to, and an A/B of fresh sessions with and without the map are in
  `~/.agents/featuremap/ab/2026-09-28-OpenIntelligence/` on the owner's Mac.
