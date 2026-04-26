# Engine Pitch

## One-Sentence Pitch

OpenIntelligence Engine is a local-first Apple-native document-intelligence prototype that ingests private documents, builds local full-text and vector indexes, retrieves source evidence, and generates source-reviewed answers on Apple devices.

## One-Paragraph Pitch

OpenIntelligence Engine is not a generic chatbot product. It is a substantial Swift/iOS engine prototype for teams exploring private document QA on Apple hardware. The codebase ingests documents locally, extracts and indexes text, combines full-text and vector retrieval, packs evidence into the public Apple model budget, generates answers through Apple-native model paths where available, and includes source review, verification logic, and benchmark tooling.

## Longer Technical-Buyer Pitch

What a buyer gets here is a meaningful technical head start, not a finished enterprise platform. The repo already contains a working ingestion pipeline, OCR fallback, structure-aware chunking, local SQLite full-text indexing, per-container vector storage, hybrid retrieval, graph-style context expansion, answer generation adapters, post-generation verification, and a debug benchmark harness with dashboards and traces. That is a lot of the hard engineering work for a local-first document QA product on Apple devices. What is still missing is the final cleanup needed to make the engine feel like a fully decoupled, polished SDK.

## What A Buyer Actually Gets

- a working Apple-platform app that proves the engine behavior
- the engine source code inside the repo
- a narrow SDK facade already defined in Swift
- benchmark harness, scripts, dashboards, and stored run artifacts
- staged evaluation packet and sample host materials
- documentation, current limitations, and claim guardrails

## Who This Is For

- teams exploring private document QA on Apple devices
- buyers who want a codebase head start instead of building retrieval from scratch
- teams that value local-first indexing and source review
- design partners, licensees, or acquirers comfortable with prototype-stage engineering work

## Who This Is Not For

- teams that need a finished enterprise SDK today
- teams that need audited production accuracy
- teams that need a cloud API rather than embedded Apple-native logic
- teams that need medical, legal, safety, IFU, or compliance-ready answer behavior as-is

## Why It May Save Engineering Time

- ingestion and OCR are already built
- local storage and retrieval layers already exist
- the public Apple model budget constraints are already handled in code
- source review and verification logic already exist
- benchmark tooling already exists for regression and buyer evaluation

## Why It Still Needs Refinement

- app and engine are still coupled in important places
- packaging is still evaluation-stage, not finished SDK productization
- answer quality can still break on difficult technical, tabular, or procedural documents
- citations and verification improve behavior, but do not prove correctness
- there is no formal third-party accuracy, compliance, or security review
