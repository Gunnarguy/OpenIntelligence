# OpenIntelligence Smoke Test Guide

**Purpose**: Quick validation of key features after major changes  
**Time**: ~10 minutes  
**Device**: iPhone 17 Pro Max Simulator (iOS 26.0+)

---

## Pre-Test Setup

1. **Build & Run**
   ```bash
   open OpenIntelligence.xcodeproj
   # ⌘R on iPhone 17 Pro Max simulator
   ```

2. **Check Build Output**
   - ✅ Zero errors, zero warnings
   - ✅ App launches successfully
   - ✅ No crash on startup

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
```
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
```
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
```
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
   ```
   Ingestion started {"file": "...", "embeddingProvider": "nl_embedding"}
   ```

3. During query, verify:
   ```
   Query embedding {"dimensions": "512", "provider": "nl_embedding"}
   ```

---

## Success Criteria

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
