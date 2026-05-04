# Data Boundaries

This is the short buyer-safe explanation of where data lives, what can leave the device, and what the current evaluation path actually does.

## One Sentence

OpenIntelligence is designed as a local-first embedded engine for Apple apps: documents are stored and indexed locally by default, and the current buyer packet does not depend on a hosted web API.

## What Stays Local By Default

For the current engine and packet story, these core steps are local-first:

- document import
- text extraction
- OCR fallback
- chunking
- local full-text indexing
- local vector indexing
- hybrid retrieval
- local storage of indexed content and metadata

This is the actual engine path described in:

- `Docs/STORAGE_AND_PIPELINE_TRACE.md`
- `OpenIntelligence/Services/Storage/SQLiteFullTextService.swift`
- `OpenIntelligence/Services/VectorStore/BNNSVectorDatabase.swift`

## Where Data Is Stored

By default, runtime data lives under Application Support in an `OpenIntelligence` folder.

The current runtime-path implementation is in:

- `OpenIntelligence/Core/Support/OpenIntelligenceRuntimePaths.swift`

The current storage shape includes:

- SQLite full-text storage for documents, chunks, and pages
- per-container vector files for embeddings and norms
- container metadata and related local runtime files

Important implementation note:

- SQLite container isolation currently relies on `container_id` inside shared tables
- vector storage is persisted per knowledge container

That is good prototype engineering, but it is not yet the same thing as a hardened multi-tenant enterprise boundary.

## What Can Leave The Device

The cleanest buyer-safe statement is:

- there is no hosted web API in the current buyer packet
- there is no developer-operated cloud dependency required for the current engine evaluation path
- Apple-managed execution behavior still matters where Apple platform features allow it

For the repo's current privacy summary, when Private Cloud Compute is explicitly allowed, only the active query and selected context are part of that Apple-managed path, not the full document archive.

Relevant source:

- `PRIVACY.md`
- `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`

## What Does Not Exist In The Buyer Packet Story

Do not describe the current packet as having:

- a hosted web API
- a developer-run backend
- a general cloud-RAG control plane
- a public 65K-token Apple context path
- Apple Foundation Models embeddings

Those are outside the current truthful buyer story.

## Logging And Telemetry

The current privacy summary says:

- no third-party analytics are shipped
- telemetry stays local unless optional export is enabled in reviewer / developer paths

Use that exact framing unless you are doing a deeper engineering review.

Source:

- `PRIVACY.md`

## How Another App Controls Storage

The current engine entry-point code allows a caller to provide a custom storage location.

That means a buyer app can choose where the engine stores its local working data, instead of being forced into one hard-coded app path forever.

Relevant file:

- `OpenIntelligence/SDK/OpenIntelligenceEngine.swift`

## What To Say In A Buyer Conversation

Use this:

"The current engine story is local-first and embedded. Documents and indexes live locally by default, there is no hosted web API in the buyer packet, and the evaluation path is designed around Apple-native execution on supported hardware. Where Apple-managed execution modes are allowed, we talk about that explicitly instead of pretending nothing ever leaves the device under any circumstance."

## What Not To Say

Do not say:

- "Nothing can ever leave the device under any circumstance"
- "This is already a hardened enterprise security boundary"
- "This is HIPAA compliant"
- "This has zero logging"

Say what is true, narrowly and directly.
