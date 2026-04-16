# OpenIntelligence

[![App Store](https://img.shields.io/badge/App%20Store-Download-blue.svg?logo=apple)](https://apps.apple.com/us/app/openintelligence/id6756559175)
[![Platform](https://img.shields.io/badge/platform-iOS%2026.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

Ask your documents anything. Get cited answers on iPhone.

OpenIntelligence is a privacy-first iPhone app for asking questions about your own documents. Import files, search them conversationally, and review grounded answers with citations while staying centered on Apple platforms and local execution.

This public repository is meant to show product direction, app quality, and native iOS craftsmanship without publishing the full retrieval engine playbook. Detailed engine tuning, evaluation thresholds, orchestration logic, and business strategy are intentionally kept out of the public docs.

<p align="center">
  <a href="https://apps.apple.com/us/app/openintelligence/id6756559175">
    <img src="https://developer.apple.com/assets/elements/badges/download-on-the-app-store.svg" alt="Download on the App Store" height="50">
  </a>
</p>

## What It Does

1. Import PDFs, office files, images, audio, and text from the device.
2. Organize documents into private libraries on iPhone.
3. Ask natural-language questions and get grounded answers with citations.
4. Review answers, sources, and app diagnostics in a native SwiftUI experience.

## Privacy

- On-device by default for parsing, storage, search, and answer generation when Apple platform capabilities allow it.
- Apple-managed cloud processing may be used only through Apple system features and user-controlled settings.
- No third-party hosted AI service is part of the core public product flow.

## Supported Content

| Category      | Examples                                             |
| ------------- | ---------------------------------------------------- |
| Documents     | PDF, TXT, MD, RTF                                    |
| Office        | DOCX, XLSX, PPTX                                     |
| Code and data | Swift, Python, JavaScript, JSON, CSV, XML, YAML, SQL |
| Media         | PNG, JPEG, HEIC, TIFF, MP3, WAV, MP4, MOV            |

## Public Scope

The public repo focuses on:

- Product experience and native iOS implementation quality
- SwiftUI screens, app shell, and user-facing workflows
- Apple platform integrations and privacy posture
- Buildable demo and portfolio value for the app itself

The public docs intentionally do not publish:

- Retrieval formulas, tuning values, and evaluation thresholds
- Multi-pass orchestration rules and verification heuristics
- Internal commercialization plans or pricing strategy work
- Detailed internal operating instructions for the engine team

## Documentation

- [HOW_IT_WORKS.md](HOW_IT_WORKS.md) - high-level product workflow
- [ARCHITECTURE.md](ARCHITECTURE.md) - public architecture summary
- [ROADMAP.md](ROADMAP.md) - public-facing product roadmap
- [CHANGELOG.md](CHANGELOG.md) - public version history
- [WHATS_NEW.md](WHATS_NEW.md) - public release highlights
- [PRIVACY.md](PRIVACY.md) - privacy posture and data handling

## Getting Started

### Requirements

- macOS with Xcode installed
- iOS 26.0+ deployment target

### Build

```bash
xcodebuild -scheme OpenIntelligence -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

### Project Layout

- `OpenIntelligence/App/` - app entry points and composition
- `OpenIntelligence/Features/` - user-facing feature areas
- `OpenIntelligence/UI/` - shared UI components and design system
- `OpenIntelligence/Resources/` - assets, privacy metadata, bundled resources
- `OpenIntelligence/Services/` - application services and platform integrations

Some engine details are deliberately undocumented in the public repo. Collaboration on deeper internals happens privately.

## Contributing

Issues and product feedback are welcome. Public contributions should stay focused on product experience, app behavior, platform fit, and documentation. Deeper engine collaboration is handled separately.

## License

MIT License - see [LICENSE](LICENSE) for details.
