# iOS GGUF Local (Embedded llama.cpp) – Linking and Setup

This project already includes the UI, diagnostics, and runtime scaffolding for fully on‑device GGUF inference on iOS (no network). To enable actual inference, you must link the LocalLLMClient Swift package (vendored in this repo) to the app target so the `LlamaCPPiOSLLMService` can import and use it.

Follow these steps in Xcode (one-time per clone):

1) Add the vendored Swift package
   - Open RAGMLCore.xcodeproj in Xcode.
   - File → Add Packages…
   - Click “Add Local…”
   - Select the folder: Vendor/LocalLLMClient
   - Confirm platforms (iOS 16+, macOS 14+) and add the package.

2) Link required products to the app target
   - Select the “RAGMLCore” app target → General (or Frameworks, Libraries, and Embedded Content).
   - Click “+” and add these package products:
     - LocalLLMClient
     - LocalLLMClientLlama
   - Note:
     - LocalLLMClientLlama has an internal dependency on LocalLLMClientLlamaC (C++ / XCFramework). You don’t need to add it manually; Xcode links it automatically via the product.
     - You do not add “LocalLLMClientCore” directly (it’s an internal target, not a product).

3) Build for device
   - Select an iPhone device (not a Simulator) and Build.
   - The first build may take time while SPM fetches and integrates the `llama-…-xcframework` binary.

4) Import a small GGUF model
   - Run the app on device.
   - Settings → Model Downloads → Open Model Manager.
   - Use “Import GGUF” (or Hugging Face integration on macOS + AirDrop to device) to place a small `.gguf` file under Documents/Models on device.
   - Recommended sizes: 2–3B quantized (e.g., Q4_K), to fit iPhone memory.

5) Activate and test
   - Settings → Model Selection:
     - Set Local Primary → your GGUF model (Menu → Set Local Primary → GGUF Models → pick your model).
     - If the primary picker still shows “unavailable,” tap “Why Unavailable?” for remediation.
   - Developer & Diagnostics → Backend Health:
     - Under “GGUF Local (iOS)”, tap “Verify Model File”, then “Run Smoke Test” or “Benchmark”.
     - You should see TTFT (time to first token) and token/sec numbers if the runtime is linked and model is valid.

6) Runtime toggles and notes
   - The app’s UI surfaces “Why Unavailable?” explaining common gating issues:
     - “GGUF runtime not bundled” → ensure Step 1–2 are done.
     - “No model selected” → import a GGUF and set it active.
   - `LlamaCPPiOSLLMService` streams tokens and emits telemetry (TTFT, tokens/sec). Strict Mode is enforced upstream in the RAG pipeline.

Troubleshooting
- Build errors mentioning C++ interop or headers:
  - Clean build folder, then build for a real iOS device again.
  - Ensure the package products above are linked to the RAGMLCore app target.
- Out‑of‑memory / slow:
  - Try a smaller model (2–3B with 4‑bit quant).
  - Reduce context in Settings or let the RAG pipeline keep context small when using Apple FM as primary.
- Model won’t activate:
  - Verify the file path under Developer & Diagnostics → Backend Health → GGUF Local (iOS) → “Verify Model File”.

Security and privacy
- GGUF Local runs 100% on device (no network calls).
- Apple Intelligence remains the default pathway when available; you can switch to GGUF at any time. PCC is never used for GGUF.

Next steps (optional)
- Core ML LLM: Once a `.mlpackage` is available, you can select “Core ML Local” in the same picker. The service is scaffolded and will be wired for one small instruct model first.
- Larger models: For development on macOS, use MLX / llama.cpp / Ollama via the Local Server presets to iterate quickly.
