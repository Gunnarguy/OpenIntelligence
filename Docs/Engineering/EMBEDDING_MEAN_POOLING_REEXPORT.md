# Re-exporting the Core AI embedding model with mean pooling

**Status: DONE 2026-08-18, code-verified, not yet benchmarked.** The export, the Swift mask and the
model artifact all landed. What remains is verification steps 2-4 below, which need a device or a
benchmark run — see "What is still unverified" at the end.

The rest of this document is kept as written, because the reasoning is why the fix looks the way it
does and a future reader deserves the argument rather than the conclusion.

Written to be executable by someone with no memory of the session that found it.

---

## What "pooling" means, in plain terms

An embedding model reads a chunk of text and produces one number per token, per dimension. A 200-token
chunk produces 200 vectors. But the app needs **one** vector for the whole chunk, so those 200 have to
be collapsed into 1. That collapsing step is called **pooling**, and there is more than one way to do
it:

- **Mean pooling** averages all the token vectors together. Every word contributes.
- **CLS pooling** throws away all of them except the first, a special marker token called `[CLS]`
  that BERT-style models put at position 0.

Neither is "correct" in general. What matters is **which one the model was trained with**, because
training is what teaches a position to carry meaning.

`sentence-transformers/all-MiniLM-L6-v2` is trained with **mean pooling**. Its own model card says so,
and this app's own Settings copy says so: *"Produces 384-dimensional vectors via mean-pooling."*

**The Core AI export takes the CLS token instead.** It is reading a position the model was never
trained to make meaningful, then using that as the entire representation of the chunk. That is the
defect.

## Why it went unnoticed

The vectors it produces are not garbage. They are 384-dimensional, normalised, and stable, so every
integrity check passes and nothing crashes. They simply encode much less about the text than they
should, which shows up only as poor retrieval, which looks like "the embedder is weak".

## The evidence

Same weights, same corpus, same 25 QASPER cases. Only the pooling differs:

| | `vector r@1` |
| --- | --- |
| Core AI, CLS token (`cmp-standard`, `tokfix`) | **0.000** |
| Core ML, mean pooling (`coreml-provider`) | **0.500** at n=4 |

`BenchmarkRuns/LEDGER.md` carries the full table. **Confirm the final number before acting**, since
n=4 is early; the run was still going when this was written.

## Why this is urgent beyond quality

`EmbeddingService.swift` routes by OS version:

```swift
if #available(iOS 27.0, macOS 27.0, *) {
    provider = CoreAISentenceEmbeddingProvider   // CLS token, wrong
} else {
    // comment calls this "falling back to CoreML"
    provider = CoreMLSentenceEmbeddingProvider   // mean pooling, correct
}
```

**Newer OS gets the worse path**, and the correct one is labelled the fallback. Upgrading degrades
retrieval.

## The fix

**Do not** solve this by routing iOS 27 to Core ML. The owner was explicit: iOS/macOS 27 must keep
Apple's newest framework. Fix the export so it is both.

Edit `scripts/compile_core_ai_model.py`. Current wrapper:

```python
class MiniLMEmbeddingWrapper(torch.nn.Module):
    def forward(self, input_ids):
        outputs = self.backbone(input_ids=input_ids)
        embeddings = outputs.last_hidden_state[:, 0, :]      # CLS token
        return {"embeddings": embeddings}

example_input = torch.ones((1, 512), dtype=torch.int32)
exported_program = torch.export.export(model, (example_input,))
```

Replace with mean pooling over a real attention mask:

```python
class MiniLMEmbeddingWrapper(torch.nn.Module):
    def forward(self, input_ids, attention_mask):
        outputs = self.backbone(input_ids=input_ids, attention_mask=attention_mask)
        hidden = outputs.last_hidden_state                    # [1, 512, 384]
        mask = attention_mask.unsqueeze(-1).to(hidden.dtype)  # [1, 512, 1]
        summed = (hidden * mask).sum(dim=1)                   # [1, 384]
        counts = mask.sum(dim=1).clamp(min=1e-9)              # avoid divide by zero
        return {"embeddings": summed / counts}

example_ids  = torch.ones((1, 512), dtype=torch.int32)
example_mask = torch.ones((1, 512), dtype=torch.int32)
exported_program = torch.export.export(model, (example_ids, example_mask))
```

Two changes: accept `attention_mask`, and average over real tokens instead of taking position 0. The
mask matters because the provider pads every input to 512; without it the average is diluted by up to
384 `[PAD]` vectors.

## The Swift side must pass the mask

`CoreAISentenceEmbeddingProvider` currently passes one input:

```swift
var outputs = try await encodeFunction.run(inputs: ["input_ids": inputTensor])
```

After re-export it must pass two. It already computes the pad length, so the mask is 1 for real tokens
and 0 for padding, the same shape as `input_ids`. `CoreMLSentenceEmbeddingProvider` around line 464
already does exactly this and is the reference implementation.

## Toolchain

Already installed, no downloading required. The owner is on a slow connection, so do not reinstall.

