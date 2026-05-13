# Core ML, Metal, and On-Device AI Research

**Updated**: April 24, 2026
**Use in this repo**: Supports the current local embedding, vector search, OCR preprocessing, and Apple Silicon optimization story.

## Primary Sources

| Area | Source | Why It Matters for OpenIntelligence |
| --- | --- | --- |
| Core ML model loading/config | [MLModelConfiguration](https://developer.apple.com/documentation/coreml/mlmodelconfiguration) | Controls model parameters and compute-device choices. |
| Compute unit selection | [MLComputeUnits](https://developer.apple.com/documentation/coreml/mlcomputeunits) | Supports choosing CPU, GPU, Neural Engine, or combinations for model execution. |
| Metal Performance Shaders | [Metal Performance Shaders](https://developer.apple.com/documentation/metalperformanceshaders) | Apple's optimized GPU compute and ML kernels. |
| MPSGraph | [Metal Performance Shaders Graph](https://developer.apple.com/documentation/metalperformanceshadersgraph) | Higher-level compute graphs across GPU/CPU/Neural Engine. |
| Accelerate | [Accelerate](https://developer.apple.com/documentation/accelerate) | CPU vector math and signal-processing foundation for efficient local compute. |
| BNNS | [BNNS](https://developer.apple.com/documentation/accelerate/bnns) | Neural-network routines under Accelerate. |
| Core ML Tools compression | [coremltools palettization](https://apple.github.io/coremltools/source/coremltools.optimize.torch.palettization.html) | Relevant to future model-size reduction and adapter/model packaging. |
| Apple 2025 model report | [Apple Intelligence Foundation Language Models Tech Report 2025](https://machinelearning.apple.com/research/apple-foundation-models-tech-report-2025) | Apple-specific evidence for quantization-aware training and on-device model optimization. |

## Repo Mapping

- `EmbeddingService.swift` selects Core ML/Natural Language embedding providers and changes compute behavior during ingestion so Vision OCR can use the Neural Engine.
- `BNNSVectorDatabase.swift` persists memory-mapped Float32 vectors and uses Accelerate/vDSP for smaller searches.
- `BNNSVectorDatabase.swift` routes large searches through Metal compute when available.
- `DocumentProcessor.swift` uses a Metal-backed Core Image context for PDF rendering and OCR preprocessing.
- `GPUComputeService.swift` and visualization services support Apple Silicon telemetry and dynamic shader behavior.

## What This Supports In The Current Repo

The app can credibly claim Apple-native acceleration:

- OCR preprocessing uses GPU-backed image operations.
- Embeddings and vector search are local.
- Vector storage is memory-mapped to reduce heap pressure.
- The app is designed to avoid third-party inference infrastructure for core flows.

## Caution

Do not imply the app trains or fine-tunes Apple's Foundation Models today unless adapter tooling is explicitly implemented, licensed, packaged, and tested. Core ML model compression is a future packaging/tooling direction, not an automatic feature of the current engine.
