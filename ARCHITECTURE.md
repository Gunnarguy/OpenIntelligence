# OpenIntelligence Public Demo Architecture

Public snapshot: May 2026

This repository is structured as a public demo surface, not as the private engine source tree.

## High-Level Layout

```text
Public demo app shell
    -> Product-facing demo screens
        -> Public docs and release materials
            -> Private engine stays outside this repo
```

## What Lives Here

| Layer            | Purpose                                                         |
| ---------------- | --------------------------------------------------------------- |
| Demo app shell   | A lightweight SwiftUI app that communicates the product story   |
| Public docs      | README, architecture, workflow, privacy, and release materials  |
| Build support    | Public-safe build workflows and helper scripts                  |

## What Does Not Live Here

The following remain private in `OpenIntelligence-Engine`:

- ingestion internals
- chunking and extraction strategy
- retrieval and reranking logic
- verification and trust heuristics
- embedding and vector search implementation
- SDK packaging and buyer packet material
- App Store submission and release-ops tooling

## Repository Boundary

This repo is intentionally generated from a private source-of-truth workflow.

The private repo is authoritative.
The public repo is a curated export target.
