#!/usr/bin/env python3
"""Build the app's reranker, OpenIntelligence/Resources/MLModels/ReRankerModel.mlpackage, and its tokenizer.

The reranker is IBM's granite-embedding-reranker-english-r2 (Apache 2.0; IBM's model card says its training data
leaves out MS MARCO because of MS MARCO's non-commercial licence). It replaced cross-encoder/ms-marco-TinyBERT-L2-v2
on 2026-11-09; the measurements are in BenchmarkRuns/2026-11-09-reranker-swap/.

What this writes:
  ReRankerModel.mlpackage   one Core ML ML program with two functions, `len256` and `len512` (fixed shapes: a fixed
                            shape is what the Neural Engine runs; enumerated shapes were planned onto the CPU),
                            weights palettized to 4 bits (k-means, a 16-entry table per group of 16 output
                            channels), compute in float16. 75 MB, under GitHub's 100 MB file limit; on 246 QASPER
                            questions it ranked as the 8-bit version did (48.4% top 5 for both, 2 better and 2
                            worse), and 4-bit per-block linear quantization fell off the Neural Engine. Inputs
                            `input_ids` and `attention_mask` ([1, L] int32), output `logits` ([1, 1], the raw
                            relevance logit; the app min-max normalises a batch of them, as it did the old model's).
  reranker_tokenizer.bundle/tokenizer.json
                            the model's own tokenizer, with its baked-in truncation and padding removed so the app's
                            code decides both.

Then it checks the Core ML functions against the untouched Hugging Face model on fixed pairs, and prints the token ids
the app's tokenizer test pins.

Run with a Python that has coremltools 9.0, torch 2.15, transformers 5.22.2, tokenizers 0.23 (the versions it was
built with on 2026-11-09):
    python scripts/build_reranker_model.py --out-model <dir> --out-tokenizer <dir>
Defaults write into the repository.
"""
import argparse
import json
import shutil
import sys
import tempfile
from pathlib import Path

import numpy as np
import torch
import coremltools as ct
import coremltools.optimize.coreml as cto
from coremltools.converters.mil import Builder as mb
from coremltools.converters.mil.frontend.torch.torch_op_registry import register_torch_op
from coremltools.converters.mil.frontend.torch.ops import _get_inputs
import coremltools.converters.mil.frontend.torch.ops as _ops
from huggingface_hub import snapshot_download
from transformers import AutoModelForSequenceClassification, AutoTokenizer

MODEL_ID = "ibm-granite/granite-embedding-reranker-english-r2"
REVISION = "d09d3d6971b689bf9c23839e45a470874d46e13a"
SHAPES = (256, 512)
ROOT = Path(__file__).resolve().parent.parent

# Pairs whose scores and token ids are checked here and pinned by RerankerModelTests.
PAIRS = [
    ("How many days notice ends the lease?",
     "Either party may terminate this lease with sixty (60) days written notice to the other party, delivered by certified mail."),
    ("What was the retention time of benzo[a]pyrene?",
     "Table 1 lists retention times for the sixteen PAHs; benzo[a]pyrene eluted at 37.24 min under the gradient described in Section 2.3."),
    ("What is the engine oil capacity?",
     "The kitchen was renovated in 2019 with quartz counters and a new range hood."),
]


# Two converter gaps in coremltools 9.0 with torch 2.15, both hit by ModernBERT.
@register_torch_op(override=False)
def new_ones(context, node):
    inputs = _get_inputs(context, node)
    size = inputs[1]
    if size.val is not None and np.size(size.val) == 0:
        context.add(mb.const(val=np.float32(1.0), name=node.name))
        return
    context.add(mb.fill(shape=mb.cast(x=size, dtype="int32"), value=1.0, name=node.name))


_orig_cast = _ops._cast


def _cast_one_element(context, node, dtype, dtype_name):
    # ModernBERT calls int() on a one-element constant; coremltools accepts only a 0-d one there.
    x = _ops._get_inputs(context, node, expected=1)[0]
    if x.val is not None and np.size(x.val) == 1 and np.ndim(x.val) > 0:
        context.add(mb.const(val=dtype(np.asarray(x.val).reshape(()).item()), name=node.name))
        return
    return _orig_cast(context, node, dtype, dtype_name)


_ops._cast = _cast_one_element


