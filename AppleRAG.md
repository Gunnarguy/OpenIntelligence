# Expert Role
On‑device RAG systems architect (Core ML + TinyBERT), specializing in “any‑document” parsing, hybrid retrieval, reranking, extractive QA, and verification‑first answering.

## Objective
Give you a full‑blown, universal, bulletproof on‑device doc understanding stack that stays in Core ML + TinyBERT, but written in shorthand (dense spec, not a watered‑down version).

## Reasoning
A “universal” system that feels like it understands any PDF or doc is not one model. It’s a pipeline whose reliability comes from enforcing three things end‑to‑end:

P(\text{correct}) \approx P(\text{right evidence})\times P(\text{answer constrained to evidence})\times P(\text{verification catches slips})

With TinyBERT‑class models, your highest‑reliability “nuclear option” is:
	•	Best‑possible document representation (structure preserved: headings, tables, lists, figures, page/bbox)
	•	Hybrid retrieval (dense + lexical) so you don’t miss exact terms or conceptual paraphrases
	•	Cross‑encoder rerank to make the top evidence correct
	•	Extractive answering (span selection + extractive summarization) to avoid hallucinations
	•	Hard verification gates + iterative retrieval instead of guessing
	•	Measured calibration (thresholds derived from evals, not vibes)

## Answer

Universal On‑device Doc Intelligence (Core ML + TinyBERT)

0) Non‑negotiable invariants (this is what makes it “bulletproof”)
	•	Evidence‑only: every claim must cite evidence_ids from retrieved context.
	•	Extractive‑first: answers are spans/sentences copied from docs unless you can prove synthesis is safe.
	•	Abstain by default when confidence < threshold.
	•	Iterate retrieval up to N times before abstaining (query expansion, section hopping, table focus).
	•	Risk tiering: “touchy” queries get stricter thresholds + stricter quoting.

⸻

1) Canonical Document Model (CDM) (all file types become this)

Every ingested artifact becomes a set of nodes:

Node {
  node_id: String (stable)
  doc_id: String
  type: enum {heading, paragraph, list_item, table_row, table_cell, figure_caption, code_block, meta}
  text: String
  page: Int?
  bbox: (x1,y1,x2,y2)?        // if available
  section_path: [String]      // hierarchical headings
  neighbors: {prev,next,parent,children} // graph edges
  tokens_lex: [String]        // for BM25/inverted index
  embedding: [Float16]        // TinyBERT bi‑encoder
  signals: {language, has_numbers, units, entities...}
}

Tables are not text blobs:
	•	table_row node = normalized row string (best for retrieval)
	•	table_cell nodes = exact cell strings (best for extraction)

⸻

2) Ingestion (universal adapters, one output)

Goal: produce CDM nodes with layout + structure as often as possible.

PDF (born‑digital)
	•	Extract text layer + per‑page positions (PDFKit or equivalent).
	•	Build headings from typography/layout heuristics (font size, numbering, spacing).
	•	Detect tables (grid/whitespace heuristics) and emit table_row + table_cell.

PDF/image (scanned)
	•	Render pages to images.
	•	Use Vision’s document reading API to get structured elements like paragraphs/lists/tables (when you have page images).  ￼
	•	OCR fallback only when text density is low:
	•	if extracted chars < 200 → OCR that page

Other doc types (DOCX, PPTX, HTML, etc.)
	•	Adapter rule: convert to “pages” + structure (render, then Vision) or parse native structure when easy.
	•	Always output nodes with section_path and type.

⸻

3) Indexes (minimum set that actually feels universal)

You want four indexes, always:
	1.	Dense vector (TinyBERT bi‑encoder embeddings)
	2.	Lexical inverted index (BM25‑ish)
	3.	Structure index (section_path, page, type filters)
	4.	Graph index (edges from headings, “see page X”, figure/table references)

Why this matters (practically):
	•	Vector alone fails on exact strings (IDs, legal clauses, error codes).
	•	Lexical alone fails on paraphrase and conceptual queries.
	•	Structure/graph is what makes multi‑hop across “see also” work.

⸻

4) Models (all TinyBERT‑class, all Core ML)

You want four small models (this is the nuclear set):
	1.	Bi‑encoder embedder

	•	E(q) and E(n) with cosine/dot similarity
	•	d = 384–768 (384 is often a good on‑device compromise)

	2.	Cross‑encoder reranker

	•	input: [CLS] query [SEP] node_text [SEP]
	•	output: relevance score s_i
	•	improves top‑1 precision massively vs bi‑encoder alone

	3.	Extractive QA span model (TinyBERT + start/end heads)

	•	given top context, outputs best (start,end) span
	•	this replaces “big LLM generation” for factual queries

	4.	Query router (tiny classifier or heuristics)

	•	labels: lookup | table_lookup | procedure | compare | summarize | investigate | compute

Core ML integration: use Core ML’s modern tensor plumbing (MLTensor) and performance tooling when you deploy transformer‑y models.  ￼

Compression: use Core ML Tools compression (palettization/quantization/pruning) to fit everything on device with sane memory.  ￼

⸻

5) Retrieval funnel (hybrid + rerank + packing)

