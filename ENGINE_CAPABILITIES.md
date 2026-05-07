# Engine Capabilities

This engine ingests internal documents, turns them into an answerable knowledge base, and lets users ask plain-English questions against that material with source-backed responses. It is designed for private, Apple-native deployment, prioritizes grounded answers over fluent guessing, and is built to show when evidence is strong, when support is thin, and when the document set does not contain a defensible answer. For a buyer, that means faster access to product knowledge, support content, and commercial collateral without handing proprietary information to a third-party software vendor.

This document is engine-only.

It does not describe the entire app. The full app also includes the SwiftUI product surface, onboarding, settings, billing, diagnostics, app lifecycle behavior, and other product layers that sit around the engine.

If you need the whole-repo mental model, start with `README.md`. If you need the exact current SDK boundary, use `SDK_BOUNDARY_AUDIT.md` and `EngineSale/ENGINE_INVENTORY.md`.

| Capability                          | Why It Matters To A Buyer                                                                                                                           |
| ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| Private document ingestion          | Lets a company load proprietary manuals, internal references, and customer-facing materials into a controlled environment.                          |
| Source-backed question answering    | Gives users answers tied to the underlying documents instead of unsupported summaries.                                                              |
| Confidence-aware response behavior  | Helps teams distinguish between well-supported answers and answers that should be treated cautiously.                                               |
| Abstention on unsupported questions | Reduces the risk of bluffing when the documents do not contain a reliable answer.                                                                   |
| Multi-document knowledge handling   | Makes it practical to work across long manuals, reference sets, and document libraries instead of one file at a time.                               |
| Offline-first operation             | Supports private use in field, clinical, manufacturing, and travel settings where connectivity is limited or undesirable.                           |
| Apple-native deployment path        | Fits organizations that want modern local AI behavior without standing up their own server stack.                                                   |
| Built-in buyer transfer value       | Shortens the path from acquisition to internal rollout because the system already includes the core engine, ingestion flow, and operator knowledge. |

## What This Engine Does NOT Do

- It does not replace formal regulatory review, quality review, or approved medical affairs workflows.
- It does not verify facts that are missing from the uploaded documents.
- It does not perform broad internet research or act like a general web search product.
- It does not deliver equally strong results across every document style; it is strongest when the source material is clear, structured, and internally consistent.
- It does not remove the need for domain review on high-stakes claims, customer commitments, or clinical statements.

## Highest-Value Use Cases

1. Sales enablement teams answering product and feature questions from approved internal and customer-facing materials.
2. Service, support, and training teams working from manuals, instructions, troubleshooting guides, and operating references.
3. Product, regulatory, and commercial teams creating a shared internal knowledge layer across large document sets.

## What A Buyer Gets

- A working engine for ingesting and answering questions over private document libraries.
- An ingestion pipeline that turns raw files into a usable internal knowledge asset.
- A verification system that is built to prefer supported answers and decline unsupported ones.
- Orchestration logic that handles retrieval, answer assembly, and answer behavior across different query situations.
- The person who built it, which materially lowers transfer risk and accelerates tuning, packaging, and rollout after a deal.
