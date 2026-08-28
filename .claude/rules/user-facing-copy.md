---
paths:
  - "OpenIntelligence/Features/**"
  - "OpenIntelligence/UI/**"
  - "WHATS_NEW.md"
  - "Docs/USER_CHANGELOG.md"
  - "Docs/RELEASE_NOTES.md"
  - "README.md"
  - "fastlane/**"
---

# Anything a user reads

**Same turn as the change:** `WHATS_NEW.md` and `Docs/USER_CHANGELOG.md` for user-visible behavior.
`CHANGELOG.md` under the section the preflight names in `documentation_targets.changelog_section`, which is **not always `[Unreleased]`**, tagged `**[UI]**`.

## Every claim here is a claim about code

The Settings mode-capability list is captioned to users as what the active mode is doing right now.
It has repeatedly described things the app does not do: two features with zero call sites, eight
tool functions of which none were registered, a `≈65 tok/s` throughput figure roughly 2.4x the
measured one, and multipliers with no benchmark anywhere in the repository. Before adding a
capability line, find the call site. Before adding a number, find the measurement and label the
hardware it came from.

The same applies to `SampleDocumentManager`. Those documents are ingested, retrieved, and cited back
to users as sourced fact, so a stale figure there is worse than the same figure in chrome.

## Before removing a claim, run `oi-claim-audit`

Withdrawing a true claim has already happened here. "TinyBERT" was deleted because
`ReRankerModel.mlpackage/Manifest.json` declared no model family, but a Core ML manifest is a
packaging descriptor and never carries the source architecture, so its silence proved nothing.
`THIRD_PARTY_NOTICES.md` bound the model by exact path the whole time.

Absence of evidence in one artifact is not evidence of absence. The fix for a claim you cannot
verify is to look harder before deleting it. Use the `oi-claim-audit` skill for any removal,
weakening, or "correction" of a specific technical name, figure, or capability.

## Roadmap rows are public

Notion roadmap row titles are published on the public roadmap page. A row title carrying an
unmeasured figure ships that figure to everyone. Correct historical entries in place with a dated
note rather than deleting them, so the record shows what was claimed and when it was withdrawn.

## One structure, every release — the drift this fixes

Past releases used at least three different shapes for the same information: `v4.9`/`v4.8` used
`### Section` headings with `*   ` (asterisk, three spaces) bullets; `v4.7`/`v4.6` used no section
headings at all, just a flat list of `**Bold Label:** explanation` bullets; spacing between the
intro paragraph and the first heading, and between sections, was inconsistent release to release and
sometimes missing entirely. None of that was a deliberate choice — it drifted because each release
was written without looking at the last one. `v5.0` is the reference shape; match it exactly:

```
## vX.Y - Month DD, YYYY
One or two sentences of plain prose: what this release is about, no bullets, no heading.

### SectionName
- **Short bold headline, a sentence fragment or full sentence.** The explanation in plain prose,
  as many sentences as it needs. No jargon that isn't defined in-line.
- **Next item.** ...

### NextSection
- **...**
```

- Bullet marker is always `-`, never `*` and never a bare bold label with no leading hyphen.
- Section names are short nouns (`Speed`, `Libraries`, `Answers`, `Settings`) or `Your <thing>` when
  the section is specifically about the user's own content (`Your Documents`, `Your Sample
  Documents`) — both forms are correct, pick whichever fits the section, but don't invent a third
  shape.
- Exactly one blank line: after the intro paragraph, before each `###` heading, and after the last
  bullet of a section. Never a double blank line, never zero.
- This governs new releases going forward. Past releases (`v4.9` and earlier) are not being
  retroactively reformatted — that would rewrite published history for no reader benefit — but if a
  past release needs a correction anyway, bring its touched section in line with this shape at the
  same time.
