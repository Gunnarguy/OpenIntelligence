# Social Media Post Templates: OpenIntelligence v4.0 & v4.1

Announce the combined v4.0 & v4.1 Apple Silicon release across X, Threads, and LinkedIn. 

Project Link: https://github.com/Gunnarguy/OpenIntelligence

---

## 1. Best Default Post (Universal Launch Post)

I build OpenIntelligence: a free, open-source app built specifically for Apple Silicon (Mac, iPad, and iPhone) that lets you search and ask questions about your documents (PDFs, manuals, notes) and get answers with verified, clickable links to the exact source page. Everything runs privately on your device.

Today, v4.1 is live on the App Store! This release is a complete rewrite of the core retrieval engine (162 files, 14,000+ lines of Swift changed) to shift performance to the GPU, harden answer accuracy, and support the new Apple Intelligence APIs on iOS 26.5 and macOS Golden Gate.

Here is the Before vs. After of the engineering work live today:

*   **Metal GPU Vector Search (4x Speedup)**:
    *   *Before*: Local document search used the CPU, which was slow for large libraries and drained the battery.
    *   *After*: I wrote custom Metal compute shaders with SIMD4 batch execution to run vector searches directly on the graphics chip. Search is now 4x faster and uses minimal battery.
*   **Hardened Engine Accuracy & Generation Safeguards**:
    *   *Before*: Prompts or model updates could cause silent citation failures, empty responses, or hallucinations.
    *   *After*: Rebuilt the generation pipeline with verification gates, retry pathways, and structured JSON generation. The app now handles API/model failures gracefully and guarantees that answers are 100% grounded in retrieved sources.
*   **Smart Ingestion & Page Complexity Analyzer**:
    *   *Before*: Scanning PDFs visually (OCR) on every page introduced typos and scanning errors on clean digital files.
    *   *After*: Added a pre-scan complexity check. Pages with valid digital text skip visual scanning entirely (preserving 100% text accuracy and saving 20% processing time), while visual scanning is dynamically scaled only for scanned pages or photos.
*   **Suggested Questions & Natural Language Filters**:
    *   *Before*: Suggested follow-up questions containing layout noise, OCR garbage, or bad grammar.
    *   *After*: Integrated natural language taggers (`NLTagger`) to analyze parts of speech in chunks. The app now filters out layout junk, verbs, and adverbs to suggest clean, grammatically correct questions, with a offline-first fallback to avoid LLM startup lag.
*   **Liquid Glass UI & Live Reasoning Telemetry**:
    *   *Before*: Static, basic chat elements with no visual indication of how the on-device model was thinking.
    *   *After*: Added the `ThinkingStreamView` directly to the `UnifiedMetricsBar` to display live reasoning telemetry, styled with native iOS 26.5 & macOS Golden Gate `.glassEffect` frosted-glass cards and GPU-accelerated queue animations.
*   **Dynamic Model Routing**:
    *   *Before*: Locked to a strict on-device model with a tight context limit.
    *   *After*: Standard tasks run on-device (4K context). Complex reasoning tasks (Deep Think modes) route securely to Apple's Private Cloud Compute enclaves (32K context), keeping your data completely private.

Everything is free, private, and open source:
https://github.com/Gunnarguy/OpenIntelligence

---

## 2. Technical Post (LinkedIn)

I build OpenIntelligence, a free and open-source application built for Apple Silicon (Mac, iPad, and iPhone) that lets you search and ask questions about your PDFs, manuals, and notes with verified, source-locked citations. Everything runs privately on your device.

I recently released v4.1 on the App Store. This release refactors the app's document Q&A pipeline (162 files, 14,000+ lines of Swift changed) to run vector search on the GPU, improve retrieval accuracy, and support the new Apple Intelligence APIs on iOS 26.5 and macOS Golden Gate.

Here is the "Before vs. After" of the engine architecture:

*   **Metal GPU Retrieval**:
    *   *Before*: CPU-bound cosine similarity calculations that caused thermal throttling during large library scans.
    *   *After*: Custom Metal compute shaders with SIMD4 batch execution. Retrieval is 4x faster, running directly on the graphics chip.
*   **Grounded Engine Accuracy**:
    *   *Before*: Model generation failures or empty outputs overwriting valid drafts.
    *   *After*: Enforced main-actor safety and implemented structured generation templates and verification gates to ensure answers are strictly backed by source citations.
*   **Adaptive Ingestion & Page Complexity Analyzer**:
    *   *Before*: Running visual scans (OCR) on every page, introducing text extraction errors.
    *   *After*: A page complexity pre-scan skips OCR on digital text to ensure 100% character accuracy, only running visual scanning on actual scanned pages or photos.
*   **Suggested Questions (NLTagger POS Filtering)**:
    *   *Before*: Suggested follow-up questions containing raw OCR junk and layout noise.
    *   *After*: Integrated Part-of-Speech analysis via `NLTagger` to verify grammar and filter out adverbs and verbs, paired with an offline-first suggestion fallback on app launch.
