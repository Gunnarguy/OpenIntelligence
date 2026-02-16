# Private Cloud Compute (PCC) — Security Architecture Reference

> **Source**: [security.apple.com/blog/private-cloud-compute](https://security.apple.com/blog/private-cloud-compute/)
> **Authors**: Apple SEAR, User Privacy, Core OS, ASE, AIML
> **Last Verified**: February 2026

**This document exists so we stop making assumptions about PCC. We do NOT have access to PCC's model directly. Understanding what PCC IS clarifies what WE get.**

---

## What PCC Is

Private Cloud Compute is Apple's cloud AI inference system. When Apple Intelligence features need more compute than the on-device ~3B model can provide, the request is routed to PCC — but **only for Apple's own features**. Third-party apps using the Foundation Models framework run **exclusively on-device**.

---

## Five Core Requirements

| #   | Requirement                      | What It Means                                                                                                                               |
| --- | -------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | **Stateless computation**        | User data is processed and DELETED. No logging, no retention, no debugging traces. Data cannot persist after response is returned.          |
| 2   | **Enforceable guarantees**       | All privacy guarantees are technically enforced, not policy-based. No dependence on external components (load balancers, etc.) for privacy. |
| 3   | **No privileged runtime access** | No remote shells, no interactive debugging, no SSH. Apple SRE staff cannot bypass privacy guarantees even during outages.                   |
| 4   | **Non-targetability**            | An attacker cannot target specific users without compromising the entire PCC system. Even physical hardware attacks are mitigated.          |
| 5   | **Verifiable transparency**      | All production PCC software images are published for independent security research. Append-only cryptographic transparency log.             |

---

## Hardware & Software Stack

### Hardware

- Custom Apple Silicon server hardware
- Same security technologies as iPhone:
  - **Secure Enclave** (cryptographic key management)
  - **Secure Boot** (code authenticity enforcement)
- Tamper switches on physical hardware
- Supply chain imaging at manufacturing
- Data center revalidation before provisioning

### Software

- Hardened subset of iOS/macOS foundations
- **No general-purpose shell** (remote or local)
- **No Developer Mode**
- **No debugging tools**
- Code Signing enforced — only trust-cache signed code runs
- No JIT compilation, no code injection
- Swift on Server for ML stack
- Sandbox isolation for inference processes

### What's Stripped Out

- Remote shells
- System introspection tools
- General-purpose logging
- Debugging mechanisms
- Developer Mode support

---

## Data Flow

```
User Device
    ├── Constructs request (prompt + model params + inference config)
    ├── Validates PCC node certificates against transparency log
    ├── Encrypts request to PUBLIC KEYS of validated PCC nodes
    │   (end-to-end encryption: load balancers CANNOT decrypt)
    └── Sends via OHTTP relay (third-party operated)
            ├── Hides source IP address
            └── Single-use RSA blind signature credential (no user identity)

PCC Node
    ├── Secure Enclave decrypts request
    ├── Processes inference
    ├── Returns response
    ├── DELETES all user data
    └── Randomizes data volume encryption keys on reboot
        (cryptographic erasure on every reboot)
```

### Key Security Properties

| Property                    | How It's Enforced                                                                                                 |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| No data at rest             | Secure Enclave randomizes encryption keys every reboot                                                            |
| No data exfiltration        | Sandboxing + Pointer Authentication Codes                                                                         |
| No targeting specific users | Target diffusion: request metadata has no PII; OHTTP relay hides IP; load balancer returns random PCC node subset |
| No unauthorized code        | Signed System Volume + Code Signing + trust cache                                                                 |
| Auditability                | Load balancer node selection is statistically auditable                                                           |

---

## What This Means for OpenIntelligence

### We Do NOT Use PCC

The Foundation Models framework gives us the **on-device ~3B model**. Period. PCC is used by:

- Siri (complex queries)
- Writing Tools
- Image Playground
- Visual Intelligence
- Other Apple-first-party features

### Implications

1. **All our LLM inference runs at 2-bit quantized ~3B quality** — not at the PT-MoE server quality level
2. **No 65K context** — we get 4096 tokens, not the server model's trained context length
3. **No cloud fallback** — if the on-device model can't handle it, we can't escalate to PCC
4. **Privacy is handled for us** — since we're on-device only, user data never leaves the device (good for our privacy pitch)
5. **Our `LocalOpenAIServerLLMService` is a developer testing fallback** — it routes to a local server for simulator testing since Apple FM is unavailable on simulator

### The One Exception: LoRA Adapters

We CAN train rank-32 LoRA adapters with Apple's Python toolkit and distribute them via Background Assets. These adapt the ~3B model for our specific use case but:

- Must be retrained per base model version
- Each adapter has significant storage cost
- Download managed by Background Assets framework

---

## References

- [Private Cloud Compute Blog Post](https://security.apple.com/blog/private-cloud-compute/)
- [Apple Platform Security Guide — Secure Enclave](https://support.apple.com/guide/security/secure-enclave-sec59b0b31ff/web)
- [Apple Platform Security Guide — Secure Boot](https://support.apple.com/guide/security/boot-process-for-iphone-and-ipad-devices-secb3000f149/web)
- [Apple Security Bounty](https://security.apple.com/bounty/)
