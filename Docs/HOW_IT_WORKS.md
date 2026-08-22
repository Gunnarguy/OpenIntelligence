# How OpenIntelligence Works

> **Documentation status:** Source-verified against `f0ac9b9` on 2026-08-21. Every architectural
> constant below was re-read from the code on that date: the 4,096-token context window, the 384
> dimensions, the 310-word chunk ceiling under a 510-token limit, the nine SQLite tables, the nine
> verification gates and the 1,000-chunk GPU threshold all hold. Subsystem line counts were recounted
> and had all drifted upward since this page was first written; recount them with the command below
> rather than trusting the table. **Two things were withdrawn rather than updated: the accuracy
> figures in section 08, and the implication anywhere that Private Cloud Compute runs in production.**
> Both are explained where they occur. `[evidence_level: code_verified, confidence: exact_for_constants_withdrawn_for_measurements]`

This is the long-form explanation of what the app does, in order, and **why each part is there**.
It is written at two levels throughout: a plain-English block for anyone, and the technical detail
underneath it.

```bash
# Recount the subsystem sizes in section 01
for s in RAG Document Infrastructure Agentic Query Storage LLM Embedding Evaluation VectorStore AIPlatform Billing; do
  printf "%-16s %8s\n" "$s" "$(find OpenIntelligence/Services/$s -name '*.swift' -exec cat {} + | wc -l)"
done
```

---

## 00. The whole thing at once

> **In plain words**
> **Imagine a librarian with a very small desk.**
> You hand over a stack of your own books. The librarian reads every one and writes index cards about what's on each page. That's the first half of the app, and it happens once, when you add a document.
> Then you ask a question. The librarian runs to the shelves, grabs the handful of cards most likely to answer it, and brings them back to the desk. Here's the catch: **the desk only fits about four pages at a time.** Not four hundred. Four. So choosing *which* cards make it onto the desk is the entire hard problem, and almost everything in this app exists to make that choice well.
> Then the librarian writes an answer using only what's on the desk. Before you see it, a fact-checker compares the answer against those pages. If the answer says something the pages don't, the fact-checker stops it. If nothing on the desk answers the question, the librarian is required to say *"that isn't in your documents"* rather than guess.
> Everything below is a detail of that story.

OpenIntelligence is a local-first retrieval-augmented generation system. Documents are parsed, chunked, embedded and indexed entirely on device. A question is answered by retrieving evidence from that index, packing it into a strictly bounded context window, generating from it, and then verifying the output against the evidence before it is shown.
The governing constraint is that Apple's on-device foundation model has a **4,096-token context window**. A document does not fit. Neither does a naive top-20 chunk set once the system prompt, tool schemas and output schema are accounted for. Every packing, compression, ordering and filtering decision in the pipeline traces back to that number.
The second constraint is that documents stay on the device. So "send the whole corpus to a larger model" is not available either. Retrieval-augmented generation is not a preference here; it is the only architecture that satisfies both constraints at once.

### Four things that make it different

> **In plain words**
> 1. **Two filing systems, not one.** Cards are filed both by the exact words on them and by what they're about. "Part number 4021-B" needs the first. "How do I change the oil" needs the second.
> 2. **The desk is tiny.** Everything about the design follows from that.
> 3. **The privacy decision is made late.** The app looks at your pages first, and only then decides whether it needs outside help. If it does, it shows you exactly what would leave before anything does.
> 4. **A fact-checker that's allowed to say no.** Most AI tools always give you an answer. This one is allowed to refuse, and that's deliberate.

1. **A dual index.** SQLite FTS5 with BM25 for lexical retrieval, a memory-mapped BNNS vector store for dense retrieval, merged by rank fusion. Neither arm is sufficient alone.
2. **A hard token budget.** Compression, sibling expansion, positional reordering and tool-schema management are all consequences of 4,096 tokens being the real ceiling.
3. **Post-retrieval routing.** The decision about whether anything leaves the device is made after evidence exists, and consent is requested for the exact minimized payload rather than in advance.
4. **Nine verification gates.** Deterministic, local, run after generation, and able to force an abstention. Refusing to answer is a designed outcome, not a failure state.

## 01. How it is built

*One Swift codebase, no server, no backend. Everything below was counted and read from the source rather than described from a design document.*

> **In plain words**
> There's no website behind this app and no account server. The whole thing is one program that runs on your device.
> Inside, it splits cleanly in two: the screens you touch, and the machinery underneath that does the reading, searching and answering. The machinery is by far the bigger half.

### The five layers

| Layer | What lives there |
|---|---|
| `App/` | Launch, the root view, and a debug validation harness |
| `Core/` | Shared models, protocols and extensions used everywhere |
| `Features/` | Ten user-facing areas: Chat, Documents, Camera, Settings, Diagnostics, Telemetry, Database, Billing, Onboarding, Debug |
| `Services/` | Twelve subsystems. All the actual work |
| `SDK/` | A single engine-facing entry point, the beginning of a reusable boundary rather than a finished one |

### The twelve subsystems

| Subsystem | Lines | Files | Responsibility |
|---|---|---|---|
| `RAG` | 32,014 | 29 | Orchestration, retrieval, context packing, verification, safety |
| `Document` | 25,669 | 25 | Parsing, OCR, layout, chunking, classification |
| `Infrastructure` | 18,368 | 25 | iCloud sync, GPU compute, device capability, background tasks, settings |
| `Agentic` | 11,631 | 11 | Multi-session reasoning, conversation memory, Siri intents |
| `Query` | 10,329 | 12 | Understanding, rewriting, intent, specification extraction, suggestions |
| `Storage` | 4,534 | 4 | SQLite and the full-text index |
| `LLM` | 3,687 | 6 | Prompt compilation and model execution |
| `Embedding` | 2,897 | 9 | Vector generation across Neural Engine and Core ML providers |
| `Evaluation` | 1,743 | 8 | The benchmark runner and its metrics |
| `VectorStore` | 1,686 | 4 | The memory-mapped vector database |
| `AIPlatform` | 1,948 | 11 | Apple Foundation Models: sessions, tools, budgets, capability, routing policy |
| `Billing` | 1,405 | 8 | StoreKit, entitlements, quotas |

> **An honest structural note**
> Three files carry about a third of the service code between them: the retrieval orchestrator at 18,459 lines, the document processor at 9,562, and the agentic orchestrator at 7,932. That is not a shape anyone would choose deliberately. It is what happens when a pipeline grows stage by stage and each new stage lands next to the one before it. Splitting them is real work that has not been done, and a page explaining the architecture should say so rather than draw a tidy diagram that implies otherwise.

### What is actually on disk

> **In plain words**
> Two things get written for each library. A database file holding the text and everything the app learned about it, and a pair of binary files holding the meaning-map coordinates. Nothing else, and nothing anywhere but your device.

One shared SQLite database, isolated per library by a container column rather than by separate files. Nine tables:

