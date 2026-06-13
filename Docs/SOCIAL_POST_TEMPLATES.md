# Social Media Post Templates: OpenIntelligence v4.0 & v4.1

Announce the combined v4.0 & v4.1 Apple Silicon release across X, Threads, and LinkedIn. 

Project Link: https://github.com/Gunnarguy/OpenIntelligence

---

## 1. Best Default Post (Universal Launch Post)

I build OpenIntelligence: a free, open-source app built specifically for Apple Silicon (Mac, iPad, and iPhone) that lets you search and ask questions about your documents (PDFs, manuals, notes) and get answers with verified, clickable links to the exact source page. Everything runs privately on your device.

Today, v4.1 is live on the App Store! This release is a complete rewrite of the core engine (162 files, 14,000+ lines of Swift changed) to shift performance to the GPU, secure local storage, and stage support for the new Apple Intelligence APIs announced at WWDC26.

Here is the "Before vs. After" of the engineering work live **today in v4.1** (on iOS 26 / macOS 16):

*   **Metal GPU Vector Search (4x Speedup)**:
    *   *What was wrong*: Searching large document libraries used the CPU, which was slow and drained the battery.
    *   *How I fixed it*: I wrote custom Metal compute shaders with SIMD4 batch execution to run vector searches directly on the device's graphics chip. Search is now 4x faster and uses minimal battery.
*   **Smart Ingestion & Page Complexity Analyzer**:
    *   *What was wrong*: Reading PDFs visually (OCR) on every page introduced typos and scanning errors on clean digital files.
    *   *How I fixed it*: Added a pre-scan complexity check. Pages with valid digital text skip visual scanning entirely (preserving 100% accuracy and saving 20% processing time), while visual scanning is dynamically scaled only for scanned pages or photos.
*   **Atomic Database Writes & Cascading Deletions**:
    *   *What was wrong*: Writing vector data directly to disk could fail if the app closed mid-write, leading to database corruption. Canceling imports also left orphaned database files on disk.
    *   *How I fixed it*: Rebuilt `BNNSVectorDatabase` to use atomic file replacement on disk. I also added a cascading deletion system so canceling an import cleanly purges FTS5 indexes, Spotlight indexes, vectors, and local files.
*   **Suggested Questions & Natural Language Filters**:
    *   *What was wrong*: The app suggests follow-up questions, but they often contained layout noise, OCR garbage, or bad grammar.
    *   *How I fixed it*: Integrated natural language taggers (`NLTagger`) to analyze parts of speech. The app now filters out layout junk, verbs, and adverbs to suggest clean, grammatically correct questions, with a offline-first fallback to avoid LLM startup lag.
*   **Continuous Evaluations Suite**:
    *   *What was wrong*: Tweaking the AI prompts or retrieval settings could cause silent regressions in answer accuracy or citation precision.
    *   *How I fixed it*: Built a native RAG evaluation runner (`RAGEvalRunner`) that tests local prompts against JSONL datasets. It automatically tracks search recall, citation precision, and unsupported-claim rates.

Here is what is **ready to unlock as soon as you update to iOS 27 & macOS 17** (leveraging the new WWDC26 Apple Intelligence APIs):

*   **System-Wide Search (Spotlight indexing)**: Spotlight will index actual text passages and citation anchors inside your files. You will be able to search for specific facts directly from your device's main system search bar, without opening the app.
*   **Voice Control (Siri App Entities)**: Document libraries are mapped to native App Entities introduced at WWDC26. You will be able to ask Siri to "summarize this folder of files" or "compare these two documents" using voice commands.
*   **Secure Cloud Scaling (Private Cloud Compute)**: Standard queries run locally. Complex reasoning tasks (Deep Think modes) will securely route to Apple's Private Cloud Compute enclaves, keeping your files completely private.

Everything is free, private, and open source:
https://github.com/Gunnarguy/OpenIntelligence

---

## 2. Technical Post (LinkedIn)

I build OpenIntelligence, a free and open-source application built for Apple Silicon (Mac, iPad, and iPhone) that lets you search and ask questions about your PDFs, manuals, and notes with verified, source-locked citations. Everything runs privately on your device.

I recently released v4.1 on the App Store. This release refactors the app's document Q&A pipeline (162 files, 14,000+ lines of Swift changed) to run vector search on the GPU today, while staging support for the WWDC26 Apple Intelligence APIs.

Here is the "Before vs. After" of the architecture:

**Live Today in v4.1 (for all iOS 26 / macOS 16 users):**
*   **Metal GPU Retrieval**:
    *   *Before*: CPU-bound cosine similarity calculations that caused thermal throttling during large library scans.
    *   *After*: Custom Metal compute shaders with SIMD4 batch execution. Retrieval is 4x faster, running directly on the graphics chip.
*   **Adaptive Ingestion & Page Complexity Analyzer**:
    *   *Before*: Running visual scans (OCR) on every page, introducing text extraction errors.
    *   *After*: A page complexity pre-scan skips OCR on digital text to ensure 100% character accuracy, only running visual scanning on actual scanned pages or photos.
*   **Atomic Saves & Cascading Purges**:
    *   *Before*: Inline `FileHandle` appending in `BNNSVectorDatabase` causing mmap crashes on write interruptions.
    *   *After*: Rebuilt storage writes to compile a contiguous memory buffer and execute atomic file replacements. Canceling imports now triggers a clean cascading deletion across FTS5 tables, vector indexes, and physical files.
*   **Suggested Questions (NLTagger POS Filtering)**:
    *   *Before*: Follow-up suggestions containing raw OCR junk and layout noise.
    *   *After*: Integrated Part-of-Speech analysis via `NLTagger` to verify grammar and filter out adverbs and verbs, paired with an offline-first suggestion fallback on app launch.

