# OpenIntelligence Smoke Test Guide

**Purpose**: Quick validation of key features after major changes  
**Time**: ~10 minutes  
**Device**: iPhone 17 Pro Max Simulator (iOS 26.0+)

---

## Pre-Test Setup

1. **Clean Install Simulation**

   ```bash
   # Reset app state for first-run testing
   defaults delete com.openintelligence.OpenIntelligence 2>/dev/null || true
   rm -rf ~/Library/Developer/CoreSimulator/Devices/*/data/Containers/Data/Application/*/Library/Preferences/com.openintelligence.OpenIntelligence.plist 2>/dev/null || true
   ```

2. **Build & Run**

   ```bash
   open OpenIntelligence.xcodeproj
   # ⌘R on iPhone 17 Pro Max simulator
   ```

3. **Check Build Output**
   - ✅ Zero errors, zero warnings
   - ✅ App launches successfully
   - ✅ No crash on startup

## Test 0: Onboarding Checklist (3 min)

**Objective**: Verify first-run onboarding flow works correctly

**Prerequisites**: Clean install (see Pre-Test Setup)

1. **Launch app** → Onboarding checklist should appear automatically
2. **Verify Checklist UI**:
   - ✅ Hero section shows "Welcome to OpenIntelligence"
   - ✅ Progress card shows "0/3 complete"
   - ✅ Three steps visible: Import Samples, Pick Model, First Question
   - ✅ Each step shows incomplete status

3. **Step 1: Import Sample Workspace**
   - Tap "Import Now" button
   - **Verify**:
     - ✅ Progress indicator appears: "Importing sample workspace…"
     - ✅ Console shows: `[DocumentProcessor] Processing document: Sample-Pricing-Brief...`
     - ✅ Console shows: `[DocumentProcessor] Processing document: Sample-Technical-Overview...`
     - ✅ Step 1 marked complete (checkmark badge)
     - ✅ Progress updates to "1/3 complete"
     - ✅ Two documents now visible in Documents tab

4. **Step 2: Pick a Model**
   - Tap "Open Settings" button
   - Select a primary model (e.g., "Apple Intelligence" or "On-Device Analysis")
   - Return to onboarding
   - **Verify**:
     - ✅ Step 2 marked complete
     - ✅ Progress updates to "2/3 complete"

5. **Step 3: Ask First Question**
   - Tap "Go to Chat" button
   - Type: `"What documents were imported?"`
   - Send query
   - **Verify**:
     - ✅ Response mentions "Sample Pricing Brief" or "Sample Technical Overview"
     - ✅ Step 3 marked complete
     - ✅ Progress shows "3/3 complete"
     - ✅ Checklist auto-dismisses

6. **Verify Persistence**
   - Quit app (⌘Q)
   - Relaunch
   - **Verify**:
     - ✅ Onboarding checklist does NOT reappear
     - ✅ Sample documents still present in Documents tab
     - ✅ `UserDefaults` key `onboarding.hasCompleted` is `true`

**Expected Console Output**:

```text
📄 [DocumentProcessor] Processing document: Sample-Pricing-Brief-<UUID>.md
   ✓ Extracted 450 characters (85 words)
   ✓ Created 2 semantic chunks
📄 [DocumentProcessor] Processing document: Sample-Technical-Overview-<UUID>.md
   ✓ Extracted 2100 characters (380 words)
   ✓ Created 8 semantic chunks
[OnboardingStateStore] Samples imported, marking complete
[OnboardingStateStore] All steps complete, dismissing checklist
```

---

## Test 0.5: Accessibility Validation (5 min)

**Objective**: Verify VoiceOver, Dynamic Type, and High Contrast compliance

**Prerequisites**: iOS Simulator with accessibility features enabled

### A. VoiceOver Testing

1. **Enable VoiceOver**:
   - Simulator → Settings → Accessibility → VoiceOver → Toggle ON
   - Or use keyboard shortcut: ⌘-Shift-V (toggle)