| Table | Kind | Holds |
|---|---|---|
| `documents` | FTS5 | Whole-document text for full-text search |
| `document_meta` | standard | Counts, dates, size, container |
| `document_content` | standard | Raw text for direct extraction |
| `chunks` | FTS5 | Chunk-level search. Nine columns, of which only `section_title`, `section_path` and `content` are searchable |
| `chunk_structured` | standard | Structured elements recovered from a chunk |
| `chunk_table_rows` | standard | Table rows stored individually, so a row survives as a row |
| `document_pages` | FTS5 | Page-level search and context boundaries |
| `semantic_query_cache` | standard | Previously embedded queries, so a repeat question skips embedding |
| `documents_vocab` | fts5vocab | The vocabulary used to expand queries with this library's own words |

Vectors live outside SQLite in three files per library: a metadata JSON of roughly 5 to 10 MB, a `_vectors.bin` of contiguous 32-bit floats, and a `_norms.bin` of precomputed lengths. The vector file is memory-mapped rather than loaded, so a large library costs almost nothing in resident memory: about 10 MB for the metadata, essentially zero for the mapped vectors, and 200 KB for the norms.

### How a search physically runs

> **In plain words**
> Comparing your question against every card is just arithmetic, repeated a lot. For a small library the processor does it directly. Past about a thousand cards it becomes worth handing to the graphics chip, which does thousands of small sums at once. The app switches automatically, and either way it reads the numbers straight from the file rather than copying them into memory first.

Below 1,000 chunks, similarity is computed with Accelerate's `vDSP_dotpr` directly against the memory-mapped pointer. At or above 1,000 chunks the same data is handed to a Metal compute shader through an unsafe buffer pointer over the same mapping, so the GPU path is near-zero-copy. Neither path materialises the embeddings on the heap.

## 02. Reading your documents: six steps

*This happens once, when a file is added. Everything later is capped by how well this goes: a fact that never made it into the index cannot be retrieved by any amount of cleverness downstream.*

#### Step 1. Get the words out

> **In plain words**
> Easy if the file is a typed document. Harder if it's a photo of a page, where the app has to look at the picture and read it, like squinting at someone's handwriting. Hardest with tables, where *where* a number sits matters as much as the number itself: "$40" in the price column means something different from "$40" in the shipping column.

**How.** Type-specific extractors. PDFKit lifts the native text layer when one exists. Vision's `RecognizeDocumentsRequest` handles scans, photos and camera captures, parsing tables into rows and columns rather than reading order. Office formats are unzipped and their XML parsed. CSV goes through an RFC 4180 parse. Audio and video go through SpeechAnalyzer. Page rendering is zero-copy, converting `CIImage` straight to `CGImage` without a PNG round trip.

**Why it matters.** Extraction is the ceiling on the entire system. The zero-copy path is a memory decision as much as a speed one: rasterising a 400-page PDF through image buffers on a phone is a reliable way to get the app killed.

#### Step 2. Cut it into pieces

> **In plain words**
> Cut the document into index-card-sized pieces, roughly 310 words each. Two rules. Let the cards **overlap** slightly, so a sentence landing on a cut isn't sliced in half and lost. And **never cut up a table**, because a number without its column heading is worthless.

**How.** Adaptive windows of ≤310 words with character overlap. Tables and lists are preserved as atomic chunks and never split. Each chunk carries a prefix naming its document and section before it is embedded.

**Why 310.** The chunk must fit under the embedding model's 510 word-piece token limit, and words are not tokens, so the cap leaves headroom. The prefix exists because a chunk read in isolation has lost what it is about, which measurably hurts retrieval.

#### Step 3. Highlight what matters

> **In plain words**
> Go through each card with a highlighter and mark the names, dates, places and the section heading it came from. Later, a match on a highlighted word counts for more than a match buried in ordinary prose.

**How.** Apple's `NLTagger` performs named entity recognition. Keywords, authors and section headers are attached to each chunk record.

**Why.** BM25 column weights prioritise section titles and entity tags, so lexical search matches against high-signal fields rather than undifferentiated body text. The section path is also what the app uses later to work out which chunks are neighbours.

#### Step 4. Check it fits

> **In plain words**
> Make sure the card actually fits on the card. Write too much and the extra doesn't spill onto a second card, it falls off the edge and vanishes, with no warning. So it gets measured first. This step is also what lets citations jump to the exact sentence rather than roughly the right page.

**How.** A Rust-backed tokenizer validates every chunk against the 510 word-piece ceiling before embedding.

**Why.** Exceeding the limit does not raise an error, it silently truncates, producing an embedding of the first 510 tokens filed under the identity of the whole chunk. That is silent index corruption and nothing downstream can detect it. The same pass yields exact byte offsets, which is what makes citations point at a character range in the source.

#### Step 5. Turn meaning into coordinates

> **In plain words**
> This is the one genuinely strange idea in the app, and it's worth getting.
> Imagine a map where things sit near each other if they *mean* similar things. "Dog" and "puppy" are neighbours. "Dog" and "tax return" are on opposite sides of town. Now imagine that map has 384 directions instead of two, because meaning is more complicated than north and east.
> Every card gets a pin on that map. Later, your question gets a pin too, and the app grabs the cards pinned nearby. That's how it finds "SAE 0W-20 synthetic" when you asked "what oil does my car take," even though those two phrases share no words at all.

**How.** 384-dimensional sentence embeddings, generated on the Neural Engine through Apple's newer on-device inference path where available, falling back to Core ML.

**Why 384.** Small enough that a whole library's vectors stay memory-mappable on a phone and similarity is a vectorised dot product rather than a search problem.

**A constraint worth knowing.** Chunk size, overlap and strategy can change mid-library without harm, because similarity is still defined across mixed chunks. Changing the embedding model or vector width changes the coordinate space itself; mixing widths makes similarity meaningless. So embedding changes are blocked during ingestion and require a full rebuild.

#### Step 6. File it twice, and leave bookmarks

> **In plain words**
> File every card **twice**: once alphabetically by the words on it, once by its pin on the meaning-map. Two systems because they fail in opposite ways. Alphabetical is perfect for "part number 4021-B" and useless for "how do I keep this thing running." The meaning-map is the reverse.
> Also drop a bookmark every few pages. A big PDF on a phone gets interrupted constantly, and without bookmarks you'd start from page one every time. The bookmark has to remember the document's *identity*, not just the page, or you end up filing a second copy of the same document.

**How.** Lexical tokens go to SQLite FTS5 with a Porter tokenizer and BM25 ranking. Dense vectors go to a memory-mapped binary store using cosine similarity. Both are isolated per library. Page-level JSON checkpoints carry a stable document ID. Documents over 10MB use a streaming lane, 15 pages at a time, flushing after each batch.

**Why two indexes.** Dense retrieval is strong on meaning and weak on exact strings such as part numbers and proper nouns. BM25 is the inverse. Running both and fusing them is cheaper and more reliable than making one arm do both jobs.

> **In plain words**
> **Skim before committing.** The app flips through the first ten pages before deciding how big to make the cards, because a physics textbook and a novel want different-sized cards, and redoing it later is the most expensive mistake available.
> **Deleted means deleted.** If you have the app on a phone and a laptop and delete a document on one, the other must not helpfully restore it. So deletions leave a note saying "this was removed on purpose," and that note wins any argument between devices.