class Wrap(torch.nn.Module):
    """ModernBERT's layers and CLS head, with both attention masks built here from the 0/1 mask: global for every
    third layer, and within +-64 tokens for the rest. transformers' own mask code does not convert."""

    def __init__(self, m):
        super().__init__()
        self.m = m
        self.cfg = m.config

    def forward(self, input_ids, attention_mask):
        base, cfg = self.m.model, self.cfg
        keep = attention_mask[:, None, None, :].to(torch.float32)
        glob = (1.0 - keep) * -10000.0
        idx = torch.arange(input_ids.shape[1])
        band = ((idx[None, :] - idx[:, None]).abs() <= cfg.local_attention // 2).to(torch.float32)[None, None]
        loc = glob + (1.0 - band) * -10000.0
        pos = idx[None, :]
        h = base.embeddings(input_ids=input_ids)
        for i, layer in enumerate(base.layers):
            is_global = i % cfg.global_attn_every_n_layers == 0
            try:
                pe = base.rotary_emb(h, pos, layer_type="full_attention" if is_global else "sliding_attention")
            except TypeError:
                pe = base.rotary_emb(h, pos)
            o = layer(h, attention_mask=glob if is_global else loc, position_embeddings=pe)
            h = o[0] if isinstance(o, tuple) else o
        h = base.final_norm(h)
        return self.m.classifier(self.m.drop(self.m.head(h[:, 0])))


def encode(tok, q, d, length):
    e = tok(q, d, truncation=True, max_length=length, padding="max_length", return_tensors="np")
    return e["input_ids"].astype(np.int32), e["attention_mask"].astype(np.int32)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-model", default=str(ROOT / "OpenIntelligence/Resources/MLModels"))
    ap.add_argument("--out-tokenizer", default=str(
        ROOT / "OpenIntelligence/swift-transformers/Sources/TokenizersWrapper/Resources/reranker_tokenizer.bundle"))
    a = ap.parse_args()

    src = Path(snapshot_download(MODEL_ID, revision=REVISION))
    tok = AutoTokenizer.from_pretrained(src)
    ref = AutoModelForSequenceClassification.from_pretrained(
        src, dtype=torch.float32, attn_implementation="eager").eval()
    wrap = Wrap(ref).eval()

    with torch.no_grad():
        for L in SHAPES:
            ids, am = encode(tok, [p[0] for p in PAIRS], [p[1] for p in PAIRS], L)
            hf = ref(input_ids=torch.tensor(ids).long(), attention_mask=torch.tensor(am).long()).logits[:, 0].numpy()
            mine = wrap(torch.tensor(ids), torch.tensor(am))[:, 0].numpy()
            if not np.allclose(hf, mine, atol=1e-3):
                sys.exit(f"the wrapper differs from the model at length {L}: {hf} vs {mine}")
            print(f"length {L}: Hugging Face logits {np.round(hf, 3)}, wrapper {np.round(mine, 3)}")

    work = Path(tempfile.mkdtemp(prefix="reranker-build-"))
    parts = {}
    for L in SHAPES:
        ex = (torch.ones(1, L, dtype=torch.int32), torch.ones(1, L, dtype=torch.int32))
        with torch.no_grad():
            traced = torch.jit.trace(wrap, ex, strict=False)
        mlm = ct.convert(
            traced,
            inputs=[ct.TensorType(name="input_ids", shape=(1, L), dtype=np.int32),
                    ct.TensorType(name="attention_mask", shape=(1, L), dtype=np.int32)],
            outputs=[ct.TensorType(name="logits")],
            convert_to="mlprogram",
            compute_precision=ct.precision.FLOAT16,
            minimum_deployment_target=ct.target.iOS18,
        )
        cfg = cto.OptimizationConfig(global_config=cto.OpPalettizerConfig(
            mode="kmeans", nbits=4, granularity="per_grouped_channel", group_size=16))
        q = cto.palettize_weights(mlm, config=cfg)
        parts[L] = work / f"len{L}.mlpackage"
        q.save(str(parts[L]))

    desc = ct.utils.MultiFunctionDescriptor()
    for L in SHAPES:
        desc.add_function(str(parts[L]), src_function_name="main", target_function_name=f"len{L}")
    desc.default_function_name = f"len{SHAPES[-1]}"
    out_model = Path(a.out_model) / "ReRankerModel.mlpackage"
    staged = work / "ReRankerModel.mlpackage"
    ct.utils.save_multifunction(desc, str(staged))

    # Check every function against the Hugging Face model on the fixed pairs.
    worst = 0.0
    with torch.no_grad():
        for L in SHAPES:
            fn = ct.models.MLModel(str(staged), function_name=f"len{L}", compute_units=ct.ComputeUnit.CPU_AND_NE)
            for q_, d_ in PAIRS:
                ids, am = encode(tok, q_, d_, L)
                hf = float(ref(input_ids=torch.tensor(ids).long(), attention_mask=torch.tensor(am).long()).logits[0, 0])
                cm = float(np.asarray(fn.predict({"input_ids": ids, "attention_mask": am})["logits"]).reshape(-1)[0])
                worst = max(worst, abs(hf - cm))
                print(f"len{L}: Hugging Face {hf:+.3f}  Core ML {cm:+.3f}")
    size = sum(f.stat().st_size for f in staged.rglob("*") if f.is_file())
    print(f"package {size / 1e6:.1f} MB, largest file {max(f.stat().st_size for f in staged.rglob('*') if f.is_file()) / 1e6:.1f} MB")
    if max(f.stat().st_size for f in staged.rglob("*") if f.is_file()) >= 100 * 1024 * 1024:
        sys.exit("a file in the package is over GitHub's 100 MiB limit; not writing anything")
    if worst > 0.25:
        sys.exit(f"Core ML differs from the model by {worst:.3f} logits; not writing anything")

    if out_model.exists():
        shutil.rmtree(out_model)
    shutil.copytree(staged, out_model)
    print(f"wrote {out_model}")

    out_tok = Path(a.out_tokenizer)
    out_tok.mkdir(parents=True, exist_ok=True)
    tj = json.loads((src / "tokenizer.json").read_text())
    tj["truncation"] = None
    tj["padding"] = None
    (out_tok / "tokenizer.json").write_text(json.dumps(tj, ensure_ascii=False))
    print(f"wrote {out_tok / 'tokenizer.json'}")

    for q_, d_ in PAIRS:
        print("ids", json.dumps(tok(q_, d_)["input_ids"]))
    shutil.rmtree(work)


if __name__ == "__main__":
    main()