Candidate generation (high recall)
	•	C_d = topK\_dense(Q, 64)
	•	C_l = topK\_lex(Q, 64)
	•	C = union(C_d, C_l)
	•	Apply structural boosts:
	•	if query mentions “table” → boost table_row
	•	if query mentions “steps/how to” → boost list_item + headings
	•	if query has numbers/units → boost nodes with has_numbers

Rerank (high precision)
	•	score each candidate with cross‑encoder:
s_i = f_{\text{cross}}(Q, N_i)
	•	keep top k_r = 12

Context packing (sufficiency)
	•	Pack: top 12 + their heading parents + ±1 neighbor each (same section)
	•	For tables: include full table row + its cell nodes
	•	For multi‑hop: follow graph edges (“see page”, “refer to”) up to 1–2 hops

⸻

6) Answering (universal without hallucination)

Everything outputs a structured object first:

{
  "refuse": false,
  "answer_type": "lookup",
  "answer": "string",
  "claims": [
    {"claim": "string", "evidence_ids": ["..."], "confidence": 0.0}
  ],
  "evidence": [
    {"evidence_id": "node_id", "page": 0, "quote": "<=240 chars"}
  ],
  "missing": [],
  "debug": {"top_score": 0.0, "loops": 1}
}

Per intent, do this (no exceptions):
	•	lookup: run extractive QA on packed context → best span → return with evidence quote
	•	table_lookup: retrieve table_row then extract target cell(s) (no QA model needed)
	•	procedure: output ordered list_item nodes + headings (preserve order)
	•	compare: retrieve evidence for A and B separately, then output side‑by‑side quotes
	•	summarize: extractive summarization only:
	•	split evidence into sentences
	•	score each sentence by bi‑encoder similarity to query
	•	pick top N sentences with coverage constraints
	•	investigate: multi‑hop loop:
	•	answer = “evidence map” + extracted sub‑facts, not prose

⸻

7) Verification gates (the part that makes it “nuclear”)

Let s_{max} be top rerank score, m = s_1 - s_2 margin.

Gate A: Retrieval confidence
	•	require s_{max} \ge \tau AND m \ge \mu

Gate B: Evidence coverage
	•	100% of claims cite evidence_ids present in packed context

Gate C: Numeric sanity
	•	if claim contains numbers/units:
	•	recompute from extracted tokens
	•	reject if mismatch

Gate D: Contradiction sweep
	•	run “counter‑retrieval” with negated/alternative phrasing
	•	if contradictions found, either:
	•	present both with citations, or
	•	abstain

If any gate fails: expand query and re‑retrieve (max loops = 3), else refuse.

⸻

8) Defaults (ship these, then calibrate)

chunk_tokens: 220
overlap_tokens: 40
dense_topk: 64
lex_topk: 64
rerank_candidate_cap: 128
final_nodes: 12
neighbor_hops: 1
graph_hops: 1
ocr_trigger_chars_lt: 200
max_loops: 3
tau_normal: 0.55
tau_touchy: 0.65
mu_margin: 0.05
embedding_dtype: float16

Memory math (so you don’t accidentally explode the app):
If N nodes, embedding dim d, bytes b:
\text{bytes} = N\cdot d\cdot b
Example: N=50{,}000, d=384, b=2 (float16) → \approx 38.4 MB.

⸻

9) Evaluation and calibration (what “bulletproof” means numerically)

Build a local test set: \ge 500 Q–A pairs with gold evidence spans.

Track:
	•	Retrieval: Recall@k, MRR
	•	Rerank: Top‑1 evidence accuracy
	•	QA: Exact Match, F1 (span overlap)
	•	Faithfulness: % claims with valid evidence
	•	Abstention quality: false‑refuse vs false‑answer
	•	Calibration: reliability curve for your confidence score

Confidence calibration (simple, effective):
P(\text{correct}) = \sigma(\alpha s_{max} + \beta m + \gamma \log(1+n_{evidence}) - \delta)

Set \tau by maximizing expected utility:
U(\tau) = \Pr(\text{correct}\mid \tau) - \lambda \Pr(\text{wrong}\mid \tau)
For “touchy,” pick \lambda high (e.g., 10–50× cost of wrong vs refuse).

⸻

10) The entire runtime loop in one tight block (copy‑paste spec)

UniversalRAG(Q):
  intent = route(Q)
  for loop in 1..max_loops:
    C = union(topDense(Q,64), topLex(Q,64))
    C = applyTypeBoosts(C, intent) + applyStructureFilters(C)
    R = topCrossRerank(Q, C, 12)
    ctx = pack(R + parents(R) + neighbors(R,±1) + graphHops(R,1))

    out = answerExtractively(intent, Q, ctx)   # QA span, table cell, list steps, sentence selection
    if verify(out, ctx) and topScore(R) >= tau(intent):
      return out

    Q = expand(Q, ctx)   # synonyms, section hints, entity normalization, table focus
  return REFUSE(missing=what_to_fetch_next)


⸻

Optional note (not required, but real): why this is “universal”

This design handles arbitrary complexity because it can:
	•	preserve structure (tables/lists/sections)
	•	retrieve via multiple channels (dense + lexical + structure + graph)
	•	rerank precisely (cross‑encoder)
	•	answer without hallucinating (extractive QA + extractive summarization)
	•	self‑correct by iterating retrieval rather than guessing

That’s the full‑blown version, compressed into a spec you can actually paste into an agent or implementation plan without losing any of the important machinery.
