# App Store Submission Package

Last updated: 2025-11-12

This reference bundles everything needed to push **OpenIntelligence** to App Store Review quickly. Work through each section in order; link back to the detailed docs when deeper context is required.

---

## 1. Build & Archive Commands

Run the following from the repo root to produce a release archive signed with distribution credentials.

```bash
# 1. Clean prior derived data if needed
./clean_and_rebuild.sh --release

# 2. Generate an App Store archive (update TEAM_ID and provisioning profile as required)
xcodebuild \
  -scheme OpenIntelligence \
  -project OpenIntelligence.xcodeproj \
  -configuration Release \
  -sdk iphoneos \
  -archivePath "build/OpenIntelligence.xcarchive" \
  archive

# 3. Export the IPA
xcodebuild \
  -exportArchive \
  -archivePath "build/OpenIntelligence.xcarchive" \
  -exportPath "build/export" \
  -exportOptionsPlist "Docs/reference/exportOptions.plist"
```

> Keep a copy of the generated `.xcarchive` until the binary is approved.

---

## 2. Required Artifacts Checklist

- ✅ Release `.ipa` and `.xcarchive`
- ✅ App Store screenshots (5.5", 6.5", iPad, macOS if applicable)
- ✅ App privacy questionnaire responses
- ✅ Updated privacy policy URL
- ✅ Latest pricing matrix (`Docs/reference/PRICING_STRATEGY.md`)
- ✅ Finalized metadata copy (`Docs/reference/APP_STORE_METADATA.md`)
- ✅ StoreKit product list export
- ✅ Reviewer notes (`Docs/reference/APP_REVIEW_NOTES_TEMPLATE.md`)
- ✅ App Review checklist (`Docs/reference/APP_REVIEW_CHECKLIST.md`)
- ✅ Smoke test results (`smoke_test.md` annotated with pass/fail)

Archive all assets in a dated folder (for example `releases/2025-11-12-appstore/`).

> Shortcut: run `bash scripts/package_submission.sh releases` to generate a timestamped folder with all reference docs and sample reviewer files. Update the copied `SMOKE_TEST.md` with your pass/fail notes before submission.

---

## 3. Metadata & Narrative

### App Description (short form)

Use this 500-character summary as the baseline and adapt for the full description:

> OpenIntelligence keeps PDF and note comprehension on your device. Import docs, ask natural-language questions, and get cited answers without sending data to third-party clouds. Apple Private Cloud Compute assists for heavy workloads; OpenAI Direct is disabled in production.

### Keywords

`on-device ai, rag, private cloud compute, document chat, apple intelligence`

### Promotional Text

> Privacy-first RAG assistant. Import PDFs, ask questions, and stay in Apples secure compute boundary.

### Support & Marketing URLs

| Purpose | URL | Notes |
| --- | --- | --- |
| Support | [https://openintelligence.app/support](https://openintelligence.app/support) | Include troubleshooting steps and contact form |
| Marketing | [https://openintelligence.app](https://openintelligence.app) | Landing page hero should highlight on-device privacy |
| Privacy Policy | [https://openintelligence.app/privacy](https://openintelligence.app/privacy) | Must mention Apple PCC scope and lack of third-party sharing |

---

## 4. Pricing & StoreKit Cross-Check

- Reference the tier mapping inside `Docs/reference/PRICING_STRATEGY.md`.
- Verify every SKU exists in App Store Connect with the correct product type and price tier.
- Confirm the paywall copy exactly reflects Apples tier pricing (for example $8.99/month, $89.99/year).
- Attach the pricing summary PDF or markdown to the submission if App Review requests context.

---

## 5. Privacy & Reviewer Access

- Ensure the release build keeps `reviewerModeEnabled` hard-disabled (see `smoke_test.md` section **Release Gate Validation**).
- Preload sample documents (`TestDocuments/sample_technical.md`, `TestDocuments/sample_pricing_brief.md`) so reviewers can test without importing their own files.
- Mention in Review Notes that no login is required and all inference remains on-device or PCC.
- Provide an optional test account only if hidden enterprise features require it; otherwise note "Not required".

---

## 6. QA Evidence

Fill out the following table before submission:

| Test | Status | Notes |
| --- | --- | --- |
| Smoke test (iPhone 17 Pro Max) | ⬜ | Paste console log excerpt showing retrieval success |
| Smoke test (macOS) | ⬜ | Ensure reviewer mode UI hidden |
| Release gate validation | ⬜ | Screenshot of Settings without OpenAI category |
| Network capture | ⬜ | Attach Charles/Proxyman log proving Apple-only domains |
| StoreKit purchase flow | ⬜ | Confirm Sandbox receipt validation |

Store the completed table (with boxes replaced by ✅/⚠️) in the release folder.

---

## 7. Submission Timeline Template

| Step | Owner | Target Date | Status |
| --- | --- | --- | --- |
| Build archive | | | |
| QA sign-off | | | |
| Metadata refresh | | | |
| App Review submission | | | |
| App Review follow-up | | | |

Copy this table into the tracking doc (for example Notion/Jira) and keep it updated until approval.

---

## 8. Post-Submission Watchlist

- Monitor App Store Connect for review questions; respond within 24 hours.
- After approval, schedule phased release or manual release as desired.
- Update release notes and marketing site to match the shipped binary.
- Trigger telemetry alert checks (error rates, retriever success) once the build is live.

---

Keeping this package current ensures fast turnaround every submission. Update the "Last updated" line after each release cycle.
