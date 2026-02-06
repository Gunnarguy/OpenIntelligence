# Google Ads Campaign Setup Guide

Step-by-step setup for OpenIntelligence App Campaign.

## Pre-Setup Checklist

- [ ] App live on App Store
- [ ] Google Ads account created
- [ ] Payment method added
- [ ] Firebase/SKAdNetwork configured (for iOS tracking)
- [ ] Assets prepared (headlines, descriptions, images, videos)

---

## Step 1: Create Campaign

1. Go to [ads.google.com](https://ads.google.com)
2. Click **+ New Campaign**
3. Select **App promotion**
4. Select **App installs**
5. Choose **iOS**
6. Enter your App Store app name or ID

---

## Step 2: Campaign Settings

### Campaign Name

```
OpenIntelligence_iOS_Installs_[Region]_[Date]
Example: OpenIntelligence_iOS_Installs_US_Feb2026
```

### Locations

**Testing Phase:**

- United States only

**Scale Phase:**

- United States
- United Kingdom
- Canada
- Australia

### Languages

- English

### Budget

| Phase        | Daily Budget | Notes                 |
| ------------ | ------------ | --------------------- |
| Testing      | $30-50       | 2 weeks minimum       |
| Optimization | $50-100      | After 50+ conversions |
| Scale        | $100+        | Proven campaigns only |

### Bidding

**Recommended: Target CPI (Cost Per Install)**

- Start at $3.00 for iOS productivity apps
- Adjust based on actual CPI after 7 days

**Alternative: Target CPA**

- Use if tracking in-app events
- Set to 50% above expected CPA initially

---

## Step 3: Ad Group Setup

### Ad Group Name

```
AG_[Focus]_[Date]
Example: AG_AllAssets_Feb2026
```

---

## Step 4: Add Assets

### Headlines (copy from headlines.txt)

```
Ask Any Document Anything
100% Private AI Assistant
PDF to Answers in Seconds
AI That Reads Your Docs
Search Smarter, Not Harder
```

### Descriptions (copy from descriptions.txt)

```
Import any PDF or document. Ask questions in plain English. Get cited answers instantly.
All AI processing happens on your device. No cloud uploads. Your documents stay private.
Students, researchers, and professionals use OpenIntelligence to search documents faster.
Powered by Apple Intelligence. Advanced RAG retrieval finds exactly what you need.
Download free. Import your first document. Ask your first question in under 60 seconds.
```

### Images

Upload from `marketing/assets/` folder:

- [ ] 1200×628 landscape
- [ ] 1200×1200 square
- [ ] 1200×1500 portrait

### Videos

Upload from `marketing/assets/` folder:

- [ ] 9:16 portrait (15-30s)
- [ ] 1:1 square (15-30s)
- [ ] 16:9 landscape (15-30s)

---

## Step 5: Review & Launch

1. Review all settings
2. Confirm budget
3. Click **Publish Campaign**

---

## Post-Launch Checklist

### Day 1

- [ ] Verify ads are serving
- [ ] Check for policy violations
- [ ] Confirm tracking is working

### Day 3

- [ ] Review initial CPI
- [ ] Check asset performance ratings
- [ ] Verify location targeting

### Day 7

- [ ] Analyze by placement (Search vs Display vs YouTube)
- [ ] Review asset report
- [ ] Adjust CPI bid if needed (±10-20% max)

### Day 14

- [ ] Full performance review
- [ ] Pause low-performing assets
- [ ] Add new asset variations
- [ ] Consider scaling budget if CPI < target

---

## Optimization Rules

### When to Increase Budget

- CPI consistently below target
- Conversion volume limited by budget
- "Limited by budget" status showing

### When to Decrease Budget

- CPI 50%+ above target after 2 weeks
- Low quality installs (high uninstall rate)

### When to Pause

- CPI 2x+ target after 3 weeks
- Policy violations
- Negative ROI on paid conversions

---

## Tracking Setup (iOS)

### Option A: Firebase (Recommended)

1. Add Firebase SDK to app
2. Enable Google Analytics
3. Link Firebase to Google Ads
4. Configure conversion events

### Option B: SKAdNetwork

1. Configure SKAdNetwork in Xcode
2. Register conversion values
3. Google Ads will automatically receive postbacks

### Key Events to Track

| Event                 | Priority | Notes         |
| --------------------- | -------- | ------------- |
| app_install           | Required | Automatic     |
| first_document_import | High     | Custom event  |
| first_query           | High     | Custom event  |
| subscription_start    | High     | Revenue event |

---

## Support Resources

- [Google Ads Help Center](https://support.google.com/google-ads)
- [App Campaign Guide](https://support.google.com/google-ads/answer/6247380)
- [iOS Tracking Guide](https://support.google.com/google-ads/answer/10384955)
- [Asset Best Practices](https://support.google.com/google-ads/answer/9176652)