2. **Navigate Paywall** (Settings → Billing → Upgrade Plan):
   - Swipe right through tier cards
   - **Verify**:
     - ✅ Each tier announces: "{Plan} plan. {Price}. {Tagline}. {Status/Hint}"
     - ✅ Example: "Starter plan. $2.99 per month. Essential workspace for pilots. Double tap to purchase"
     - ✅ Current plan announces: "Pro plan. $8.99 per month. Unlimited RAG workspace. Currently active"
   - Swipe to footer links (Terms, Privacy)
   - **Verify**:
     - ✅ Links announce as buttons with clear labels: "View Terms of Service", "View Privacy Policy"

3. **Navigate Terms/Privacy Views**:
   - Open Terms of Service
   - **Verify**:
     - ✅ Sections announce with headers: "1. Acceptance of Terms"
     - ✅ Body text reads smoothly without skipping paragraphs
     - ✅ Close button announces: "Close terms of service. Button"
   - Return and open Privacy Policy
   - **Verify same structure**

4. **Disable VoiceOver**: ⌘-Shift-V

### B. Dynamic Type Testing

1. **Increase Font Size**:
   - Simulator → Settings → Accessibility → Display & Text Size → Larger Text
   - Drag slider to "Accessibility XXL" (maximum)

2. **Check Paywall Layout**:
   - Navigate to Settings → Billing → Upgrade Plan
   - **Verify**:
     - ✅ Tier card text scales but doesn't overflow
     - ✅ Price labels scale with `.minimumScaleFactor(0.7)` preventing cutoff
     - ✅ Feature list remains readable at large sizes
     - ✅ No text truncation (...) in critical UI

3. **Check Legal Views**:
   - Open Terms of Service
   - **Verify**:
     - ✅ Section headers scale up to Accessibility 3
     - ✅ Body text remains readable without horizontal scrolling
     - ✅ All content accessible via vertical scroll
   - Return and check Privacy Policy

4. **Reset Font Size**: Settings → Display & Text Size → Default

### C. High Contrast Mode

1. **Enable High Contrast**:
   - Simulator → Settings → Accessibility → Display & Text Size → Increase Contrast → Toggle ON

2. **Verify Color Contrast**:
   - Navigate to paywall
   - **Verify**:
     - ✅ Text-on-background contrast ≥ 7:1 (WCAG AAA)
     - ✅ Featured tier badge remains visible
     - ✅ Shadows don't disappear (featured tier glow)
     - ✅ Secondary text readable against `.surface` backgrounds

3. **Check Interactive Elements**:
   - **Verify**:
     - ✅ Buttons have clear borders/backgrounds
     - ✅ Disabled state visually distinct from active
     - ✅ Links underlined or clearly differentiated

4. **Disable High Contrast**: Settings → Display & Text Size → Increase Contrast → Toggle OFF

### D. Color Blindness Simulation (Optional)

1. **Enable Color Filters** (protanopia simulation):
   - Settings → Accessibility → Display & Text Size → Color Filters → Enable
   - Select "Protanopia" (red-green colorblindness)

2. **Verify Information Not Conveyed by Color Alone**:
   - Paywall tier badges use text labels ("Best Value", "Most Popular")
   - Purchase state uses icons + text ("Current Plan", "Upgrade")
   - **Verify**: ✅ All states distinguishable without color perception

**Expected Telemetry** (Console):

```text
📊 [TelemetryCenter] Billing event: paywall_viewed (entry_point: settings)
📊 [TelemetryCenter] Billing event: Terms viewed
📊 [TelemetryCenter] Billing event: Privacy policy viewed
```

---

1. **Verify hidden OpenAI settings**
   - Open **Settings** on a _release-signed_ build (Debug builds may expose reviewer mode).
   - Confirm the **OpenAI** category is absent from the navigation list.
2. **Attempt to toggle reviewer mode**
   - Using any backdoor (e.g., defaults or stored state) should snap `reviewerModeEnabled` back to `false`.
   - Inspect logs: `SettingsStore` emits a warning if a release build attempts to enable reviewer mode.
3. **Model pickers**
   - Primary and fallback model lists must never include `.openAIDirect` when the app is built for the App Store.