**Predictive pre-scan.** Before page one, the first 10 pages or 10,000 characters are analysed for code and mathematics patterns, list and table density, multi-column layout and vocabulary characteristics. A chunking plan is resolved from those signals and applied to this document and subsequent imports, so the configuration is not discovered to be wrong after paying to embed everything.
**Deletion-wins tombstones.** The ingestion queue is an iCloud-coordinated file, so a document dismissed on one device could otherwise be resurrected by a stale snapshot from another. Removal writes a bounded tombstone that is merged before queue items and survives an empty queue. Automatic index repair is single-flight and sequential, and is suppressed per library until an explicit import clears it.

## 03. Answering a question

*Six phases, listed in the order they run. Every stage below was read out of the shipped code rather than from a specification, so the numbering is the app's own and it has gaps and letters where stages were inserted between existing ones over time.*

> **On the number 23**
> The app is usually described as a 29-step pipeline, six for reading a document and 23 for answering a question. That 23 counts steps 1 through 9 of the published specification, leaving out a step 0 that warms a vocabulary cache before any question exists and a step 10 that draws the finished answer on screen, since neither is part of turning a question into an answer.
> **The shipped code actually runs more than that.** Five stages below appear in no specification: two vocabulary expansions at 1.5b and 1.5c, a section boost at 3.5, cross-reference resolution alongside 4.6, and the specification-table search at 4.8. One documented stage, extractive answering at 5.10, is switched off. All of them are described here anyway, because the point of this page is what the app does rather than what was written down about it.

> **In plain words**
> 1. **Work out what was actually asked.**
> 2. **Go find candidate cards**, both filing systems at once.
> 3. **Be picky about which ones survive.**
> 4. **Arrange them on the desk**, in a specific order, because that turns out to matter.
> 5. **Write the answer, then fact-check it.**
> 6. **Show it with sources you can tap.**

### Phase A · Understand the question

> **In plain words**
> People don't ask questions using the words that are in the document. You say "what oil does my car take," the manual says "SAE 0W-20 synthetic, 5.3 quarts." Not one word in common. So before searching anything, the app rewrites the question a few different ways to improve its odds.

Questions and documents do not share vocabulary. Embedding the raw question searches the wrong region of the space, so this phase reshapes it first.

#### Step 1. Resolve what the question refers to

> **In plain words**
> Work out what "it" means. "What about the second one?" isn't searchable until you know what the second one *is*, so the app looks back at the conversation.

**How.** Pronoun resolution, normalisation and entity labelling. Conversation memory retains 5 turns in Standard, 10 in Deep Think and 20 in Maximum.

#### Step 1.5. Ask it several ways

> **In plain words**
> Ask the same question in several forms at once, using words the app learned from your own documents. Six versions in the fast mode, twelve in the thorough one. Several rough guesses beat one confident guess.

**How.** Query variants generated from corpus and library vocabulary: up to 6, 8 or 12 by mode. Each variant is embedded separately, so expansion precedes embedding rather than following it.

#### Step 1.5b. Add words this library uses

> **In plain words**
> Every library has its own dialect. A car manual, a medical file and a legal contract all name things differently. The app learns each library's vocabulary as it indexes, and expands the question using words from *that* library rather than generic synonyms.

**How.** Per-container vocabulary expansion, drawing on terms learned during ingestion from this library specifically.

#### Step 1.5c. Add known domain terms

> **In plain words**
> On top of what it learned from your files, the app has prepared lists of terms for common subject areas, and pulls in the relevant ones.

**How.** Gazetteer-based domain vocabulary enrichment, layered on top of the corpus and container expansions.

#### Step 1.6. Work out what kind of question it is

> **In plain words**
> "What's the tyre pressure" is a look-up-a-number question. "How do I replace the filter" is a follow-the-steps question. "Summarise this" is a whole-document question. Each needs a different approach, so the app decides which it's facing before doing anything else.

**How.** Five intents: lookup, procedure, compare, summarize, general QA.

**Why.** Intent conditions the rest of the pipeline. Lookup gets a specification boost and can bypass generation entirely. Summarize routes to hierarchical summaries. Compare gets multi-hop handling. Without it, one pipeline shape serves five question shapes badly.

> **A deliberate default that looks like a bug**
> In the fast mode, several of these rewriting features are switched **off**. That is intentional. A hypothetical answer invented by a small model can pull an exact-value lookup off target, and an automated rewrite can drift away from a literal question. So the modes that need breadth enable them, and the mode that needs precision keeps the question literal.

### Phase B · Find candidates

#### Step 2. Put the question on the map

> **In plain words**
> Pin the question to the meaning-map, so the app can see which cards are pinned nearby.

**How.** Each variant becomes a 384-dimensional vector in the same space as the chunks, from the same provider at the same width.

#### Step 2.5. Route whole-library questions to summaries

> **In plain words**
> If the question is about the *whole* library rather than one fact in it, don't go looking for individual cards. No ten cards can tell you what a hundred documents are about. Go to the summaries instead. It's the difference between "what's on page 40" and "what is this, generally."

**How.** Global or summary-shaped queries route to summary nodes built during chunking rather than to leaf chunks. Retrieval happens at whichever level of the hierarchy the question lives at.

#### Step 3. Search both systems and merge

> **In plain words**
> Search both filing systems at once, then merge the two lists.
> Merging is trickier than it sounds. The two systems score things on totally different scales, like one judge marking out of 10 and another out of 100, except nobody knows the scales. So the app **throws the scores away** and keeps only the *rankings*. Anything both systems put near the top wins. The two scoring systems never have to be made to agree, which is fortunate, because they can't be.

**How.** BM25 over FTS5 and cosine similarity over the vector store run in parallel, and the two ranked lists merge by Reciprocal Rank Fusion at *k* = 60. Candidate depth starts at 30, 35 or 50 by mode and scales with library size.

**Why rank fusion rather than score blending.** BM25 scores and cosine similarities are on incomparable scales with no stable mapping between them, so any weighted sum needs calibration that drifts per corpus. Rank fusion discards the scores and uses only position, which makes it calibration-free.

#### Step 3.5. Boost cards whose section fits the question

> **In plain words**
> Promote cards whose section heading matches what was asked. A card from a chapter called "Maintenance Schedule" is a better bet for a maintenance question than one from the middle of the warranty terms, even if the words happen to line up.

**How.** Section metadata boost, applied to the fused result set before reranking. This is the stage reported as `boosted` in the per-stage retrieval measurements further down.

### Phase C · Decide what survives

#### Step 4. Re-sort with a slower, better reader

> **In plain words**
> Now a slower, pickier reader looks at the question and each candidate card *side by side* and re-sorts them properly.
> Why not use the picky reader from the start? Because it's slow. Reading the question against every card in the library would take forever. So: a fast rough method narrows thousands of cards to fifty, then the slow careful method sorts those fifty. Skim to shortlist, read to rank. That two-speed pattern is the backbone of the whole design.

**How.** A bundled Core ML cross-encoder rescores the fused candidates, degrading to a term-proximity heuristic if the model is unavailable rather than failing.

**Why.** The retrieval embedder encodes question and chunk separately and never sees them together. A cross-encoder runs attention over the pair, which is far more accurate and far too slow to run over a whole library. That asymmetry is precisely why the architecture retrieves first and reranks second.

#### Step 4.3. Discard the weak candidates

> **In plain words**
> A mediocre card on the desk is worse than an empty slot, because the app will use it and then cite it, and now there's a real-looking source that doesn't actually support the answer.

