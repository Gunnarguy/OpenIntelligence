SIDEPROJECTORS SUBMISSION SHEET

This file is meant to match the actual SideProjectors submission wizard.

Submission flow:

1. Project information
2. Media
3. How is this project built?
4. Revenue
5. Metrics
6. Sale information
7. Confirm & submit

Use this as a direct fill sheet.

PAGE 1. PROJECT INFORMATION

What type of project are you selling?
Select the standard for-sale project option.

Project name
OpenIntelligence

Logo
Use the current OpenIntelligence logo.

Please pitch your project in one sentence
Use this:

Private Apple-native document engine for grounded local-first answers

Project homepage
https://github.com/Gunnarguy/OpenIntelligence

Project description
Markdown field
Paste this:

# OpenIntelligence

OpenIntelligence is a private Apple-native document-intelligence engine that currently lives inside a shipped iOS codebase.

The public app was the proving ground. The thing for sale is the engine itself: the Swift/iOS code, the current source-distributed SDK lane, the evaluation materials, and the handoff context around it.

This started because I kept wanting AI help with the exact documents I did not want pushed through a generic hosted workflow. Manuals. IFUs. Service guides. Internal references. Training material. Product docs. Sensitive operational stuff.

So I built the Apple-native version I wanted to exist.

## What is actually here

- adaptive multi-format document import, extraction, OCR fallback, and page preservation
- structure-aware chunking with metadata enrichment and section-aware context
- local SQLite full-text storage plus per-library vector indexes
- hybrid retrieval with BM25, vector search, reranking, diversity, and parent-context expansion
- context packing tuned to fit Apple's current public model window
- grounded answer generation, citations, verification gates, and abstention behavior
- a repo-root Swift package surface, sample integration host, validation scripts, and buyer packet materials

## What the engine does

At a high level, it takes raw files, turns them into a searchable knowledge layer, finds the best supporting evidence with hybrid retrieval, compresses that evidence into the available model budget, and then returns a cited answer with confidence-aware behavior instead of just fluent output. Apple Foundation Models is the answer layer where available, but most of the engine's value is the ingestion, indexing, retrieval, packing, and verification stack around that step.

## What I am actually selling

The strongest commercial lane today is a private source-distributed SDK with assisted integration, packet-based diligence, and a clean handoff path.

There is no hosted web API in the buyer packet. Documents and indexes are local-first by default. I am not representing this as a polished self-serve enterprise SDK, a toolchain-agnostic binary SDK, or a regulated-use answer system.

This is also not a sale of the whole app business by default. It is a sale or license discussion around the engine, the repo, the evaluation materials, and the handoff context around the engine.

If a repo snapshot is transferred, some app-side files still exist around the engine because that is where the engine was built, but those are context around the asset, not the asset being valued.

## Current state

- the engine is real and substantial
- the source-distributed SDK lane is real and validated
- the buyer packet and partner packet are current
- the repo is a serious head start for Apple-native private document QA
- it still needs more cleanup and productization before it looks like a polished standalone SDK

Select up to 5 markets related to this project
Use these:

- Artificial Intelligence
- Developer Tools
- Mobile Devices
- Productivity Software
- iOS

Project Social Media Links

X (Twitter) handle
Leave blank unless you want to include it.

Facebook handle
Leave blank.

LinkedIn username
Gunnar-Hostetler

Instagram handle
Leave blank.

YouTube channel
@Gunzino

TikTok handle
Leave blank.

Pinterest username
Leave blank.

Reddit username
Gunnarguy

Telegram username
Gunzino

Discord server
Leave blank unless you want it included.

PAGE 2. MEDIA

Use the current listing media unless you are intentionally refreshing it.

Recommended:

- keep the current main project image
- keep the current Loom/video link
- keep the existing logo unless you have a cleaner updated version ready

PAGE 3. HOW IS THIS PROJECT BUILT?

Languages
Use these:

- Swift 6
- Ruby
- HTML
- CSS
- JavaScript
- Python

Frameworks
Use these:

- Apple Foundation Models
- CoreML
- Vision
- PDFKit
- NaturalLanguage
- AVFoundation
- Accelerate/BNNS
- Foundation

Libraries & Packages
Use these:

- Swift Package Manager (SPM)
- SQLite/SQLite FTS5
- swift-transformers
- Tokenizers
- swift-jinja
- swift-collections
- Python benchmark tooling
- CoreML model assets
- local benchmark dashboard/reporting scripts

Databases
Use these:

- SQLite
- SQLite FTS5
- local file-backed storage
- local vector indexes
- container-scoped document storage