4. **Consent defaults**
   - In Settings > Execution & Privacy, verify OpenAI consent reads **Denied** (or **Not Determined**) and cannot be flipped to **Allowed** in production builds.

---

## Test 0.8: Local Model Preview Funnel (4 min)

**Objective**: Verify the three-run local-model preview, gating copy, and telemetry.

**Prerequisites**: Clean install, tier = Free/Starter, no GGUF/Core ML models enabled.

1. **Attempt to enable GGUF/Core ML model**
   - Go to **Settings → Intelligence Pipeline** and pick a GGUF/Core ML backend.
   - **Verify**:
     - ✅ Banner shows "3 preview runs remaining" chip.
     - ✅ `PlanUpgradeSheet` logs entry point `localModelGated` (only when previews are gone).

2. **Run three local queries**
      - Install/import a GGUF model if needed from Model Manager.
      - In **Chat**, send a short prompt ("Summarize the sample workspace") three times.
      - **Verify Telemetry** (Console):

         ```text
         📊 [TelemetryCenter] Billing event: preview_model_used (remaining: 2)
         📊 [TelemetryCenter] Billing event: preview_model_used (remaining: 1)
         📊 [TelemetryCenter] Billing event: preview_model_used (remaining: 0)
         📊 [TelemetryCenter] Billing event: preview_exhausted
         ```

3. **Observe gating state**
   - Fourth attempt to select GGUF/Core ML should show "Upgrade to unlock unlimited private inference" CTA.
   - **Verify**:
     - ✅ `LocalModelAccessState` = `.blocked` (Settings disables toggle, triggers plan sheet).
     - ✅ Telemetry emits `preview_gate_triggered` with backend metadata.

4. **Upgrade to Starter/Pro via paywall (simulated)**
   - Trigger paywall (use Manage Plan → Starter Monthly in StoreKit Test).
   - Complete purchase to move to Starter/Pro.
   - **Verify**:
     - ✅ Telemetry log: `preview_to_paid (preview_runs: 3, product: starter_monthly)`.
     - ✅ `localModelPreviewRemaining` resets to 0 (Pro unlocks unlimited access).

5. **Regression**: Try another GGUF run post-upgrade
   - Should succeed without consuming tickets or showing gating banners.

**Expected Console Output**:

```text
🧪 [RAGService] Local preview ticket issued (remaining: 2)
🧪 [RAGService] Preview ticket consumed (remaining: 1)
⚠️ [TelemetryCenter] Billing event: preview_exhausted
⚠️ [TelemetryCenter] Billing event: preview_gate_triggered
🎉 [TelemetryCenter] Billing event: preview_to_paid (product: pro_monthly)
```

---

## Test 1: Document Ingestion (2 min)

**Objective**: Verify document processing pipeline works

1. Navigate to **Documents** tab
2. Tap "+" button → Select `TestDocuments/sample_technical.md`
3. **Verify**:
   - ✅ Processing overlay appears
   - ✅ Progress updates: "Loading" → "Extracting" → "Embedding" → "Storing"
   - ✅ Document appears in list with metadata (chunks, words, date)
   - ✅ No error messages

**Expected Telemetry** (check Console):

```text
🔢 [EmbeddingService] Generating embeddings for N chunks via provider...
✅ [EmbeddingService] Complete: N embeddings in X.XXs
```

---

## Test 2: Query with Retrieval (2 min)

**Objective**: Verify RAG pipeline end-to-end

1. Navigate to **Chat** tab
2. Type: `"What is this document about?"`
3. Tap Send
4. **Verify**:
   - ✅ Message appears in chat
   - ✅ Streaming response starts (text appears gradually)
   - ✅ **InferenceLocationBadge** shows execution location (📱/☁️/🔑)
   - ✅ No errors in response

**Expected Console Output**:

```text
📦 ENHANCED RAG QUERY PIPELINE
✓ Generated 512-dimensional embedding
✓ Hybrid search complete
✓ Response generated
```

---

## Test 3: Tool Calling (Apple Intelligence Only, 2 min)

**Objective**: Verify agentic tool execution