**How.** Candidates below a safety margin are pruned, on the reasoning that a weak chunk in context produces a citation pointing somewhere real but irrelevant.

#### Step 4.4. Spread across sources

> **In plain words**
> Don't let one document hog the desk. If a question spans three files and all five slots went to file one, the answer is confidently incomplete.

**How.** Source diversity is enforced separately from semantic diversity, because two chunks from two different documents can still be close in embedding space.

#### Step 4.5. Remove near-duplicates

> **In plain words**
> Taking the five best-scoring cards often gets you five copies of the same paragraph, because whatever made one score well made its neighbours score well too. So each new card has to earn its slot by being good *and* by saying something the chosen ones don't.

**How.** Maximal Marginal Relevance, which scores relevance to the query minus similarity to what is already selected. λ is 0.60, 0.55 or 0.50 by mode; the thorough mode favours breadth.

### Phase D · Arrange the desk

> **In plain words**
> Everything left goes on the desk. But the desk is tiny, so how it's arranged changes the answer. This phase is entirely about arrangement.

#### Step 4.6. Bring the neighbouring cards too

> **In plain words**
> For every card that survived, also grab the couple of cards on either side.
> Small cards are great for *finding* things and bad for *reading*. The card that matched often starts mid-argument, and the sentence that qualifies it ("...but only on models before 2019") is on the next card. So the app searches small and reads big.

**How.** Each surviving chunk is expanded with siblings from the same page or section: 2, 3 or 5 per side by mode. Expansion applies its own literal-text redundancy check so it cannot reintroduce duplicates.

**Why this runs after de-duplication rather than before.** It looks backwards, since expanding to adjacent text seems to reinject the redundancy just removed. It isn't. Diversity is enforced at *selection*, so the anchor chunks cover distinct topics; expansion then restores local context around each anchor, and siblings never compete for anchor slots. Two redundancy mechanisms operate at two levels, one in meaning-space for choosing and one in literal text for assembling.

#### Step 4.6b. Follow cross-references

> **In plain words**
> If a card says "see section 7.3," go and get section 7.3. Documents point at themselves constantly, and an answer built from a card that defers to another page is an answer that stops right before the useful part.

**How.** Cross-reference resolution, run alongside sibling expansion so that referenced sections are pulled in rather than left dangling.

#### Step 4.8. Hunt directly for specification tables

> **In plain words**
> This one exists because of a measured flaw in the careful reader from step 4.
> That reader **prefers prose to tables.** Shown a paragraph and a table that answer the question equally well, it scores the paragraph roughly two and a half times higher. Which is a disaster for exactly the questions where tables matter most: dosages, torque specs, prices, legal section numbers.
> So for those questions the app runs a separate, blunt search that ignores meaning-matching and ignores the careful reader entirely, and just hunts for cards where the question's distinctive words sit next to numbers. That pattern is the signature of a specification table.

**How.** Targeted spec retrieval, internally the "Spec Table Sniper". It bypasses both semantic similarity and reranker scoring, searching all chunks for co-occurrence of discriminative query keywords with numeric or structured data.

**Why it exists.** The cross-encoder carries a measured prose bias, scoring roughly 0.78 for prose against roughly 0.30 for tables. Reranking is a net gain overall, but it systematically demotes exactly the content that answers specification, dosage, statute-number and financial-figure lookups. This stage routes around its known weakness rather than trying to retune it.

#### Step 4.7. Cross out the irrelevant sentences

> **In plain words**
> A card might hold four hundred words and only two useful sentences. The rest is taking up desk space and distracting the reader.

**How.** Query-irrelevant sentences are dropped per chunk. Enabled in Deep Think; disabled in the fast mode, where losing a detail from an exact-value lookup is the greater risk, and in the thorough mode, which has the budget to keep everything.

#### Step 4.9. Add a small map

> **In plain words**
> Note at the top of the desk which section each card came from and which names connect to which. Cheap context that helps the reader orient.

**How.** Entity paths, section outlines and reference tags are packed under an explicit token budget. This is graph-*style* packing over deterministic entities, not a derived knowledge graph, and the app does not claim otherwise.

#### Step 5. Put the best material at both ends

> **In plain words**
> Put the best cards at the **very top and the very bottom** of the pile, and the weaker ones in the middle.
> This sounds like superstition. It isn't. Language models pay much more attention to the start and end of what they're given and genuinely skim the middle, the same way you remember the first and last items on a shopping list. The effect is big enough to lose an answer that was right there. So this runs dead last, after every decision about *what* is on the desk is settled, because it's the only step about *where* things sit.

**How.** The final chunk set is reordered by position so the highest-scoring evidence sits at the beginning and end. A set ranked [1,2,3,4,5,6] is emitted as [1,3,5,6,4,2].

**Why it is last.** It is a positional decision, so it runs after every content decision is final. Any stage that added or removed a chunk afterwards would undo it. The general rule the pipeline follows: content decisions first, position decisions last.

#### Step 5.9. Assemble summaries directly for overview questions

> **In plain words**
> For "summarise this," build the answer by assembling the relevant passages rather than asking the model to compose from scratch. Faster, and it can't drift from the source.

**How.** Extractive paragraph assembly, conditioned on a summarize intent.

#### Step 5.10. Extractive answers: built, then switched off

> **In plain words**
> There used to be a shortcut here: for a plain "what's the number" question, copy the number straight out of the table instead of asking the AI. It sounds obviously right, and it was **turned off**, because it guessed wrong too often. Asked for fuel tank capacity, it once answered "three-quarters" because that phrase sat near the right words. So every question now goes through the model, which is slower and more reliable.

**Status.** **Disabled.** The code path is commented out and every query proceeds to model generation. The recorded reason: heuristic extraction produced false positives, returning "three-quarters" for a fuel-tank-capacity query, and bypassed the model entirely when it fired.

**What replaced it.** Exact-value questions are now served by targeted retrieval at step 4.8 rather than by a generation bypass. Evidence is steered toward specification tables and the model still writes the answer, so a wrong extraction becomes a wrong *candidate* that the verification checks can catch, instead of a wrong answer that skipped them.

### Phase E · Write it, then check it

#### Step 6. Generate the answer

> **In plain words**
> Finally, write the answer using only what's on the desk.
> One detail worth knowing: the desk is shared by everything, not just your pages. The instructions, the list of tools the AI is allowed to use, the pages, and the answer being written all come out of the same four pages of room. The tool list alone eats about a quarter of it. So once the app has already fetched the right pages, it puts the tool list away, because advertising tools that are no longer needed is the most wasteful thing it could do.

**How.** The packed prompt goes into an Apple `LanguageModelSession` within the 4,096-token budget. Temperature is 0.4 in the standard modes and 0.3 in the most precise one. Tool schemas are removed once context has already been assembled, since they cost roughly 1,000 of the available tokens.

#### Step 6.5 / 7. Tidy up and score it

> **In plain words**
> Fix the formatting, since small models produce broken bullet lists often enough that repairing them is cheaper than asking nicely. Then score how well the answer came out, which feeds the confidence number later.

**How.** Markdown normalisation, list indentation repair and output-structure enforcement, followed by a synthesis quality score that feeds calibration.

#### Step 7.5. Run the nine checks

> **In plain words**
> The fact-checker. Nine separate checks, run on the finished answer against the pages on the desk, before you see any of it. Full list in the next section.

