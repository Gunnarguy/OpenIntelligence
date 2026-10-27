# Project

Corrected 2026-10-20 against the working tree (`b868fc0` plus the 5.7 work in progress), where "In scope"
disagreed with the code or left out what it does: which Office files fail, what the vector index is, the
weighted fusion, the defaults a new install starts with for Private Cloud Compute, and the three answer
modes, with a pointer to `Docs/HOW_IT_WORKS.md` section 07 for the loop. Line numbers are that tree's, with
`RAGService.swift` re-pinned to the file as it stood at 22:27 PDT, and they will move.

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
  code, plain text, images, audio, and video, and from 5.7 JSON and JSON Lines files as records. **Pages, Numbers and Keynote are explicitly out of
  scope**: modern iWork stores content as compressed protobuf in `Index/*.iwa`, no Apple API
  exposes it, and `extractTextFromIWorkDocument` throws on every such file by construction. The
  picker still offers them so the failure is reachable and explained rather than hidden.
  Corrected 2026-10-20: "Office files" means `.docx`, `.xlsx` and `.pptx`, read from their zipped XML. A
  legacy `.doc`, `.xls` or `.ppt` does not open as a ZIP, and its import fails with "Office document
  detected. For best results, export as PDF before importing." `[evidence_level: code_verified,
  confidence: high, evidence_source: DocumentProcessor.swift:9389-9487, 10015-10020, 10118-10119]`
- On-device indexing: dense vectors plus a SQLite FTS5 keyword index.
  Corrected 2026-10-20: the vectors are 384 numbers a passage from MiniLM-L6-v2 (512 from `NLEmbedding`
  when it stands in), kept in one flat file per library in arrival order, rewritten whole at each save, and
  searched by comparing the question with every vector, not through an approximate index such as HNSW. The keyword index stems words
  (porter) and weights section titles. `Docs/INGESTION_PIPELINE.md` §4 has the detail. `[evidence_level:
  code_verified, confidence: high, evidence_source: CoreMLSentenceEmbeddingProvider.swift:66,
  EmbeddingService.swift:181-213, BNNSVectorDatabase.swift:26-41, 1104-1201, SQLiteFullTextService.swift:242-255,
  1440-1461]`
- Hybrid retrieval with reciprocal rank fusion and cross-encoder reranking.
  Added 2026-10-20: the fusion is weighted, with `k = 60`. `[evidence_level: code_verified, confidence:
  exact, evidence_source: HybridSearchService.swift:1328-1334, QueryProfileService.swift:49-52]`
- Answers with tappable citations back to the source excerpt.
- Optional final-answer generation on Apple Private Cloud Compute, with consent.
  Corrected 2026-10-20: a new install starts with the route Hybrid and the PCC permission "Ask when
  needed", so the first question the route planner sends to PCC brings up the consent sheet (Always Allow,
  Just Once, Deny), and after Always Allow later sends are not asked about. PCC needs iOS or macOS 27, a
  build made with Swift 6.4 or later, the app's entitlement, and quota left. `[evidence_level:
  code_verified, confidence: high, evidence_source: SettingsStore.swift:44-50, 450-462, LLMModel.swift:218,
  264-268, ChatScreen.swift:3172-3190, RAGService.swift:4391-4440, FoundationModelSessionFactory.swift:86-110]`
- Three answer modes (added 2026-10-20): Standard, the default for a new install, gathers its evidence in
  one pipeline and writes the answer in one generation, with at most a citation retry and an integrity repair
  on the same route. The nine verification gates then run once and never send the answer back to the model:
  Standard can withhold an answer they score low, and a lookup whose gates failed, unless the extracted-value
  override already replaced its answer, then gets the source-only check, two on-device calls that can rewrite
  or withhold it. Deep Think and Maximum search with several phrasings and, when what they find grades
  excellent or good, read it over several sessions, on the device unless the person picked PCC in the model
  picker, before a final synthesis, with no tools in any session. They run the gates from 5.7, as a label only
  (in 5.6 those answers read Not Checked). `Docs/HOW_IT_WORKS.md` section 07 has the loop and its stop rules.
  `[evidence_level: code_verified, confidence: high, evidence_source: SettingsStore.swift:617-624,
  RAGService.swift:11588, 11239-11263, 16274-16392, 16571-16834, 16870-16894, 19500-19525,
  AgenticOrchestrator.swift:339, 544-1143, 5313, 9228-9240]`
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
  Corrected 2026-10-27: "Swift tools 6.0" is the root `Package.swift`'s tools version, not the language mode.
  The app targets and the root package compile in Swift 5 language mode: `SWIFT_VERSION = 5.0` in the Debug and
  Release configurations of all seven targets in `project.pbxproj` (the project-level pair sets none), and
  `swiftLanguageModes: [.v5]` in `Package.swift`. The vendored `swift-transformers` package declares tools 6.0 and
  sets no language mode, so the Swift 5 clause here does not cover it.
  `[evidence_level: code_verified+grep_verified, confidence: exact, evidence_source: grep -o 'SWIFT_VERSION = [^;]*' OpenIntelligence.xcodeproj/project.pbxproj (14 matches, all 5.0) and a parse of its 16 XCBuildConfiguration blocks against their configuration lists; Package.swift:1 and 97-99; OpenIntelligence/swift-transformers/Package.swift:1; read at 1e4a718]`
- Built with Xcode 27.0 (`27A266a`, Swift 6.4) at `/Applications/Xcode.app`; the beta application was removed on 2026-09-10 (`CLAUDE.md`).
- Targets: `OpenIntelligence` (app), `OpenIntelligenceEngine` (SwiftPM library),
  `OpenIntelligenceLiveActivities` (widget extension), `OpenIntelligenceTests`.

## Critical dependencies

- **Apple Foundation Models**, for on-device and Private Cloud Compute generation. The public SDK
  exposes no model-tier selector and no server-side architecture or context window, so do not name
  either in code or copy.
- **Core ML**, for the bundled cross-encoder reranker at
  `OpenIntelligence/Resources/MLModels/ReRankerModel.mlpackage`. `THIRD_PARTY_NOTICES.md` binds it to
  `cross-encoder/ms-marco-TinyBERT-L2-v2`, Apache 2.0, by exact path.
- **Core ML and Core AI**, for the bundled sentence embedder, `sentence-transformers/all-MiniLM-L6-v2`, one
  copy for each framework. From 5.7 a new library uses the Core ML copy on iPhone and iPad and the Core AI
  copy on macOS 27 (`EmbeddingProviderDefaults` in `EmbeddingService.swift`), and a library keeps the copy
  it was built with.
- **swift-transformers**, vendored locally at `OpenIntelligence/swift-transformers`, for tokenizers.
- **Vision**, for OCR.
- **StoreKit 2**, for billing.
- **CloudKit / iCloud Drive**, for library sync.
  Corrected 2026-10-27: iCloud Drive only, no CloudKit. No Swift file imports CloudKit or uses `CKContainer`,
  `CKDatabase` or `CKRecord`, and the app's `com.apple.developer.icloud-services` entitlement lists only
  `CloudDocuments` (the Share and Live Activities extensions have no iCloud entitlement). Library sync is
  `WorkspaceSyncService`, which watches the ubiquitous documents scope with `NSMetadataQuery`.
  `[evidence_level: code_verified+grep_verified, confidence: exact, evidence_source: git grep -E 'import CloudKit|CKContainer|CKDatabase|CKRecord' over all Swift (no match); plutil -p of OpenIntelligence.entitlements, OpenIntelligenceShare.entitlements and OpenIntelligenceLiveActivities.entitlements; WorkspaceSyncService.swift:3648-3649 (NSMetadataQuery over NSMetadataQueryUbiquitousDocumentsScope); Docs/DOCUMENTATION_CONSISTENCY_AUDIT.md section 3, "Sync"; read at 1e4a718]`

External services used by the project but not by the app: Notion (roadmap), App Store Connect and
Xcode Cloud (release; as recorded 2026-09-22 it archives and has no test action, see
`Docs/ai/RUNBOOK.md` `## Release`). There is no GitHub Actions workflow:
`.github/` holds only templates and assets (checked 2026-09-24).