**Ready for iOS 27 / macOS 17 (Leveraging WWDC26 APIs on upcoming OS releases):**
*   **System Search (Spotlight Passage Indexing)**:
    *   *Before*: Spotlight search only indexed filenames.
    *   *After*: Spotlight indexes specific text passages and citation anchors, turning the system search bar into a semantic search plane.
*   **Siri Integration (App Entities)**:
    *   *Before*: Siri could only open the app.
    *   *After*: Mapped document libraries to native App Entities introduced at WWDC26, letting users ask Siri to summarize or compare files using voice or Shortcuts.
*   **Model Routing (Private Cloud Compute)**:
    *   *Before*: Locked to a strict on-device model with a tight context limit.
    *   *After*: Standard tasks run on-device. Complex reasoning routes securely to Apple's Private Cloud Compute enclaves, giving users the power of a large cloud model with the privacy of local hardware.

We also built a native evaluations runner (`RAGEvalRunner`) to test local retrieval and generation quality gates (Recall@5 $\ge 0.85$, Citation Precision $\ge 0.90$, Hallucination Rate $\le 0.05$) against JSONL-backed datasets in development.

Check out the code:
https://github.com/Gunnarguy/OpenIntelligence

#AppleSilicon #MetalGPU #Swift #SwiftUI #AppleIntelligence #OpenSource #PrivacyFirst #WWDC26 #iOSDev

---

## 3. X Thread: Rebuilding Local Document Q&A for Apple Silicon

1/ I build OpenIntelligence: a free, open-source app built specifically for Apple Silicon (Mac, iPad, and iPhone) that lets you ask questions about your documents (PDFs, manuals, notes) and get answers with verified, clickable links to the exact source.

Today I released v4.1 on the App Store! It features a complete rewrite (162 files, 14,000+ lines changed) to deliver GPU search speedups today and stage support for the new WWDC26 Apple Intelligence APIs.

Here is the Before vs. After of how the app is evolving: 👇

2/ **Live Today in v4.1: Metal GPU Vector Search (4x Speedup)**
*   *Before*: CPU similarity calculations that drained battery and warmed up your device.
*   *After*: Custom Metal compute shaders running cosine similarity. Searching is 4x faster on-device, saving battery and allowing deeper local search.

3/ **Live Today in v4.1: Page Complexity pre-scan**
*   *Before*: Running visual scans (OCR) on every page, which led to scanning errors on digital PDFs.
*   *After*: Automatically checks if a page is digital first (preserving 100% text accuracy) and only scans if it's a photo or handwritten note.

4/ **Live Today in v4.1: Atomic Saves & Cascading Purges**
*   *Before*: Appending writes directly to disk, leading to database corruption if interrupted.
*   *After*: Rebuilt storage writes to perform atomic file replacements. Canceling imports now triggers a clean cascading deletion across SQLite, vector indexes, and physical files.

5/ **Live Today in v4.1: Suggested Questions POS Filter**
*   *Before*: Suggested follow-up questions containing OCR junk and layout noise.
*   *After*: Integrated Part-of-Speech verification via `NLTagger` to filter out layout noise, adverbs, and verbs, ensuring grammatically clean suggestions.

6/ **Ready for iOS 27 / macOS 17: Spotlight Search**
*   *After*: Spotlight indexes specific passages and citation anchors, letting you search inside your documents directly from the device's main system search bar without opening the app.

7/ **Ready for iOS 27 / macOS 17: Siri App Entities**
*   *After*: Documents and libraries are native App Entities. Siri will be able to search, compare, or summarize files using voice commands.

8/ **Ready for iOS 27 / macOS 17: Private Cloud Compute**
*   *After*: Simple queries run entirely on-device. Complex queries will scale securely to Apple's Private Cloud Compute servers, processed privately and immediately deleted.

9/ Rebuilt from the ground up for Apple Silicon. We also added a native evaluations runner (`RAGEvalRunner`) to validate RAG accuracy metrics against JSONL datasets. Try v4.1 on the App Store today!
Code: https://github.com/Gunnarguy/OpenIntelligence

#AppleIntelligence #AppleSilicon #macOS #iOS #SwiftUI #OpenSource #MetalGPU #PrivacyFirst #WWDC26

---

## 4. Hook/Short Post

Most AI document readers are simple wrappers. But the new Apple Intelligence APIs announced at WWDC26 allow for something much better.

Today, v4.1 of OpenIntelligence is live on the App Store! It moves search to the GPU for 4x faster speeds on Apple Silicon (Mac, iPad, and iPhone) and prepares the codebase for the upcoming iOS 27 / macOS 17 Apple Intelligence updates.

Here is the Before vs. After of the engineering work:

**Available now in v4.1 (iOS 26 / macOS 16):**
*   **Metal GPU Search**: Wrote custom GPU shaders to replace CPU search, making retrieval 4x faster.
*   **Smart Ingestion**: Added a page complexity analyzer that skips OCR on digital text to ensure 100% accuracy.
*   **Atomic Saves**: Swapped direct file appends for atomic file replacements to prevent database corruption.

**Coming next in iOS 27 / macOS 17 (WWDC26 APIs):**
*   **Spotlight**: Search inside your documents directly from your device's main search bar.
*   **Siri**: Ask Siri to compare files or summarize folders with voice commands.
*   **Privacy**: Complex tasks scale securely to Apple's Private Cloud Compute enclaves.

It's free, private, and open source:
https://github.com/Gunnarguy/OpenIntelligence
