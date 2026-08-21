# Project

## Purpose

Ask questions of your own documents and get answers that cite the excerpt they came from, without
the documents ever leaving the device.

The bet is that a genuinely good retrieval engine fits on an iPhone, and that an answer is more
trustworthy when you can see what it was built from. Most document AI requires uploading your files
first, which is the whole problem when those files are medical, legal, financial, or simply yours.

`[evidence_level: code_verified, confidence: high, evidence_source: README.md, Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md]`

## Users

People with private document libraries who want retrieval over them and are unwilling to upload
them. Shipping publicly on the App Store, so the audience is general consumers rather than
developers, and product copy is read by people who will not check the source.

## In scope

- Ingesting PDFs (including OCR through Vision when the text layer is unreliable), Office files,
  code, plain text, images, audio, and video. **Pages, Numbers and Keynote are explicitly out of
  scope**: modern iWork stores content as compressed protobuf in `Index/*.iwa`, no Apple API
  exposes it, and `extractTextFromIWorkDocument` throws on every such file by construction. The
  picker still offers them so the failure is reachable and explained rather than hidden.
- On-device indexing: dense vectors plus a SQLite FTS5 keyword index.
- Hybrid retrieval with reciprocal rank fusion and cross-encoder reranking.
- Answers with tappable citations back to the source excerpt.
- Optional final-answer generation on Apple Private Cloud Compute, with consent.
- iCloud sync of the document library across a user's own devices.
- Siri Shortcuts and App Intents.
- Paid tiers with quotas.

## Out of scope, deliberately

- No account and no server operated by this project.
- No third-party AI service anywhere in the path. Not OpenAI, not Anthropic, not Google.
- No uploading documents to make search work. Retrieval is local, always.
- Not a web app or a cross-platform app. Apple platforms only.

These are not roadmap gaps. They are the product.

## Platforms and toolchain

`[evidence_level: code_verified, confidence: exact, evidence_source: project.pbxproj, Package.swift, verified 2026-08-07]`

- Deployment target iOS 26.0 and macOS 26.0. Some capabilities are gated to 27+, notably native
  Private Cloud Compute execution.
- Swift tools 6.0, SwiftUI.
- Built with Xcode 27, installed at `/Applications/Xcode-beta.app`.
- Targets: `OpenIntelligence` (app), `OpenIntelligenceEngine` (SwiftPM library),
  `OpenIntelligenceLiveActivities` (widget extension), `OpenIntelligenceTests`.

## Critical dependencies

- **Apple Foundation Models**, for on-device and Private Cloud Compute generation. The public SDK
  exposes no model-tier selector and no server-side architecture or context window, so do not name
  either in code or copy.
- **Core ML**, for the bundled cross-encoder reranker at
  `OpenIntelligence/Resources/MLModels/ReRankerModel.mlpackage`. `THIRD_PARTY_NOTICES.md` binds it to
  `cross-encoder/ms-marco-TinyBERT-L2-v2`, Apache 2.0, by exact path.
- **swift-transformers**, vendored locally at `OpenIntelligence/swift-transformers`, for tokenizers.
- **Vision**, for OCR.
- **StoreKit 2**, for billing.
- **CloudKit / iCloud Drive**, for library sync.

External services used by the project but not by the app: Notion (roadmap), App Store Connect and
Xcode Cloud (release), GitHub Actions (CI).

## Constraints that change implementation decisions

1. **The repository lives in iCloud-synced `~/Documents`.** This is the single largest source of
   false build failures. See [DECISIONS.md](DECISIONS.md) and [RUNBOOK.md](RUNBOOK.md).
2. **A schema, on-disk format, or embedding-dimension change forces every existing user to reindex
   their whole library.** Migrations must be additive first, then swap.
3. **Claims in the app are claims about code.** The Settings capability list is captioned to users as
   live behavior and has repeatedly described features with no call sites and figures with no
   measurement. Verify before adding, and verify harder before removing.
4. **`RAGAppIntents.swift` uses 9 of 10 Siri shortcut slots.**
5. **The suite is 173 tests across 22 files, and none of them cover routing, gates, sync, or
   end-to-end retrieval.** The seams between subsystems are where the real defects have been found.
   `[evidence_level: test_verified_by_prior_session, confidence: high, evidence_source: CHANGELOG.md "suite 173/173" recorded 2026-08-07, file count verified 2026-08-07, verify: run the suite command in RUNBOOK.md]`

## Source-of-truth locations

| Question | Authority |
|---|---|
| Does the app do X? | The source. Then `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`. |
| What is planned? | The Notion roadmap database, not `Docs/ROADMAP.md`. |
| What version is this? | The first `## <number>` heading in `CHANGELOG.md`, which drives `MARKETING_VERSION`. |
| What may I edit? | The route from the RepoOS preflight, plus `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`. |
| How do agents behave here? | `AGENTS.md`, then `CLAUDE.md` for Claude Code specifically. |
| What is happening right now? | [STATE.md](STATE.md). |
