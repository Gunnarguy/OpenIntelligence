#!/usr/bin/env python3
"""Build the app's embedding model, OpenIntelligence/Resources/MLModels/EmbeddingModel.mlpackage, and its tokenizer.

The embedder is IBM's granite-embedding-small-english-r2 (Apache 2.0, 47M parameters, 384 dimensions; IBM's model card
says its training data leaves out MS MARCO because of MS MARCO's non-commercial licence). It replaces
sentence-transformers/all-MiniLM-L6-v2, whose card lists 9,144,553 MS MARCO training triplets (the owner's rule 1,
2026-11-12). On the Mac (2026-11-09, BenchmarkRuns/2026-11-09-reranker-swap) it put the answer's passage in the top 5 for
39.0% of 246 QASPER questions against MiniLM's 37.0%, MRR@10 +0.039 (p=0.006).

What this writes:
  EmbeddingModel.mlpackage   one Core ML ML program with two functions, `len256` and `len512` (fixed shapes, which the
                             Neural Engine runs), CLS pooling and L2 normalisation inside the graph, weights palettized
                             to --bits (k-means, per grouped channel), compute in float16. Inputs `input_ids` and
                             `attention_mask` ([1, L] int32), output `embedding` ([1, 384], unit length).
  embedding_tokenizer.bundle/tokenizer.json
                             the model's own tokenizer, with its baked-in truncation and padding removed so the app's
                             code decides both.

It checks every function against the untouched Hugging Face model (cosine of the vectors) on fixed texts and refuses
to write anything below --min-cosine. Same Python as scripts/build_reranker_model.py (coremltools 9.0, torch 2.15,
transformers 5.22.2, tokenizers 0.23):
    python scripts/build_embedding_model.py --out-model <dir> --out-tokenizer <dir>
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
from transformers import AutoModel, AutoTokenizer

MODEL_ID = "ibm-granite/granite-embedding-small-english-r2"
REVISION = "2ab6fa8ea2d674564defd37171ae19079b864b33"
SHAPES = (256, 512)
ROOT = Path(__file__).resolve().parent.parent

# Texts whose vectors are checked here. A question, a table row, a lease clause, a number-heavy line, a long passage.
TEXTS = [
    "How many days notice ends the lease?",
    "Either party may terminate this lease with sixty (60) days written notice to the other party, delivered by certified mail.",
    "Table 1 lists retention times for the sixteen PAHs; benzo[a]pyrene eluted at 37.24 min under the gradient described in Section 2.3.",
    "ROW 3: Sample C | FL (mg/kg): 0.08 | Pyr (mg/kg): 0.46",
    "The kitchen was renovated in 2019 with quartz counters and a new range hood.",
    "What is the engine oil capacity with filter change?",
    ("Mitochondrial membrane potential was measured with TMRM in non-quenching mode. Cells were loaded for 30 min at 37 C, "
     "washed twice, and imaged on a spinning-disk confocal microscope. The proton motive force comprises the electrical "
     "potential and the pH gradient; in E. coli the pH gradient contributes about -35 mV at neutral external pH, while "
     "the membrane potential contributes the larger share. ") * 6,
]


# Two converter gaps in coremltools 9.0 with torch 2.15, both hit by ModernBERT (as in build_reranker_model.py).
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
    x = _ops._get_inputs(context, node, expected=1)[0]
    if x.val is not None and np.size(x.val) == 1 and np.ndim(x.val) > 0:
        context.add(mb.const(val=dtype(np.asarray(x.val).reshape(()).item()), name=node.name))
        return
    return _orig_cast(context, node, dtype, dtype_name)


_ops._cast = _cast_one_element


class Wrap(torch.nn.Module):
    """ModernBERT's layers with both attention masks built here from the 0/1 mask (global every third layer, within
    +-64 tokens for the rest), then the CLS vector, L2-normalised: the model card's sentence-transformers pooling."""

    def __init__(self, m):
        super().__init__()
        self.m = m
        self.cfg = m.config

    def forward(self, input_ids, attention_mask):
        base, cfg = self.m, self.cfg
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
        cls = h[:, 0]
        return cls / torch.clamp(torch.linalg.vector_norm(cls, dim=-1, keepdim=True), min=1e-12)


def encode(tok, text, length):
    e = tok(text, truncation=True, max_length=length, padding="max_length", return_tensors="np")
    return e["input_ids"].astype(np.int32), e["attention_mask"].astype(np.int32)


