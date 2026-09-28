---
name: repo-map
description: Rebuild and republish the Repo Map pages, the owner's private pages that show every file in a repository, a trust status for each doc checked against the code, the Swift files nothing uses, and the loose files git ignores, for OpenIntelligence and his other App Store apps (OpenResponses, OpenManual, OpenCone). Use when the owner asks to refresh, rebuild or open a repo map, asks which docs are stale, accurate or safe to archive, which files are unused, or wants to see or visualize a repository. It is a page for the owner, not the agent feature index; that is the global codemap skill.
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

## The owner's other App Store apps

The same builder maps any Swift app repository. The parts that need something OpenIntelligence has
(its doc gate, its architecture tables and flow diagram, its Engine target, `Docs/SHIPPED_VERSION.json`)
switch on only where they exist; a repository with a codemap (`docs/ai/codemap/`, from the global
`codemap` skill) gets its features listed by name. Nothing is written inside the mapped repository.

| App | Repository | Page |
|---|---|---|
| OpenResponses | `~/Documents/GitHub/OpenResponses` | https://claude.ai/artifact/B6HQyzdf8Gxa1ZBRVm8MYa |
| OpenManual | `~/Documents/GitHub/OpenManual` | https://claude.ai/artifact/RhpBCzLL15CrdHqg5efEWf |
| OpenCone | `~/Documents/GitHub/OpenCone` | https://claude.ai/artifact/1EfQKxBhW2TtjRg4wKySFF |

```bash
APP=OpenCone; OUT="${TMPDIR:-/tmp}/$APP-map"
python3 .claude/skills/repo-map/scripts/build_map.py --root ~/Documents/GitHub/$APP --name $APP \
    --live-version 3 --out "$OUT/data.json"
python3 .claude/skills/repo-map/scripts/render.py "$OUT/data.json" "$OUT/repo-map.html"
```

`--live-version` is the version live on the App Store; take it from the store rather than from
memory: `curl -s "https://itunes.apple.com/lookup?bundleId=<bundle id>"`. Which apps are live was
read on 2026-09-28 from App Store Connect (`/v1/apps`, through `~/ASC`) plus that lookup: the four
above. WoWCA, Bud4, WoWGuessr, OpenAssistant and ASCDash exist in App Store Connect but were not in
the US store. The repositories live in iCloud, so read each `.git` once before a survey
(`find .git -type f -print0 | xargs -0 cat > /dev/null`), or git can stall on evicted objects.
`REPO_MAP_ROOT=<repo> REPO_MAP_NAME=<app> python3 .claude/skills/repo-map/scripts/test_build_map.py`
runs the same checks against another repository.

## Reading the documents the reference check cannot judge

The survey tests every file, type, function and line a document names. Prose it cannot test is read:
one reader per batch of documents checks each claim against the code with `path:line` evidence
(`reading/READ_BRIEF.md`), then a second reader tries to refute every "this is wrong" finding
(`reading/VERIFY_BRIEF.md`). Only findings that survive, and whose cited lines exist, are kept.
`reading/aggregate.py collect` gathers the readers' results and checks the cited lines;
`reading/aggregate.py apply` keeps what the second reader confirmed and writes the verdicts to
`~/.claude/repo-map-verdicts/<app>.json`, outside every repository, because a private repository's
findings must not land in this public one. The survey reads them from there. A verdict holds only while
the document is byte-for-byte what was read (it stores the git blob id); a changed document shows
"Read on <date>, but the document has changed since" and needs reading again.

## What each doc status means

| Status | Rule |
|---|---|
| Mostly out of date | At least 3 references, and at least 10% of them, name a file, type or function that no longer exists |
| Dead references | One or two references no longer resolve |
| Code moved on | Every reference resolves, but at least 3 (and at least half) of the Swift files it cites changed after its last edit, or its header names a version older than the live one |
| Gate-checked | On `scripts/verify_doc_claims.py`'s list, and every reference resolves |
| References resolve | Three or more references, all resolve, and the code it cites has mostly not changed since |
| Can't check | Fewer than 3 references; prose |
| History | Archives, audits, snapshots, release logs, a folder per shipped version (`docs/releases/v2.6/`), a review or audit folder, or a doc that says it was superseded |
| Some claims wrong | Read: at most a third of the claims checked are contradicted by the code, each confirmed by a second reader |
| Read, holds up | Read: nothing checked is contradicted; claims the code cannot settle are listed, not counted |
| Open plan | Proposes work that is not built, or only partly |
| Outside reference | A copy of outside documentation; the reading notes whether the app uses it |
| Nothing to check | Keywords, names, links or a template |
| Not read yet | Too few names for the mechanical check, and not read |

"Removed" means not declared or used in live code (comments do not count), not an Apple SDK type,
and not from a package dependency. A missing name whose own sentence or table cell says it is gone
("legacy", "replaced", "removed", "no longer exists", "never created") counts as history, not as a
dead reference; the page lists those under the document as history mentions.

## Traps it handles; keep them when editing

`[evidence_level: code_verified, confidence: high, evidence_source: survey of df2c5b5 on 2026-09-28;
grep of the Xcode 27 SDK .swiftinterface files; ExtractiveQAService.swift:112-223]`

- `PrivateCloudComputeLanguageModel`, `ContextOptions`, `ReasoningLevel` and `LanguageModel` were once
  declared here as shims and are now Apple SDK types. A type is called removed only after the SDK
  interfaces and `.build/checkouts` are searched for it.
- Comments are stripped before a use is counted. `BertTokenizer` survives in live code only inside a <!-- verify-doc-claims: ignore -->
  commented-out block. A doc that presents it as the current tokenizer is flagged; one that calls it
  legacy or replaced in the same sentence is not. The context is the sentence, not the paragraph: a
  paragraph-wide window let an unrelated "Replaced" excuse an example file that never existed.
- `RAGService+Streaming.swift`: the `+` belongs to the file name, so a match never starts after it.
  `OpenIntelligenceTests/EmbeddingProviderAgreementTests` is xcodebuild's `-only-testing:` target and
  class, not a path.
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

- `.claude/skills/repo-map/scripts/build_map.py`: the survey. It imports `scripts/verify_doc_claims.py` for its patterns and
  reads the tables in `Docs/ai/ARCHITECTURE.md` and the Engine target in `Package.swift`.
- `.claude/skills/repo-map/scripts/page_template.html`: the page, with `/*__DATA__*/` where the survey goes.
- `.claude/skills/repo-map/scripts/render.py`: puts the survey into the page.
- `.claude/skills/repo-map/scripts/test_build_map.py`: runs the real survey and re-checks its verdicts independently.
