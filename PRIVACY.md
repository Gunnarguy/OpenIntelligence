# RAGMLCore Privacy Summary

Last updated: November 2025

## Data Processing Overview

- **Local-first default**: Document ingestion, chunking, embedding, vector search, and answer synthesis all execute on-device by default. No document text or telemetry leaves the device unless the user explicitly selects a cloud pathway.
- **Cloud fallbacks**: When the user opts into Apple Private Cloud Compute or provides an OpenAI API key, only the active query, retrieval metadata, and the selected context snippets are transmitted. We never send raw document archives, file metadata beyond what is necessary for grounding, analytics, or device identifiers.
- **Telemetry**: The app does not ship third-party analytics. TelemetryCenter events stay on-device unless the user enables optional export within Reviewer/Developer mode.

## Model Pathways

| Pathway | Execution Location | What Leaves the Device | User Action Required |
| --- | --- | --- | --- |
| On-Device Analysis | Local Neural Engine / CPU | Nothing | Default state |
| Apple Foundation Models | On-device first, falls back to Private Cloud Compute | Query text + top-N context chunks | Allow Private Cloud Compute toggle |
| OpenAI Direct | HTTPS to OpenAI | Same payload as above via OpenAI API | Reviewer/Test user supplies API key |
| Local Servers (GGUF/Core ML) | Local process or LAN endpoint | Nothing | Import runtime/package |

## Keys & Credentials

- Third-party credentials (e.g., OpenAI API keys) are entered by the user in Settings.
- Keys persist only in `Keychain` using the `kSecAttrAccessibleAfterFirstUnlock` class.
- The app refuses to use embedded development keys in Release builds. Reviewers must provide their own credentials to exercise cloud fallbacks.

## Storage & Retention

- **Documents**: Stored locally in `Application Support/OpenIntelligence`. Users can delete individual knowledge containers or purge all documents from Settings → Knowledge Base.
- **Vectors & Embeddings**: Persisted per container in JSON via `PersistentVectorDatabase`. Deleting a container removes both metadata and embedding files.
- **Cache**: Hybrid retrieval caches (20 most recent queries) are ephemeral and automatically expire after five minutes.

## User Controls

- **Reviewer Mode** (Settings): Surfaces the active pathway, last payload preview, and explicit transmit consent toggles for Apple PCC and OpenAI. Reviewers can force each pathway to verify privacy behavior.
- **Consent Prompts**: Before the first cloud-bound request, users get an inline disclosure describing the payload contents and destination. Choices persist until revoked in Settings.
- **Data Deletion**: Users can clear individual documents, drop entire knowledge containers, remove cached embeddings, and revoke third-party keys from Settings → Privacy & Data.

## Private Cloud Compute & Export Compliance

- Apple PCC sessions are end-to-end encrypted with cryptographic deletion after response completion.
- App declares `ITSAppUsesNonExemptEncryption=true` in Info.plist. No additional export compliance documentation is necessary.

## Contact

For privacy inquiries or data deletion assistance, contact the maintainer at `privacy@openintelligence.app`.
