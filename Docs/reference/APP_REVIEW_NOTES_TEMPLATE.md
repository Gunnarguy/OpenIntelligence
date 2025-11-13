# App Review Notes Template

Last updated: 2025-11-12

Use this template when pasting notes into App Store Connect. Update the placeholders before submission and keep language concise. The goal is to make the reviewers path obvious and emphasize the closed-loop privacy model.

---

## Quick Copy Block

```text
Hello App Review,

• All inference runs on-device or through Apple Private Cloud Compute; OpenAI Direct is entirely disabled in production builds.
• No sign-in is required. The app ships with sample documents (“Sample Pricing Brief”, “Sample Technical Overview”) so you can import, retrieve, and chat without additional setup.
• Navigate to Settings ▸ Execution & Privacy to confirm “Reviewer Mode” is locked off in release builds; OpenAI settings are hidden and cannot be enabled.
• When a cloud call is needed (Apple PCC only), a consent sheet will appear describing the transfer. Decline to keep everything on-device.
• To evaluate retrieval: Documents tab ▸ “+” ▸ pick any bundled sample, then Chat tab ▸ ask “Summarize the newest document.” The response includes citations that reference the imported file.
• In-app purchases use StoreKit only; pricing tiers follow Apple’s matrix and no external payment links exist.

Thank you!
```

---

## Reviewer Walkthrough (Detailed)

1. **Launch & Documents**
   - App opens directly to the Chat screen.
   - Switch to **Documents** ▸ tap **Import Sample** ▸ choose any file (no account required).
2. **Retrieval Demo**
   - Return to **Chat**.
   - Send: `"What does the imported sample cover?"`
   - Response streams with citations; the retrieval tray lists matching chunks.
3. **Privacy & Consent**
   - Any call that leaves the device is handled by Apple PCC.
   - If you trigger such a call, you will see a consent sheet explaining the transfer; denying the sheet keeps the interaction on-device.
4. **Settings Verification**
   - Open **Settings**.
   - Confirm the OpenAI category is absent and `Reviewer Mode` cannot be enabled.
   - Primary/Fallback model pickers show Apple Intelligence, On-Device Analysis, and other local options only.
5. **Purchases**
   - Optional: Open **Settings ▸ About** to see the plan comparison table.
   - All upsell buttons route to native StoreKit sheets; there are no web views or external price mentions.

---

## Submission Checklist

- [ ] Update sample document names in the copy block if they change.
- [ ] Double-check that the build you submit is signed for production and `reviewerModeEnabled` is hard-disabled.
- [ ] Attach the latest privacy policy URL and the pricing summary from `Docs/reference/PRICING_STRATEGY.md` in App Store Connect metadata.
- [ ] If additional demo data is required (e.g., enterprise container), list credentials here and flag them clearly.

---

## Change Log

| Date       | Author | Notes |
|------------|--------|-------|
| 2025-11-12 | Copilot | Initial template aligned with closed-loop submission requirements |
