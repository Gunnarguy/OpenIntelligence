# Social Media Post Templates: OpenIntelligence v4.0 & v4.1

Announce the combined v4.0 & v4.1 Apple Intelligence release across X, Threads, and LinkedIn. 

Project Link: https://github.com/Gunnarguy/OpenIntelligence

---

## 1. Best Default Post (Universal Launch Post)

I build OpenIntelligence: a free, open-source app built specifically for Apple Silicon (Mac, iPad, and iPhone) that lets you search and ask questions about your documents (PDFs, manuals, notes) and get answers with verified, clickable links to the exact source page. Everything runs privately on your device.

When Apple announced their new Apple Intelligence integrations at WWDC26, I knew I had to rebuild my app to support them. Today I'm releasing v4.0 & v4.1—a complete rewrite (14,000+ lines of Swift changed) that connects the app's document search directly to system-level features like Spotlight search and Siri voice commands on macOS, iPadOS, and iOS.

Here is the Before vs. After of what has changed in this update:

*   **System-Wide Search (Spotlight)**:
    *   *Before*: You could only find files by typing their exact name.
    *   *After*: Your Apple Silicon device now indexes the actual text passages inside your files. You can search for specific facts directly from your device's main system search bar (Spotlight), without even opening the app.
*   **Voice & System Control (Siri)**:
    *   *Before*: Siri could only open the app.
    *   *After*: Siri understands what files you have. You can ask Siri to "summarize this folder of files" or "compare these two documents" using voice commands.
*   **Local Privacy + Secure Cloud (Private Cloud Compute)**:
    *   *Before*: You had to choose between slow private searches on your device or sending your data to servers where you don't control it.
    *   *After*: Standard questions are answered entirely on your device. For huge files or complex tasks, the app securely routes them to Apple's Private Cloud Compute servers where they are processed privately and immediately deleted. Your files stay 100% private.
*   **Finding Answers (GPU Speed)**:
    *   *Before*: Searching through massive documents was slow and drained your battery.
    *   *After*: I moved the search math directly to the device's graphics chip (GPU). Finding answers is now 4x faster without heating up your Mac, iPad, or iPhone.
*   **Camera & Image Q&A**:
    *   *Before*: Limited to typed document files.
    *   *After*: You can scan a printed page or whiteboard. The app reads the image and highlights the exact spot where the answer was found.
*   **Fewer Typos (Smart PDF Scanning)**:
    *   *Before*: Reading digital PDFs often introduced typos because the app treated clean digital text as if it were a photo.
    *   *After*: The app automatically detects clean digital text first (preserving 100% accuracy) and only scans pages that are photos or handwriting.

Everything is free, private, and open source:
https://github.com/Gunnarguy/OpenIntelligence

---

## 2. Technical Post (LinkedIn)

I build OpenIntelligence, a free and open-source application built for Apple Silicon (Mac, iPad, and iPhone) that lets you search and ask questions about your PDFs, manuals, and notes with verified, source-locked citations. Everything runs privately on your device.

WWDC26 completely changed the game for on-device AI. The moment Apple announced their new system-wide integration APIs, I set out to rewrite the app's entire document Q&A pipeline (162 files, 14,000+ lines of Swift changed) to support them.

Instead of keeping the app isolated, I integrated its document search directly with native system search and Siri voice control on macOS, iPadOS, and iOS using the new WWDC26 APIs.

Here is the "Before vs. After" of the architecture:

*   **System Search (Spotlight Passage Indexing)**:
    *   *Before*: Spotlight search only indexed filenames.
    *   *After*: Leveraging the new search indexing APIs, Spotlight now indexes specific text passages, letting you search your document library directly from the main system search bar.
*   **Siri Integration (App Entities)**:
    *   *Before*: Siri could only open the app.
    *   *After*: Mapped document libraries to native App Entities introduced at WWDC26, letting users ask Siri to summarize or compare files using voice or Shortcuts.
*   **Model Routing (Private Cloud Compute)**:
    *   *Before*: Locked to a strict on-device model with a tight context limit.
    *   *After*: Standard tasks run on-device. Complex reasoning routes securely to Apple's Private Cloud Compute enclaves, giving users the power of a large cloud model with the privacy of local hardware.