Hosting & Infrastructure
Use these:

- GitHub
- local benchmark/dashboard tooling
- local evaluation artifacts

Third-Party SaaS & APIs
Use these:

- Apple Foundation Models
- Apple platform frameworks

Other
Markdown field
Paste this:

## Technical shape

OpenIntelligence is an Apple-native document-intelligence engine with a real end-to-end document pipeline around the answer layer.

The practical flow is:

import -> extraction and OCR fallback -> page preservation -> semantic chunking and metadata enrichment -> SQLite full-text and vector indexing -> hybrid retrieval and reranking -> context packing -> Apple-native generation or extractive fallback -> citations and verification gates

What matters is that Apple Foundation Models is one layer inside that system, not the whole system.

More concretely, the engine includes:

- text extraction and OCR fallback
- page-level preservation for source review and exact lookup
- structure-aware chunking and metadata enrichment
- local SQLite full-text indexing
- local vector indexing
- hybrid retrieval and reranking
- diversity, parent-context expansion, and graph-style cross-reference following
- nearby-context expansion and context packing
- citation packaging and source review
- verification-oriented answer handling and abstention
- benchmark and regression tooling for corpus-level evaluation

The private repo also includes implemented and/or documented paths for HyDE-style query expansion, RAPTOR-lite routing, Reciprocal Rank Fusion, MMR diversification, parent-document retrieval, contextual compression, graph-style context packing, lost-in-the-middle mitigation, quality modes, adaptive pipeline optimization, benchmark tooling, and multi-session orchestration.

## Documentation split

There are two useful architecture views in the repo:

- ARCHITECTURE.md is the shipped app and product view
- EngineSale/ENGINE_INVENTORY.md and SDK_BOUNDARY_AUDIT.md are the engine and SDK boundary view

That split matters because the public app and the engine are related, but they are not the same thing.

## Honest boundary

The current implementation is a serious Swift/iOS engine prototype and codebase head start.

It is not being represented as:

- a finished enterprise SDK
- a full GraphRAG system
- a guaranteed-accuracy answer engine
- a regulated-use document system

Any other information you want to share about how this project was built?
Markdown field
Paste this:

## Why I built it this way

OpenIntelligence started from a real problem I kept running into: I work around large volumes of technical documentation, IFUs, manuals, internal reference material, and sensitive information that should not be sent into mainstream hosted AI systems.

Even when big AI vendors say they do not train on user data, the workflow still requires sending the material outside the local app environment. For the kinds of documents I had in mind, that was not an acceptable default.

That curiosity became OpenIntelligence.

Once Apple Foundation Models became available to developers, I wanted to see how far an Apple-native private document QA system could realistically go. I used that as the answer layer, but most of the real work became everything around it: ingestion, OCR and layout recovery, chunking, full-text and vector indexing, retrieval, reranking, context packing, citations, and getting the system to refuse or fall back when support was weak.

## What that turned into

The result is not just an app shell. The private engine includes adaptive document ingestion, OCR-oriented processing, layout-aware extraction, semantic chunking, page preservation, local full-text indexing, local vector search, hybrid retrieval, reranking, context packing, Apple-native generation paths, extractive fallback paths, source review, verification/confidence logic, quality modes, benchmark tooling, and handoff documentation.

One hard constraint is the public Apple Foundation Models context budget. The engine does not claim to remove that limit. It works inside it by retrieving better evidence, preserving page and chunk context, packing aggressively, and using fallback and verification behavior so longer-document workflows do not collapse into a single oversized prompt.

The benchmark tooling became the reality check. I built it because demos are easy to make look better than the system really is. The benchmark path let me see where the engine actually worked and where it broke. It can perform well on some corpora and struggle on others, especially dense technical documents, IFUs, tables, layout-heavy PDFs, procedural text, and strict source-fidelity questions.

That is part of why I think the value here is as a serious head start, not a polished finished answer engine.

PAGE 4. REVENUE

Revenue
Use this:

This project is generating revenue, but the amount is not disclosed.

PAGE 5. METRICS

Average monthly unique visitors
Undisclosed

Average monthly pageviews
Undisclosed

Additional details about traffic
Use this:

This should be evaluated primarily as a codebase and engine sale, not as a traffic or audience-acquisition asset.

Average monthly downloads
Undisclosed

Hours per week spent on this project
Undisclosed

PAGE 6. SALE INFORMATION

What items are included in the sale?
Recommended selections if you want the listing to match the actual handoff scope:

