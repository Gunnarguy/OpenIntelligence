# Social Media Post Templates: OpenIntelligence v4.0 & v4.1

Announce the combined v4.0 & v4.1 Apple Intelligence release across X, Threads, and LinkedIn. 

Project Link: https://github.com/Gunnarguy/OpenIntelligence

---

## 1. Best Default Post (Universal Launch Post)

I build OpenIntelligence: a free, open-source app built specifically for Apple Silicon (Mac, iPad, and iPhone) that lets you search and ask questions about your documents (PDFs, manuals, notes) and get answers with verified, clickable links to the exact source page. Everything runs privately on your device.

Today, v4.1 is live on the App Store! This release (162 files, 14,000+ lines of Swift changed) delivers massive performance upgrades today on iOS 26 & macOS 16, while laying the codebase groundwork for the new Apple Intelligence features announced at WWDC26.

Here is what you get **right now in v4.1** (running on iOS 26 / macOS 16):

*   **4x Faster Search (GPU Speed)**:
    *   *Before*: Searching through massive documents was slow and drained your battery.
    *   *After*: I moved the search math directly to your device's graphics chip (GPU) using Metal. Finding answers is now 4x faster and uses minimal battery.
*   **Fewer Typos (Smart PDF Scanning)**:
    *   *Before*: Reading digital PDFs often introduced typos because the app treated clean digital text as if it were a photo.
    *   *After*: The app automatically detects clean digital text first (preserving 100% accuracy) and only scans pages that are photos or handwriting.
*   **Camera & Image Q&A**:
    *   *Before*: Limited to typed document files.
    *   *After*: You can snap a photo of a whiteboard, printed manual, or book page. The app reads the image and highlights the exact spot where the answer was found.

Here is what will **unlock when you update to iOS 27 & macOS 17** (supporting the new WWDC26 Apple Intelligence APIs):

*   **System-Wide Search (Spotlight integration)**:
    *   *After*: Spotlight will index actual text passages inside your files. You will be able to search for specific facts directly from your device's main system search bar (Spotlight), without even opening the app.
*   **Voice Control (Siri App Entities)**:
    *   *After*: Siri will understand what files you have. You will be able to ask Siri to "summarize this folder of files" or "compare these two documents" using voice commands.
*   **Secure Cloud Scaling (Private Cloud Compute)**:
    *   *After*: Standard queries run on-device. Complex reasoning will securely route to Apple's Private Cloud Compute enclaves, keeping your data completely private.

Everything is free, private, and open source:
https://github.com/Gunnarguy/OpenIntelligence

---

## 2. Technical Post (LinkedIn)

I build OpenIntelligence, a free and open-source application built for Apple Silicon (Mac, iPad, and iPhone) that lets you search and ask questions about your PDFs, manuals, and notes with verified, source-locked citations. Everything runs privately on your device.

I recently released v4.1 on the App Store. This release refactors the app's document Q&A pipeline (162 files, 14,000+ lines of Swift changed) to run vector search on the GPU today, while staging support for the WWDC26 Apple Intelligence APIs.

Here is the "Before vs. After" of the architecture:

**Live Today in v4.1 (for all iOS 26 / macOS 16 users):**
*   **Vector Retrieval**:
    *   *Before*: Slow, CPU-bound search that was too slow for large local libraries.
    *   *After*: Custom Metal compute shaders running cosine similarity (GPU-accelerated search). Retrieval is 4x faster, running directly on the graphics chip.
*   **Text Ingestion**:
    *   *Before*: Running visual scans (OCR) on every page, introducing text extraction errors.
    *   *After*: The app automatically detects clean digital text to preserve 100% accuracy, only running visual scanning on actual photos or scanned pages.

**Ready for iOS 27 / macOS 17 (Leveraging WWDC26 APIs on upcoming OS releases):**
*   **System Search (Spotlight Passage Indexing)**:
    *   *After*: Leveraging the new search indexing APIs, Spotlight will index specific text passages, letting you search your document library directly from the main system search bar.