*   **Vector Retrieval**:
    *   *Before*: Slow, CPU-bound search that was too slow for large local libraries.
    *   *After*: Custom Metal compute shaders running cosine similarity (GPU-accelerated search). Retrieval is 4x faster, running directly on the graphics chip.
*   **Text Ingestion**:
    *   *Before*: Running visual scans (OCR) on every page, introducing text extraction errors.
    *   *After*: The app automatically detects clean digital text to preserve 100% accuracy, only running visual scanning on actual photos or scanned pages.

The result is a local, private document AI app that behaves like a native system feature across all Apple Silicon devices.

Check out the code:
https://github.com/Gunnarguy/OpenIntelligence

#AppleSilicon #M4 #A18Pro #macOS #iOS #SwiftUI #AppleIntelligence #OpenSource #MetalGPU #PrivacyFirst #WWDC26

---

## 3. X Thread: Rebuilding Local Document Q&A for Apple Silicon

1/ I build OpenIntelligence: a free, open-source app built specifically for Apple Silicon (Mac, iPad, and iPhone) that lets you ask questions about your documents (PDFs, manuals, notes) and get answers with verified, clickable links to the exact source.

When Apple announced the new Apple Intelligence system integrations at WWDC26, I decided to completely rewrite the app (162 files, 14,000+ lines changed) to leverage these new platform APIs.

Here is the Before vs. After of what has changed: 👇

2/ **Searching from the Home Screen (Spotlight Integration)**
*   *Before*: You could only find files by typing their names in system search.
*   *After*: Spotlight indexes actual passages, letting you find specific answers on Mac, iPad, or iPhone without even opening the app.

3/ **Voice Control with Siri (App Entities)**
*   *Before*: Siri could only open the app.
*   *After*: Documents and libraries are native App Entities. Siri can search, compare, or summarize files using voice commands.

4/ **Privacy-First Cloud Computing (Private Cloud Compute)**
*   *Before*: Stuck with a small, slow on-device AI model for large files.
*   *After*: Simple queries run entirely on-device. Complex queries scale to secure Private Cloud Compute servers. Your data is processed privately and immediately deleted—never saved or used for training.

5/ **Using the Graphics Chip (GPU) for Search**
*   *Before*: Slow searches that drained battery and warmed up your device.
*   *After*: Custom Metal GPU shaders. Searching is 4x faster on-device, saving battery and allowing deeper local search.

6/ **Snap a Picture of Text**
*   *Before*: Limited to reading digital PDFs and text files.
*   *After*: Scan a whiteboard or paper page. The app reads the image and highlights the exact spot where the answer is.

7/ **Avoiding Typos (Smart PDF Scanning)**
*   *Before*: Reading files visually (OCR) on every page, which led to scanning errors.
*   *After*: The app checks if a page is digital first (preserving 100% text accuracy) and only scans if it's a photo or handwritten note.

8/ Privacy-first, open-source, and faster. Rebuilt from the ground up to support the new WWDC26 Apple Intelligence capabilities across the Apple Silicon ecosystem. Check out the code here:
https://github.com/Gunnarguy/OpenIntelligence

#AppleIntelligence #AppleSilicon #macOS #iOS #SwiftUI #OpenSource #MetalGPU #PrivacyFirst #WWDC26

---

## 4. Hook/Short Post

Most AI document readers are simple wrappers. But the new Apple Intelligence APIs announced at WWDC26 allow for something much better.

For OpenIntelligence v4.0 & v4.1, I rebuilt the app to support the new WWDC26 platform features across Apple Silicon (Mac, iPad, and iPhone):

*   **Spotlight (System Search)**: Search inside your documents directly from your device's main search bar.
*   **Siri**: Ask Siri to compare files or summarize folders with voice commands.
*   **Privacy**: Standard tasks run locally on-device. Large tasks scale securely to Apple's Private Cloud Compute. No data is saved or tracked.
*   **Speed**: Search runs on your graphics chip (GPU), making it 4x faster and saving battery.
*   **Smart Scan**: Auto-detects clean digital text to prevent typos, only scanning scanned pages or photos.

It's free, private, and open source:
https://github.com/Gunnarguy/OpenIntelligence