- Domain name: do not select
- Source code: select
- All related data: do not select
- Design, images, logo: do not select
- Twitter account: do not select
- Email account: do not select

Why not select All related data?
Because the current sale does not include private benchmark corpora, sensitive benchmark traces, personal accounts, or every possible project artifact. It is safer to define the real scope in the custom sale text below.

Are there anything else that you want to include as part of this sale?
Plain textarea
Paste this:

Included in the sale or license discussion by default:

- private engine/source-code repo snapshot or agreed repo transfer scope pinned to a commit
- repo-root Swift package surface for OpenIntelligenceEngine
- current public engine facade under OpenIntelligence/SDK/OpenIntelligenceEngine.swift
- engine-relevant Swift source across document processing, chunking, embeddings, storage, vector search, retrieval, verification, and answer orchestration layers
- repo-side source consumer sample app and simulator smoke-test path
- buyer packet zip
- partner packet zip
- packet-local evaluation host app
- benchmark harness code, reporting scripts, and evaluation fixtures already in the repo
- limited handoff documentation
- limited post-transfer clarification if written into scope

Incidental repo context only, not part of the asset story:

- some app-side project files remain in the same repo because the engine currently lives inside that tree

Default handoff path:

1. Scope and exclusions are written down.
2. The buyer packet and partner packet are used for diligence.
3. The transfer is pinned to a named commit SHA.
4. Delivery happens via repo transfer or repo archive plus both packet zips.
5. A short handoff call is held.
6. The buyer confirms receipt of access and artifacts.

Not included by default:

- App Store app transfer
- App Store listing or release pipeline
- consumer app business context
- Apple Developer account access
- signing certificates
- provisioning profiles
- API keys or service credentials
- personal accounts
- private benchmark corpora
- sensitive benchmark traces
- long-term support
- custom feature development
- exclusivity
- production SDK warranty
- regulated-use validation

Separately negotiable:

- App Store app transfer
- exclusive field-of-use license
- broader source-code acquisition
- longer transition support
- custom integration help
- private walkthrough sessions
- deeper SDK cleanup and packaging work

How much are you selling this project for?
If you want to keep the current live listing behavior, use this:

- USD $3500.00
- select: Above is the minimum price. Buyers are welcome to offer better price.

If you intentionally want to change the listing price, update this section deliberately so the text and public listing stay aligned.

Why are you selling this project?
Plain textarea
Paste this:

I proved the core idea through the public app, and built the engine far enough that it feels more valuable as a serious handoff candidate than as something I keep half-feeding on the side.

The next phase is not just app polish. It is SDK separation, retrieval hardening, source-fidelity improvement, difficult-document handling, broader benchmark coverage, and workflow-specific productization. I would rather hand that phase to someone who actually wants to push it all the way than keep pretending I am going to do every part of that myself.

How can the buyer take this project further?
Markdown field
Paste this:

## How I think a buyer should use this

If I were buying this from someone else, I would think about it as a head start, not a finish line.

The most obvious next move is engine separation. The valuable logic already exists, but parts of it are still coupled to app services, runtime paths, storage assumptions, diagnostics, and UI surfaces. A buyer could turn that into a cleaner SDK or internal framework with a narrower API and a more reproducible handoff path.

After that, I think the biggest gains are in retrieval and source fidelity. The engine already has ingestion, OCR-oriented processing, chunking, local full-text search, vector retrieval, context packing, Apple Foundation Models integration, source review, verification-oriented behavior, and benchmark tooling. What still needs work is getting the exact right supporting chunk or page more reliably, preserving important evidence through packing, and getting the system better at refusing when support is weak.

The other big area is hard documents. Manuals, IFUs, service guides, spec-heavy PDFs, tables, and procedural material are exactly why I built this, and they are also the hardest things to get right. That means table extraction, page-level evidence, procedural-step fidelity, cross-reference handling, and exact-value lookup are all good places for a buyer to keep pushing.

I also think the benchmark side matters more than the demo side. The benchmark harness gives a buyer a way to test the engine on their own corpus instead of just watching me run a polished sample. For the right buyer, that is where the real value starts showing up.

The strongest buyer path is probably not trying to make this work for every document on earth. It is to narrow it around one real workflow where grounded answers over private docs are actually worth money.

That could be:

- field-service manuals
- internal technical references
- compliance material
- product support libraries
- training workflows
- private knowledge bases on Apple devices

That is the opportunity as I see it: take the real ingestion, indexing, retrieval, context prep, answer generation, source review, and benchmark work that already exists here, then harden it around one actual buyer problem until it becomes much more than a prototype.
