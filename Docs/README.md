# OpenIntelligence Documentation

Quick reference documentation for the OpenIntelligence project.

---

## Reference Documents

| Document | Description | Last Updated |
|----------|-------------|--------------|
| [ARCHITECTURE.md](reference/ARCHITECTURE.md) | Full technical architecture, 51 services, 23-step pipeline | Jan 29, 2026 |
| [ADVANCED_RAG.md](reference/ADVANCED_RAG.md) | Advanced RAG techniques (HyDE, compression, agentic) | Jan 2026 |
| [APPLE_API.md](reference/APPLE_API.md) | Apple framework API reference (FoundationModels, NL) | Jan 2026 |
| [RELEASE.md](reference/RELEASE.md) | Release checklist, smoke tests, StoreKit testing | Jan 2026 |
| [PRICING_STRATEGY.md](reference/PRICING_STRATEGY.md) | Business/pricing documentation (private) | — |
| [AFW.md](reference/AFW.md) | App Firewall configuration notes | — |

---

## Quick Start

### For New Contributors
1. Read [ARCHITECTURE.md](reference/ARCHITECTURE.md) first
2. Review [ADVANCED_RAG.md](reference/ADVANCED_RAG.md) for retrieval techniques
3. Check [APPLE_API.md](reference/APPLE_API.md) for framework specifics

### For Debugging RAG Issues
1. See [ADVANCED_RAG.md](reference/ADVANCED_RAG.md) § Troubleshooting
2. Check relevant service file (HyDEService, ContextualCompressionService, etc.)
3. Enable debug logging via `LoggingConfiguration.swift`

### For Release Preparation
1. Follow [RELEASE.md](reference/RELEASE.md) checklist
2. Run smoke tests on physical device
3. Verify StoreKit products

---

## Test Documents

The [TestDocuments/](TestDocuments/) folder contains test fixtures for `DocumentProcessor` unit tests:

| File | Purpose |
|------|---------|
| `sample_1page.txt` | Basic single-page document |
| `sample_empty.txt` | Empty file handling |
| `sample_special_chars.txt` | Special character encoding |
| `sample_technical.md` | Markdown with code blocks |
| `sample_unicode.txt` | Unicode/emoji handling |
| `sample_whitespace.txt` | Whitespace normalization |

---

## Related Files

| File | Location | Purpose |
|------|----------|---------|
| [ROADMAP.md](../ROADMAP.md) | Root | Task tracking, version history |
| [README.md](../README.md) | Root | Project overview |
| [CHANGELOG.md](../CHANGELOG.md) | Root | Version changelog |
| [PRIVACY.md](../PRIVACY.md) | Root | Privacy policy |