**How.** Nine deterministic verification gates, always local. Detailed in the next section.

#### Step 8 / 8.1. Package it and calibrate the confidence

> **In plain words**
> Bundle the answer with its citations, then convert the app's raw internal score into the confidence percentage you actually see. That conversion matters: a raw score of "0.8" doesn't mean "right 80% of the time," and showing it as though it did would be a lie with a number attached.

**How.** The answer, citation index map and evidence record are assembled, then Platt scaling maps the raw quality score toward something closer to a probability. Calibration is only ever as good as the data it was fit on.

### Phase F · Show it

#### Step 9 / 10. Render with tappable sources

> **In plain words**
> Show the answer with citations that jump to the exact sentence in the original file. Those precise jump points come from the measuring step back in ingestion, step 4. Nothing in this app is only one component.

**How.** Timings, token footprint, cache hits and thermal state are recorded, then the answer renders with inline citation controls that resolve to the exact source span using the byte offsets captured during ingestion.

## 04. The nine checks

*Every answer is verified against its own evidence before it is shown. All nine checks are deterministic and run on your device, even when the writing happened elsewhere.*

> **In plain words**
> In plain terms the nine checks ask: *did we find anything good enough to answer with? does every sentence trace back to a page? do the numbers match? do the pages contradict each other? does the answer actually resemble what the pages say? did we mix up two similar-looking things? is it well formed? did we answer the whole question or only half? are these pages even about the same subject?*
> Fail an important one and the app refuses to answer rather than guessing.

| Check | Name | What it verifies |
|---|---|---|
| `A` | Retrieval Confidence | The best evidence clears a threshold *and* beats the runner-up by a margin. A high top score with no margin means the ranking did not actually discriminate. |
| `B` | Evidence Coverage | Every claim maps to a specific piece of evidence. Uncited assertions are the definition of ungrounded. |
| `C` | Numeric Sanity | Numbers in the answer appear in the sources. Checked against all retrieved candidates, not just the packed set, so a correct number that lost a packing slot is not falsely flagged. |
| `D` | Contradiction Sweep | Conflicting evidence across the retrieved set, including negation. |
| `E` | Semantic Grounding | How closely the answer resembles the evidence in meaning, on both an absolute and a relative threshold, plus a topical alignment check. The strongest of the nine. |
| `F` | Quote Faithfulness | Catches an abbreviation being expanded using a different document that happened to be in the same context. |
| `G` | Generation Quality | Structural soundness of the output itself. |
| `H` | Answer Completeness | Multi-step and comparison answers where each step is individually plausible but the chain is not supported end to end. |
| `I` | Domain Isolation | Rejects evidence drawn from unrelated subject areas before an answer is written. Relaxed when everything came from one document, since that is not mixing. |

Thresholds rise with mode: 0.50 in Standard, 0.60 in Deep Think, 0.80 in Maximum. Failing a critical check produces a grounded abstention rather than a hedged answer.

> **Known behaviour worth stating**
> The checks are currently tuned conservatively enough that they sometimes hedge an answer that is correct and fully supported. In one measured case the verifier lowered its confidence because the answer did not supply a date and a name that the source documents never contained and the question never asked for. That trade is deliberate in direction, if not in degree: the app errs toward under-claiming rather than over-claiming, and tightening it is ongoing work.

## 05. Where your data goes

*Reading, indexing, searching and verifying all happen on your device. Only the final writing step can ever use Apple's Private Cloud Compute, and only with your explicit approval of a specific payload.*

> **Important correction, 2026-08-21: this has never run for a real user**
> Everything in this section is implemented, entitled and signed, and none of it has ever executed in a shipped build. Apple's `PrivateCloudComputeLanguageModel` requires the iOS 27 SDK, which means Xcode 27. Xcode Cloud builds this app with **Xcode 26.6**, so every build that has ever reached the App Store was compiled without that SDK and took the on-device path unconditionally.
> This was found by tracing the release toolchain rather than the code, and it is the reason the routing described below should be read as *built and gated correctly*, not as *in production*. It cannot ship until Apple releases the Xcode 27 Release Candidate.

> **In plain words**
> Sometimes a question is too hard for the phone. There's a bigger service available, but using it means some of your text leaves your device.
> Most apps decide that *before* looking at anything, which means asking permission to send something nobody has seen yet. This one works the other way round on purpose. It finds your pages first, works out the smallest possible bundle it would need to send, **shows you that exact bundle**, and only then asks. Say no and it answers on your device instead.
> And the fact-checking never leaves. Even when the writing happens elsewhere, the checking happens here.

### Routing after retrieval, not before

Three settings are available: On-Device, Hybrid and Private Cloud Compute. Hybrid does not decide up front. Local retrieval runs first and produces an evidence set; only then is a route selected, using that evidence together with entitlement state, live model availability, quota, network status, foreground state and exact token budgets.

Two reasons for that ordering. You cannot know whether a question needs more capability until you have seen what the evidence looks like, so routing on the question alone is guessing. And you cannot minimise a payload before you know what is in it, so consent asked in advance is consent to an unknown envelope.

### The decision, in the order it is actually made

The planner is a strict priority ladder, and the order matters more than any individual rule. The first condition that matches wins.

| # | Condition | Result |
|---|---|---|
| 1 | Evidence is insufficient | **Abstain.** Cloud use is prohibited outright, not merely skipped |
| 2 | You selected On-Device | Local. No further conditions are consulted |
| 3 | You selected Private Cloud Compute | Cloud only if entitlement, availability, quota, network and either foreground or prior consent all hold. Otherwise local, with the specific blocking reason recorded |
| 4 | The answer is an exact value and nothing contradicts it | Deterministic local path |
| 5 | Cloud is disallowed by privacy settings | Local |
| 6 | Otherwise (Hybrid) | Cloud only if the payload fits *and* either the evidence overflows the local window or the question needs multi-document synthesis in a non-Standard mode. Otherwise local |

Two consequences of that last rule are worth stating because they are easy to assume wrong. **Standard mode never escalates to the cloud on difficulty alone**; it escalates only when the evidence physically does not fit on device. And escalation additionally requires the minimized payload to fit the cloud budget, so a query too large for both stays local.

### The shape of the plan itself

The privacy guarantee is not a convention that separate code paths happen to honour. Every plan is constructed with the same three stages and only the middle one is variable:

| Stage | Target |
|---|---|
| Retrieve | always deterministic and local |
| Synthesize | the routed target, the only stage that can leave the device |
| Verify | always deterministic and local |

The fallback attached to a cloud plan is always local and is explicitly marked as non-retrying, so a failed cloud attempt degrades once rather than oscillating.

### What the minimized payload actually is

> **In plain words**
> Not your document. Not even the full set of pages the app found. It takes the pages in order of how relevant they were, gives each one a character allowance, cuts each to that length, and stops when the budget runs out. It also counts how many pages it had to leave out, so the number you approve is honest about what it excludes.

Chunks are sorted by rank and each is granted an allowance of at most the total budget divided by the number of chunks capped at eight, with a floor of 240 characters, then truncated to it. The envelope records both its total character count and the number of chunks omitted. Availability and quota are rechecked immediately before the session is created, after consent rather than before.

### Fail-closed capability checks

