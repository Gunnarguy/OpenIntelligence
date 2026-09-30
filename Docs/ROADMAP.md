# OpenIntelligence roadmap

> **The roadmap lives in Notion, not in this file.** The public view is the
> [OpenIntelligence public roadmap](https://gunzino.notion.site/OpenIntelligence-Public-Roadmap-e4446012bb8940e6b78a745aee688075),
> and fascinaiting.me draws its board from the same database. Agents reach the database with the
> `notion-roadmap` skill. This page only says where things stand, so it cannot drift the way a copy of the
> roadmap did: until 2026-09-29 this file still described Private Cloud Compute as pending weeks after it
> shipped in 5.2.
> When a release or milestone changes where things stand, update the dated section below and nothing
> else; `AGENTS.md` rule 14 lists this file for that reason.

## Where things stand (2026-09-30)

- **Live:** 5.5 on iPhone, iPad and Mac since 2026-09-30, build 483. `Docs/SHIPPED_VERSION.json` is the
  per-platform record. It carries three changes: a "how much" question only looks for a volume when it asks
  about something measured that way, so it no longer locks a weight like "1 lb." from an unrelated document;
  a Pro subscription gives Pro while it is active instead of permanent Lifetime; and the plans screen shows
  what each plan saves against the others, from the store's own prices, for the prices in force from
  2026-09-30 (Lifetime $49.99) and 2026-10-01 (Pro $4.99 a month, $24.99 a year). The question that exposed
  the first fix then went to the model, which still answered it wrong and marked it Verified, so that
  roadmap row stays open.
- **Open:** nothing. The next source change needs a `## 5.6` heading in `CHANGELOG.md` first.
- **Next candidates** are the roadmap's Future Backlog rows, including the ones the 2026-09-26 retrieval audit
  filed (`Docs/AuditArtifacts/RAGArchitectureAudit_2026-09-26/README.md`).

`[evidence_level: release_state_verified, confidence: exact, evidence_source: Docs/SHIPPED_VERSION.json (app_store 5.5 on both platforms); App Store Connect read 2026-09-30 10:14 PT, iOS 5.5 and macOS 5.5 READY_FOR_SALE with build 483]`

## The old page

The sections this file carried until 2026-09-29 (the v4.7 submission gate, instrumentation, the post-4.9
retrieval arc, near-term items, third-party local models, platform integration) were written before 5.0 and
are kept as a dated record in `Docs/Archive/ROADMAP_record_through_2026-09-29.md`.
