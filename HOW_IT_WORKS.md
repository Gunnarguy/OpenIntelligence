# How This Public Demo Repo Works

Public snapshot: May 2026

This repo shows the public demo surface for OpenIntelligence.

## Demo Workflow

```text
Understand the product -> inspect the public docs -> review the demo app shell -> keep the private engine private
```

## What You Can Learn Here

1. What the product is trying to do.
2. How the public trust model is framed.
3. What the user-facing experience looks like.
4. How the public docs and release notes are organized.

## What Is Intentionally Not Shipped Here

This repo does not expose the private engine implementation.

That includes:

- ingestion internals
- retrieval internals
- verification heuristics
- embedding and vector search code
- SDK packaging and commercialization materials
- App Store submission and release-ops tooling

Those stay in `OpenIntelligence-Engine`.

## Public Repo Role

This repository is a product-facing demo and documentation surface.

It is not the full private working tree.
It is also not the repo used for App Store submission.