```
/private/tmp/oi-export-venv/bin/python
```

Contains torch 2.11.0, transformers 5.15.0, coreai-torch 0.4.1. Note the script pulls the MiniLM
weights from HuggingFace on first run, roughly 90MB, which is the only network cost.

## How to verify, in order

1. **The exported model declares two inputs.** Check `FeatureDescriptions.json` in the new package,
   or the protobuf, for `input_ids` **and** `attention_mask`.
2. **A short string and a long string embed differently.** If the mask is ignored the padding
   dominates and short inputs converge toward each other.
3. **Cosine similarity against the Core ML provider on identical text should be very high**, since
   both should now compute the same thing from the same weights. If they disagree, the pooling still
   differs.
4. **Re-run the 25-case benchmark** and compare `vector r@1` against `BenchmarkRuns/coreml-provider`.
   Correct Core AI should match correct Core ML, not merely beat CLS.

```bash
python3 scripts/run_quality_matrix.py \
  --app <built app> --manifest Benchmarks/ResearchFixtures/qasper_external_v1/manifest.json \
  --modes standard --pcc deny --pool-limit 10 --reset-shared-library --timeout 1500 --limit 25 \
  --sampling topk --seed 42 --temperature 0.7 \
  --embedding-provider coreai_sentence_embedding \
  --output-dir BenchmarkRuns/coreai-meanpool
```

Attach `scripts/watch_benchmark_defects.sh` to it. Never run a build or the test suite while a
benchmark is measuring: doing so once cost a 25 minute misdiagnosis.

## After it works

**Every existing library must be re-embedded**, because stored vectors were produced by CLS pooling
and new ones will not be comparable.

**Superseded 2026-08-18: the app now detects this.** `EmbeddingFingerprint` (commit `3b48c88`) hashes
the tokenizer bytes, the pooling recipe and the model revision, and `CoreAISentenceEmbeddingProvider`
now declares `mean-attention-masked/l2` and `MiniLM-L6-v2/coreai-mlirb-meanpool`, so the fingerprint
moves and the mismatch fires. The response is deliberately a **flag, not a wipe**: old vectors are
stale rather than incompatible, so the library keeps working and surfaces the rebuild banner instead
of going offline. The paragraph below was written when none of that existed:

> Nothing in the app detects this: `KnowledgeContainer` persists
only `embeddingProviderId` and `embeddingDim`, and neither changes. See the Notion row *"Existing
libraries keep truncated vectors because nothing detects the embedding change"*, which also lists the
eight display sites that a provider-id bump would break.

The owner's own library is 15 documents; deleting and re-importing is faster and safer than shipping
a migration.

## What must not be done first

**Do not benchmark bge-small-en-v1.5 or any replacement embedder until this is fixed.** Every
`vector` number recorded before this date came from the CLS path. Comparing a candidate against a
misconfigured incumbent would make the candidate look better than it is and would repeat the exact
confound this arc spent a day removing.

`[evidence_level: measured, confidence: high_for_mechanism, confirm_final_numbers_in_LEDGER]`

---

## What is still unverified (added 2026-08-18)

Verification step 1 passed and is conclusive: `strings` on the new `main.mlirb` lists `input_ids`,
`attention_mask` and `embeddings`, where the previous committed artifact listed only `input_ids` and
`embeddings`. The graph takes the mask.

Step 3 now has a test, `OpenIntelligenceTests/EmbeddingProviderAgreementTests`, which embeds the same
text with both providers and asserts cosine > 0.99, plus a second case asserting two unrelated short
texts stay apart (the signature of padding dominating the mean is that they converge).

**It skips in the simulator, and cannot be made to run there.** `CoreAISentenceEmbeddingProvider`
resolves its model resource at line 78 and sets `isModelLoadingFailed` when that lookup fails, before
any load is attempted; `isAvailable` is `!isModelLoadingFailed`. The device log shows the other side:
`Created .aimodel symlink`, `Loaded Core AI model successfully`, `available: true`. The tokenizer
loads in both places; the model only loads on hardware.

So this is a device test:

```bash
xcodebuild test -scheme OpenIntelligence \
  -destination 'platform=iOS,id=<device-udid>' \
  -only-testing:OpenIntelligenceTests/EmbeddingProviderAgreementTests
```

A skip means unverified, not fine.

Steps 2, 3 and 4 have **not** been done:

- A short string and a long string embedding differently.
- Cosine similarity against `CoreMLSentenceEmbeddingProvider` on identical text being very high.
  This is the strongest available check, because both providers should now compute the same thing
  from the same weights. If they disagree, the pooling still differs.
- The 25-case benchmark, comparing `vector r@1` against `BenchmarkRuns/coreml-provider`. Correct
  Core AI should **match** correct Core ML, not merely beat CLS.

Until step 3 or 4 runs, the claim is "the graph accepts a mask and the app passes one", not "the
vectors are right". Those are different claims and only the second one is the fix.

`[evidence_level: code_verified+artifact_verified, confidence: exact_for_the_graph_shape, vectors_unverified]`
