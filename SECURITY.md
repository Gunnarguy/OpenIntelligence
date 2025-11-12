# RAGMLCore Security Notes

Last updated: November 2025

## Secrets & Key Management

- **Source control**: No API keys or shared secrets live in the repository. `scripts/secret_scan.py` enforces this in CI.
- **Runtime storage**: Third-party credentials (e.g., OpenAI) are saved only in the iOS Keychain (`kSecAttrAccessibleAfterFirstUnlock`), never in `UserDefaults`.
- **Environment separation**: Debug builds may load development keys from `.env` via `direnv`. The release build asserts that no bundled fallback key exists and surfaces an error instead of silently using a dev credential.

## Data Flow Surfaces

| Component | Direction | Data | Notes |
| --- | --- | --- | --- |
| `DocumentProcessor` | Local | Raw files → structured chunks | Runs entirely on-device via PDFKit/Vision |
| `EmbeddingService` (`NLEmbedding`) | Local | Chunk text → 512-dim vectors | No network usage |
| `HybridSearchService` / `RAGEngine` | Local | Embeddings + BM25 metadata | Cached for 5 minutes |
| `AppleFoundationLLMService` | Optional cloud | Query + retrieved context | Honours PCC consent toggle and logs execution location |
| `OpenAILLMService` | Cloud (user opt-in) | Same payload as above | Requires user supplied API key + consent prompt |
| `PersistentVectorDatabase` | Local | Container-scoped vectors | Stored under Application Support |

## Build & Release Guardrails

1. Run `scripts/preflight_check.sh` prior to `xcodebuild` archives.
2. Refuse to compile the Release configuration if `SecretsConfig.bundleKeyCount > 0` (see TODO in `BuildGuards.swift`).
3. Ensure Reviewer Mode remains available in Release to expose pathway transparency and purge actions.

## Reporting a Vulnerability

Email `security@openintelligence.app` with reproduction steps, the affected build number, and a proof of concept. You will receive acknowledgement within two business days.
