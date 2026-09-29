# OpenIntelligence roadmap

> **The roadmap lives in Notion, not in this file.** The public view is the
> [OpenIntelligence public roadmap](https://gunzino.notion.site/OpenIntelligence-Public-Roadmap-e4446012bb8940e6b78a745aee688075),
> and fascinaiting.me draws its board from the same database. Agents reach the database with the
> `notion-roadmap` skill. This page only says where things stand, so it cannot drift the way a copy of the
> roadmap did: until 2026-09-29 this file still described Private Cloud Compute as pending weeks after it
> shipped in 5.2.
> When a release or milestone changes where things stand, update the dated section below and nothing
> else; `AGENTS.md` rule 14 lists this file for that reason.

## Where things stand (2026-09-29)

- **Live:** 5.4 on iPhone, iPad and Mac since 2026-09-24, build 478. `Docs/SHIPPED_VERSION.json` is the
  per-platform record.
- **Open:** 5.5, with one change so far: a "how much" question only looks for a volume when it asks about
  something measured that way, such as fuel, oil, coolant or a tank, so it no longer locks a weight like
  "1 lb." from an unrelated document as its answer. The question that exposed it then went to the model,
  which still answered it wrong and still marked it Verified, so the roadmap row stays open. Build 481
  carries it in TestFlight on both platforms, and nothing is submitted for review.
- **Next candidates** are the roadmap's Future Backlog rows, including the ones the 2026-09-26 retrieval audit
  filed (`Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/README.md`).

`[evidence_level: release_state_verified, confidence: exact, evidence_source: Docs/SHIPPED_VERSION.json (app_store 5.4, preparing 5.5); App Store Connect read 2026-09-28 22:00 PT, both 5.5 records PREPARE_FOR_SUBMISSION with build 481]`

## The old page

The sections this file carried until 2026-09-29 (the v4.7 submission gate, instrumentation, the post-4.9
retrieval arc, near-term items, third-party local models, platform integration) were written before 5.0 and
are kept as a dated record in `Docs/Archive/ROADMAP_record_through_2026-09-29.md`.