*   **Siri Integration (App Entities)**:
    *   *After*: Mapped document libraries to native App Entities introduced at WWDC26, letting users ask Siri to summarize or compare files using voice or Shortcuts.
*   **Model Routing (Private Cloud Compute)**:
    *   *After*: Complex reasoning tasks will route securely to Apple's Private Cloud Compute enclaves, giving users the power of a large cloud model with the privacy of local hardware.

Check out the code:
https://github.com/Gunnarguy/OpenIntelligence

#AppleSilicon #MetalGPU #Swift #SwiftUI #AppleIntelligence #OpenSource #PrivacyFirst #WWDC26

---

## 3. X Thread: Rebuilding Local Document Q&A for Apple Silicon

1/ I build OpenIntelligence: a free, open-source app built specifically for Apple Silicon (Mac, iPad, and iPhone) that lets you ask questions about your documents (PDFs, manuals, notes) and get answers with verified, clickable links to the exact source.

Today I released v4.1 on the App Store! It features a complete rewrite (162 files, 14,000+ lines changed) to deliver GPU search speedups today and stage support for the new WWDC26 Apple Intelligence APIs.

Here is how the app is evolving: 👇

2/ **Live Today in v4.1 (iOS 26 / macOS 16): Metal GPU Search**
*   *Before*: Slow searches that drained battery and warmed up your device.
*   *After*: Custom Metal GPU shaders. Searching is 4x faster on-device, saving battery and allowing deeper local search.

3/ **Live Today in v4.1: Avoiding Typos (Smart PDF Scanning)**
*   *Before*: Reading files visually (OCR) on every page, which led to scanning errors.
*   *After*: The app checks if a page is digital first (preserving 100% text accuracy) and only scans if it's a photo or handwritten note.

4/ **Live Today in v4.1: Snap a Picture of Text**
*   *Before*: Limited to reading digital PDFs and text files.
*   *After*: Scan a whiteboard or paper page. The app reads the image and highlights the exact spot where the answer is.

5/ **Ready for iOS 27 / macOS 17: Searching from the Home Screen (Spotlight)**
*   *After*: Spotlight will index actual passages, letting you find specific answers on Mac, iPad, or iPhone directly from your system search bar without opening the app.

6/ **Ready for iOS 27 / macOS 17: Voice Control with Siri (App Entities)**
*   *After*: Documents and libraries are native App Entities. Siri will be able to search, compare, or summarize files using voice commands.

7/ **Ready for iOS 27 / macOS 17: Privacy-First Cloud Computing (Private Cloud Compute)**
*   *After*: Simple queries run entirely on-device. Complex queries will scale to secure Private Cloud Compute servers, processed privately and immediately deleted.

8/ Rebuilt from the ground up for Apple Silicon. Try v4.1 on the App Store today!
Code: https://github.com/Gunnarguy/OpenIntelligence

#AppleIntelligence #AppleSilicon #macOS #iOS #SwiftUI #OpenSource #MetalGPU #PrivacyFirst #WWDC26

---

## 4. Hook/Short Post

Most AI document readers are simple wrappers. But the new Apple Intelligence APIs announced at WWDC26 allow for something much better.

Today, v4.1 of OpenIntelligence is live on the App Store! It moves search to the GPU for 4x faster speeds on Apple Silicon (Mac, iPad, and iPhone) and prepares the codebase for the upcoming iOS 27 / macOS 17 Apple Intelligence updates:

**Available today in v4.1 (iOS 26 / macOS 16):**
*   **GPU Speed**: Search runs on your graphics chip (GPU), making it 4x faster and saving battery.
*   **Smart Scan**: Auto-detects clean digital text to prevent typos, only scanning scanned pages or photos.

**Coming next in iOS 27 / macOS 17 (WWDC26 APIs):**
*   **Spotlight**: Search inside your documents directly from your device's main search bar.
*   **Siri**: Ask Siri to compare files or summarize folders with voice commands.
*   **Privacy**: Complex tasks scale securely to Apple's Private Cloud Compute. No data is saved or tracked.

It's free, private, and open source:
https://github.com/Gunnarguy/OpenIntelligence