def reference(ref, tok, text, length):
    ids, am = encode(tok, text, length)
    out = ref(input_ids=torch.tensor(ids).long(), attention_mask=torch.tensor(am).long()).last_hidden_state[:, 0]
    v = out[0].numpy()
    return v / np.linalg.norm(v)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-model", default=str(ROOT / "OpenIntelligence/Resources/MLModels"))
    ap.add_argument("--out-tokenizer", default=str(
        ROOT / "OpenIntelligence/swift-transformers/Sources/TokenizersWrapper/Resources/embedding_tokenizer.bundle"))
    ap.add_argument("--bits", type=int, default=8, choices=[4, 6, 8, 16])
    ap.add_argument("--min-cosine", type=float, default=0.995)
    a = ap.parse_args()

    src = Path(snapshot_download(MODEL_ID, revision=REVISION))
    tok = AutoTokenizer.from_pretrained(src)
    ref = AutoModel.from_pretrained(src, dtype=torch.float32, attn_implementation="eager").eval()
    wrap = Wrap(ref).eval()

    with torch.no_grad():
        for L in SHAPES:
            for t in TEXTS:
                ids, am = encode(tok, t, L)
                mine = wrap(torch.tensor(ids), torch.tensor(am))[0].numpy()
                c = float(np.dot(mine, reference(ref, tok, t, L)))
                if c < 0.9999:
                    sys.exit(f"the wrapper differs from the model at length {L}: cosine {c:.6f}")
        print("wrapper matches the Hugging Face model (cosine >= 0.9999 on every text)")

    work = Path(tempfile.mkdtemp(prefix="embedder-build-"))
    parts = {}
    for L in SHAPES:
        ex = (torch.ones(1, L, dtype=torch.int32), torch.ones(1, L, dtype=torch.int32))
        with torch.no_grad():
            traced = torch.jit.trace(wrap, ex, strict=False)
        mlm = ct.convert(
            traced,
            inputs=[ct.TensorType(name="input_ids", shape=(1, L), dtype=np.int32),
                    ct.TensorType(name="attention_mask", shape=(1, L), dtype=np.int32)],
            outputs=[ct.TensorType(name="embedding")],
            convert_to="mlprogram",
            compute_precision=ct.precision.FLOAT16,
            minimum_deployment_target=ct.target.iOS18,
        )
        if a.bits < 16:
            cfg = cto.OptimizationConfig(global_config=cto.OpPalettizerConfig(
                mode="kmeans", nbits=a.bits, granularity="per_grouped_channel", group_size=16))
            mlm = cto.palettize_weights(mlm, config=cfg)
        parts[L] = work / f"len{L}.mlpackage"
        mlm.save(str(parts[L]))

    desc = ct.utils.MultiFunctionDescriptor()
    for L in SHAPES:
        desc.add_function(str(parts[L]), src_function_name="main", target_function_name=f"len{L}")
    desc.default_function_name = f"len{SHAPES[-1]}"
    staged = work / "EmbeddingModel.mlpackage"
    ct.utils.save_multifunction(desc, str(staged))

    worst = 1.0
    with torch.no_grad():
        for L in SHAPES:
            fn = ct.models.MLModel(str(staged), function_name=f"len{L}", compute_units=ct.ComputeUnit.CPU_AND_NE)
            for t in TEXTS:
                ids, am = encode(tok, t, L)
                cm = np.asarray(fn.predict({"input_ids": ids, "attention_mask": am})["embedding"]).reshape(-1)
                c = float(np.dot(cm / np.linalg.norm(cm), reference(ref, tok, t, L)))
                worst = min(worst, c)
            print(f"len{L}: lowest cosine against Hugging Face so far {worst:.5f}")
    files = [f for f in staged.rglob("*") if f.is_file()]
    print(f"{a.bits}-bit package {sum(f.stat().st_size for f in files) / 1e6:.1f} MB, "
          f"largest file {max(f.stat().st_size for f in files) / 1e6:.1f} MB, lowest cosine {worst:.5f}")
    if max(f.stat().st_size for f in files) >= 100 * 1024 * 1024:
        sys.exit("a file in the package is over GitHub's 100 MiB limit; not writing anything")
    if worst < a.min_cosine:
        sys.exit(f"Core ML's vectors differ from the model's (lowest cosine {worst:.5f}); not writing anything")

    out_model = Path(a.out_model) / "EmbeddingModel.mlpackage"
    Path(a.out_model).mkdir(parents=True, exist_ok=True)
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
    for extra in ("tokenizer_config.json", "special_tokens_map.json"):
        if (src / extra).exists():
            shutil.copy(src / extra, out_tok / extra)
    print(f"wrote {out_tok / 'tokenizer.json'}")

    for t in TEXTS[:4]:
        print("ids", json.dumps(tok(t)["input_ids"]))
    shutil.rmtree(work)


if __name__ == "__main__":
    main()
