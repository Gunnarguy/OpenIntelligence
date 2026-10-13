# OpenIntelligence roadmap

> **The roadmap lives in Notion, not in this file.** The public view is the
> [OpenIntelligence public roadmap](https://gunzino.notion.site/OpenIntelligence-Public-Roadmap-e4446012bb8940e6b78a745aee688075),
> and fascinaiting.me draws its board from the same database. Agents reach the database with the
> `notion-roadmap` skill. This page only says where things stand, so it cannot drift the way a copy of the
> roadmap did: until 2026-09-29 this file still described Private Cloud Compute as pending weeks after it
> shipped in 5.2.
> When a release or milestone changes where things stand, update the dated section below and nothing
> else; `AGENTS.md` rule 14 lists this file for that reason.

## Where things stand (2026-10-12)

- **Live:** 5.6 on iPhone, iPad and Mac since 2026-10-08, build 485. `Docs/SHIPPED_VERSION.json` is the
  per-platform record.
- **In preparation:** 5.7, opened 2026-10-09. Its records exist in App Store Connect on both platforms
  (`PREPARE_FOR_SUBMISSION`); no Xcode Cloud build has run for it. In source so far: JSON and JSON Lines
  import as records; very large text files imported a piece at a time with checkpoints; Shortcuts actions that
  return results, with new actions for adding, finding, creating and opening; files accepted through "Open
  in", paste, Home Screen actions and keyboard commands; sharing an answer with its sources and exporting a
  conversation; a notification when an import or a long answer is done; fixes to how numbers are checked and
  how sentences are selected; a very large library no longer slowing launch, Chat and the first question; an
  Atlas that names its clusters and axes from the library's own words; the Core ML copy of the embedding model
  for new libraries on iPhone and iPad. `Docs/USER_CHANGELOG.md` has each of these in plain words.
- **Still open in 5.7:** indexing the vector store's passage file instead of decoding it at launch; device
  checks of the items above; the roadmap rows on `v5.7` that are `To Do`.
- **Next candidates** beyond that are the roadmap's Future Backlog rows, including the ones the 2026-09-26
  retrieval audit filed (`Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/README.md`).

`[evidence_level: release_state_verified, confidence: exact, evidence_source: Docs/SHIPPED_VERSION.json (app_store 5.6 on both platforms, preparing 5.7); App Store Connect read 2026-10-12 20:25 PT, 5.7 PREPARE_FOR_SUBMISSION on iOS and macOS; and 2026-10-08 13:18 PT, iOS 5.6 and macOS 5.6 READY_FOR_SALE with build 485]`

## The old page

The sections this file carried until 2026-09-29 (the v4.7 submission gate, instrumentation, the post-4.9
retrieval arc, near-term items, third-party local models, platform integration) were written before 5.0 and
are kept as a dated record in `Docs/Archive/ROADMAP_record_through_2026-09-29.md`.