*   **Liquid Glass UI & Telemetry**:
    *   *Before*: CPU-heavy layout overlays and a static chat footer.
    *   *After*: Real-time reasoning telemetry displayed in `ThinkingStreamView`, utilizing native iOS 26.5/macOS Golden Gate `.glassEffect` system styling and GPU-driven opacity/scale transitions.
*   **Model Routing (Private Cloud Compute)**:
    *   *Before*: Locked to a strict on-device model with a tight context limit.
    *   *After*: Standard tasks run on-device. Complex reasoning tasks route securely to Apple's Private Cloud Compute enclaves, giving users the power of a large cloud model with the privacy of local hardware.

We also built a native evaluations runner (`RAGEvalRunner`) to test local retrieval and generation quality gates (Recall@5 $\ge 0.85$, Citation Precision $\ge 0.90$, Hallucination Rate $\le 0.05$) against JSONL-backed datasets in development.

Check out the code:
https://github.com/Gunnarguy/OpenIntelligence

#AppleSilicon #MetalGPU #Swift #SwiftUI #AppleIntelligence #OpenSource #PrivacyFirst #WWDC26 #iOSDev

---

## 3. X Thread: Rebuilding Local Document Q&A for Apple Silicon

1/ I build OpenIntelligence: a free, open-source app built specifically for Apple Silicon (Mac, iPad, and iPhone) that lets you ask questions about your documents (PDFs, manuals, notes) and get answers with verified, clickable links to the exact source.

Today I released v4.1 on the App Store! It features a complete rewrite (162 files, 14,000+ lines changed) to deliver GPU search speedups and RAG engine accuracy improvements on iOS 26.5 and macOS Golden Gate.

Here is the Before vs. After of how the engine is evolving: 👇

2/ **Metal GPU Vector Search (4x Speedup)**
*   *Before*: CPU similarity calculations that drained battery and warmed up your device.
*   *After*: Custom Metal compute shaders running cosine similarity. Searching is 4x faster on-device, saving battery and allowing deeper local search.

3/ **Engine Accuracy & Verification Gates**
*   *Before*: Prompt changes causing citation failures or empty model responses.
*   *After*: Hardened RAG pipeline with verification gates, retry policies, and structured JSON generation to prevent hallucinations and empty drafts.

4/ **Page Complexity Pre-Scan**
*   *Before*: Running visual scans (OCR) on every page, which led to scanning errors on digital PDFs.
*   *After*: Automatically checks if a page is digital first (preserving 100% text accuracy) and only scans if it's a photo or handwritten note.

5/ **Suggested Questions POS Filter**
*   *Before*: Suggested follow-up questions containing OCR junk and layout noise.
*   *After*: Integrated Part-of-Speech verification via `NLTagger` to filter out layout noise, adverbs, and verbs, ensuring grammatically clean suggestions.

6/ **Liquid Glass UI & Telemetry**
*   *Before*: Static chat elements with no visual feedback during model thinking.
*   *After*: Animated `ThinkingStreamView` in `UnifiedMetricsBar` displaying live reasoning metrics, styled with native iOS 26.5 & macOS Golden Gate `.glassEffect` frosted-glass cards.

7/ **Private Cloud Compute Routing**
*   *Before*: Stuck with a small, slow on-device AI model for large files.
*   *After*: Simple queries run entirely on-device (4K context). Complex queries scale securely to Apple's Private Cloud Compute servers (32K context), processed privately and immediately deleted.

8/ Rebuilt from the ground up for Apple Silicon. We also added a native evaluations runner (`RAGEvalRunner`) to validate RAG accuracy metrics against JSONL datasets. Try v4.1 on the App Store today!
Code: https://github.com/Gunnarguy/OpenIntelligence

#AppleIntelligence #AppleSilicon #macOS #iOS #SwiftUI #OpenSource #MetalGPU #PrivacyFirst #WWDC26

---

## 4. Hook/Short Post

Most AI document readers are simple wrappers. But the new Apple Intelligence APIs announced at WWDC26 allow for something much better.

Today, v4.1 of OpenIntelligence is live on the App Store! It moves search to the GPU for 4x faster speeds on Apple Silicon (Mac, iPad, and iPhone) running iOS 26.5 and macOS Golden Gate.

Here is the Before vs. After of the engine engineering:

*   **Metal GPU Search**: Wrote custom Metal shaders to replace CPU search, making retrieval 4x faster.
*   **Engine Accuracy**: Hardened RAG pipeline with verification gates and retry policies to prevent hallucinations.
*   **Smart Ingestion**: Added a page complexity analyzer that skips OCR on digital text to ensure 100% accuracy.
*   **Suggested Questions**: Used `NLTagger` grammar filters to clean up suggested topics, running offline-first for instant loading.
*   **Liquid Glass UI**: Refreshed the interface with native frosted glass effects and real-time reasoning metrics.
*   **Private Cloud Compute**: Standard tasks run locally. Large tasks scale securely to Apple's Private Cloud Compute enclaves.

It's free, private, and open source:
https://github.com/Gunnarguy/OpenIntelligence
