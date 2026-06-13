# Owner's Guide: RAG Reliability and Reranking Systems - OpenIntelligence v4.1

This document explains in plain English how the RAG (Retrieval-Augmented Generation) pipeline, verification checks, and reranking systems work in OpenIntelligence v4.1.

---

### 1. What happens when a user asks a question?
When you type a question, the app does not just send it straight to an AI model. First, it performs a search across your imported documents to find paragraphs (called chunks) that are likely to contain the answer. It ranks those chunks, selects the best ones, organizes them into a structured prompt, and feeds them to the AI model alongside your question. Finally, before showing you the model's answer, the app runs several safety verification checks to verify that the answer is completely grounded in the retrieved text.

### 2. What is first-pass retrieval?
First-pass retrieval is the initial search. It scans the database containing all document chunks to narrow down the search from thousands of possibilities to a smaller candidate pool (such as the top 100 or 250 chunks). It uses two different search techniques in parallel—vector search and lexical search—and combines their results.

### 3. What is vector search?
Vector search converts the meaning of your question and document chunks into lists of numbers (embeddings). By comparing these numbers, the system can find chunks that are conceptually similar to your question, even if they use different words. For example, a search for "physician" will successfully match a document chunk containing the word "doctor".

### 4. What is BM25 / lexical search?
Lexical search is keyword matching. It looks for the exact words from your question in the document chunks. The BM25 algorithm ranks these matches by looking at how often the words appear in a chunk relative to how common they are across all your documents. This ensures that unique terms (like a specific model number) are weighted heavily.

### 5. What is reciprocal rank fusion?
Reciprocal rank fusion is the math used to combine the ranked lists from vector search and lexical search. Instead of trying to normalize and compare vector similarity scores with BM25 scores directly, it looks at the rank position of a chunk in both lists. If a chunk ranks high in both searches, it is pushed to the top of the combined list.

### 6. What is reranking?
First-pass search is fast but can be imprecise. Reranking is a second search pass that takes the top candidates (e.g. the top 100) and scores them using a slower, much more accurate method. This ensures that the most relevant information is placed at the very top of the list before it is handed to the AI model.

### 7. What is cross-encoder reranking?
Cross-encoder reranking is a neural network technique where the question and a document chunk are fed into a model together. The model analyzes the relationship between the question and the chunk directly, word by word. This is much more accurate than comparing them separately, though it requires more processing power.

### 8. How is cross-encoder reranking different from embedding similarity?
Embedding similarity compares the pre-computed vectors of the query and the chunk independently. It is fast but does not capture fine-grained context or word relationships. Cross-encoder reranking looks at the query and the chunk simultaneously, allowing the network to evaluate complex relationships and exact semantic overlaps.

### 9. What does “on-device reranking” mean in this app?
It means the cross-encoder model runs entirely on your device (iPhone, iPad, or Mac) using Apple's Core ML framework. It does not send your documents or questions to external servers for ranking, which preserves user privacy and allows offline execution.

### 10. What happens if the reranker model is missing?
If the Core ML cross-encoder model or its vocabulary file fails to load, the app automatically switches to a fallback reranker. This fallback uses a smart heuristic formula combining the vector similarity score, keyword matches, term proximity (how close query words are to each other in the text), and document structure penalties to rank the chunks.

### 11. What is MMR?
MMR (Maximal Marginal Relevance) is a diversity filter. If the search results contain three chunks that say the exact same thing, MMR will penalize the redundant chunks and select chunks that provide new, diverse information. This ensures the AI model gets a broad set of facts within its limited context budget.

### 12. What is context packing?
Context packing is the process of formatting the selected document chunks into a single text block for the AI. It handles Jaccard word-overlap deduplication, contextual title prefixes, and sentence-level truncation so that as much high-yield information as possible is packed into the AI model's context budget.

### 13. What are citations?
Citations are links inserted into the AI's response pointing back to the specific source documents (e.g., "[S1]" or "[S2]"). The app matches claims in the response to the exact chunk index and page number of the source document so the user can verify the facts.

### 14. What are structured claims?
Structured claims are atomic statements extracted from the AI's candidate response (e.g., "The engine capacity is 2.4 liters"). The app extracts these claims into structured data so they can be independently verified against the source text.

### 15. What are verification gates?
Verification gates are a sequence of nine automated checks (A through I) that verify response quality. They evaluate factors like whether the search similarity scores are high enough, if the statements match source quotes, if domain rules are followed, and if the response is semantically grounded.

### 16. What is numeric sanity?
Numeric sanity is a check (Gate C) that extracts every number from the AI's generated response and verifies that it appears verbatim in the source documents. If the AI invents a number (like claiming a capacity is 50 gallons when the document says 5 gallons), this check fails.

### 17. What is semantic grounding?
Semantic grounding is a check (Gate E) that converts the generated response into an embedding vector and compares it to the source chunks. If the conceptual similarity between the answer and the sources is too low—or if it drifts significantly compared to the original query—the answer is flagged as ungrounded (a hallucination).

### 18. What is a contradiction sweep?
The contradiction sweep (Gate D) scans the retrieved document chunks for explicit negation patterns (such as "X is Y" vs. "X is not Y"). If contradictory statements are found in the documents, the app lowers its confidence rating and flags a warning, but it does not block the answer.

### 19. What is an abstention path?
The abstention path is the refusal routine. If any critical verification checks fail (retrieval confidence, numeric sanity, semantic grounding, or domain isolation), the app overrides the generated answer and displays a refusal message stating that the documents do not contain enough evidence to answer safely.

### 20. When should the app refuse to answer?
The app refuses to answer when the retrieval scores are too low (meaning no relevant documents were found), when numbers in the answer cannot be found in the sources, when the answer drifts semantically from the sources, or when domain isolation rules reject the source documents.

### 21. What does the app currently do well?
The app has a highly structured on-device verification pipeline. Gate A (retrieval confidence), Gate C (numbers), Gate E (semantic grounding), and Gate I (domain isolation) successfully catch factual fabrications and numerical hallucinations. The Core ML reranker and fallback heuristics ensure that relevant context is prioritized.

### 22. What is still weak or uncertain?
The contradiction sweep (Gate D) is very simple; it only catches literal negation phrases and cannot detect complex logical conflicts. In addition, the candidate-pool formula contains a comment mismatch that unnecessarily discards candidate chunks in small databases. Finally, Private Cloud Compute (PCC) routing is simulated locally, meaning all requests currently execute on the local device model.

### 23. What can I safely say to engineers?
*   "I run an on-device Core ML cross-encoder model to rerank retrieved document chunks."
*   "I have a nine-gate verification pipeline that checks numeric sanity, semantic grounding, and domain isolation, and triggers a refusal if critical checks fail."
*   "I limit cross-encoder concurrency to between 2 and 4 to manage device thermal limits."

### 24. What should I avoid saying?
*   "The app guarantees zero hallucinations." (No RAG system can guarantee this.)
*   "I resolve logical contradictions in the documents." (The sweep only matches basic negation words.)
*   "I run reranking on Apple's Core AI framework today." (Core AI is only stubs/scaffolding; the app runs on Core ML.)
*   "I route cloud workloads to actual Apple PCC secure servers." (PCC is simulated locally using compatibility stubs.)

### 25. What questions should I ask smart RAG people?
*   "How do you trade off candidate-pool size versus latency and memory limits when running cross-encoders on-device?"
*   "How do you implement semantic contradiction detection without incurring the latency cost of running another LLM check?"
*   "What strategies do you use to calibrate semantic grounding thresholds when transitioning from keyword-heavy searches to concept-heavy searches?"
