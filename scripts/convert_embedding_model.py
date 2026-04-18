#!/usr/bin/env python3
"""
convert_embedding_model.py

Converts the on-device embedding and re-ranker models to Core ML (.mlpackage) with
Apple Neural Engine compatibility.

Models:
1) sentence-transformers/all-MiniLM-L6-v2  → EmbeddingModel.mlpackage
2) cross-encoder/ms-marco-TinyBERT-L2-v2 → ReRankerModel.mlpackage

Settings:
- compute_units=ct.ComputeUnit.ALL
- compute_precision=ct.precision.FLOAT16 (required for ANE)
- sequence length = 512

Usage:
    python -m venv .venv
    source .venv/bin/activate
    pip install -r scripts/requirements_conversion.txt
    python scripts/convert_embedding_model.py
"""

from __future__ import annotations

import json
from pathlib import Path
from typing import Tuple

import coremltools as ct
import torch
from transformers import (
    AutoModel,
    AutoModelForSequenceClassification,
    AutoTokenizer,
)

# Paths
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent
OUTPUT_DIR = REPO_ROOT / "OpenIntelligence" / "Resources" / "MLModels"
OUTPUT_DIR.mkdir(parents=True, exist_ok=True)

# Shared config
MAX_LEN = 512
DEPLOY_TARGET = ct.target.iOS17

EMBEDDING_CONFIG = {
    "model_id": "sentence-transformers/all-MiniLM-L6-v2",
    "mlpackage": "EmbeddingModel.mlpackage",
    "vocab": "embedding_vocab.json",
    "description": "384-dim sentence embeddings (MiniLM-L6-v2)",
}

RERANKER_CONFIG = {
    "model_id": "cross-encoder/ms-marco-TinyBERT-L2-v2",
    "mlpackage": "ReRankerModel.mlpackage",
    "vocab": "reranker_vocab.json",
    "description": "Cross-encoder reranker (TinyBERT-L2-v2)",
}


def _save_vocab(tokenizer, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8") as f:
        json.dump(tokenizer.vocab, f, ensure_ascii=False)
    print(f"   📖 Saved vocab → {path} ({len(tokenizer.vocab)} tokens)")


def _trace_inputs(tokenizer) -> Tuple[torch.Tensor, torch.Tensor, torch.Tensor]:
    input_ids = torch.randint(
        low=0, high=tokenizer.vocab_size, size=(1, MAX_LEN), dtype=torch.int64
    )
    attention_mask = torch.ones((1, MAX_LEN), dtype=torch.int64)
    token_type_ids = torch.zeros((1, MAX_LEN), dtype=torch.int64)
    return input_ids, attention_mask, token_type_ids


def convert_embedding() -> None:
    print(f"\n🚀 Converting embedding model: {EMBEDDING_CONFIG['model_id']}")
    tokenizer = AutoTokenizer.from_pretrained(EMBEDDING_CONFIG["model_id"])
    model = AutoModel.from_pretrained(EMBEDDING_CONFIG["model_id"], torchscript=True)
    model.eval()

    _save_vocab(tokenizer, OUTPUT_DIR / EMBEDDING_CONFIG["vocab"])

    sample_inputs = _trace_inputs(tokenizer)
    traced = torch.jit.trace(model, sample_inputs)

    print("   🔄 coremltools.convert (Float16, ANE)...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_LEN), dtype=int),
            ct.TensorType(name="attention_mask", shape=(1, MAX_LEN), dtype=int),
            ct.TensorType(name="token_type_ids", shape=(1, MAX_LEN), dtype=int),
        ],
        outputs=[
            ct.TensorType(name="last_hidden_state"),
            ct.TensorType(name="pooler_output"),
        ],
        compute_units=ct.ComputeUnit.ALL,
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=DEPLOY_TARGET,
    )

    mlmodel.author = "OpenIntelligence"
    mlmodel.short_description = EMBEDDING_CONFIG["description"]
    dest = OUTPUT_DIR / EMBEDDING_CONFIG["mlpackage"]
    mlmodel.save(dest)
    print(f"   ✅ Saved {dest}")


def convert_reranker() -> None:
    print(f"\n🚀 Converting reranker model: {RERANKER_CONFIG['model_id']}")
    tokenizer = AutoTokenizer.from_pretrained(RERANKER_CONFIG["model_id"])
    model = AutoModelForSequenceClassification.from_pretrained(
        RERANKER_CONFIG["model_id"], torchscript=True
    )
    model.eval()

    _save_vocab(tokenizer, OUTPUT_DIR / RERANKER_CONFIG["vocab"])

    sample_inputs = _trace_inputs(tokenizer)
    traced = torch.jit.trace(model, sample_inputs)

    print("   🔄 coremltools.convert (Float16, ANE)...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, MAX_LEN), dtype=int),
            ct.TensorType(name="attention_mask", shape=(1, MAX_LEN), dtype=int),
            ct.TensorType(name="token_type_ids", shape=(1, MAX_LEN), dtype=int),
        ],
        outputs=[ct.TensorType(name="logits")],
        compute_units=ct.ComputeUnit.ALL,
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=DEPLOY_TARGET,
    )

    mlmodel.author = "OpenIntelligence"
    mlmodel.short_description = RERANKER_CONFIG["description"]
    dest = OUTPUT_DIR / RERANKER_CONFIG["mlpackage"]
    mlmodel.save(dest)
    print(f"   ✅ Saved {dest}")


def main() -> None:
    torch.set_grad_enabled(False)
    convert_embedding()
    convert_reranker()
    print(
        "\n🎉 Conversion complete — add the .mlpackage files and vocab JSONs to the app bundle."
    )


if __name__ == "__main__":
    main()
