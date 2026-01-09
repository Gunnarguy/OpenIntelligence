#!/usr/bin/env python3
"""
convert_models.py

Downloads and converts two models to Core ML for the 'Native Intelligence' Architecture:
1. Embedding: sentence-transformers/all-MiniLM-L6-v2
2. Re-Ranking: cross-encoder/ms-marco-TinyBERT-L-2-v2

Exports .mlpackage files with FLOAT16 precision (ANE compatible) and their vocabularies.

Usage:
    pip install -r requirements_conversion.txt
    python3 convert_models.py
"""

import os
import json
import torch
import coremltools as ct
from transformers import AutoModel, AutoTokenizer, AutoModelForSequenceClassification

# Configuration
OUTPUT_DIR = "../Models/Resources"
MODELS = {
    "embedding": {
        "id": "sentence-transformers/all-MiniLM-L6-v2",
        "filename": "EmbeddingModel.mlpackage",
        "vocab_name": "embedding_vocab.json",
        "type": "feature_extraction",
        "description": "512-dim Sentence Embedding Model (MiniLM-L6-v2)",
    },
    "reranker": {
        "id": "cross-encoder/ms-marco-TinyBERT-L-2-v2",
        "filename": "ReRankerModel.mlpackage",
        "vocab_name": "reranker_vocab.json",
        "type": "classification",
        "description": "Cross-Encoder Re-Ranker (TinyBERT-L-2-v2)",
    },
}


def export_tokenizer_vocab(tokenizer, path):
    vocab = tokenizer.vocab
    with open(path, "w") as f:
        json.dump(vocab, f)
    print(f"   📖 Saved vocabulary to {path} ({len(vocab)} tokens)")


def convert_embedding_model(config):
    model_id = config["id"]
    print(f"\n🚀 Processing Embedding Model: {model_id}...")

    tokenizer = AutoTokenizer.from_pretrained(model_id)
    model = AutoModel.from_pretrained(model_id, torchscript=True)
    model.eval()

    # Export Vocab
    vocab_path = os.path.join(OUTPUT_DIR, config["vocab_name"])
    export_tokenizer_vocab(tokenizer, vocab_path)

    # Trace
    print("   ⚡️ Tracing...")
    dummy_input_ids = torch.randint(0, tokenizer.vocab_size, (1, 512))
    dummy_mask = torch.ones((1, 512))
    dummy_token_type = torch.zeros((1, 512))  # BERT uses token_type_ids

    traced_model = torch.jit.trace(
        model, (dummy_input_ids, dummy_mask, dummy_token_type)
    )

    # Convert
    print("   🔄 Converting to Core ML (Float16)...")
    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, 512), dtype=int),
            ct.TensorType(name="attention_mask", shape=(1, 512), dtype=int),
            ct.TensorType(name="token_type_ids", shape=(1, 512), dtype=int),
        ],
        outputs=[
            ct.TensorType(name="last_hidden_state"),
            ct.TensorType(name="pooler_output"),
        ],
        compute_units=ct.ComputeUnit.ALL,
        compute_precision=ct.precision.FLOAT16,  # Neural Engine Requirement
        minimum_deployment_target=ct.target.iOS17,
    )

    mlmodel.author = "OpenIntelligence"
    mlmodel.short_description = config["description"]
    mlmodel.save(os.path.join(OUTPUT_DIR, config["filename"]))
    print(f"   ✅ Saved {config['filename']}")


def convert_reranker_model(config):
    model_id = config["id"]
    print(f"\n🚀 Processing Re-Ranker Model: {model_id}...")

    tokenizer = AutoTokenizer.from_pretrained(model_id)
    model = AutoModelForSequenceClassification.from_pretrained(
        model_id, torchscript=True
    )
    model.eval()

    # Export Vocab
    vocab_path = os.path.join(OUTPUT_DIR, config["vocab_name"])
    export_tokenizer_vocab(tokenizer, vocab_path)

    # Trace
    print("   ⚡️ Tracing...")
    # Cross-encoders take pairs, so sequence length can be up to 512
    dummy_input_ids = torch.randint(0, tokenizer.vocab_size, (1, 512))
    dummy_mask = torch.ones((1, 512))
    dummy_token_type = torch.zeros((1, 512))

    traced_model = torch.jit.trace(
        model, (dummy_input_ids, dummy_mask, dummy_token_type)
    )

    # Convert
    print("   🔄 Converting to Core ML (Float16)...")
    mlmodel = ct.convert(
        traced_model,
        inputs=[
            ct.TensorType(name="input_ids", shape=(1, 512), dtype=int),
            ct.TensorType(name="attention_mask", shape=(1, 512), dtype=int),
            ct.TensorType(name="token_type_ids", shape=(1, 512), dtype=int),
        ],
        outputs=[ct.TensorType(name="logits")],  # Classification output
        compute_units=ct.ComputeUnit.ALL,
        compute_precision=ct.precision.FLOAT16,
        minimum_deployment_target=ct.target.iOS17,
    )

    mlmodel.author = "OpenIntelligence"
    mlmodel.short_description = config["description"]
    mlmodel.save(os.path.join(OUTPUT_DIR, config["filename"]))
    print(f"   ✅ Saved {config['filename']}")


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    # 1. Embedding Model
    convert_embedding_model(MODELS["embedding"])

    # 2. Re-Ranker Model
    convert_reranker_model(MODELS["reranker"])

    print("\n🎉 Conversion Complete!")
    print(f"Drag files from '{OUTPUT_DIR}' into Xcode.")


if __name__ == "__main__":
    main()
