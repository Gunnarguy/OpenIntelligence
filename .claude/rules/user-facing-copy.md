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
`CHANGELOG.md` under `[Unreleased]`, tagged `**[UI]**`.

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
