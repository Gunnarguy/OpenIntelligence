# Private Cloud Compute (PCC) Security Architecture Reference

> **Primary source**: [Apple Security: Private Cloud Compute](https://security.apple.com/blog/private-cloud-compute/)
> **Research source**: [Apple Security: PCC security research](https://security.apple.com/blog/pcc-security-research/)
> **Last Verified**: April 24, 2026

This document exists so OpenIntelligence does not overclaim PCC. PCC is Apple's cloud AI privacy architecture. OpenIntelligence does not own a PCC endpoint, does not directly select Apple's server model, and should not claim a larger FoundationModels context window through PCC.

## What PCC Is

Private Cloud Compute is Apple's cloud inference system for Apple Intelligence features that need more compute than the local device can provide. Apple designed PCC to extend device-style privacy guarantees into cloud inference through Apple Silicon servers, a hardened OS, end-to-end encryption to validated PCC nodes, target diffusion, stateless processing, and public transparency logs.

PCC matters to OpenIntelligence as platform context, but the product should be documented as local-first and Apple-native, not as an app with direct access to Apple's server model.

## Five Core Requirements

| # | Requirement | What It Means |
| --- | --- | --- |
| 1 | Stateless computation | User data is processed for the request and then deleted. |
| 2 | Enforceable guarantees | Privacy properties are technically enforced rather than just policy promises. |
| 3 | No privileged runtime access | Apple SRE staff cannot use shells or debuggers to bypass privacy guarantees. |
| 4 | Non-targetability | Requests cannot be routed to a specific node for a targeted user attack without broader system compromise. |
| 5 | Verifiable transparency | Production PCC software images and measurements are made available for independent inspection. |

## Hardware and Software Stack

- Custom Apple Silicon server hardware.
- Secure Enclave and Secure Boot lineage.
- Hardened subset of iOS/macOS foundations for inference.
- No general-purpose remote shell or debugging path.
- Code signing and trust-cache enforcement.
- Sandbox isolation for inference processes.
- Public research tooling and transparency logs for PCC software releases.

## Data Flow

```text
User device
  -> validates PCC node software/certificates
  -> encrypts request to validated node public keys
  -> sends through relay/load-balancing infrastructure

PCC node
  -> decrypts inside trusted node boundary
  -> runs inference
  -> returns response
  -> deletes user data
```

## What This Means for OpenIntelligence

OpenIntelligence leverages Apple's public Foundation Models framework. The app supports dynamic route selection policies, routing standard/offline queries to `SystemLanguageModel.default` and reasoning-heavy or context-overflow queries to `PrivateCloudComputeLanguageModel`.

The safe implementation assumptions are:

1. Local On-Device sessions are budgeted at 4,096 tokens.
2. Private Cloud Compute (PCC) sessions are budgeted at 32,768 tokens, dynamically used in Deep Think and Maximum quality modes or when local context boundaries are exceeded.
3. The app does not own the PCC servers, but leverages Apple's OS-level PCC execution API.
4. Simulator behavior is not production behavior; Apple Intelligence availability needs physical-device validation.
5. Core privacy copy should focus on local document parsing, local indexes, and Apple-native generation where supported.

## What Not To Say

- "OpenIntelligence operates its own Private Cloud Compute servers."
- "OpenIntelligence gets a 65K local context window."
- "PCC makes the app compliant with regulated workflow requirements."
- "The app can override Apple's cloud routing safety rules."

## What To Say

- "OpenIntelligence dynamically routes queries between on-device models (4K token context) and Apple's secure Private Cloud Compute (32K token context) depending on the selected quality mode and context size."
- "The app keeps core document ingestion, indexing, retrieval, and storage local."
- "PCC is Apple's native privacy-safe cloud architecture, accessed via official OS APIs."

## Adapter Note

Apple documents adapter support for Foundation Models, but OpenIntelligence should only market adapters after the app has a built, signed, distributed, and evaluated adapter flow.

Potential requirements:

- Adapter entitlement and distribution path.
- Per-model-version retraining plan.
- Background Assets or equivalent delivery.
- Evaluation proving domain improvement without hurting citation faithfulness.

## References

- [Private Cloud Compute Blog Post](https://security.apple.com/blog/private-cloud-compute/)
- [Security research on Private Cloud Compute](https://security.apple.com/blog/pcc-security-research/)
- [Foundation Models Framework](https://developer.apple.com/documentation/FoundationModels)
- [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Apple Security Bounty](https://security.apple.com/bounty/)
