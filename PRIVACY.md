# OpenIntelligence Privacy Summary

Last updated: February 2026

## Data Processing Overview

- **Local-first by design**: Document ingestion, chunking, embedding, vector search, and answer synthesis all execute on-device using Apple's Neural Engine. No document text or telemetry leaves your device unless you explicitly enable Private Cloud Compute.
- **Cloud fallback**: For complex queries, the routing policy escalates to Apple Private Cloud Compute (PCC) secure server enclaves. Execution is run natively on Apple enclaves via `FoundationModels.PrivateCloudComputeLanguageModel` when running on iOS 27 / macOS 27+, falling back cleanly to local simulation on older OS versions. In a production PCC environment, only the active query and selected context snippets are transmitted via Apple's encrypted PCC protocol, and Apple guarantees cryptographic deletion after response completion.
- **Telemetry**: The app does not ship third-party analytics. TelemetryCenter events stay on-device unless the user enables optional export within Reviewer/Developer mode.
- **Motherboard HUD**: The hardware telemetry overlay (CPU, GPU, memory, thermal, battery data) reads system metrics locally via Darwin/sysctl APIs. No telemetry data is transmitted, stored persistently, or shared. The HUD is purely visual and ephemeral.

## Model Pathways

| Pathway                 | Execution Location        | What Leaves the Device                      | User Action Required         |
| ----------------------- | ------------------------- | ------------------------------------------- | ---------------------------- |
| On-Device Analysis      | Local Neural Engine / CPU | Nothing                                     | Default state                |
| Apple Foundation Models | On-device Neural Engine   | Nothing                                     | None (automatic)             |
| Private Cloud Compute   | Native enclaves on iOS/macOS 27+ only; older OS versions never use PCC and stay fully on-device | Minimized evidence payload, shown before sending (encrypted, zero-retention) | Post-retrieval consent prompt; remembered choice in Settings |

## Keys & Credentials

- **No third-party API keys required.** OpenIntelligence uses only Apple Intelligence (on-device + Private Cloud Compute).
- App Store credentials for StoreKit subscriptions are managed by Apple's secure infrastructure.
- No external cloud services, no API keys to manage, no data leaving Apple's ecosystem.

## Storage & Retention

- **Documents**: Stored locally in `Application Support/OpenIntelligence`. Users can delete individual knowledge containers or purge all documents from Settings → Knowledge Base.
- **Vectors & Embeddings**: Persisted per container in binary memory-mapped vector database files managed by `BNNSVectorDatabase`. Deleting a container removes both metadata and embedding files.
- **Evidence Threads**: Chat thread history is stored locally in isolated JSON files under `LocalCache/EvidenceThreads/<containerId>/` to prevent unintended synchronization via iCloud Drive.
- **Cache**: Hybrid retrieval caches (20 most recent queries) are ephemeral and automatically expire after five minutes.


## User Controls

- **Reviewer Mode** (Settings): Surfaces the active pathway, last payload preview, and Private Cloud Compute consent toggle. Reviewers can verify privacy behavior by inspecting execution location.
- **Consent Prompts**: Before the first cloud-bound request, users get an inline disclosure describing the payload contents and destination. Choices persist until revoked in Settings.
- **Data Deletion**: Users can clear individual documents, drop entire knowledge containers, remove cached embeddings, and revoke third-party keys from Settings → Privacy & Data.

## Private Cloud Compute & Export Compliance

- In production, Apple PCC sessions are end-to-end encrypted with cryptographic deletion after response completion. Currently, PCC routing runs natively on iOS/macOS 27+ and falls back to local simulation on older OS versions.
- App declares `ITSAppUsesNonExemptEncryption=false` in Info.plist. The app uses only standard encryption (HTTPS/TLS) provided by the operating system, which is exempt from export compliance documentation.

## Contact

For privacy inquiries or data deletion assistance, contact the maintainer at `Gunnarguy@me.com`.
