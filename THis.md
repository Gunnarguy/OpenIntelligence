ℹ️  StoreKit test harness disabled (StoreKitTest framework linking not available in this build)
ℹ️  [DocumentProcessor] Loaded BertTokenizer for accurate chunk validation
ℹ️  [CoreMLSentenceEmbeddingProvider] Loaded EmbeddingModel.mlmodelc - compute: GPU+CPU (forced GPU mode)
ℹ️  [CoreMLSentenceEmbeddingProvider] Loaded tokenizer
ℹ️  🔧 Initializing with user's selected model: apple_intelligence
🔍 AppleFoundationLLMService initialized (model will be loaded on first use)
ℹ️  ✓ Using Apple Foundation Models (on-device + PCC)
🔍 🔥 Preloading model in background for instant first query
ℹ️   Foundation Models available on device
ℹ️  🔗 Tool handler connected for agentic RAG
ℹ️  🔍 Requesting 4 products from StoreKit: pro_monthly, pro_annual, lifetime_cohort, doc_pack_addon
ℹ️  🧾 StoreKit diagnostics: environment=device, bundleId=Gunndamental.OpenIntelligence, appVersion=4.4, buildNumber=96, receiptPresent=unknown, receiptSandboxHint=unknown
🔍 [Warm-up] Starting Foundation Model preload...
🔍 Initialized 4 engine-native tools for agentic RAG
ℹ️  [Warm-up] Foundation Model preloaded in 0.03s (using prewarm API)
ℹ️  [RAGService] Loaded 5 documents (349 chunks)
ℹ️  [MetalBufferPool] 📦 Cache configured: 32MB, 4 buffers/bucket
ℹ️  [GPUComputeService] ✓ SIMD4 cosine similarity pipeline ready (4x faster)
ℹ️  [GPUComputeService] ✓ SIMD4 normalize pipeline ready
ℹ️  [GPUComputeService] ✓ Threadgroup cosine similarity pipeline ready (fastest)
ℹ️  [GPUComputeService] ✓ Metal 4 residency set initialized (capacity: 64)
ℹ️  [GPUComputeService] 🚀 Metal GPU initialized: Apple A18 Pro GPU
ℹ️  [GPUComputeService] 📦 Buffer pool ready (0MB cache)
ℹ️  [GPUComputeService] ✓ Batch cosine similarity pipeline ready
ℹ️  🚀 GPU Compute: Apple A18 Pro GPU ready for vector operations
ℹ️  🚀 GPU Image Processing: Metal context ready for OCR
ℹ️  Model resolved: Apple Intelligence (User Selected)
ℹ️  📦 StoreKit returned 4 products
ℹ️    ✅ Loaded: doc_pack_addon - Document Pack ($2.99)
ℹ️    ✅ Loaded: lifetime_cohort - Lifetime Cohort ($59.99)
ℹ️    ✅ Loaded: pro_monthly - Pro Monthly ($5.99)
ℹ️    ✅ Loaded: pro_annual - Pro Annual ($49.99)
🔍 [SuggestedQuestions] Cache invalidated for container CE72BA0E
🔍 [SuggestedQuestions] Cache invalidated for container CE72BA0E
ℹ️  [BILLING] Products refreshed – {bundleId=Gunndamental.OpenIntelligence, environment=device, expected=4, loaded=4, loadedIDs=doc_pack_addon,lifetime_cohort,pro_annual,pro_monthly, missingIDs=, receiptPresent=unknown, receiptSandboxHint=unknown}
ℹ️  ✅ Reconciled entitlement: lifetime_cohort
ℹ️  🌍 StoreKit environment: Xcode, storefront: USA
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  Entitlement reconciliation complete — activeTier: lifetime, effectiveTier: lifetime, legacy: historicalPaidPurchase, docs: 9223372036854775807, libs: 20
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [SuggestedQuestions] Returning 10 questions from bank (refresh: false)
🔍 [SuggestedQuestions] Returning 10 cached questions for container
🔍 [SuggestedQuestions] Returning 10 cached questions for container
🔍 [SuggestedQuestions] Returning 10 cached questions for container
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [Consent Prewarm] Checking key 'cloudConsent.applePCC' = 'allowed'
ℹ️  [Consent Prewarm] PCC consent already determined (persisted): allowed
🔍 [ChatScreen] Generated 10 dynamic suggested questions (force: false)
ℹ️  [SQLiteFTS5] Database initialized at /var/mobile/Containers/Data/Application/BF4039A5-CE05-4C0E-90EB-199C6DD0A0E6/Library/Application Support/OpenIntelligence/LocalCache/FTS5/fulltext.sqlite
ℹ️  [SQLiteFTS5] Chunk-level FTS5 table initialized
ℹ️  [SQLiteFTS5] Page-level FTS5 table initialized
ℹ️  [SQLiteFTS5] Deleted 3 documents for container 9A09DC08-759D-49DB-AC1C-84E92AB701B9
🔍 [SQLiteFTS5] Deleted document 1C9EE82E-FD72-40B0-8E9E-875951304F38
🔍 [SQLiteFTS5] Stored document 1C9EE82E-FD72-40B0-8E9E-875951304F38 (7679 chars, 1192 words)
ℹ️  [SQLiteFTS5] Stored 13 chunks for document 1C9EE82E-FD72-40B0-8E9E-875951304F38
ℹ️  [SelfTuning] Skipping automatic rebuild/config change during standard ingestion for container CE72BA0E-73B0-421A-8445-0D26B6055C7B. Explicit rebuild required for: Window 350→300
ℹ️  [SQLiteFTS5] Stored 1 pages for document 1C9EE82E-FD72-40B0-8E9E-875951304F38
🔍 [SQLiteFTS5] Deleted document 163C4A8F-AF61-457E-B2BF-0EAAFDFBC3A7
🔍 [SQLiteFTS5] Stored document 163C4A8F-AF61-457E-B2BF-0EAAFDFBC3A7 (5544 chars, 843 words)
ℹ️  [SQLiteFTS5] Stored 10 chunks for document 163C4A8F-AF61-457E-B2BF-0EAAFDFBC3A7
🔍 [SQLiteFTS5] Deleted document F8AEEF14-6E19-4107-9998-C689185E3F44
🔍 [SQLiteFTS5] Stored document F8AEEF14-6E19-4107-9998-C689185E3F44 (5141 chars, 782 words)
ℹ️  [SQLiteFTS5] Stored 9 chunks for document F8AEEF14-6E19-4107-9998-C689185E3F44
ℹ️  [SQLiteFTS5] Deleted 2 documents for container CE72BA0E-73B0-421A-8445-0D26B6055C7B
🔍 [SQLiteFTS5] Deleted document DC0E9860-0C35-4CBB-9FC3-59804AAA8B9C
🔍 [SQLiteFTS5] Stored document DC0E9860-0C35-4CBB-9FC3-59804AAA8B9C (209 chars, 29 words)
ℹ️  [SQLiteFTS5] Stored 2 chunks for document DC0E9860-0C35-4CBB-9FC3-59804AAA8B9C
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [SQLiteFTS5] Deleted 1 documents for container B84584AD-C9F9-45F7-8CC7-DD1C5161A3CF
🔍 [SQLiteFTS5] Deleted document ABC853BB-3219-41C0-AB4D-90FEA2D18CD9
🔍 [SQLiteFTS5] Stored document ABC853BB-3219-41C0-AB4D-90FEA2D18CD9 (239452 chars, 34254 words)
ℹ️  [SQLiteFTS5] Stored 320 chunks for document ABC853BB-3219-41C0-AB4D-90FEA2D18CD9
ℹ️  [SQLiteFTS5] Stored 27 pages for document ABC853BB-3219-41C0-AB4D-90FEA2D18CD9
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 32 chunks (persist deferred)
🔍 [BNNS] Persisted 32 chunks (32 mmap'd)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 32 chunks (persist deferred)
🔍 [BNNS] Persisted 32 chunks (32 mmap'd)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 2 chunks (persist deferred)
🔍 [BNNS] Persisted 2 chunks (2 mmap'd)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 2 chunks (persist deferred)
🔍 [BNNS] Persisted 2 chunks (2 mmap'd)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 320 chunks (persist deferred)
🔍 [BNNS] Persisted 320 chunks (320 mmap'd)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 320 chunks (persist deferred)
🔍 [BNNS] Persisted 320 chunks (320 mmap'd)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 32 chunks (persist deferred)
🔍 [BNNS] Persisted 32 chunks (32 mmap'd)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 32 chunks (persist deferred)
🔍 [BNNS] Persisted 32 chunks (32 mmap'd)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 2 chunks (persist deferred)
🔍 [BNNS] Persisted 2 chunks (2 mmap'd)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 2 chunks (persist deferred)
🔍 [BNNS] Persisted 2 chunks (2 mmap'd)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 320 chunks (persist deferred)
🔍 [BNNS] Persisted 320 chunks (320 mmap'd)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 320 chunks (persist deferred)
🔍 [BNNS] Persisted 320 chunks (320 mmap'd)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BackgroundTasks] Submitted continued query task
📝 [HardwareTelemetry] Haptic pulse: selection
📝 [HardwareTelemetry] Haptic pulse: message-sent
ℹ️  [SYSTEM] Continued query submitted – {backgroundGPU=disabled, battery=45%, chip=A18 Pro, deviceTier=enhanced, formFactor=iPhone, lowPowerMode=off, mode=balanced, rationale=This device does not advertise background GPU support. | Continue on CPU/ANE-first routing to maximize survivability under background constraints., subtitle=Why do transient signals affect later…, thermal=Nominal, title=Answering your questi…}
📝 [HardwareTelemetry] Haptic pulse: processing
📝 [HardwareTelemetry] Haptic pulse: processing
📝 [HardwareTelemetry] Haptic pulse: message-received
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 70%
🔍 [QueryEnhancement] Intent: conceptual (keyword=0, conceptual=2)
ℹ️  [QueryRuntime] Using Standard mode
ℹ️  [RAG] Reliability-first fallbacks enabled
ℹ️  [CoreMLSentenceEmbeddingProvider] Loaded EmbeddingModel.mlmodelc - compute: GPU+CPU (forced GPU mode)
ℹ️  [CoreMLSentenceEmbeddingProvider] Loaded tokenizer
ℹ️  [EmbeddingService] Using provider 'coreml_sentence_embedding' (available: true)
🔍 [RAGService] Quality mode 'Standard' features: HyDE=false, ReRank=true, MMR=true, Verification=true, QueryExpand=false, ContainerVocab=true, ParentDoc=true, Compression=false

╔══════════════════════════════════════════════════════════════╗
║ ENHANCED RAG QUERY PIPELINE                                  ║
╠══════════════════════════════════════════════════════════════╣
║ 📝 Query: Why do transient signals affect later behavior?    ║
║ 🎯 Retrieving top 50 chunks from 2 total                     ║
║ 🧬 Embeddings: coreml_sentence_embedding • 384D              ║
║ ⚙️ Quality Mode: Standard                                    ║
╚══════════════════════════════════════════════════════════════╝
ℹ️  [SYSTEM] Query received – {characters=47, container=Library 2, containerId=CE72BA0E-73B0-421A-8445-0D26B6055C7B, embeddingDim=384, embeddingProvider=coreml_sentence_embedding, minSimilarity=0.28, qualityMode=Standard, question=Why do transient signals affect later behavior?, topK=50, words=7}

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 0: Corpus Analysis
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 70%
🔍 [CorpusVocabulary] Built vocabulary: 12 terms (kwMinFreq=1), 0 co-occurrence entries (coMinFreq=2), filtered 0 invalid terms
🔍 Built corpus vocabulary in 24ms

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 1: Query Understanding
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 70%
🔍 [ConversationMemory] Using memory for query rewriting (1 turns, 8 entities)
ℹ️  [RAG] Query expansion skipped (quality mode: Standard)
🔍 [QueryEnhancement] Intent: conceptual (keyword=0, conceptual=2)
ℹ️  [RETRIEVAL] Query understanding – {originalLength=47, rewritten=false, rewrittenLength=47}
ℹ️  ✓ Answer intent: investigate (extractive-first: false, multi-hop: true)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 2: Query Embedding
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️  [HyDE] Gates: qualityMode=false, settings=true, available=true → enabled=false
📝 [HardwareTelemetry] Pulse Embedding @ 80%
📝 [HardwareTelemetry] Pulse Embedding @ 70%
ℹ️  ✓ Generated 384-dimensional embedding
🔍   Vector magnitude: 1.0000
🔍   Time: 1580ms
ℹ️  [RAPTOR-lite] Query type: detail (confidence: 30%) → search Detail (L0)
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 70%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 3: Hybrid Search (Vector + BM25)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 [RAGService] Query intent: conceptual → weights adjusted to vector=0.60, keyword=0.40
🔍 [Hybrid] Using FTS5-accelerated BM25 for container CE72BA0E-73B0-421A-8445-0D26B6055C7B
🔍 [Hybrid] True parallel hybrid search starting (vector + FTS5)
🔍 [SQLiteFTS5] Chunk search 'Why do transient signals affect later behavior?' needed OR fallback → 1 results
🔍 [Hybrid] Keyword 'transient' hit 50% of chunks — zero boost (≥50%)
🔍 [Hybrid] True parallel search completed in 15.5ms — 2 vector + 1 FTS5 + 0 row hits (0 lexical-only)
🔍 [SQLiteFTS5] Cached query successfully: 'why do transient signals affect later behavior'
🔍 [RAGService] Wrote 2 chunks to semantic cache for query: 'why do transient signals affect later behavior'
ℹ️  ✓ Retrieved 2 chunks with hybrid fusion
🔍   Time: 28ms
🔍   Top semantic score: 0.2616
🔍   Source: Psychiatry Clin Neurosci - 2019 - Yagishita - Transient and sustained effects of dopamine and serotonin signaling in.pdf

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 4: Multi-Signal Re-ranking
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️  [RETRIEVAL] Hybrid retrieval – {avgWords=14.5, candidates=2, container=Library 2, containerId=CE72BA0E-73B0-421A-8445-0D26B6055C7B, topK=100, topWords=29, totalWords=29}
ℹ️  [RAGEngine] Loaded ReRankerModel.mlmodelc
ℹ️  [RAGEngine] Loaded ReRanker Tokenizer
📝 [HardwareTelemetry] Pulse ReRanking @ 85%
🔍 [RAGEngine] AI Re-ranking: raw -5.25→-1.84, normalized 0.10→0.90
🔍 [RAGEngine] Top chunk preview: The document examines dopamine and serotonin signaling in psychiatry. It focuses on transient and sustained effects of these neurotransmitters. The pu...
ℹ️  ✓ Re-ranked to top 2 in 619ms
🔍 Hybrid search starting (vector: 0.38, keyword: 0.62)
ℹ️  [RETRIEVAL] Re-ranking complete – {candidates=2}
📝 [HardwareTelemetry] Pulse BM25 Scoring @ 60%
📝 [HardwareTelemetry] Pulse Query Processing @ 50%
🔍 [Hybrid] Keyword 'transient' hit 50% of chunks — zero boost (≥50%)
🔍 Hybrid fusion: 2 results from 2 vector + 2 BM25
⚠️     ⚠️  Filtered out 1 low-confidence chunks (< 0.28)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 4.5: MMR Diversification
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️  [RETRIEVAL] Gating metrics – {avgTop5=0.500, dynamicMin=0.28, lenient=false, minSimilarity=0.28, override=true, secondSim=0.100, topSim=0.900}
⚠️  [RETRIEVAL] Low-confidence filtered – {dropped=1}
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 70%
📝 [HardwareTelemetry] Pulse Query Processing @ 50%
ℹ️  ✓ Selected 1 diverse chunks in 17ms
🔍   λ=0.60 (60% relevance, 39% diversity)
🔍 [Hybrid Context] Summary chunks already in candidates - no injection needed
ℹ️  Parent document expansion: 1 → 1 chunks (+0 siblings) in 0ms
ℹ️  [RETRIEVAL] MMR diversification – {avgWords=29.0, lambda=0.60, maxWords=29, selected=1, totalWords=29}
ℹ️  [GraphPack] 1 core + 1 context chunks (147 tokens) in 13ms
🔍 [LexicalRelevance] 1/5 keywords found = 20%
🔍 [LexicalRelevance] 1/5 keywords found = 20%
🔍 [SQLiteFTS5] Chunk search 'Why do transient signals affect later behavior?' needed OR fallback → 1 results
🔍 [SQLiteFTS5] Chunk search 'transient signals affect later' needed OR fallback → 1 results
🔍 [SQLiteFTS5] Chunk search 'transient signals' returned 1 results
🔍 [SQLiteFTS5] Chunk search 'affect later behavior' returned 0 results
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 70%
ℹ️  [RAG] Auto-disabled tools: context pre-assembled (2 chunks). Reclaimed ~1000 tokens for context.
🔍 [RAG] Transcript history: ~1886 tokens (auto-trimmed by LLM service, not deducted from context)
🔍 Context budget: base=32768, question=19, transcript=1886(not deducted), available=29731 tokens → 45000 chars, compact=false
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 50%
📝 [HardwareTelemetry] Pulse Query Processing @ 50%
ℹ️     ✓ Using 2/2 chunks (742 chars) • mmr

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 5: Context Assembly Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️  ✓ Final context: 742 chars, 104 words from 2 chunks
ℹ️  [RETRIEVAL] Context assembled – {chars=742, chunks=2, container=Library 2, containerId=CE72BA0E-73B0-421A-8445-0D26B6055C7B}
🔍 [LexicalRelevance] 1/5 keywords found = 20%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 6: LLM Generation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 [ConversationMemory] Context injection: 506 chars (budget: 2000, query-aware: true)
🔍 [ConversationMemory] Injected memory context (506 chars)
ℹ️  [RAG] Using constrained structured answer generation (direct)
ℹ️  Model resolved: Apple Intelligence (User Selected)
ℹ️  [SYSTEM] Cloud call authorized – {bytes=1318, chars=572, chunks=2, grant=remembered, model=Apple Intelligence, provider=Apple PCC}
ℹ️  Model resolved: Apple Intelligence (20B Advanced) (User Selected)
ℹ️  ✓ Response generated
ℹ️    Model: Apple Intelligence
ℹ️    Generation time: 5.04s
🔍   Response length: 207 chars
🔍   Words: 27
🔍   Tokens: 148
🔍   Speed: 29.4 tokens/sec

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 7: Quality Assessment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 70%
ℹ️  [GENERATION] Response generated – {characters=207, container=Library 2, containerId=CE72BA0E-73B0-421A-8445-0D26B6055C7B, model=Apple Intelligence, tokens=148, words=27}
⚠️  ⚠️  Quality Warnings:
⚠️     • Limited context: Only 2 relevant chunks found
⚠️     • Single source: Information from only one document
ℹ️  📊 Confidence Score: 72.0%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 7.5: Verification Gates
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️  [SYSTEM] Response evaluated – {confidence=0.72}
📝 [HardwareTelemetry] Pulse Embedding @ 80%
📝 [HardwareTelemetry] Pulse Embedding @ 70%
🔍 [VerificationGates] Result: FAIL (confidence: 0.86, touchy: false)
⚠️  ⚠️ Verification gates failed - response may contain unsupported claims
⚠️     • Gate Gate B: Evidence Coverage: supported 0, partial 0, unsupported 1, cited 1/1
ℹ️  📊 Calibrated confidence: 57.4% (medium)

╔══════════════════════════════════════════════════════════════╗
║ ENHANCED PIPELINE COMPLETE ✓                                 ║
╠══════════════════════════════════════════════════════════════╣
║ Total time: 7.65s                                            ║
║   - Query Expansion: 0ms                                     ║
║   - Embedding: 1580ms                                        ║
║   - Hybrid Retrieval: 28ms                                   ║
║   - Re-ranking: 619ms                                        ║
║   - MMR Diversification: 17ms                                ║
║   - Quality Assessment: <1ms                                 ║
║   - Verification Gates: 64ms                                 ║
║   - Generation: 5.04s                                        ║
╚══════════════════════════════════════════════════════════════╝
🔍 [StructuredAnswer] type=refused, claims=0, evidence=2, gaps=2
ℹ️  ✅ Enhanced RAG pipeline complete in 7.65s
ℹ️  [SYSTEM] Verification complete – {confidence=0.86, failedGates=Gate B: Evidence Coverage, passed=false}
ℹ️  [SYSTEM] Query complete – {chunks=2, container=Library 2, containerId=CE72BA0E-73B0-421A-8445-0D26B6055C7B, duration=7.65}
ℹ️  📊 RAG Query Statistics
ℹ️    • Query: Why do transient signals affect later behavior?… (≈7 words)
ℹ️    • Chunks: 2 (≈15 words avg)
ℹ️    • Retrieval: 0.03s
ℹ️    • Generation: 5.04s
ℹ️    • Response words: 10
ℹ️    • Model: Apple Intelligence (20B Advanced) (Structured)
ℹ️    • Tokens per second: 29.4
ℹ️  [SYSTEM] Query stats – {chunkCount=2, chunkWords=29, generationTime=5.04, model=Apple Intelligence (20B Advanced) (Structured), queryWords=7, responseWords=10, retrievalTime=0.03}
🔍 [ConversationMemory] Added turn. Recent: 2, Entities: 8
📝 [HardwareTelemetry] Haptic pulse: light
📝 [HardwareTelemetry] Pulse Query Processing @ 60%
📝 [HardwareTelemetry] Pulse Query Processing @ 50%
🔍 [ConversationMemory] Flushed 1 pending saves to disk
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 32 chunks (persist deferred)
🔍 [BNNS] Persisted 32 chunks (32 mmap'd)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 32 chunks (persist deferred)
🔍 [BNNS] Persisted 32 chunks (32 mmap'd)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 2 chunks (persist deferred)
🔍 [BNNS] Persisted 2 chunks (2 mmap'd)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 2 chunks (persist deferred)
🔍 [BNNS] Persisted 2 chunks (2 mmap'd)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 320 chunks (persist deferred)
🔍 [BNNS] Persisted 320 chunks (320 mmap'd)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 320 chunks (persist deferred)
🔍 [BNNS] Persisted 320 chunks (320 mmap'd)
📝 [HardwareTelemetry] Haptic pulse: soft
📝 [HardwareTelemetry] Haptic pulse: selection
📝 [HardwareTelemetry] Haptic pulse: selection
🔍 [RAGService] Reset Deep Think live metrics and audit snapshot
ℹ️  [RAGService] Reset LLM session - context budget restored
🔍 [RAGService] Deleted thread EB113991-2343-497A-8D06-1EBA3ED50F72
🔍 [RAGService] Reset Deep Think live metrics and audit snapshot
🔍 [ConversationMemory] Cleared memory for container CE72BA0E-73B0-421A-8445-0D26B6055C7B
🔍 [RAGService] Cleared chat history, transcript, memory, and live metrics for container CE72BA0E-73B0-421A-8445-0D26B6055C7B
ℹ️  [RAGService] Reset LLM session - context budget restored
🔍 [TranscriptPersistence] Deleted transcript for container CE72BA0E-73B0-421A-8445-0D26B6055C7B
ℹ️  [BackgroundTasks] Submitted continued query task
📝 [HardwareTelemetry] Haptic pulse: selection
📝 [HardwareTelemetry] Haptic pulse: message-sent
ℹ️  [SYSTEM] Continued query submitted – {backgroundGPU=disabled, battery=40%, chip=A18 Pro, deviceTier=enhanced, formFactor=iPhone, lowPowerMode=off, mode=balanced, rationale=This device does not advertise background GPU support. | Continue on CPU/ANE-first routing to maximize survivability under background constraints., subtitle=How does dopamine shape motivation?, thermal=Nominal, title=Answering your questi…}
📝 [HardwareTelemetry] Haptic pulse: processing
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 32 chunks (persist deferred)
🔍 [BNNS] Persisted 32 chunks (32 mmap'd)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 32 chunks (persist deferred)
🔍 [BNNS] Persisted 32 chunks (32 mmap'd)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 2 chunks (persist deferred)
🔍 [BNNS] Persisted 2 chunks (2 mmap'd)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 2 chunks (persist deferred)
🔍 [BNNS] Persisted 2 chunks (2 mmap'd)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 320 chunks (persist deferred)
🔍 [BNNS] Persisted 320 chunks (320 mmap'd)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 320 chunks (persist deferred)
🔍 [BNNS] Persisted 320 chunks (320 mmap'd)
📝 [HardwareTelemetry] Haptic pulse: processing
📝 [HardwareTelemetry] Haptic pulse: message-received
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 70%
🔍 [QueryEnhancement] Intent: conceptual (keyword=0, conceptual=3)
ℹ️  [QueryRuntime] Using Standard mode
ℹ️  [RAG] Reliability-first fallbacks enabled
ℹ️  [CoreMLSentenceEmbeddingProvider] Loaded EmbeddingModel.mlmodelc - compute: GPU+CPU (forced GPU mode)
ℹ️  [CoreMLSentenceEmbeddingProvider] Loaded tokenizer
ℹ️  [EmbeddingService] Using provider 'coreml_sentence_embedding' (available: true)
🔍 [RAGService] Quality mode 'Standard' features: HyDE=false, ReRank=true, MMR=true, Verification=true, QueryExpand=false, ContainerVocab=true, ParentDoc=true, Compression=false

╔══════════════════════════════════════════════════════════════╗
║ ENHANCED RAG QUERY PIPELINE                                  ║
╠══════════════════════════════════════════════════════════════╣
║ 📝 Query: How does dopamine shape motivation?                ║
║ 🎯 Retrieving top 50 chunks from 2 total                     ║
║ 🧬 Embeddings: coreml_sentence_embedding • 384D              ║
║ ⚙️ Quality Mode: Standard                                    ║
╚══════════════════════════════════════════════════════════════╝
ℹ️  [SYSTEM] Query received – {characters=35, container=Library 2, containerId=CE72BA0E-73B0-421A-8445-0D26B6055C7B, embeddingDim=384, embeddingProvider=coreml_sentence_embedding, minSimilarity=0.28, qualityMode=Standard, question=How does dopamine shape motivation?, topK=50, words=5}
ℹ️  [RAGService] ✅ Exact cache hit for query: 'how does dopamine shape motivation'

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 0: Corpus Analysis
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 70%
🔍 [RAGService] Using cached corpus vocabulary for container CE72BA0E-73B0-421A-8445-0D26B6055C7B
🔍 Using cached corpus vocabulary (0ms)
🔍 [RAGService] Query rewriting disabled, using original query
ℹ️  [RAG] Query expansion skipped (quality mode: Standard)
🔍 [QueryEnhancement] Intent: conceptual (keyword=0, conceptual=3)
ℹ️  ✓ Answer intent: lookup (extractive-first: true, multi-hop: false)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 2: Query Embedding
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️  [HyDE] Gates: qualityMode=false, settings=true, available=true → enabled=false
ℹ️  [RAGService] ✅ Reusing cached 384-dim embedding (exact cache hit)
ℹ️  [RAPTOR-lite] Query type: detail (confidence: 30%) → search Detail (L0)
ℹ️  ✓ Retrieved 115 chunks with hybrid fusion
🔍   Time: 0ms
🔍   Top semantic score: 0.8752
🔍   Source: Unknown (p. 5)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 4: Multi-Signal Re-ranking
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️  [RETRIEVAL] Hybrid retrieval – {avgWords=129.5, candidates=115, container=Library 2, containerId=CE72BA0E-73B0-421A-8445-0D26B6055C7B, topK=100, topWords=7379, totalWords=14896}
📝 [HardwareTelemetry] Pulse ReRanking @ 85%
🔍 [RAGEngine] AI Re-ranking: raw -10.38→-2.99, normalized 0.10→0.90
🔍 [RAGEngine] Top chunk preview: Thus, it is possible that plasticity mechanisms are shared between learning and stress responses. Future studies are required to clarify the ways in w...
ℹ️  ✓ Re-ranked to top 115 in 325ms
ℹ️  [RETRIEVAL] Re-ranking complete – {candidates=115}
⚠️     ⚠️  Filtered out 74 low-confidence chunks (< 0.24)
ℹ️     🔧 Spec preservation: rescued 5 spec chunks (score=0.85)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 4.5: MMR Diversification
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️  [RETRIEVAL] Gating metrics – {avgTop5=0.800, dynamicMin=0.24, lenient=false, minSimilarity=0.28, override=true, secondSim=0.827, topSim=0.868}
⚠️  [RETRIEVAL] Low-confidence filtered – {dropped=74}
ℹ️  [RETRIEVAL] Spec preservation – {boostedScore=0.85, intent=lookup, rescued=5}
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 70%
📝 [HardwareTelemetry] Pulse Query Processing @ 50%
ℹ️  ✓ Selected 46 diverse chunks in 33ms
🔍   λ=0.60 (60% relevance, 39% diversity)
ℹ️  Parent document expansion: 46 → 46 chunks (+0 siblings) in 0ms
ℹ️  [RETRIEVAL] MMR diversification – {avgWords=196.0, lambda=0.60, maxWords=290, selected=46, totalWords=9018}
🔍 [LexicalRelevance] 2/4 keywords found = 50%
🔍 [SQLiteFTS5] Chunk search 'How does dopamine shape motivation?' needed OR fallback → 1 results
🔍 [SQLiteFTS5] Chunk search 'does dopamine shape motivation' needed OR fallback → 1 results
🔍 [SQLiteFTS5] Chunk search 'does dopamine' returned 1 results
🔍 [SQLiteFTS5] Chunk search 'dopamine shape motivation' needed OR fallback → 1 results
📝 [HardwareTelemetry] Pulse ReRanking @ 85%
🔍 [RAGEngine] AI Re-ranking: raw -9.50→-2.99, normalized 0.10→0.90
🔍 [RAGEngine] Top chunk preview: Thus, it is possible that plasticity mechanisms are shared between learning and stress responses. Future studies are required to clarify the ways in w...
🔍 [LexicalRelevance] 3/4 keywords found = 75%
ℹ️  [Corrective] Adopted lexical corrective retrieval: +1 hits, lexical 50%->75%
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 70%
ℹ️  [RAG] Auto-disabled tools: context pre-assembled (47 chunks). Reclaimed ~1000 tokens for context.
🔍 Context budget: base=32768, question=14, transcript=0(not deducted), available=29736 tokens → 45000 chars, compact=false
ℹ️  [RAG] Corpus-aware: discounted generic keywords ["dopamine", "motivation"] (>40% of chunks)
ℹ️  [RAG] Extractive query - prioritizing specs (discriminative: [does, shape])
ℹ️  [RETRIEVAL] Corrective retrieval – {added=1, postLexical=0.75, postTop=0.86, preLexical=0.50, preTop=0.85}
ℹ️  [RAG] Sentence extraction: 225 sentences from 38 sources (21358 chars)
ℹ️     ✓ Using 38/47 chunks (21358 chars) • corrective_fts

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 5: Context Assembly Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️  ✓ Final context: 21358 chars, 2875 words from 38 chunks
ℹ️  [RETRIEVAL] Context assembled – {chars=21358, chunks=38, container=Library 2, containerId=CE72BA0E-73B0-421A-8445-0D26B6055C7B}
🔍 [LexicalRelevance] 3/4 keywords found = 75%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 6: LLM Generation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 [ConversationMemory] Context injection: 635 chars (budget: 2000, query-aware: true)
🔍 [ConversationMemory] Injected memory context (635 chars)
🔍 [RAG] Structured answer generation skipped due to token budget (~17693 input tokens)
ℹ️  System prompt changed, recreating session
🔍 RAG mode: context=21358 chars, prompt=## Conversation Context

### Recent Conversation
U...
⚠️  [FM] Input approaching context limit: ~15891 tokens
🔍 Generation: ~8872 tokens, exec=preferCloud
ℹ️  [SYSTEM] Cloud call authorized – {bytes=22106, chars=689, chunks=38, grant=remembered, model=Apple Intelligence, provider=Apple PCC}
ℹ️  [GENERATION] Apple FM: Generation started – {execPref=preferCloud, maxTokens=2048, pccAllowed=true, route=onDeviceAdvanced, temperature=0.4}
📝 [HardwareTelemetry] Sustain START LLM Inference
⚠️  Primary model Apple Intelligence failed: The session's transcript exceeded the model's context size.
⚠️  [RAG] Context overflow (PCC request overflowed) - building evidence pack
⚠️  [SYSTEM] Context overflow - evidence pack – {chunks=47, reason=PCC request overflowed}
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 50%
📝 [HardwareTelemetry] Pulse Query Processing @ 50%
ℹ️  [RAG] Using constrained structured answer generation (direct)
⚠️  [SYSTEM] Evidence-pack retry – {chunksUsed=3, contextChars=2778}
ℹ️  ✓ Response generated
ℹ️    Model: Apple Intelligence
ℹ️    Generation time: 10.07s
🔍   Response length: 169 chars
🔍   Words: 17
🔍   Tokens: 121
🔍   Speed: 17.8 tokens/sec
🔍 [ExtractiveQA] Query parsing - Entities: [], Descriptive: ["dopamine", "shape", "motivation"]
🔍 [ExtractiveQA] Primary entities: []
🔍 [ExtractiveQA] Descriptive keywords: ["dopamine", "shape", "motivation"]
🔍 [ExtractiveQA] Proximity candidate: 'results.38' score=0.15 keywords=["dopamine"]
🔍 [ExtractiveQA] Proximity candidate: 'movements.40' score=0.15 keywords=["dopamine"]
🔍 [ExtractiveQA] Proximity candidate: 'cues.53' score=0.00 keywords=[]
🔍 [ExtractiveQA] No proximity match found (best: 0.15)
🔍 [ExtractiveQA] Found 4 candidates
🔍 [ExtractiveQA] Candidate: 'results.38' (PartNumber) score=0.48
ℹ️  [GENERATION] Response generated – {characters=169, container=Library 2, containerId=CE72BA0E-73B0-421A-8445-0D26B6055C7B, model=Apple Intelligence, tokens=121, words=17}
🔍 [ExtractiveQA] Candidate: '38 In' (Measurement) score=0.45
🔍 [ExtractiveQA] Candidate: 'movements.40' (PartNumber) score=0.40
🔍 [ExtractiveQA] Ambiguous: 2 competing values

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 7: Quality Assessment
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📝 [HardwareTelemetry] Pulse RAG Pipeline @ 70%
⚠️  ⚠️  Quality Warnings:
⚠️     • Single source: Information from only one document
ℹ️  📊 Confidence Score: 76.0%

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Step 7.5: Verification Gates
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ℹ️  [SYSTEM] Response evaluated – {confidence=0.76}
📝 [HardwareTelemetry] Pulse Embedding @ 80%
📝 [HardwareTelemetry] Pulse Embedding @ 70%
⚠️  [RAG] Gate E: No chunk embeddings loaded — vector DB may not support getEmbeddings. Gate E will be skipped.
🔍 [VerificationGates] Result: FAIL (confidence: 0.89, touchy: false)
⚠️  ⚠️ Verification gates failed - response may contain unsupported claims
⚠️     • Gate Gate B: Evidence Coverage: supported 0, partial 0, unsupported 3, cited 3/3
🔍 [Verification] Extractive intent 'lookup' - using relaxed threshold 25%
ℹ️  📊 Calibrated confidence: 56.3% (medium)

╔══════════════════════════════════════════════════════════════╗
║ ENHANCED PIPELINE COMPLETE ✓                                 ║
╠══════════════════════════════════════════════════════════════╣
║ Total time: 11.63s                                           ║
║   - Query Expansion: 0ms                                     ║
║   - Embedding: 0ms                                           ║
║   - Hybrid Retrieval: 152ms                                  ║
║   - Re-ranking: 470ms                                        ║
║   - MMR Diversification: 33ms                                ║
║   - Quality Assessment: <1ms                                 ║
║   - Verification Gates: 105ms                                ║
║   - Generation: 10.07s                                       ║
╚══════════════════════════════════════════════════════════════╝
ℹ️  [SYSTEM] Verification complete – {confidence=0.89, failedGates=Gate B: Evidence Coverage, passed=false}
ℹ️  [SYSTEM] Query complete – {chunks=3, container=Library 2, containerId=CE72BA0E-73B0-421A-8445-0D26B6055C7B, duration=11.63}
⚠️  [SourceOnly] Draft generation failed: The session's transcript exceeded the model's context size.
🔍 [StructuredAnswer] type=refused, claims=0, evidence=3, gaps=4
ℹ️  ✅ Enhanced RAG pipeline complete in 32.18s
ℹ️  📊 RAG Query Statistics
ℹ️    • Query: How does dopamine shape motivation?… (≈5 words)
ℹ️    • Chunks: 3 (≈78 words avg)
ℹ️    • Retrieval: 0.15s
ℹ️    • Generation: 6.79s
ℹ️    • Response words: 10
ℹ️    • Model: Apple Intelligence (20B Advanced) (Structured)
ℹ️    • Tokens per second: 17.8
ℹ️  [SYSTEM] Query stats – {chunkCount=3, chunkWords=234, generationTime=6.79, model=Apple Intelligence (20B Advanced) (Structured), queryWords=5, responseWords=10, retrievalTime=0.15}
🔍 [ConversationMemory] Added turn. Recent: 3, Entities: 8
📝 [HardwareTelemetry] Haptic pulse: light
📝 [HardwareTelemetry] Pulse Query Processing @ 60%
📝 [HardwareTelemetry] Pulse Query Processing @ 50%
🔍 [ConversationMemory] Flushed 1 pending saves to disk
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 32 chunks (persist deferred)
🔍 [BNNS] Persisted 32 chunks (32 mmap'd)
ℹ️  [BNNS] Loaded 32 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 32 chunks (persist deferred)
🔍 [BNNS] Persisted 32 chunks (32 mmap'd)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 2 chunks (persist deferred)
🔍 [BNNS] Persisted 2 chunks (2 mmap'd)
ℹ️  [BNNS] Loaded 2 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 2 chunks (persist deferred)
🔍 [BNNS] Persisted 2 chunks (2 mmap'd)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 320 chunks (persist deferred)
🔍 [BNNS] Persisted 320 chunks (320 mmap'd)
ℹ️  [BNNS] Loaded 320 chunks (mmap'd 0MB vectors, 0 bytes heap)
🔍 [BNNS] Batch buffered 320 chunks (persist deferred)
🔍 [BNNS] Persisted 320 chunks (320 mmap'd)
📝 [HardwareTelemetry] Haptic pulse: soft

-----
════════════════════════════════════════════════════════════════════════
  OPENINTELLIGENCE PIPELINE TRACE
  Generated: 2026-06-28T05:53:50Z
  Message ID: 0BB9ABE4-73A7-4056-BF0B-C89EB5FC0FCE
  Container: CE72BA0E-73B0-421A-8445-0D26B6055C7B
════════════════════════════════════════════════════════════════════════

▶ QUERY
────────────────────────────────────────────────────────────────────────
How does dopamine shape motivation?

▶ RESPONSE (64 chars)
────────────────────────────────────────────────────────────────────────
I couldn't verify a reliable answer from the retrieved evidence.

▶ METADATA
────────────────────────────────────────────────────────────────────────
  Model:            Apple Intelligence (20B Advanced) (Structured)
  Quality Mode:     Standard
  Agentic:          NO
  Retrieval Config: Balanced
  Retrieval Time:   152ms
  Total Gen Time:   6.8s
  Tokens Generated: 121
  Tokens/sec:       17.8
  Gating:           acceptance_override,unverified:Gate B: Evidence Coverage
  Embedding:        coreml_sentence_embedding

▶ THINKING EVENTS (19 events)
────────────────────────────────────────────────────────────────────────
  +000000ms [Planning] Execution plan: Standard Retrieval │ The query asks about dopamine's role in motivation, which is a conceptual biological/psychological topic. No specific model numbers, codes, or units are mentioned, so a general retrieval of scientific literature on dopamine and motivation is appropriate. No tool call is needed as the question is conceptual in nature and doesn't require direct specification of entities or data formats.
  +000046ms [Planning] Standard mode │ ReRank • MMR • Verify • Vocab • Parent
  +000047ms [Planning] Scoping query │ Top 50 • Library 2
  +000074ms [Retrieval] Exact Cache Hit │ Bypassed rewriting, embedding, and database search
  +000101ms [Query Rewrite] Query expansion skipped │ Quality mode: Standard
  +000117ms [Intent Routing] Intent: lookup │ Extractive-first
  +000158ms [Vector Search] Vector search │ Semantic similarity • 60% weight
  +000159ms [BM25 (Keyword)] BM25 search │ Keyword matching • 40% weight
  +000159ms [RRF Fusion] RRF fusion │ 115 candidates merged
  +000482ms [Re-ranking] Cross-encoder rerank │ 115 candidates scored
  +000525ms [Confidence Gate] Confidence gate (Balanced) │ min 0.24 • top 0.87
  +000556ms [MMR Diversity] MMR diversity │ λ=0.6 • 46 selected
  +001176ms [Retrieval] Corrective retrieval │ +1 lexical/page hits
  +001251ms [Position Reorder] Position reorder │ Attention-optimal placement
  +001251ms [Context Assembly] Context ready │ 38 chunks • 2875 words
  +001402ms [Generation] Generating answer │ Apple Intelligence
  +011438ms [Generation] Answer composed │ 121 tokens in 10.07s
  +011701ms [Verification Gates] Gates failed ✗ │ Confidence: 89%
  +011701ms [Confidence Calibration] Confidence: medium │ 56% P(correct)

▶ REASONING TRACE (8 sessions)
────────────────────────────────────────────────────────────────────────
  Session 1: Planning: Execution plan: Standard Retrieval — The query asks about dopamine's role in motivation, which is a conceptual biological/psychological topic. No specific model numbers, codes, or units are mentioned, so a general retrieval of scientific literature on dopamine and motivation is appropriate. No tool call is needed as the question is conceptual in nature and doesn't require direct specification of entities or data formats.
  Session 2: Planning: Standard mode — ReRank • MMR • Verify • Vocab • Parent
  Session 3: Planning: Scoping query — Top 50 • Library 2
  Session 4: Retrieval: Exact Cache Hit — Bypassed rewriting, embedding, and database search
  Session 5: Generation: Generating answer — Apple Intelligence
  Session 6: Generation: Answer composed — 121 tokens in 10.07s
  Session 7: Verification Gates: Gates failed ✗ — Confidence: 89%
  Session 8: Confidence Calibration: Confidence: medium — 56% P(correct)

▶ RETRIEVED CHUNKS (3 chunks)
────────────────────────────────────────────────────────────────────────

  ── Chunk 1 ──
  Source:     Unknown
  Rank:       3
  Similarity: 0.8678
  Page:       3
  Section:    PCNPsychiatry and Clinical Neurosciences
  Path:       REVIEW ARTICLE > PCNPsychiatry and Clinical Neurosciences
  Structure:  paragraph
  Content:    dopamine activity allowed the demonstration of the rapid activation of dopamine axonal activity at the onset of locomotion, which terminated at movement offset in sub-second order, validating the manipulation results.38 In the study, stimulation of dopaminergic terminals in the ventral striatum or N...

  ── Chunk 2 ──
  Source:     Unknown
  Rank:       5
  Similarity: 0.4561
  Page:       3
  Section:    PCNPsychiatry and Clinical Neurosciences
  Path:       REVIEW ARTICLE > PCNPsychiatry and Clinical Neurosciences
  Structure:  paragraph
  Content:    lation effects emerged within a minute of the onset of the stimulation and disappeared within a minute following cessation of the stimulation, which indicated that the dopamine effect was transient. When the dopamine activities were recorded, the timing of light illumination did not correspond to th...

  ── Chunk 3 ──
  Source:     Unknown
  Rank:       7
  Similarity: 0.3354
  Page:       3
  Section:    PCNPsychiatry and Clinical Neurosciences
  Path:       REVIEW ARTICLE > PCNPsychiatry and Clinical Neurosciences
  Structure:  paragraph
  Content:    n was applied during the task trial but not when it was applied between the task trials, which were tens of seconds, suggesting that the serotonin effect was transient in the regulation of the moment-tomoment level of patience. During engaging in the task, serotonin stimulation did not affect motor ...

════════════════════════════════════════════════════════════════════════
  END OF TRACE
════════════════════════════════════════════════════════════════════════


-------
ok so we cant just haev this thing refusing every answer now lol...
