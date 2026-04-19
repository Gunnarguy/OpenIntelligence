# OpenIntelligence

[![App Store](https://img.shields.io/badge/App%20Store-Download-blue.svg?logo=apple)](https://apps.apple.com/us/app/openintelligence/id6756559175)
[![Platforms](https://img.shields.io/badge/platform-iPhone%20%7C%20iPad-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

OpenIntelligence is an Apple-native document intelligence app for turning private files into a searchable, cited, inspectable knowledge layer.

Import documents, ask natural-language questions, inspect the evidence behind each answer, and see when the app cannot support a claim strongly enough to answer cleanly. The goal is not generic chat. The goal is grounded answers over the material you actually gave it.

This repository is intentionally product-facing. It shows the app, the native client architecture, and the user-visible trust model without publishing the full private SDK packaging, internal evaluation playbook, or commercial transfer materials.

<p align="center">
  <a href="https://apps.apple.com/us/app/openintelligence/id6756559175">
    <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="50">
  </a>
</p>

## Product Snapshot

OpenIntelligence is built for people who need answers from their own material, not another free-form model summary. The app ingests documents locally, organizes them into private libraries, retrieves supporting evidence, and returns answers that are designed to stay tied to source material instead of drifting into confident filler.

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

The current app target is built for:

- iPhone
- iPad

The codebase is also being shaped for broader Apple-native engine packaging, but this public app target is currently an iPhone and iPad product rather than a native macOS app.

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

| Category | Examples |
| --- | --- |
| Documents | PDF, TXT, MD, RTF |
| Office | DOCX, XLSX, PPTX |
| Code and data | Swift, Python, JavaScript, JSON, CSV, XML, YAML, SQL |
| Media | PNG, JPEG, HEIC, TIFF, MP3, WAV, MP4, MOV |

## Public vs Private Scope

This repo intentionally emphasizes:

- app experience
- native SwiftUI implementation
- Apple-platform integration
- product behavior that users can actually inspect

This repo intentionally does not publish:

- internal retrieval thresholds
- answer verification heuristics in full detail
- private SDK packaging work
- pricing and partner materials
- internal evaluation and commercialization docs

## Documentation

- [HOW_IT_WORKS.md](HOW_IT_WORKS.md): high-level workflow
- [ARCHITECTURE.md](ARCHITECTURE.md): public architecture summary
- [ROADMAP.md](ROADMAP.md): product roadmap
- [CHANGELOG.md](CHANGELOG.md): version history
- [WHATS_NEW.md](WHATS_NEW.md): release highlights
- [PRIVACY.md](PRIVACY.md): privacy posture and data handling

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
