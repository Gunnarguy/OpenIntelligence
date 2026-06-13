# Social Media Post Templates: OpenIntelligence v4.0 & v4.1

Announce the combined v4.0 & v4.1 Apple Intelligence release across X, Threads, and LinkedIn. 

Project Link: https://github.com/Gunnarguy/OpenIntelligence

---

## 1. Best Default Post (Universal Launch Post)

I build OpenIntelligence: a free, open-source iPhone app that lets you search and ask questions about your documents (PDFs, manuals, notes) and get answers with verified, clickable links to the exact source. 

Today I released v4.0 & v4.1. Across 162 files and 14,000+ lines of Swift changed, I completely rebuilt the app so that it integrates directly into your iPhone's operating system, rather than just being a separate app you have to open.

Here is the Before vs. After of how it makes finding facts in your documents better:

*   **Finding Answers (GPU Speed)**:
    *   *Before*: Searching through massive documents was slow and drained your phone's battery.
    *   *After*: I moved the search math directly to the phone's graphics chip (GPU). Finding answers is now 4x faster without warming up your phone.
*   **Home Screen Search (Spotlight)**:
    *   *Before*: You could only find files by typing their exact name.
    *   *After*: Your iPhone now indexes the actual text passages inside your files. You can search for specific facts directly from your iPhone's main home screen search bar, without even opening the app.
*   **Local Privacy + Secure Cloud**:
    *   *Before*: You had to choose between slow private searches on your phone or sending your data to servers where you don't control it.
    *   *After*: Standard questions are answered entirely on your device. For huge files or complex tasks, the app securely routes them to Apple's Private Cloud Compute servers where they are processed privately and immediately deleted. Your files stay 100% private.
*   **Siri Integration**:
    *   *Before*: Siri could only open the app.
    *   *After*: Siri understands what files you have. You can ask Siri to "summarize this folder of files" or "compare these two documents" using voice commands.
*   **Camera & Image Q&A**:
    *   *Before*: Limited to typed document files.
    *   *After*: You can snap a photo of a whiteboard, printed manual, or book page. The app reads the image and highlights the exact spot where the answer was found.
*   **Fewer Typos (Smart PDF Scanning)**:
    *   *Before*: Reading digital PDFs often introduced typos because the app treated clean digital text as if it were a photo.
    *   *After*: The app automatically detects clean digital text first (preserving 100% accuracy) and only scans pages that are photos or handwriting.

Everything is free, private, and open source:
https://github.com/Gunnarguy/OpenIntelligence

---

## 2. Technical Post (LinkedIn)

I build OpenIntelligence, a free and open-source iOS application that lets you search and ask questions about your PDFs, manuals, and notes with verified, source-locked citations. Everything runs privately on your device.

For the v4.0 & v4.1 release, I spent the last few weeks completely refactoring the app's document Q&A pipeline (162 files, 14,000+ lines of Swift changed) to run as a native Apple Intelligence evidence system.

Instead of writing another standalone app that sits on top of files, I integrated directly into the operating system.

Here is the "Before vs. After" of the architecture:

*   **Vector Retrieval**:
    *   *Before*: Slow, CPU-bound search that was too slow for large local libraries.
    *   *After*: Custom Metal compute shaders running cosine similarity (GPU-accelerated search). Retrieval is 4x faster, running directly on the graphics chip.
*   **System Search**:
    *   *Before*: Spotlight search only indexed filenames.
    *   *After*: Spotlight indexes specific text passages, letting you search your document library directly from the iOS main search bar.
*   **Siri Integration**:
    *   *Before*: Siri could only open the app.
    *   *After*: Mapped document libraries to native App Entities, letting users ask Siri to summarize or compare files using voice or Shortcuts.
*   **Model Routing**:
    *   *Before*: Locked to a strict on-device model with a tight context limit.
    *   *After*: Standard tasks run on-device. Complex reasoning routes securely to Apple's Private Cloud Compute enclaves, keeping your files completely private.
*   **Text Ingestion**:
    *   *Before*: Running visual scans (OCR) on every page, introducing text extraction errors.
    *   *After*: The app automatically detects clean digital text to preserve 100% accuracy, only running visual scanning on actual photos or scanned pages.

The result is a local, private document AI app that behaves like a native system feature.

Check out the code:
https://github.com/Gunnarguy/OpenIntelligence

#iOSDevelopment #Swift #SwiftUI #AppleIntelligence #OpenSource #MetalGPU #PrivacyFirst

---

## 3. X Thread: Rebuilding Local Document Q&A for Apple Silicon

1/ I build OpenIntelligence: a free, open-source iOS app that lets you ask questions about your documents (PDFs, manuals, notes) and get answers with verified, clickable links to the exact source.

I just released v4.0 & v4.1. I completely rebuilt the app (162 files, 14,000+ lines changed) to transition it into an Apple Intelligence-native system.

Here is the Before vs. After of how it works: 👇

2/ **Using the Graphics Chip (GPU) for Search**
*   *Before*: Slow searches that drained battery and warmed up your phone.
*   *After*: Custom Metal GPU shaders. Searching is 4x faster on-device, saving battery and allowing deeper local search.

3/ **Searching from the Home Screen**
*   *Before*: You could only find files by their names in iOS Spotlight search.
*   *After*: Spotlight indexes actual passages, letting you find specific answers without even opening the app.

4/ **Voice Control with Siri**
*   *Before*: Siri could only open the app.
*   *After*: Documents and libraries are native App Entities. Siri can search, compare, or summarize files using voice commands.

5/ **Snap a Picture of Text**
*   *Before*: Limited to reading digital PDFs and text files.
*   *After*: Take a photo of a whiteboard or paper page. The app reads the image and highlights the exact spot where the answer is.

6/ **Avoiding Typos (Smart PDF Scanning)**
*   *Before*: Reading files visually (OCR) on every page, which led to scanning errors.
*   *After*: The app checks if a page is digital first (preserving 100% text accuracy) and only scans if it's a photo or handwritten note.

7/ **Privacy-First Cloud Computing**
*   *Before*: Stuck with a small, slow on-device AI model for large files.
*   *After*: Simple queries run entirely on-device. Complex queries scale to secure Private Cloud Compute servers. Your data is processed privately and immediately deleted—never saved or used for training.

8/ Privacy-first, open-source, and faster. Check out the code here:
https://github.com/Gunnarguy/OpenIntelligence

#AppleIntelligence #SwiftUI #OpenSource #iOSDev #MetalGPU #PrivacyFirst

---

## 4. Hook/Short Post

Most AI document readers are simple wrappers. If you have to open the app every time you want to find a passage, wait for slow searches, or deal with typos from bad scans, the experience falls apart.

For OpenIntelligence v4.0 & v4.1, I rebuilt the app to integrate directly into the iPhone:

*   **Spotlight**: Search inside your documents directly from the iPhone home screen search bar.
*   **Speed**: Search runs on your graphics chip (GPU), making it 4x faster and saving battery.
*   **Siri**: Ask Siri to compare files or summarize folders with voice commands.
*   **Smart Scan**: Auto-detects clean digital text to prevent typos, only scanning scanned pages or photos.
*   **Privacy**: Standard tasks run locally on-device. Large tasks scale securely to Apple's Private Cloud Compute. No data is saved or tracked.

It's free, private, and open source:
https://github.com/Gunnarguy/OpenIntelligence