**Prerequisites**: Apple Intelligence model selected in Settings

1. In Chat, ask: `"How many documents do I have?"`
2. **Verify**:
   - ✅ Response uses `list_documents` tool
   - ✅ **ToolCallBadge** appears showing count (e.g., "🔧 1")
   - ✅ Response includes actual count

**Expected Console**:

```text
[Tool] list_documents called
[Tool] Returned N documents
```

---

## Test 4: UI Badges (1 min)

**Objective**: Verify telemetry badges display correctly

1. Open **Chat** tab with previous messages
2. Scroll through messages
3. **Verify Each Message Shows**:
   - ✅ Timestamp (🕐)
   - ✅ **InferenceLocationBadge** with icon+label
   - ✅ **ToolCallBadge** (if tools were used)

4. Tap "Details" on any response
5. **Verify ResponseDetailsView Shows**:
   - ✅ Both badges at top
   - ✅ Performance metrics
   - ✅ Retrieved chunks (if RAG query)

---

## Test 5: Model Switching (2 min)

**Objective**: Verify model selection works

1. Navigate to **Settings** tab
2. Change **Primary Model** dropdown
3. **Verify Options Available**:
   - ✅ Apple Intelligence (if device supports)
   - ✅ ChatGPT Extension (if iOS 18.1+)
   - ✅ On-Device Analysis (always)
   - ✅ GGUF Local (if models installed)
   - ✅ Core ML Local (if models installed)

4. Select different model
5. Return to **Chat** → Ask simple question
6. **Verify**:
   - ✅ Response generated with new model
   - ✅ Badge shows correct model name

---

## Test 6: Container Isolation (1 min)

**Objective**: Verify per-container vector stores work

1. In **Documents**, tap container dropdown (top)
2. Create new container: "Test Container 2"
3. **Verify**:
   - ✅ New container is empty (no documents)
   - ✅ Switch back to original container
   - ✅ Original documents still visible

4. Import document into new container
5. Query in **Chat** tab
6. **Verify**:
   - ✅ Only new container's documents are searched
   - ✅ Original container's content not retrieved

---

## Test 7: Embedding Provider (Optional, 2 min)

**Objective**: Verify per-container embedding provider works

**Note**: Currently no UI selector, tests backend logic only

1. Check console during document ingestion
2. **Verify Log Contains**:

   ```text
   Ingestion started {"file": "...", "embeddingProvider": "nl_embedding"}
   ```

3. During query, verify:

   ```text
   Query embedding {"dimensions": "512", "provider": "nl_embedding"}
   ```

---

## Success Criteria

✅ **Onboarding checklist completes successfully**  
✅ **All 6 core tests pass**  
✅ **No crashes or errors**  
✅ **Badges display correctly**  
✅ **Console shows expected telemetry**  
✅ **Model switching works**  
✅ **Container isolation works**

---

## Common Issues & Fixes

### Issue: "Apple Intelligence unavailable"

**Fix**: Select "On-Device Analysis" or "ChatGPT Extension" instead

### Issue: No badges showing

**Fix**:

1. Check that query completed successfully
2. Verify `ResponseMetadata` has `toolCallsMade` field
3. Rebuild project: `./clean_and_rebuild.sh`

### Issue: Documents not importing

**Fix**:

1. Check file picker permissions
2. Try different document from `TestDocuments/`
3. Check console for error details

### Issue: Streaming not working

**Fix**:

1. Verify LLM service is selected correctly
2. Check network connection (for cloud models)
3. Try "On-Device Analysis" as fallback

---

## Performance Benchmarks

| Operation | Target | Pass/Fail |
|-----------|--------|-----------|
| Document ingestion | <3s for sample_technical.md | ⬜ |
| Query embedding | <200ms | ⬜ |
| Hybrid search (100 chunks) | <100ms | ⬜ |
| LLM TTFT | <1s (on-device) | ⬜ |
| Badge rendering | Instant | ⬜ |

---

**Last Updated**: November 2025  
**Test Duration**: ~10 minutes  
**Automation Status**: Manual (automation planned)
