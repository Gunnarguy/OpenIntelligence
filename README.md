# OpenIntelligence

[![App Store](https://img.shields.io/badge/App%20Store-Download-blue.svg?logo=apple)](https://apps.apple.com/us/app/openintelligence/id6756559175)
[![Platforms](https://img.shields.io/badge/platform-iPhone%20%7C%20iPad-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

OpenIntelligence is private document Q&A for Apple Intelligence-capable iPhone and iPad today, with Mac evaluation paths in this repo through Mac Catalyst benchmarking and internal validation.

Today, the public App Store target in this repository ships on iPhone and iPad. The broader Apple-native engine and product direction include Mac, but the current repo path there is Mac Catalyst evaluation and benchmarking rather than a separately shipped native macOS product.

Import documents, ask natural-language questions, inspect the evidence behind each answer, and see when the app cannot support a claim strongly enough to answer cleanly. The goal is not generic chat. The goal is grounded answers over the material you actually gave it, with local-first handling for the parts that matter most.

This repository is intentionally product-facing. It shows the app, the native client architecture, and the user-visible trust model without publishing the full private SDK packaging, internal evaluation playbook, or commercial transfer materials.

<p align="center">
  <a href="https://apps.apple.com/us/app/openintelligence/id6756559175">
    <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="50">
  </a>
</p>

## Product Snapshot

OpenIntelligence is built for people who need answers from their own material, not another free-form model summary. The app ingests documents locally, organizes them into private libraries, retrieves supporting evidence, and returns answers that are designed to stay tied to source material instead of drifting into confident filler.

The market shift is away from AI novelty and toward trustworthy answers over private material. That is why the product centers local-first handling, source review, and visible uncertainty instead of generic chatbot performance.

## Simplest Mental Model

If you only want one answer about what this repo is, use this:

- `OpenIntelligence` is the full shipping Apple app and product codebase.
- `OpenIntelligenceEngine` is the narrower reusable engine boundary living inside that same codebase.
- The engine is real, but it does not include the entire app shell.
- The repo also carries evaluation and buyer materials around that engine.

In practical terms, the app includes the full product surface: SwiftUI screens, onboarding, settings, billing, diagnostics, app lifecycle behavior, and the engine integrated into a user-facing product.

The engine lane is the reusable document-intelligence core: ingestion, OCR and parsing, chunking, indexing, storage, retrieval, reranking, grounded answer generation, citations, verification, and availability checks for Apple Intelligence paths.

That means this repository is not "just the app" and it is not "just an SDK" either. It is the app, plus the internal engine boundary, plus the material needed to evaluate and explain that boundary.

## Repo Lanes

This repository currently carries three distinct lanes:

- public app and product surface
- engine and SDK evaluation materials
- buyer and partner operating materials

| Lane                   | Start here                                                                                                                                                          | Why                                                                              |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------- |
| App and product lane   | `HOW_IT_WORKS.md`, `ARCHITECTURE.md`, `CHANGELOG.md`, `WHATS_NEW.md`                                                                                                | Understand the shipping product story and public app surface.                    |
| Engine and SDK lane    | `output/OpenIntelligence-SDK-Package/START_HERE.md`, `SDK_BOUNDARY_AUDIT.md`, `EngineSale/ENGINE_INVENTORY.md`, `OpenIntelligence/SDK/OpenIntelligenceEngine.swift` | Understand the sellable engine boundary and current technical evaluation packet. |
| Buyer and partner lane | `EngineSale/README.md`, `output/OpenIntelligence-Partner-Packet/README.md`                                                                                          | Understand what lives where, what is pushable, and what a buyer actually sees.   |

## App vs Engine

| Scope                       | What it includes                                                                                                                                       | What it explicitly does not mean                                                               | Current status                                                |
| --------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------- | ------------------------------------------------------------- |
| Full app                    | user experience, SwiftUI screens, onboarding, settings, billing, diagnostics, app lifecycle behavior, document libraries, and the engine in product    | not a standalone SDK boundary                                                                  | shipping public product on iPhone and iPad                    |
| Engine boundary             | ingestion, parsing, OCR, chunking, embeddings, local storage, FTS/vector retrieval, reranking, grounded answer generation, citations, and verification | not the whole app repackaged; excludes the full product shell and other app-only surfaces      | real evaluation-stage engine boundary inside the app codebase |
| Evaluation and buyer packet | staged XCFramework, sample host app, install docs, packet docs, and commercialization support material                                                 | not a full source-code transfer and not a finished self-serve universal commercial SDK handoff | usable for evaluation and partner conversations today         |

If you need the precise version of that split, read `ARCHITECTURE.md` for the app lane, `ENGINE_CAPABILITIES.md` and `EngineSale/ENGINE_INVENTORY.md` for the engine lane, and `SDK_BOUNDARY_AUDIT.md` for the exact current SDK boundary.

It is especially useful when the cost of a wrong answer is not abstract:

- product and technical documentation
- operating manuals and service guides
- internal references and approved collateral
- dense mixed-format files that are awkward to search manually

## Core Experience

1. Import PDFs, Office files, text, code, images, audio, and video from Apple file surfaces.
2. Organize documents into private libraries that keep work scoped and navigable.
3. Ask questions in plain English instead of manually opening and skimming files.
4. Review cited answers with support details, dropped claims, and evidence visibility.
5. See abstention when the document set does not actually support a reliable answer.

## Why It Feels Different

- It is built around source-backed answering, not generic assistant-style confidence.
- It exposes answer quality instead of hiding uncertainty behind polished prose.
- It is local-first, Apple-native, and designed around privacy-sensitive document use.
- It treats answer refusal as a feature when evidence is weak.

## Platform Scope

Broader product direction in this repository:

- Apple Intelligence-capable iPhone
- Apple Intelligence-capable iPad
- Apple silicon Mac through Mac Catalyst evaluation and benchmarking

Current public shipping target in this repository:

- iPhone
- iPad

This matters for messaging. The current App Store binary and primary public target configuration in this repository are still iPhone and iPad. Mac support here is an evaluation and benchmarking path through Mac Catalyst, not a separate shipped native macOS app.

## Privacy Posture

- Document import, storage, retrieval, and most answer work are local-first.
- Apple-managed cloud processing can be used only through Apple platform capabilities and user-controlled settings.
- No third-party hosted AI service is part of the core public product path.
- The product is designed to keep proprietary material inside Apple-controlled execution paths rather than pushing it into generic external AI infrastructure.

For the fuller privacy summary, see [PRIVACY.md](PRIVACY.md).

## Reliability Posture

- Answers are meant to come from the provided material, not from broad background guessing.
- Unsupported claims can be removed before final answer rendering.
- Response review surfaces make it possible to inspect what was supported, what was dropped, and where the evidence came from.
- Audit tooling exists to catch regressions in abstention, citation mapping, and source-faithful behavior.

This does not make the product magic or infallible. It means the app is intentionally biased toward groundedness over performance theater.

## Supported Content

| Category      | Examples                                             |
| ------------- | ---------------------------------------------------- |
| Documents     | PDF, TXT, MD, RTF                                    |
| Office        | DOCX, XLSX, PPTX                                     |
| Code and data | Swift, Python, JavaScript, JSON, CSV, XML, YAML, SQL |
| Media         | PNG, JPEG, HEIC, TIFF, MP3, WAV, MP4, MOV            |

## Public vs Private Scope

This repo intentionally emphasizes:

- app experience
- native SwiftUI implementation
- Apple-platform integration
- product behavior that users can actually inspect

The public-facing story intentionally does not lead with:

- internal retrieval thresholds
- answer verification heuristics in full detail
- private SDK packaging work
- pricing and partner materials
- internal evaluation and commercialization docs

In this private working repository, the current founder/design-partner packet and commercialization materials live under:

- `output/OpenIntelligence-SDK-Package/`
- `output/OpenIntelligence-Partner-Packet/`

Those materials should track the current public release line. The app and engine targets are currently on 3.5, so rebuild the buyer packet from current source before sending it after any future release.

## Documentation

- [HOW_IT_WORKS.md](HOW_IT_WORKS.md): high-level workflow
- [ARCHITECTURE.md](ARCHITECTURE.md): public app and product architecture summary
- [ROADMAP.md](ROADMAP.md): product roadmap
- [CHANGELOG.md](CHANGELOG.md): version history
- [WHATS_NEW.md](WHATS_NEW.md): release highlights
- [PRIVACY.md](PRIVACY.md): privacy posture and data handling
- `ENGINE_CAPABILITIES.md`: buyer-level summary of what the engine itself does and does not include
- `SDK_BOUNDARY_AUDIT.md`: internal map of the smallest credible SDK boundary and what stays out of it
- `EngineSale/README.md`: control tower for the sale lane, push policy, and packet map
- `EngineSale/ENGINE_INVENTORY.md`: current reusable engine inventory and SDK-boundary hotspot list
- `output/OpenIntelligence-SDK-Package/START_HERE.md`: private evaluation SDK packet entrypoint
- `output/OpenIntelligence-Partner-Packet/README.md`: private design-partner and outreach packet

## Build

### Requirements

- macOS with Xcode installed
- iOS 26.0+ SDK/toolchain support

### App Build

```bash
xcodebuild -scheme OpenIntelligence -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Simulator Smoke Build

```bash
./scripts/build_simulator_smoke.sh
```

Use this for a fast compile-and-link validation pass in Simulator.

### Device Reliability Audit

```bash
./scripts/run_generation_audit.sh
```

This audit is meant for a connected physical device. Apple Foundation Models behavior is not meaningfully validated in Simulator, so Simulator is useful for build health while real answer-behavior checks belong on supported hardware.

## Project Layout

- `OpenIntelligence/App/`: app entry points and composition
- `OpenIntelligence/Features/`: user-facing feature areas
- `OpenIntelligence/UI/`: shared UI and presentation building blocks
- `OpenIntelligence/Resources/`: assets, privacy metadata, bundled resources
- `OpenIntelligence/Services/`: ingestion, retrieval, generation, storage, and platform integrations

## Contributing

Issues and product feedback are welcome. Public contributions should stay focused on app behavior, platform fit, UI quality, and documentation. Deeper engine and commercial packaging work is handled privately.

## License

MIT License. See [LICENSE](LICENSE) for details.
