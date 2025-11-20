# StoreKit Testing Setup

## Problem
When tapping purchase buttons, you see "Product unavailable" or nothing happens. This is because the StoreKit Configuration file isn't being used during testing.

## Solution: Configure Xcode Scheme (Required)

### Step 1: Open Scheme Editor
1. In Xcode, click the scheme dropdown next to the Run button (shows "OpenIntelligence")
2. Select **Edit Scheme...**

### Step 2: Enable StoreKit Configuration
1. In the left sidebar, select **Run**
2. Click the **Options** tab
3. Find the **StoreKit Configuration** dropdown
4. Select **StoreKitConfiguration.storekit**
5. Click **Close**

### Step 3: Clean and Rebuild
```bash
# Clean build folder
⌘ + Shift + K (or Product → Clean Build Folder)

# Rebuild
⌘ + B

# Run
⌘ + R
```

## Verification

After these steps, you should see in the console:
```
✅ StoreKit test configuration found at: /path/to/StoreKitConfiguration.storekit
```

And when tapping a purchase button, you should see:
- The Apple payment sheet appear
- **Double-click side button to confirm** prompt
- Product name and price ($2.99, $8.99, etc.)
- Ability to complete test purchase

## What Products Are Available

From `StoreKitConfiguration.storekit`:

| Product ID | Type | Price | Description |
|------------|------|-------|-------------|
| `starter_monthly` | Auto-renewable subscription | $2.99/mo | 40 documents, 3 libraries |
| `starter_annual` | Auto-renewable subscription | $24.99/yr | Same as monthly, 7-day trial |
| `pro_monthly` | Auto-renewable subscription | $8.99/mo | Unlimited documents |
| `pro_annual` | Auto-renewable subscription | $89.99/yr | Same as monthly, 7-day trial |
| `lifetime_cohort` | Non-consumable | $59.99 | One-time unlock |
| `doc_pack_addon` | Consumable | $4.99 | +25 documents |

## Testing Purchase Flow

1. Tap any plan card in the paywall
2. **Apple payment sheet appears** with product details
3. Face ID / Touch ID / Side Button authentication prompt
4. On simulator: Double-click side button (or use Touch ID in menu bar)
5. Purchase completes
6. Entitlements update immediately
7. Check Settings → Developer to see active tier

## Troubleshooting

### "Product unavailable" error
- **Cause**: Scheme not configured
- **Fix**: Follow Step 2 above to select StoreKitConfiguration.storekit

### Empty product catalog
- **Cause**: Configuration file not in bundle or scheme not set
- **Fix**: 
  1. Verify file exists at `OpenIntelligence/StoreKit/StoreKitConfiguration.storekit`
  2. Check it's included in target (select file → File Inspector → Target Membership)
  3. Set scheme option (Step 2)

### Payment sheet doesn't appear
- **Cause**: Purchase call failing silently
- **Fix**: Check console for billing errors, ensure `isProcessing` flag isn't stuck

### "StoreKit test harness unavailable"
- **Cause**: Running on physical device without sandbox account
- **Fix**: Use simulator for local testing, or set up sandbox tester in App Store Connect

## For App Store Submission

Before submitting to App Store Connect:

1. **Create matching products** in App Store Connect with same IDs:
   - starter_monthly
   - starter_annual  
   - pro_monthly
   - pro_annual
   - lifetime_cohort
   - doc_pack_addon

2. **Match pricing** to StoreKitConfiguration.storekit

3. **Add subscription group** ID: `com.openintelligence.subscriptions`

4. **Set up sandbox testers** for pre-release testing

5. **Test on physical device** with sandbox account before submission

## Console Logs to Watch For

**Success:**
```
ℹ️  [BILLING] Products refreshed – {count=6}
ℹ️  [BILLING] Purchase initiated – {product=starter_monthly}
✅ [BILLING] Purchase succeeded – {product=starter_monthly, transactionId=...}
```

**Failure:**
```
⚠️  [BILLING] Products unavailable – {requested=starter_monthly,...}
❌ [BILLING] Product unavailable – {product=starter_monthly}
```

---

**Last Updated**: November 19, 2025  
**Status**: Ready for local testing once scheme is configured