The capability snapshot that feeds all of the above is deliberately pessimistic. In the Simulator, cloud support reports as unsupported with an explicit reason. Without a valid signed entitlement, quota reports as *unknown* rather than as available. Any future quota state the SDK might add that this code does not recognise also maps to unknown. Unknown never authorises cloud execution. The on-device context size is read from the SDK at runtime rather than assumed, and if the cloud context size cannot be read the snapshot marks itself partial rather than exact, so a budget decision made on incomplete information is labelled as such.

### The badge tells you what happened

> **In plain words**
> The little badge on each answer isn't a label for what you asked for, it's a record of what actually happened. If you chose the cloud and the cloud was unavailable so your device answered instead, the badge says so. The app is not allowed to imply a route it didn't take.

Each answer carries an execution receipt recording intended, attempted, actual, fallback and completed targets separately. The badge is computed from the receipt, so a cloud request served locally displays as an on-device fallback while the receipt preserves the original intent. On iOS and macOS 26 the app is local-only and never presents local execution as cloud execution.

## 06. Which AI actually answers

*The app tells you where a question ran. It deliberately does not tell you which model version served it, because that is not something any app can currently verify.*

> **In plain words**
> The AI doing the writing isn't part of this app. It's Apple's, built into the operating system. Apple doesn't tell apps which version they got or how large it is, and there's no way to ask.
> So this app never claims to know. It says "this ran on your device" or "this ran in the cloud," which are both things it can genuinely verify, and it stops there. Plenty of apps quote a model size. This one would rather only say what it can check.

- Local generation targets `SystemLanguageModel.default`. Cloud generation targets `PrivateCloudComputeLanguageModel` on iOS and macOS 27 or later.
- Apple's public Foundation Models SDK **exposes no model-size selector**. Session construction accepts a default model, a use case (a task selector, not a size selector), or an adapter. There is no API to request a specific variant and no API to observe which one served a request.
- Apple's own published figure for the on-device model is approximately 3 billion parameters, from their Foundation Models technical report. That is Apple's number about Apple's model, not a claim this app makes about its own routing.
- The larger on-device model announced at WWDC26 is real but managed by the operating system, with no developer-facing selection or observation.
- Accordingly the app labels routes rather than asserting parameter counts, and a continuous-integration check watches for the day Apple exposes selection.

> **Re-checked against the installed SDK on 10 August 2026**
> These are not claims carried forward from an old note. Each line below was compiled against `iPhoneSimulator27.0.sdk` today. A statement that something is *absent* is only worth as much as the check behind it, so here is the check.

> **Why the context window matters more than the size**
> The number that actually shapes this app is not parameter count, it is the 4,096-token context window. That is what makes retrieval quality decisive: with a small window there is nowhere to hide mediocre retrieval, because the model only ever sees what the pipeline chose to give it. A larger window would let several stages of this pipeline be deleted. It would also make the retrieval quality invisible.

## 07. Thinking in loops

*For harder questions the app does not run the pipeline once. It plans, searches, reads, notices what is missing, and goes back out, deciding for itself when to stop.*

> **In plain words**
> An ordinary app follows a fixed recipe: do A, then B, then C, then stop. This one gets to make some choices while it works. Which tool to reach for. Whether to go back for more. When it has done enough.
> Picture the librarian on a hard question. They don't do one lap. They fetch some pages, read them, realise there's a gap, write a note to themselves, and go back out. Again, and again. Until either they can answer, or they notice each trip is bringing back nothing new. **Deciding when to stop** is the hard part.

### Choosing tools

### Carrying a notepad between sessions

> **In plain words**
> The desk gets wiped clean between trips. So before each trip the librarian copies what they've learned onto a notepad in shorthand and carries the notepad through. The notepad also tracks which parts of the question are still unanswered. That notepad is what turns fifty separate lookups into one continuous piece of work.

Because a single session is capped at 4,096 tokens, complex questions are answered across a chain of sessions: plan, search, analyse, synthesise, refine. Deep Think runs roughly 8 sessions and Maximum up to 50. State is carried by a fact bank that decomposes the question into sub-questions, tracks which are answered, and accumulates verified facts. Hierarchical compression carries *facts* forward rather than raw text, because raw text does not fit.

### Knowing when to stop

> **In plain words**
> Two separate reasons to stop, and either alone is enough. **Either** the question is answered well enough, **or** the last few trips brought back nothing new and most of the library has already been seen, so more trips won't help.
> They have to be separate. An earlier version required both at once, and that combination turned out to be unreachable. The scoring could never climb high enough to trigger it, so the loop ran every one of its fifty trips, every time, long after it had what it needed. It knew it was finished and had no way to say so.

Two independent stop conditions. *Completed*: confidence and sub-question coverage both clear their targets. *Converged*: novelty is exhausted, measured as streak-based patience over low novelty, high saturation or 85% source coverage, and the chain is past a minimum session count so a cold start cannot be mistaken for exhaustion. These were previously conjoined with a 0.98 confidence requirement that was unreachable by construction, which meant the loop always ran to its ceiling.

> **In plain words**
> The obvious fix was "stop when you stop ticking off new parts of the question." It sounds right. Measured, it made things worse.
> The list of parts had been stuck since the first trip for a boring reason: one part of the question simply wasn't in the documents and never would be. But the librarian wasn't idle. They were still finding *better* evidence for the parts already covered. Stopping on the stuck list cut them off early, before they'd found the one solid quote that made the answer trustworthy.
> Not making progress *outward* isn't the same as not making progress. Sometimes you're going deeper. So that signal is still watched and recorded, but it is no longer allowed to end the work.

| Stop rule | Sessions | Answer length | Verified citations |
|---|---|---|---|
| Ceiling only, no convergence | 50 | 48 | 0 |
| Saturation convergence | 23 | 209 | 1 of 2, accepted |
| Coverage plateau | 8 | 67 | 0 of 1, retried |

Coverage measures breadth, and it was flat from the first session because one sub-question was never present in the corpus. Novelty meanwhile held at 61 to 86% because the chain was accumulating depth for sub-questions already covered. Stopping on flat breadth removed the depth that eventually produced the one citation the verifier accepted. Coverage plateau is therefore instrumented and logged but deliberately not acted on.

### Backing off when the device is under pressure

> **In plain words**
> If the device is hot or the battery is low, the app quietly does less work rather than grinding things to a halt. It has a fixed order for what to give up first, so the things that matter most survive longest.

Thermal state, battery level and available memory are read per query, selecting one of four levels with candidate depth capped at 50, 30, 20 or 10 and features dropped in priority order. A short cooldown may be applied before heavy generation.

> **What this is not**
> This is not an autonomous agent that takes actions in the world. It has no ability to write, send or change anything, and it does not act outside answering a question. It is an agentic *retrieval* loop: it plans its own sub-questions, chooses its own tools, decides how long to keep working, and stops on a criterion it computes for itself.

## 08. How well it works

*This section was rewritten on 2026-08-21. The figures it used to carry are withdrawn, and the reason is worth more than the figures were.*

> **In plain words**
> An earlier version of this page said the app answered 18 of 20 test questions correctly and never once invented an answer. Both numbers came from a test set written alongside the questions it was grading, and the run they came from has since been flagged as one where the answer-writing step probably never executed at all. So they are gone.
> What replaced them is a harder test on real research papers the project did not write, and the app does considerably worse on it. That is the more useful number, and the reason for the swap.

