# App Store Metadata Packet

Last updated: 2025-11-12

Copy-paste these values directly into App Store Connect. Update the version numbers and localized strings if needed.

---

## App Information

| Field | Value | Notes |
| --- | --- | --- |
| Name | OpenIntelligence | Matches bundle display name |
| Subtitle | Private document intelligence | ≤30 characters |
| Bundle ID | Gunndamental.OpenIntelligence | Already provisioned |
| Primary Category | Productivity | |
| Secondary Category | Business | Optional but recommended |
| Content Rights | “No” (we do not have rights for third-party content) | |
| Age Rating | 4+ | No sensitive content |
| License Agreement | Standard Apple EULA | |
| Routing App Coverage File | Not applicable | |

---

## Version Information

| Field | Value | Notes |
| --- | --- | --- |
| Version | 1.0.0 | Increment as appropriate |
| Copyright | © 2025 Gunnar Hostetler. All rights reserved. | |
| Primary Language | English (U.S.) | |

### Promotional Text (170 characters max)

> Privacy-first RAG assistant. Import PDFs, ask questions, and keep everything inside Apple’s secure compute boundary.

### Description (Suggested 3000 characters)

```text
OpenIntelligence is the privacy-first research assistant that understands your documents without sending sensitive data to external clouds. Import PDFs, technical notes, or decks and ask natural-language questions to receive cited answers sourced from your own knowledge base.

• Closed-loop retrieval: Hybrid semantic + keyword search runs on device, then Apple Private Cloud Compute handles heavy generation while preserving user privacy.
• Reviewer-only cloud pathways disabled: OpenAI Direct is removed from public builds, guaranteeing compliance with App Store privacy policies.
• Document library: Organize research into containers, monitor ingestion progress, and inspect the chunks feeding each response.
• Live badges: Every reply clearly shows where inference happened (on-device vs. PCC), which tools were invoked, and how long it took.
• Team-ready roadmap: Bring-your-own Core ML or GGUF cartridges, automated rerank refreshes, and structured telemetry coming soon.

Nothing leaves your Apple ecosystem unless you explicitly allow it. Whether you are preparing executive briefings or synthesizing research, OpenIntelligence keeps your content secured while surfacing answers fast.
```

### Keywords

`on-device ai, rag, private cloud compute, document chat, apple intelligence`

### Support URL

<https://openintelligence.app/support>

### Marketing URL

<https://openintelligence.app>

### Privacy Policy URL

<https://openintelligence.app/privacy>

### Contact Email (Optional)

<mailto:support@openintelligence.app>

---

## In-App Purchase Metadata

| Product ID | Reference Name | Type | Price Tier | Cleared for Sale | Notes |
| --- | --- | --- | --- | --- | --- |
| starter_monthly | Starter Monthly | Auto-Renewable Subscription | S3 ($2.99) | Yes | 1-month duration |
| starter_annual | Starter Annual | Auto-Renewable Subscription | S15 ($24.99) | Optional | Enable if annual plan is visible |
| pro_monthly | Pro Monthly | Auto-Renewable Subscription | S9 ($8.99) | Yes | Includes advanced retrieval |
| pro_annual | Pro Annual | Auto-Renewable Subscription | S69 ($89.99) | Yes | 1-year duration, 7-day trial recommended |
| lifetime_cohort | Lifetime Access | Non-Consumable | Tier 60 or 80 | Limited | Choose based on promo |
| doc_pack_addon | Document Pack | Consumable | Tier 5 ($4.99) | Yes | Adds 25 documents |

---

## Release Notes (What’s New)

```text
• Launch version delivering closed-loop retrieval augmented generation on iPhone and iPad.
• Import PDFs and Markdown, then ask natural-language questions with cited answers.
• Apple Private Cloud Compute assists heavy workloads; OpenAI Direct is reviewer-only and disabled in production builds.
• Telemetry badges show exactly where inference ran (device vs. PCC) and which tools were invoked.
• Built-in sample documents let you evaluate the experience without creating an account.
```

---

## App Review Notes

See `Docs/reference/APP_REVIEW_NOTES_TEMPLATE.md` for the copy block to paste into the Review Notes field.

---

## Localization Checklist

| Locale | Description | Keywords | Screenshots | Status |
| --- | --- | --- | --- | --- |
| en-US | ✅ Provided above | ✅ Provided above | Pending final capture | ⬜ |
| Add other locales here | | | | |

---

Update this file whenever metadata changes so App Store Connect stays aligned with the product.
