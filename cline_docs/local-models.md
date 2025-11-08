# Local Models Setup Guide (MLX, llama.cpp, Ollama)

This guide explains how to run local LLMs on macOS and iOS and connect them to OpenIntelligence. On macOS we use a unified OpenAI-compatible client; on iOS we provide an in-app embedded GGUF (llama.cpp) option.

OpenIntelligence supports local backends:
- MLX (Apple Silicon native, via mlx-lm server) [macOS]
- llama.cpp (GGUF models; HTTP server mode) [macOS]
- Ollama (model runtime with OpenAI-compatible endpoints) [macOS]
- GGUF Local (embedded llama.cpp runtime; in-app, no HTTP) [iOS]

All three speak OpenAI-style /v1/chat/completions and are handled by our LocalOpenAIServerLLMService with optional SSE streaming.

---

## 1) MLX (mlx-lm) — Recommended for Apple Silicon

Prerequisites:
- Python 3.10+
- Apple Silicon Mac (M1 or later)

Install:
```bash
pip install mlx-lm
```

Download a model (example):
```bash
python -m mlx_lm.download qwen2.5-7b-instruct
```

Run the server (default port 17860):
```bash
python -m mlx_lm.server --model qwen2.5-7b-instruct --port 17860
```

OpenIntelligence configuration:
- Settings → AI Model → "MLX Local (macOS)"
- Optionally adjust:
  - Base URL: http://127.0.0.1:17860
  - Model: local-mlx-model (or the server's actual model name if required)
  - Streaming: toggle SSE (if supported by the server)
- Click "Test Connection" to verify reachability
- Click "Apply Settings"

Notes:
- No data leaves your Mac.
- If "Test Connection" fails, ensure the server is running and reachable.

---

## 2) llama.cpp

Prerequisites:
- Build llama.cpp server binary (see llama.cpp docs)
- GGUF model file

Run the server (example defaults):
```bash
./server -m ./models/your-model.gguf -c 8192 -ngl 99 -a 127.0.0.1 -p 8080
```

OpenIntelligence configuration:
- Settings → AI Model → "llama.cpp Local (macOS)"
- Defaults:
  - Base URL: http://127.0.0.1:8080
  - Streaming: Enabled by default
- Apply and chat

Notes:
- Some builds expose GET /health or /v1/models; our health check will fall back to probing the base URL if needed.

---

## 3) Ollama

Install and run:
```bash
brew install ollama
ollama serve
```

Pull and run a model (example):
```bash
ollama pull llama3.1
```

OpenIntelligence configuration:
- Settings → AI Model → "Ollama Local (macOS)"
- Defaults:
  - Base URL: http://127.0.0.1:11434
  - Streaming: Enabled by default
- Apply and chat

Notes:
- Many Ollama builds expose OpenAI-compatible APIs under /v1; our client uses /v1/chat/completions.

---

## iOS: GGUF Local (On-Device)

Prerequisites:
- iPhone 16 Pro/Pro Max or later recommended
- A small quantized .gguf model (e.g., Gemma 2B, Qwen 1.8B–3B, 4-bit)

Setup:
1. Open Settings → AI Model → select "GGUF Local (iOS)".
2. In the "GGUF Model" section, tap "Select .gguf File" and choose your model from Files. The app copies it to Documents/Models.
3. Tap "Apply Settings".

Diagnostics:
- Go to Developer & Diagnostics → Backend Health → "GGUF Local (iOS)".
- Tap "Verify Model File" to ensure the path is valid.
- Tap "Run Smoke Test" to confirm wiring.
  - Note: the current backend is a stub that echoes and confirms configuration until the embedded llama.cpp runtime is added.

Notes:
- Recommended models for iPhone 16 Pro Max: Gemma 2B or Qwen 1.8–3B (quantized, e.g., 4-bit).
- Streaming and tokenizer integration will arrive with the embedded llama.cpp runtime.

## Health Diagnostics

Use Developer & Diagnostics → Backend Health to:
- Verify the active backend
- Check Apple FM availability and reasons if unavailable
- Test local server connectivity (MLX/llama.cpp/Ollama)

---

## Troubleshooting

- If streaming seems stuck:
  - Disable "Streaming (SSE)" and try again (some servers have partial SSE support).
- If the model answers but Settings shows "unavailable":
  - Use Backend Health to test connectivity and verify base URL/ports.
- If OpenIntelligence reports "Embedding dimension mismatch":
  - You changed embedding provider/dimensions. Use the container’s re-embed workflow (coming UI) or create a new container with the desired dimensions, then re‑ingest documents.

---

## Security and Privacy

- MLX/llama.cpp/Ollama modes keep data on your machine by default.
- OpenIntelligence will show execution badges and telemetry (model used, TTFT, tokens/sec) in the chat surfaces as available.

---

## Advanced Configuration (Developers)

- Under the hood, MLX/llama.cpp/Ollama presets wrap LocalOpenAIServerLLMService:
  - Config(baseURL, model, path=/v1/chat/completions, stream, headers?)
  - SSE streaming supported where servers emit OpenAI-style delta tokens
- You can add new OpenAI-compatible servers by instantiating LocalOpenAIServerLLMService with a custom baseURL and path.

---

## Hugging Face Model Downloads (macOS + iOS)

You can browse and download models directly from Hugging Face.

Flow:
1) Open the app → RAG Intelligence → Model Gallery card → Add from Hugging Face
2) Enter owner/repo (e.g., TheBloke/Qwen2.5-7B-Instruct-GGUF) and optional revision (default: main)
3) Tap “List Files” to fetch repo files
4) Pick a .gguf file (Core ML .mlpackage/.zip support is in progress)
5) Tap “Download” to start a background download (pause/resume, ETA, Wi‑Fi-only respected)
6) After install completes, the model appears in “Installed Models” and can be made active (GGUF on iOS; Core ML coming soon)

Gated models (token):
- Some repos require accepting a license or a token.
- Go to Settings → Models & Downloads and paste your Hugging Face token (optional).
- If listing or downloading fails with 403, accept the license on the model page and try again.

Checksum verification:
- When the file’s LFS metadata provides sha256, the app verifies the downloaded file before installing. If verification fails, the file is discarded and you can retry.

Background/resume details:
- Downloads use a background URLSession for resilience across app restarts.
- Wi‑Fi-only preference is respected (Settings → Models & Downloads).
- Progress shows percent, bytes/sec (smoothed), and ETA; you can Pause/Resume or Cancel.

### Using hf:// entries in your JSON catalog

Catalog JSON can include Hugging Face targets using the hf:// scheme. Format:
- hf://owner/repo[:revision]/path/to/file.gguf

Example entry:
```json
{
  "name": "Qwen2.5 7B Instruct (Q4_K_M, GGUF)",
  "backend": "gguf",
  "url": "hf://TheBloke/Qwen2.5-7B-Instruct-GGUF:main/Qwen2.5-7B-Instruct-Q4_K_M.gguf",
  "sizeBytes": 4068472320,
  "checksumSHA256": "optional_sha256_hex",
  "vendor": "Hugging Face",
  "quantization": "Q4_K_M",
  "filename": "Qwen2.5-7B-Instruct-Q4_K_M.gguf"
}
```

Notes:
- If revision is omitted, main is used.
- checksumSHA256 is optional; when present, it will be verified after download.
- filename lets you control the installed file name in Documents/Models.
