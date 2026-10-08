# OpenIntelligence roadmap

> **The roadmap lives in Notion, not in this file.** The public view is the
> [OpenIntelligence public roadmap](https://gunzino.notion.site/OpenIntelligence-Public-Roadmap-e4446012bb8940e6b78a745aee688075),
> and fascinaiting.me draws its board from the same database. Agents reach the database with the
> `notion-roadmap` skill. This page only says where things stand, so it cannot drift the way a copy of the
> roadmap did: until 2026-09-29 this file still described Private Cloud Compute as pending weeks after it
> shipped in 5.2.
> When a release or milestone changes where things stand, update the dated section below and nothing
> else; `AGENTS.md` rule 14 lists this file for that reason.

## Where things stand (2026-10-08)

- **Live:** 5.6 on iPhone, iPad and Mac since 2026-10-08, build 485. `Docs/SHIPPED_VERSION.json` is the
  per-platform record. It carries twelve fixes to a person's first few answers and one change. Inline
  citations open their passage; numbers and times stay as the document wrote them; the Verified badge has
  three states and shows Verified only for a check that ran and passed; "Just Once" consent for Private
  Cloud Compute covers one question; a device that cannot run Apple Intelligence is told so; and a healthy
  library is no longer told to rebuild its search index. The change: a Deep Think session reads its chunks
  whole when they fit the device's window. The roadmap rows for these stay open until each is seen on a
  device.
- **Open:** nothing in source. The next source change needs a `## 5.7` heading in `CHANGELOG.md` first.
- **Next candidates** are the roadmap's Future Backlog rows, including the ones the 2026-09-26 retrieval audit
  filed (`Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/README.md`).

`[evidence_level: release_state_verified, confidence: exact, evidence_source: Docs/SHIPPED_VERSION.json (app_store 5.6 on both platforms); App Store Connect read 2026-10-08 13:18 PT, iOS 5.6 and macOS 5.6 READY_FOR_SALE with build 485]`

## The old page

The sections this file carried until 2026-09-29 (the v4.7 submission gate, instrumentation, the post-4.9
retrieval arc, near-term items, third-party local models, platform integration) were written before 5.0 and
are kept as a dated record in `Docs/Archive/ROADMAP_record_through_2026-09-29.md`.
