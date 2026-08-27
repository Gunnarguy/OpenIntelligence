> **Documentation status:** Historical reference. This document may describe earlier implementation plans or deprecated architecture. Do not use as the source of truth for OpenIntelligence v4.1.

# Apple Intelligence Foundation Language Models — Tech Report 2025

> **Source**: [arXiv:2507.13575v3](https://arxiv.org/abs/2507.13575) (August 2025)
> **Apple Research**: [machinelearning.apple.com/research/apple-foundation-models-tech-report-2025](https://machinelearning.apple.com/research/apple-foundation-models-tech-report-2025)
> **Last Verified**: April 24, 2026

**DO NOT deviate from these facts. This is what Apple actually shipped.**

## April 2026 Repo Grounding

This report describes Apple's model family. It does not mean OpenIntelligence has direct app access to every model or context window described in the paper.

Current app-safe interpretation:

- Public app generation uses Apple's Foundation Models framework where available.
- The repo budgets `LanguageModelSession` work at 4096 tokens.
- The server/PCC model is platform context, not a direct OpenIntelligence server-model dependency.
- Foundation Models are used for generation, guided output, and tool calling; current embeddings are Core ML/Natural Language based.
- The shipped architecture should be described as retrieval-first, not long-context-first.

See also:

- [Apple Intelligence and Foundation Models Research](../Research/APPLE_INTELLIGENCE_AND_FOUNDATION_MODELS.md)
- [Private Cloud Compute](./PRIVATE_CLOUD_COMPUTE.md)
- [Hard Limits](./HARD_LIMITS.md)

---

## Table of Contents

1. [Two Models, Not One](#two-models-not-one)
2. [On-Device Model (~3B)](#on-device-model-3b)
3. [Server Model (PT-MoE)](#server-model-pt-moe)
4. [Vision Encoders](#vision-encoders)
5. [Context Windows](#context-windows)
6. [Compression & Quantization](#compression--quantization)
7. [Foundation Models Framework](#foundation-models-framework)
8. [Training Data](#training-data)
9. [Benchmark Performance](#benchmark-performance)
10. [What the Model IS and IS NOT](#what-the-model-is-and-is-not)

---

## Two Models, Not One

Apple Intelligence runs **two separate foundation models**:

| Property        | On-Device                               | Server (PCC)                               |
| --------------- | --------------------------------------- | ------------------------------------------ |
| Parameters      | ~3B                                     | Undisclosed (large MoE)                    |
| Architecture    | Dense transformer with KV-cache sharing | PT-MoE (Parallel-Track Mixture-of-Experts) |
| Compression     | 2-bit QAT                               | 3.56-bit ASTC                              |
| KV cache        | 8-bit quantized                         | 8-bit quantized                            |
| Embedding table | 4-bit (QAT joint training)              | 4-bit (post-training)                      |
| Runs on         | Apple Silicon (iPhone, iPad, Mac)       | Private Cloud Compute                      |
| Context window  | **4096 tokens** (TN3193)                | Trained on up to **65K tokens**            |
| Vision backbone | ViTDet-L (300M params)                  | ViT-g (1B params)                          |
| Tokenizer vocab | 150K tokens                             | 150K tokens                                |
| Languages       | 16                                      | 16                                         |

**The Foundation Models framework exposes ONLY the on-device ~3B model to third-party developers.**

The server model is used exclusively by Apple's own features via PCC. Direct access to PT-MoE is not available.


---

## On-Device Model (~3B)

### Architecture: KV-Cache Sharing

The on-device model is split into **two blocks** at a 5:3 depth ratio:

- **Block 1** (62.5% of layers): Standard transformer, generates KV caches
- **Block 2** (37.5% of layers): **No key/value projections** — shares KV cache from Block 1

This means:

- KV cache memory reduced by **37.5%**
- Block 2 is bypassed during prefill → TTFT (time-to-first-token) reduced by **~37.5%**

### Training Pipeline

1. Trained dense ~3B model for ~14T tokens
2. Sparse-upcycled a **64-expert MoE teacher** from a pre-trained ~3B model using 1T high-quality data
3. Retrained the dense model for the last **10% of tokens (~1.4T)** using distillation loss from the MoE teacher
4. Teacher training cost reduced by **90%**

### Compression to 2-bit

- **Quantization-Aware Training (QAT)** — not post-training quantization
- Learnable clipping factor `f` per weight tensor
- Balanced 2-bit set: `{-1.5, -0.5, 0.5, 1.5}` (smoother than `{-2, -1, 0, 1}`)
- AdamW optimizer (more stable than Adafactor at low-bit)
- Exponential Moving Average (EMA) of weights for stability
- Weight decay = 0 (to use full quantization range)
- LoRA recovery adapters applied after compression

### Image Resolution Modes (On-Device)

| Mode     | Resolution                      | Image Tokens  | Use Case                              |
| -------- | ------------------------------- | ------------- | ------------------------------------- |
| High-res | 1344×1344 (2×2 tile + overview) | 5 × 144 = 720 | Text-rich images, detailed analysis   |
| Balanced | 672×672 (overview only)         | 144           | General image understanding           |
| Rapid    | 224×224                         | 9             | High-level understanding, low latency |

---

## Server Model (PT-MoE)

### Architecture: Parallel-Track Mixture-of-Experts

This is **NOT** a standard MoE. It's a novel architecture with three innovations:

#### 1. Parallel Tracks

The model is partitioned into **multiple smaller transformers** (tracks). Each track consists of stacked "track blocks." Tracks process tokens **independently** — synchronization happens only at track block boundaries.

- Reduces synchronization overhead from `2L` (tensor parallelism) to `L/D` (track parallelism)
- With `D=4`: **87.5% reduction** in synchronization overhead

#### 2. Mixture-of-Experts within Tracks

Every other transformer layer replaces the dense FFN with an MoE layer. Experts are **local to their track** — no cross-track expert routing.

- Top-k routing via grouped GEMM
- Zero token dropping
- Increased sparsity → lower latency at scale

#### 3. Interleaved Global/Local Attention

Repeating pattern within each transformer block:

- **3 local attention layers** with sliding window of **4096** + RoPE positional embeddings
- **1 global attention layer** with **NoPE** (no positional embeddings)

Benefits:

- Better length generalization (no out-of-distribution position issues for long contexts)
- Reduced KV cache size
- Model quality maintained

### Training

- Trained on **8192 v5p Cloud TPU** accelerators (4 × 2048 chip slices) using AXLearn framework
- **13.4T text tokens** with track parallelism crossing no slice boundary
- 93% good output (fault tolerance)
- Compressed to **3.56 bpw** using ASTC (Adaptive Scalable Texture Compression)

### ASTC Compression (Server Only)

- Originally a GPU graphics texture compression format
- Uses fixed-function hardware decompression on Apple GPUs → **zero compute overhead**
- 6×6 blocks (36 weights per block) → 128-bit ASTC values → 3.56 bpw
- HDR-ch mode with min-value subtraction per block
- LoRA adapters recover quality post-compression
- Before ASTC: most significant singular vectors pulled into LoRA adapter; ASTC compresses residuals

---

## Vision Encoders

### On-Device: RW-ViTDet-L (300M params)

- ViTDet with window attention + 3 cross-window global attention layers
- Novel **Register-Window (RW)** mechanism: global register token interacts with local windows before global aggregation
- CLIP contrastive pre-training on 6B+ image-text pairs at 448×448
- Joint training with adaptor module at 672×672
- Vision-language adaptor: transformer layer + linear projection + 3×3 conv → average pooling → 144 fixed image tokens

### Server: ViT-g (1B params)

- Standard Vision Transformer at 1B parameters
- CLIP contrastive pre-training on 6B+ image-text pairs at 448×448
- Joint training with adaptor module
- FLIP masking strategy for training efficiency

---

## Context Windows

### On-Device (Limits)

| Constraint                   | Value                        | Source                  |
| ---------------------------- | ---------------------------- | ----------------------- |
| Hard context limit           | **4096 tokens**              | TN3193                  |
| Token ≈ characters (English) | ~3-4 chars/token             | TN3193                  |
| Token ≈ characters (CJK)     | ~1 char/token                | TN3193                  |
| Max practical characters     | ~14,336 (English)            | Derived                 |
| RAG context budget           | ~5,500 chars / ~1,500 tokens | Architecture constraint |

### Server Training Context

The server model was trained on sequences up to **65K tokens** in the context-lengthening stage. However:

- **Third-party developers have NO access to the server model's context window**
- The server model serves Apple's own features via PCC
- Only the 4096-token on-device model is exposed through the Foundation Models framework


### What Eats Tokens

Everything in a `LanguageModelSession` counts:

- Instructions
- All prior prompts (multi-turn)
- All prior responses
- Tool schemas (names, descriptions, parameter types)
- `@Generable` type schemas
- `@Guide` descriptions
- Tool call inputs and outputs

---

## Compression & Quantization Summary

| Component        | On-Device                    | Server (PCC)                  |
| ---------------- | ---------------------------- | ----------------------------- |
| Decoder weights  | 2-bpw via QAT                | 3.56-bpw via ASTC             |
| Embedding table  | 4-bit via QAT                | 4-bit post-training           |
| KV cache         | 8-bit                        | 8-bit                         |
| Quality recovery | LoRA adapters                | LoRA adapters (SVD-informed)  |
| MMLU impact      | -4.6% regression (67.8→64.4) | -2.3% regression              |
| IFEval impact    | -2.8% regression (85.1→82.3) | +1.1% improvement (89.1→90.2) |

---

## Foundation Models Framework

### What It Provides

- Access to the **~3B on-device model ONLY**
- **Guided generation** (`@Generable` macro → constrained decoding)
- **Tool calling** (`Tool` protocol → guaranteed structural correctness)
- **LanguageModelSession** (append-only, stateful, KV-cache-coupled)
- **Streaming** via snapshots
- **LoRA adapter training** (rank-32, Python toolkit)
- **Speculative decoding** (optional draft model training)
- Xcode playground, profiler, simulator support

### What It Is Designed For

Per Apple:

> "The ~3B language foundation model excels at a diverse range of text tasks like summarization, entity extraction, text understanding, refinement, short dialog, generating creative content, and more."

### What It Is NOT

Per Apple:

> "It is not designed to be a chatbot for general world knowledge."

### Critical Constraints

| Constraint            | Value                                                |
| --------------------- | ---------------------------------------------------- |
| Max tools per session | 3-5 recommended                                      |
| Max response tokens   | Configurable but risky (can truncate)                |
| Adapter rank          | 32 (fixed)                                           |
| Adapter compatibility | **Per base model version** — must retrain on updates |
| Background Assets     | Required for adapter distribution                    |

---

## Training Data

### Text Data

- Hundreds of billions of web pages via Applebot
- Licensed publisher data
- Open-source datasets
- Enhanced with headless rendering, JavaScript execution
- LLM-powered content extraction for complex pages
- Model-based filtering (replaced aggressive heuristic rules)
- Extended from 100K to **150K vocabulary tokenizer** for multilingual

### Image Data

- **10B+** image-text pairs (web crawl + alt-text filtering)
- **175M** interleaved image-text documents (550M+ images)
- **294M** public interleaved image-text images
- **5B+** synthetic image-caption pairs (multi-detail-level captioning)
- Text-rich data: PDFs, infographics, tables, charts, manuscripts
- High-quality domain-specific: science, healthcare, specialized fields
- **15 languages** for multilingual OCR

### Post-Training

- Supervised Fine-Tuning (SFT): human demonstrations + synthetic data
- RLHF via RLOO (REINFORCE Leave-One-Out)
- Distributed asynchronous RL infrastructure
- Diverse reward signals: reward model, ground truth verification, code execution, LLM-as-judge
- Novel prompt selection: cohesion-based neighborhood search
- Multilingual data in both SFT and RLHF (80:20 English:multilingual ratio)
- RLHF → 16:9 win/loss over SFT alone

---

## Benchmark Performance

### On-Device vs Competitors

| Model             | MMLU      | MMMLU     | MGSM      |
| ----------------- | --------- | --------- | --------- |
| **AFM On-Device** | **67.85** | **60.60** | 74.91     |
| Qwen-2.5-3B       | 66.37     | 56.53     | 64.80     |
| Qwen-3-4B         | 75.10     | 66.52     | 82.97     |
| Gemma-3-4B        | 62.81     | 56.71     | 74.74     |
| Gemma-3n-E4B      | 57.84     | 50.93     | **77.77** |

The on-device model **beats Qwen-2.5-3B** across the board, is **competitive with 4B models**, but **lags Qwen-3-4B**.

### Server vs Competitors

| Model          | MMLU  | MMMLU | MGSM  |
| -------------- | ----- | ----- | ----- |
| **AFM Server** | 80.20 | 74.60 | 87.09 |
| LLaMA 4 Scout  | 84.88 | 80.24 | 90.34 |
| Qwen-3-235B    | 87.52 | 82.95 | 92.00 |
| GPT-4o         | 85.70 | 84.00 | 90.30 |

Server model is **behind** LLaMA 4 Scout, Qwen-3-235B, and GPT-4o on all benchmarks.

### Post-Compression Quality (Realized Performance)

| Model                 | MMLU (compressed) | IFEval (compressed) |
| --------------------- | ----------------- | ------------------- |
| AFM On-Device (2-bit) | 64.4              | 82.3                |
| AFM Server (3.56-bit) | 79.2              | 90.2                |

---

## What the Model IS and IS NOT

### IS (Designed For)

- Summarization
- Entity extraction
- Text understanding and classification
- Text refinement/rewriting
- Short dialog
- Creative content generation
- Tool calling (structured output)
- Guided generation (constrained decoding)
- Image understanding (3 resolution modes)
- Multilingual OCR (15 languages)

### IS NOT (Do Not Expect)

- General-purpose chatbot
- World knowledge oracle
- Long-context reasoning (4096 token limit)
- Multi-hop reasoning across many documents (token budget too small)
- Code generation at GPT-4 level (competitive with 3B class, not 70B+)
- Cloud API endpoint (no direct server model access)

---

## Implications for OpenIntelligence

### What This Means for the RAG Pipeline

1. **4096 tokens is the hard ceiling** — every prompt, instruction, tool schema, context chunk, and response must fit. There is no escape hatch.

2. **The on-device model is ~3B parameters at 2-bit quantization** — it's good at extraction, summarization, classification. It is NOT good at complex multi-hop reasoning, creative synthesis across many sources, or deep analytical thinking.

3. **Direct access to PT-MoE is not available** — the server model with its 65K context window and higher quality is Apple-internal only. The entire pipeline runs through the ~3B on-device model.

4. **Full GraphRAG with LLM-powered entity resolution and triple extraction is not a shipped claim** — those operations require evaluated entity extraction, relationship extraction, clustering, and community summaries. The current app uses graph-lite context packing, deterministic entities, and RAPTOR-lite summaries.

5. **The existing pipeline is correctly architected** — semantic chunking + vector search + BM25 hybrid + context packing into ~5500 chars is the correct approach for a 4096-token model. The multi-session agentic approach (3-50 sessions) matches Apple's recommendations for complex tasks.

6. **NLTagger NER + PascalCase entity extraction is appropriate** — using the OS-level NER (which is fast and free) instead of burning LLM tokens on entity extraction is the right call.

7. **Tool calling is limited** — Apple recommends 3-5 tools max. The current project has 12+. This requires optimization.


---

## References

- [arXiv:2507.13575v3 — Apple Intelligence Foundation Language Models Tech Report 2025](https://arxiv.org/abs/2507.13575)
- [Apple ML Research Blog — Updates to Foundation Models](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)
- [TN3193 — Managing the on-device foundation model's context window](https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Private Cloud Compute](https://security.apple.com/blog/private-cloud-compute/)
- [Foundation Models Framework](https://developer.apple.com/documentation/foundationmodels)
