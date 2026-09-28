---
name: repo-map
description: Rebuild and republish the OpenIntelligence Repo Map, the owner's private page that shows every file in the repository, a trust status for each doc checked against the code, the Swift files nothing uses, a flow diagram, and the loose files git ignores. Use when the owner asks to refresh, rebuild or open the repo map, asks which docs are stale, accurate or safe to archive, which files are unused, or wants to see or visualize the repository. It is a page for the owner, not the agent feature index; that is the global codemap skill.
---

# Repo Map

The page: https://claude.ai/artifact/TJVQ32i3gjkBPvFUxcySyk, private to the owner. It is a snapshot
of one commit, so rebuild it after the repository changes.

## Rebuild and republish

```bash
OUT="${TMPDIR:-/tmp}/oi-repo-map"
python3 .claude/skills/repo-map/scripts/build_map.py --out "$OUT/data.json"
python3 .claude/skills/repo-map/scripts/render.py "$OUT/data.json" "$OUT/repo-map.html"
```

Then publish `$OUT/repo-map.html` with the Artifact tool to the URL above. From a conversation that
did not publish it, read it first (`action: "read"`) and publish with `url` set, so the link stays
the same. The survey takes about 40 seconds and is read-only: it runs git, reads files, and greps the
Xcode SDK's `.swiftinterface` files. `build_map.py` refuses an output path inside the repository.

To look at it before publishing, add `--preview "$OUT/preview.html"` to `render.py` and serve `$OUT`
over `python3 -m http.server`; the browser pane will not open a `file://` page it did not create.

## What each doc status means

| Status | Rule |
|---|---|
| Mostly out of date | At least 3 references, and at least 10% of them, name a file, type or function that no longer exists |
| Dead references | One or two references no longer resolve |
| Code moved on | Every reference resolves, but at least 3 (and at least half) of the Swift files it cites changed after its last edit, or its header names a version older than the live one |
| Gate-checked | On `scripts/verify_doc_claims.py`'s list, and every reference resolves |
| References resolve | Three or more references, all resolve, and the code it cites has mostly not changed since |
| Can't check | Fewer than 3 references; prose |
| History | Archives, audits, snapshots, release logs, or a doc that says it was superseded |

"Removed" means not declared or used in live code (comments do not count), not an Apple SDK type,
and not from a package dependency.

## Traps it handles; keep them when editing

`[evidence_level: code_verified, confidence: high, evidence_source: survey of df2c5b5 on 2026-09-28;
grep of the Xcode 27 SDK .swiftinterface files; ExtractiveQAService.swift:112-223]`

- `PrivateCloudComputeLanguageModel`, `ContextOptions`, `ReasoningLevel` and `LanguageModel` were once
  declared here as shims and are now Apple SDK types. A type is called removed only after the SDK
  interfaces and `.build/checkouts` are searched for it.
- Comments are stripped before a use is counted. `BertTokenizer` survives in live code only inside a
  commented-out block, so the docs that describe it as the current tokenizer are correctly flagged.
- An extension of a file's own type, such as a delegate conformance, does not make the file used. An
  extension of another type does, when a member it adds is named elsewhere.
- Lines carrying `verify-doc-claims: ignore` are skipped. `Type.init`, `allCases` on a `CaseIterable`
  enum and SwiftUI modifiers written as `ContentView.task` are not missing members.
- App Intents, widgets, `@main` types and previews are never "unused": the system finds them.

## Limits

- A green status means every file, type, function and line anchor a doc names still exists. Prose is
  not checked.
- "Unused" means no other Swift file names the file's types or its extension methods. Code reached
  through strings or reflection still looks unused, so nothing is deleted on this signal alone.
- GitHub links point at the newest commit origin has. An unpushed HEAD is surveyed but not linked.

## Files

- `scripts/build_map.py`: the survey. It imports `scripts/verify_doc_claims.py` for its patterns and
  reads the tables in `Docs/ai/ARCHITECTURE.md` and the Engine target in `Package.swift`.
- `scripts/page_template.html`: the page, with `/*__DATA__*/` where the survey goes.
- `scripts/render.py`: puts the survey into the page.
- `scripts/test_build_map.py`: runs the real survey and re-checks its verdicts independently.