## Constraints that change implementation decisions

1. **The repository lives in iCloud-synced `~/Documents`.** This is the single largest source of
   false build failures. See [DECISIONS.md](DECISIONS.md) and [RUNBOOK.md](RUNBOOK.md).
2. **A schema, on-disk format, or embedding-dimension change forces every existing user to reindex
   their whole library.** Migrations must be additive first, then swap.
3. **Claims in the app are claims about code.** The Settings capability list is captioned to users as
   live behavior and has repeatedly described features with no call sites and figures with no
   measurement. Verify before adding, and verify harder before removing.
4. **`RAGAppIntents.swift` uses 10 of 10 Siri shortcut slots since 5.7** (9 through 5.6; "Find Passages" took
   the tenth). An eleventh stops every one registering with no error, and `AppShortcutsProviderTests` fails the
   suite at eleven.
5. **The suite is 832 tests as of 2026-10-12 (106 Swift files under `OpenIntelligenceTests`; it was 504
   tests in 65 files on 2026-09-28), and it tests components, not the seams between them.** The 65 counted
   on 2026-09-28 were 63 test files and two ingestion fixture builders. Some pieces now
   have unit tests: `ModelExecutionPlannerTests` covers the routing decision
   `ModelExecutionPlanner.makePlan` (9 of its 13 tests; the other 4 cover the route badge and the receipt's Codable round trip), and `SourceOnlyStandardGateTests` covers
   `RAGService.standardSkipsSourceOnlyCheck`, the rule that lets Standard skip the source-only check
   once the gates pass. Since then `VerificationGateService.verify` has callers in `NumericSanityGateTests`,
   `SemanticGroundingClaimTests` and `ClaimCheckEvaluationTests`, and `WorkspaceSyncImportGuardTests` covers the
   sync pass's import guard and its chunk merge (checked 2026-10-12). No test calls
   `FoundationModelRoutePolicy.determineRoute`, none reconciles two devices' libraries, and none runs a question
   end to end from retrieval to answer. The seams
   between subsystems are where the real defects have been found.
   `[evidence_level: test_verified_by_prior_session, confidence: high, evidence_source: full iOS suite on the merged tree, 504 tests, 4 skipped, 0 failures (Docs/ai/STATE.md, Verification 2026-09-28); git ls-files OpenIntelligenceTests (65 Swift files, 63 declaring an XCTestCase, 504 func test declarations) and a grep of that folder for each named symbol, 2026-09-29. Superseded figure: 173 tests across 22 files, recorded 2026-08-07]`

## Source-of-truth locations

| Question | Authority |
|---|---|
| Does the app do X? | The source. Then `Docs/CANONICAL_OPENINTELLIGENCE_SOURCE_OF_TRUTH.md`. |
| What is planned? | The Notion roadmap database, not `Docs/ROADMAP.md`. |
| What version is this? | The first `## <number>` heading in `CHANGELOG.md`, which drives `MARKETING_VERSION`. |
| What may I edit? | The route from the RepoOS preflight, plus `Docs/RepoOS/03_FORBIDDEN_EDIT_BOUNDARIES.md`. |
| How do agents behave here? | `AGENTS.md`, then `CLAUDE.md` for Claude Code specifically. |
| What is happening right now? | [STATE.md](STATE.md). |
