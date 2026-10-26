# OpenIntelligence roadmap

> **The roadmap lives in Notion, not in this file.** The public view is the
> [OpenIntelligence public roadmap](https://gunzino.notion.site/OpenIntelligence-Public-Roadmap-e4446012bb8940e6b78a745aee688075),
> and fascinaiting.me draws its board from the same database. Agents reach the database with the
> `notion-roadmap` skill. This page only says where things stand, so it cannot drift the way a copy of the
> roadmap did: until 2026-09-29 this file still described Private Cloud Compute as pending weeks after it
> shipped in 5.2.
> When a release or milestone changes where things stand, update the dated section below and nothing
> else; `AGENTS.md` rule 14 lists this file for that reason.

## Where things stand (2026-10-26)

- **Live:** 5.7 on iPhone, iPad and Mac since 2026-10-22, build 487, released automatically on Apple's
  approval. `Docs/SHIPPED_VERSION.json` is the per-platform record. 5.7 is about getting things in and out
  of the app: JSON and JSON Lines import as records; very large text files and PDFs over 500 MB import a
  piece at a time and resume where they stopped; Shortcuts actions that return their results, with new
  actions for adding, finding, creating and opening; Siri that asks before using Private Cloud Compute;
  Spotlight, Visual Intelligence, Handoff, widgets, and the Mac menu bar and Services; files accepted through
  "Open in", paste and the share sheet; sharing an answer with its sources and exporting a conversation;
  every label in an answer opening its passage, and Deep Think and Maximum answers checked; a very large
  library no longer slowing launch, Chat and the first question. `Docs/USER_CHANGELOG.md` has each of these
  in plain words.
- **Open:** nothing in source. On 2026-10-26 the owner said 5.7 is where he stops for a while. The next
  source change needs a `## 5.8` heading in `CHANGELOG.md` first. 131 roadmap rows are still on `v5.7` and not
  Completed (104 In Progress, 27 To Do, read 2026-10-26); whether they move to Future Backlog is his call. Rows
  that close only on his phone or Mac stay open until they are seen there.
- **Next candidates** are the roadmap's Future Backlog rows, including the ones the 2026-09-26 retrieval
  audit filed (`Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/README.md`).

`[evidence_level: release_state_verified, confidence: exact, evidence_source: Docs/SHIPPED_VERSION.json (app_store 5.7 on both platforms); App Store Connect read 2026-10-26, iOS 5.7 and macOS 5.7 READY_FOR_SALE with build 487]`

## The old page

The sections this file carried until 2026-09-29 (the v4.7 submission gate, instrumentation, the post-4.9
retrieval arc, near-term items, third-party local models, platform integration) were written before 5.0 and
are kept as a dated record in `Docs/Archive/ROADMAP_record_through_2026-09-29.md`.