### Why the old figures were withdrawn

Three separate problems, each sufficient on its own.

- **The corpus graded itself.** The 20-case set was synthetic and authored alongside its own questions. It measured self-consistency, not retrieval quality.
- **The run is flagged.** `BenchmarkRuns/PROGRESSION.md` marks runs averaging under 60 seconds per case as ones where generation almost certainly did not run. The run behind "18 of 20" averaged **7 seconds per case** and carries that flag.
- **The stage table was measuring the ruler.** It showed reranking and final selection losing ground against a perfect vector stage. That turned out to be ground truth crediting one of the two documents each multi-hop question required. Corrected on 2026-08-11, after which every stage read 1.000, which is its own problem: a fixture at ceiling can detect a regression and cannot demonstrate an improvement.

### What is measured now

Real external ground truth, from QASPER: **40 research papers, 83 scored cases**, none of them written by this project.

| Measure | Result |
|---|---|
| Cases scored | 77 of 83 |
| Exact-match accuracy | **0.410** |
| Retrieval, gold document in top 10 | 0.649 |
| Reranking nDCG@5 | 0.431 |
| Final-context recall@10 | 0.549 |

That accuracy is a floor rather than a quality score: it is exact-match against expected answer patterns, so a correct answer phrased differently counts as wrong.

### Where the failures actually are

Decomposed on 2026-08-21, and the answer surprised the project: it is **not one bottleneck, it is two of roughly equal size**.

- The answer-bearing passage **fails to reach the model** in 10 of 24 measurable cases.
- When it does reach the model, the answer is **still wrong** in 7 of 14.

Every prior plan had assumed one of those dominated. Retrieval and synthesis each account for about half.

> **What these numbers do not show**
> - **±1 case at n=24 is the measured noise floor.** Two runs of the same build, differing only in debug output printed after generation, scored 11/24 and 10/24. Nothing smaller than roughly a four-case swing resolves in the accuracy column. The per-stage columns are far more stable and are what a change should be judged on.
> - **Deep Think and Maximum have no valid accuracy figure and none is quoted anywhere.** The one Deep Think benchmark attempted scored 1 of 5 with a timeout at 1800 seconds.
> - **Three run directories were deleted before being re-read.** `BenchmarkRuns/*` is gitignored, so the conclusions drawn from them survive and their raw data does not. Those rows are marked unauditable in the ledger rather than quietly dropped.
> - Document-level recall credits a whole document when any chunk of it appears, which inflated `r@1` on runs where a summary was injected.

**The older figure is still quoted elsewhere in this repository**, including `README.md`, `Docs/LIMITATIONS.md`, `Docs/EVALS.md` and `Docs/RELEASE_NOTES.md`. Withdrawing it from those is a deliberate claim-removal pass that has not been done yet, so if one of them says 80% across 20 cases, this section is the newer reading and the reasons above are why.

The live record is `BenchmarkRuns/PROGRESSION.md` for the numbers and `BenchmarkRuns/LEDGER.md` for what each run was testing and what it settled. Read those rather than trusting any figure quoted here, including these.

## 09. What it can't do

*Stated plainly, because a tool that shows you its sources should also show you its edges.*

> **In plain words**
> Answers are only as good as what the app could read out of your files. If a scan is blurry or a layout is unusual, the words it extracted may be wrong, and everything after that inherits the mistake. Citations show you what supported an answer; they aren't proof the answer is right. And confidence percentages are a useful signal, not a guarantee.

### Known boundaries

### Not for these uses

## 10. Word bank

*Two parts. First every stage of both pipelines on one page, in running order. Then every concept that appears anywhere above, defined twice.*

### Every step, in order

#### Reading a document: six steps

| Step | In plain terms | Technical name |
|---|---|---|
| `1` | Get the words out of the file | Parsing and extraction: PDFKit text layer, Vision document recognition, Office XML, RFC 4180 CSV, speech transcription |
| `2` | Cut it into overlapping index cards, keep tables whole | Semantic and structure-aware chunking, ≤310 words, atomic table preservation, contextual prefixing |
| `3` | Highlight names, dates and section headings | Named entity recognition and metadata tagging |
| `4` | Check each card fits before filing it | Token gating, ≤510 word-piece tokens, with byte-offset capture for citations |
| `5` | Give each card a position on a map of meaning | Dense embedding generation, 384 dimensions, Neural Engine or Core ML |
| `6` | File every card twice, and leave bookmarks | Dual index storage: FTS5 lexical plus memory-mapped vector store, with page-level checkpointing |

#### Answering a question

| Step | In plain terms | Technical name |
|---|---|---|
| `0` | Load this library's word list | Corpus vocabulary cache build or retrieval |
| `1` | Work out what "it" refers to | Query understanding: pronoun resolution, normalisation, entity labelling |
| `1.5` | Ask the question several ways | Corpus-aware query expansion |
| `1.5b` | Add words this library uses | Per-container vocabulary expansion **(undocumented)** |
| `1.5c` | Add known terms for the subject area | Gazetteer domain vocabulary enrichment **(undocumented)** |
| `1.6` | Decide what kind of question this is | Answer intent classification: lookup, procedure, compare, summarize, general |
| `2` | Put the question on the map of meaning | Query embedding, 384 dimensions |
| `2.5` | Send whole-library questions to summaries | Summary-first routing over a hierarchical summary tree |
| `3` | Search both filing systems and merge by position | Hybrid search: BM25 plus vector similarity, merged by Reciprocal Rank Fusion at k=60 |
| `3.5` | Promote cards from a fitting section | Section metadata boost **(undocumented)**, reported as `boosted` in the measurements |
| `4` | Re-sort with a slower, better reader | Cross-encoder reranking, with heuristic fallback |
| `4.3` | Bin the weak candidates | Low-confidence filtering |
| `4.4` | Don't let one document hog the desk | Multi-document representation |
| `4.5` | Drop near-duplicates | Maximal Marginal Relevance, λ 0.60 / 0.55 / 0.50 by mode |
| `4.6` | Bring the neighbouring cards too | Parent document retrieval, 2 / 3 / 5 siblings per side, with Jaccard dedup |
| `4.6b` | Follow "see section 7.3" pointers | Cross-reference resolution **(undocumented)** |
| `4.8` | Hunt directly for specification tables | Targeted spec retrieval, bypassing both similarity and the reranker **(undocumented)** |
| `4.7` | Cross out irrelevant sentences | Contextual compression |
| `4.9` | Add a small map of sections and names | Graph-style context packing under a token budget |
| `5` | Put the best material at both ends | Context assembly with Lost-in-the-Middle positional reordering |
| `5.9` | Assemble summaries directly | Extractive summarization for summarize intent |
| `5.10` | Copy exact numbers instead of generating
**(switched off)** | Extractive QA override, **disabled**; superseded by step 4.8 |
| `6` | Write the answer from the desk | Generation within a 4,096-token session, tool schemas withdrawn once evidence is assembled |
| `6.5` | Repair the formatting | Response formatting and markdown normalisation |
| `7` | Score how well it came out | Quality assessment |
| `7.5` | Run the nine fact-checks | Verification gates A through I |
| `8` | Bundle answer, citations and evidence | Result packaging |
| `8.1` | Turn the raw score into a real percentage | Calibrated confidence via Platt scaling |
| `9` | Record timings and system state | Response metadata |
| `10` | Draw it with tappable sources | Markdown rendering with inline citation resolution |

### Reading documents

**Chunk**
  One index card, about 310 words.The retrievable unit: ≤310 words with character overlap, carrying a document and section prefix.

**Atomic chunk**
  A table kept whole, never cut up.A table or list preserved unsplit, so a cell never loses its column header.

**Contextual prefix**
  Writing the document and section name at the top of every card.A document and section label prepended before embedding, so an isolated chunk retains what it is about.

**Token**
  A piece of a word. The unit models count in, and there are more of them than there are words.Word-piece sub-word unit. Why a 310-word cap sits under a 510-token limit with headroom.

**Embedding**
  A pin on a 384-direction map of meaning. Similar things land near each other.A 384-dimensional dense vector where cosine distance approximates semantic distance.

**OCR**
  Reading words out of a picture of a page.Optical character recognition. Here via Vision's document API, which also recovers table rows and columns rather than reading order alone.

**Full-text index**
  The alphabetical filing system.SQLite FTS5 with BM25 ranking and a Porter stemmer, so "documents" and "document" share a stem.

**Library isolation**
  Each library is a sealed room. A question is never answered from a room you didn't open.Every stored row and vector is tagged with a container identifier and queries are scoped to it.

**Checkpoint**
  A bookmark, so an interrupted import resumes instead of restarting.Page-level state plus a stable document identity, so resume continues rather than re-indexing as a new document.

### Finding evidence

**Retrieval**
  Fetching the handful of cards most likely to answer the question.Selecting candidate chunks from the index for a given query.

**Hybrid search**
  Searching both filing systems at once, because they fail on different questions.Dense and lexical retrieval run in parallel and merged, since they fail on different inputs.

**Rank fusion**
  Merging two result lists by *position* rather than score, so the two systems never have to agree on a scale.Reciprocal Rank Fusion at k=60, calibration-free because it uses only rank position.

**Reranking**
  The slow careful reader who looks at the question and each card side by side.A cross-encoder scoring query-chunk pairs jointly. More accurate than the retrieval encoder, too slow for corpus scale.

**Diversity selection**
  Don't pick five copies of the same paragraph. Each new card must add something.Maximal Marginal Relevance: relevance minus similarity to what is already selected.

**Small-to-big**
  Search with small cards, read with big ones.Embed small chunks for retrieval precision, then expand to neighbouring chunks for coherence.

**Lost in the middle**
  Models skim the middle of what they're given, so the good material goes at both ends.A documented attention bias toward the start and end of a context window, mitigated by positional reordering applied last.

**Summary routing**
  Whole-library questions go to summaries, because no ten cards can describe a hundred documents.Hierarchical summary nodes retrieved for global queries instead of leaf chunks.

### Answering and checking

**Context window**
  The desk. About four pages. Everything competes for it, including the instructions.4,096 tokens on device. Prompt, tool schemas, evidence, output schema and response all share it.

**Grounding**
  Every sentence in the answer traces back to a page on the desk.The property that every claim maps to retrieved evidence, measured as answer-to-evidence similarity.

**Hallucination**
  Stating something confidently that isn't in your documents.Ungrounded generation. Measured on trick questions where the correct behaviour is refusal.

**Abstention**
  Saying "that isn't in your documents" instead of guessing.Refusing to answer when evidence is insufficient. A designed outcome, not a failure.

**Verification check**
  One of nine fact-checks an answer must pass before you see it.A deterministic post-generation gate that can lower confidence or force abstention. Always local.

**Calibration**
  Turning the app's internal score into a percentage that means something.Platt scaling, mapping an uncalibrated score toward a probability.

**Citation**
  A tappable link back to the exact sentence that supported a claim.A byte-offset span into the source document, captured during ingestion tokenization.

**Private Cloud Compute**
  Apple's secure cloud, used only for the writing step and only with your approval.Apple's stateless enclave-based inference service. Reached only after a minimized payload is built and consented to.

**Execution receipt**
  A record of what actually happened, not what was requested.Intended, attempted, actual, fallback and completed targets stored separately, so the route badge reports history.

**Agentic loop**
  Going back out for more, repeatedly, and deciding for yourself when to stop.Multi-session reasoning with a persistent fact bank and an independent convergence criterion.

## 11. Common questions

### Why not just give the whole document to an AI?

PlainBecause the AI on your device can only look at about four pages at once, and a document can be four hundred. And sending your files somewhere with more room would break the promise the app is built on. So there's no version of this that skips the hard part.
Two constraints, both hard. The on-device model has a 4,096-token context window, so a document does not fit. And documents stay on the device by design, so sending the corpus to a larger model is not available either. Retrieval-augmented generation is the only architecture that satisfies both.

### How do I know it isn't making things up?

PlainNine checks run on every answer before you see it, and they're allowed to stop it. On the last measured run it never once invented an answer, and on every trick question it correctly said "not in here." Every claim also links to the sentence that supports it, so you can check yourself.
Nine deterministic verification gates run locally after generation, including a semantic grounding check that compares the answer against its evidence. On the most recent benchmark, trick questions produced zero confident answers and refusal correctness was 100%. Citations resolve to exact source spans rather than to whole documents.

### Does anything leave my device?

PlainOnly if you say yes, only the final writing step, and only after the app shows you the exact text it would send. Reading, indexing, searching and fact-checking always happen on your device. Choose On-Device in settings and nothing ever leaves.
Ingestion, indexing, retrieval and all verification are local unconditionally. Only synthesis can target Private Cloud Compute, and only after a minimized evidence envelope is constructed and explicitly consented to for that exact payload. The On-Device setting is absolute.

### Why does it sometimes refuse to answer?

PlainBecause the answer wasn't in your documents, and inventing one would be worse than admitting it. That refusal is a feature, not a malfunction. It also occasionally hedges an answer that was actually fine, which is the cost of erring in that direction.
A failed critical verification gate produces a grounded abstention rather than a hedged answer. The gates are currently tuned conservatively, so a small number of correct, fully supported answers are also hedged. The trade is deliberate in direction; the degree is being tuned.

### Does it work offline?

PlainYes. Importing, searching and answering all work in airplane mode. There's no account and no API key to set up.
The full local path requires no network. Only the optional cloud synthesis step does, and it degrades to local execution when unavailable, recording the fallback in the answer's receipt.

### Why 29 steps? What are they?

PlainSix for reading and filing a document, twenty-three for turning a question into a checked answer. Every one is listed in the word bank above, with a plain-English name. The app also runs a few extra stages that were never written into the specification, and those are listed too.
Six ingestion steps plus 23 query steps, where the 23 covers steps 1 through 9 of the specification. A step 0 warms a vocabulary cache before any question exists and a step 10 renders the finished answer; neither is part of the question-to-answer transformation, so neither is counted. The shipped code additionally runs five stages absent from any specification (1.5b, 1.5c, 3.5, cross-reference resolution at 4.6, and 4.8) and has one specified stage switched off (5.10). The pipeline is also adaptive and does not run every stage for every question.