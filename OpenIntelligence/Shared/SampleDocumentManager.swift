import Foundation

/// Describes a built-in sample file packaged for onboarding.
struct SampleDocumentDescriptor {
    let filename: String
    let `extension`: String
    let body: String
}

/// Handles authoring and importing curated sample documents for a better first-run experience.
@MainActor
final class SampleDocumentManager {
    static let shared = SampleDocumentManager()

    private init() {}

    private let samples: [SampleDocumentDescriptor] = [
        SampleDocumentDescriptor(
            filename: "Sample Pricing Brief",
            extension: "md",
            body: #"""
# Sample Pricing Brief

## Value Ladder
- **Free**: 5 docs, 1 library, full privacy dashboard.
    - **Pro($5.99 / mo or $49.99 / yr)**: Unlimited docs, 5 libraries, priority ingestion.
    - **Lifetime($59.99)**: Unlimited docs, 10 libraries, all Pro features forever.

## Messaging Pillars
1. *Privacy-first*: Data stays on-device or Apple PCC.
2. *Retrieval speed*: Hybrid search + MMR for grounded answers.
3 .* Simple pricing*: One upgrade path, no confusing tiers.

## Launch Tasks
- Sync App Store screenshots with this pricing grid.
- Include privacy copy on paywall and onboarding surfaces.
- Instrument upgrade funnels (quota hits, paywall views).

## Talking Points
> "OpenIntelligence keeps your knowledge base local. The Free tier lets you try it, Pro unlocks the full RAG stack."
"""#
        ),
        SampleDocumentDescriptor(
            filename: "Sample Technical Overview",
            extension: "md",
            body: #"""
# Technical Documentation: RAG Implementation

## Architecture Overview

This document provides technical specifications for the RAGMLCore implementation.

### Core Components

#### DocumentProcessor
```swift
class DocumentProcessor {
    private let targetChunkSize: Int = 350  // Optimized for retrieval quality
    private let chunkOverlap: Int = 60      // ~17% overlap

    func processDocument(at url: URL) async throws -> (Document, [String]) {
        // Implementation details
    }
}
```

**Key Features:**
- Semantic paragraph-based chunking
- Configurable chunk size and overlap
- Support for PDF, TXT, MD, RTF formats

#### EmbeddingService
Uses Apple's NLEmbedding framework for 512-dimensional semantic vectors.

**Algorithm:**
1. Split text into words
2. Generate word-level embeddings
3. Average vectors for chunk representation

**Performance Targets:**
- <100ms per chunk
- Batch processing support
- Memory-efficient implementation

### Vector Search

Cosine similarity formula:
```
similarity = (A · B) / (||A|| × ||B||)
```

Where A and B are embedding vectors.

### Configuration Parameters

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| chunk_size | 350 | 250-550 | Words per chunk (content-adaptive) |
| chunk_overlap | 60 | 40-70 | Word overlap (~17%) |
| top_k | 3 | 1-10 | Results returned |
| temperature | 0.7 | 0.0-1.0 | LLM randomness |

## Edge Cases

### Unicode Support
Test strings: 你好世界, مرحبا, Здравствуй, 🚀🎯✨

### Special Characters
Test: !@#$%^&*()_+-=[]{}|;':",./<>?

### Performance Tests
- Document size: 1KB - 10MB
- Chunk count: 1 - 10,000+
- Concurrent queries: 1 - 100

## Error Handling

All components implement proper error handling:
```swift
enum DocumentProcessingError: Error {
    case unsupportedFormat
    case pdfLoadFailed
    case emptyDocument
    case corruptedFile
}
```

## Testing Checklist

- [ ] Import various document types
- [ ] Verify chunk boundaries
- [ ] Validate embedding dimensions
- [ ] Test retrieval accuracy
- [ ] Measure performance metrics
- [ ] Handle edge cases gracefully

## References

- Apple NLEmbedding: https://developer.apple.com/documentation/naturallanguage/nlembedding
- Vector similarity: https://en.wikipedia.org/wiki/Cosine_similarity
- RAG paper: arXiv:2005.11401
"""#
        ),
        SampleDocumentDescriptor(
            filename: "Apple Intelligence Architecture 2026",
            extension: "md",
            body: #"""
The Heterogeneous Intelligence Architecture: A Deep Dive into Apple's 2026 Foundation Models and Ecosystem

Status and scope
This report integrates published Apple documentation and research with forward-looking commentary from public reports. Any item marked "Forward-looking" is provisional and should be treated as speculative.

1. Introduction: The Bifurcation of Intelligence
The release of the Apple Intelligence ecosystem in 2026 marks a definitive inflection point in consumer computing architecture. We are witnessing the transition from a paradigm of purely local, explicit instruction execution to a hybrid model of probabilistic inference and deterministic orchestration. This shift is not merely an addition of features but a fundamental restructuring of the operating system's kernel-level priorities, memory management strategies, and hardware-software integration.

At the core of this transformation is a recognition of the physical limitations of mobile silicon. While server-side Large Language Models (LLMs) have scaled to trillions of parameters, the constraints of thermal envelopes, battery density, and memory bandwidth on edge devices necessitate a radically different approach. Apple's strategy, as detailed in technical reports and developer documentation, relies on a bifurcated architecture: a highly optimized, quantized on-device foundation model for privacy and latency, coupled with a cryptographically secured Private Cloud Compute (PCC) infrastructure for complex reasoning. [1] [2]

This report provides a structured technical analysis of this architecture. It dissects the rigid context limits that define developer interactions, the routing layers that balance edge and cloud, the developer-facing framework that exposes system intelligence, and the debate regarding "thinking modes" and reasoning capabilities. It also delineates the stratification of hardware capabilities across device classes.

2. The Foundation Model Architecture
The architecture of Apple Intelligence is defined by its duality. Unlike competitors who often rely on a single monolithic model accessed via API, Apple employs a heterogeneous mix of models specialized for their execution environments. [1] [2]

2.1 The On-Device Foundation Model
The primary workhorse of the ecosystem is the on-device foundation model. With approximately 3 billion parameters, this model is small by industry standards but is engineered for extreme efficiency within the Apple Silicon Unified Memory Architecture (UMA). [1]

2.1.1 Quantization and Memory Residency
To function effectively on a device like the iPhone, which must simultaneously maintain the operating system, background processes, and active applications in memory, the model cannot monopolize RAM. Apple achieves this through low-bit quantization-aware training. [1]

Standard post-training quantization often degrades model performance by simply reducing the precision of weights (for example, from 16-bit floating point to 4-bit integer). Apple's approach incorporates quantization error into the training loss function itself. This allows the model to operate at extremely low precision without the catastrophic accuracy loss typically associated with such compression. This technique reduces the model's memory footprint enough to fit within on-device constraints while remaining resident for low-latency access. [1]

2.1.2 KV-Cache Sharing and Block Optimization
The architecture further optimizes inference through Key-Value (KV) cache sharing. In transformer models, the KV cache stores the attention context for processed tokens. As the context length grows, this cache can consume significant memory, becoming a bottleneck for long conversations. By sharing KV caches across layers, the on-device model reduces the memory bandwidth required per token generation. [1]

Additionally, the model aligns block depth ratios to the execution pipelines of the Neural Engine, ensuring that tensor operations are scheduled to minimize idle cycles. [1]

2.2 The Server Foundation Model (Private Cloud Compute)
When a task exceeds the capabilities of the 3-billion-parameter model, it is elevated to the server foundation model running on Private Cloud Compute (PCC). This model utilizes a Parallel-Track Mixture-of-Experts (PT-MoE) architecture. [1] [2]

2.2.1 Parallel-Track Mixture-of-Experts (PT-MoE)
The PT-MoE architecture addresses the two primary costs of server-side inference: computational expense and latency.

- Mixture of Experts (MoE): Rather than activating all parameters for every token, the model routes tokens to specific "expert" sub-networks. This sparsity ensures that while the model may have a massive total parameter count, the active parameter count for any single inference pass is manageable, keeping costs competitive. [1]
- Track Parallelism: By processing different "tracks" of the transformer in parallel, the server reduces the time-to-first-token (TTFT). This is critical for maintaining the illusion of responsiveness; users expecting on-device speeds will not tolerate significant cloud latency. [2]

2.2.2 Interleaved Global-Local Attention
The server model is trained to handle contexts up to 65,000 tokens. [4] To manage this without quadratic complexity scaling, it employs interleaved global-local attention. The model alternates between attending to the local context (immediate sentences) and the global context (the entire document). This allows it to maintain coherence over long-form content, such as summarizing long PDFs, without the prohibitive computational cost of full dense attention. [4]

3. Context Limits: The 4096-Token Constraint
For developers, the most immediate and rigid constraint of the Apple Intelligence framework is the context window of the on-device model.

3.1 The Hard Limit
The on-device foundation model enforces a strict limit of 4096 tokens per session. [5]

- Token density: In English and other Latin-based languages, a token corresponds to roughly 3-4 characters. For multi-byte languages like Chinese, Japanese, and Korean (CJK), the ratio is approximately one character per token. [5]
- Implication: This creates a disparity in effective context size. An English user might fit a 3,000-word article into the context window, while a Japanese user might only fit 4,000 characters.

This limit is not arbitrary software gating but a hardware necessity. The KV cache size scales linearly with context length. On a device with limited unified memory, allowing a larger context would encroach on system memory and risk app terminations or UI stutters.

3.2 Error Handling and Session Management
When a developer attempts to pass a prompt or context that exceeds this limit, the FoundationModels framework throws a specific error: LanguageModelSession.GenerationError.exceededContextWindowSize(_:). [6]

The architecture does not automatically truncate or window the input. It is the developer's responsibility to manage the token budget. This requires a shift in application logic from "stateful" conversations where history is indefinitely appended, to "managed" sessions where context is aggressively pruned or summarized. [6]

From an implementation perspective, this pushes developers toward deliberate session lifecycle control: keep sessions scoped to a task, re-create sessions when the system prompt changes, and treat over-limit errors as signals to reframe or compress context. [6]

3.3 Strategies to Exceed the Limit: RAG and Chunking
Since the hardware limit is immutable for the current generation, developers must employ software architectures to handle larger datasets.

3.3.1 Recursive Chunking
For tasks like summarization of long texts, the standard pattern is recursive chunking.

- Segmentation: The input text is split into overlapping segments of approximately 3,500 tokens (reserving buffer for the prompt).
- Parallel inference: Each chunk is processed individually by the SystemLanguageModel.
- Aggregation: The resulting summaries are concatenated and passed through the model again for a final synthesis. [6]

This approach trades latency for capacity, as it requires multiple inference passes.

3.3.2 Retrieval-Augmented Generation (RAG) via Core Spotlight
The most robust solution for exceeding the context limit is Retrieval-Augmented Generation (RAG). In the Apple ecosystem, this is implemented not through external vector databases (like Pinecone or Milvus) but through the system-native Semantic Index provided by Core Spotlight. [7] [8] [9]

The Semantic Index as a Vector Store:
In iOS 26 and macOS Sequoia, Core Spotlight evolves from a keyword-based inverted index to a semantic vector store. When developers use CSSearchableItem to index app content, the system generates embeddings for this content using a quantized encoder running on the Neural Engine. [9]

The RAG workflow:
- Indexing: The app donates content (notes, emails, messages) to the Semantic Index. [8]
- Querying: When a user asks a question via Siri or an App Intent, the system converts the query into a vector. [9]
- Retrieval: A similarity search retrieves the most relevant chunks of text from the on-device index. [9]
- Context injection: Only these relevant chunks, fitting within the 4096-token limit, are injected into the foundation model's context window. [7]

This architecture allows the 3B model to answer questions about a user's entire library of data (potentially gigabytes of text) without ever exceeding the 4096-token processing limit. [7]

4. The Apple Intelligence Framework: Developer Surface
Apple exposes system intelligence through a developer-facing framework that wraps model access, tool calling, and session management while preserving OS-level privacy and routing constraints. [6]

4.1 FoundationModels: Model Access and Sessions
The FoundationModels framework provides a system model abstraction and session-based interactions. Developers supply instructions, optional tools, and user prompts, and the system handles routing, execution context, and guardrails. [6]

Key integration characteristics:
- Session-oriented usage: Sessions encapsulate context and state for a bounded interaction. [6]
- Instruction layering: Apps provide system-style instructions that shape tone and behavior while remaining subordinate to system safety policies. [6]
- Tool calling: The model can call tools with structured arguments, enabling deterministic operations outside the model. [6]
- Streaming and structure: Responses can be streamed and can be requested in structured forms when precise output formatting is required. [6] [16]

4.2 Session Lifecycle: Practical Control Points
The framework is designed to be stateful but not indefinite. Developers should treat sessions as task-scoped, discard them on significant prompt changes, and plan for explicit re-creation after errors or context overflows. [6]

Operationally, the recommended lifecycle is:
- Build instructions and tool registry.
- Create a session for a bounded task.
- Submit user prompts and handle tool calls.
- Reset or re-create the session when the system prompt or task changes. [6]

4.3 Tool Calling and App Intents
Apple Intelligence encourages tools over free-form reasoning for tasks requiring determinism. App Intents are the primary mechanism for exposing app capabilities to the system. [24]

Integration implications:
- App Intents make app functionality addressable to system intelligence surfaces such as Siri and in-app experiences. [24]
- Tool calls should be idempotent and safe to retry, since the model may re-issue or refine calls as it converges on an answer. [6]
- Tool outputs should be concise and structured to minimize token usage and reduce hallucinated interpretation. [6]

4.4 Structured Output and Post-Validation
When developers request structured output, they should still validate outputs in app code. The framework can encourage structured responses, but final verification remains the developer's responsibility. [6] [16]

4.5 Retrieval Integration via Core Spotlight
Core Spotlight is the first-class substrate for on-device retrieval and aligns directly with RAG strategies described in Section 3.3.2. Developers who do not donate content to Spotlight limit the system's ability to ground responses in private data. [8] [9]

4.6 UX Contract: Latency, Transparency, and Privacy Gates
The framework operates within OS-level user experience expectations: response latency, privacy gating, and transparency about cloud offload. Even when developers request richer model behavior, the system enforces policy constraints around sensitive data and Private Cloud Compute eligibility. [3] [11] [12]

From an app design standpoint, this means:
- Provide clear UI states for streaming and partial responses.
- Expect offload decisions to override app preferences when privacy or device constraints require it.
- Design for graceful degradation when offload is denied or delayed. [3] [11] [12]

4.7 Execution Preferences and System Authority
The framework is a mediated surface, not a direct transport. Where APIs allow apps to express preferences (for example, allowing or disallowing cloud execution), the system remains the final arbiter. Developers should design for denied, delayed, or rerouted executions and avoid building UX that assumes a fixed path. [3] [11] [12]

4.8 End-to-End Integration Pattern
Putting the pieces together, the common integration loop looks like this:
- Assemble system instructions and declare tools (including App Intents where appropriate). [6] [24]
- Retrieve relevant context (Spotlight-backed RAG) and constrain it to the token budget. [7] [8] [9]
- Run the session, handle tool calls, and validate structured outputs. [6] [16]
- Render responses with streaming-aware UI, and handle routing failures gracefully. [3] [11] [12]

5. The Orchestration Layer: modelmanagerd
The seamless transition between the constrained on-device model and the expansive server model is not managed by the application but by a system daemon: modelmanagerd. This component acts as the orchestrator, making real-time routing decisions based on a complex set of heuristics. [3]

5.1 Routing Heuristics and Decision Matrix
Apple does not publicly document the full routing logic. The following factors reflect documented constraints and commonly cited system considerations; they should be read as inferred, not definitive. [3] [11] [12]

Decision matrix (inferred)

| Decision factor | Condition | Routing outcome | Source |
| --- | --- | --- | --- |
| Complexity | Prompt requires reasoning beyond the on-device model | Server (PCC) | [1] [2] |
| Context length | Input + output exceeds 4096 tokens | Server (PCC) | [5] |
| World knowledge | Query requires up-to-date or broad internet data | Server (PCC) | [11] |
| Thermal state | Device thermal pressure is high or critical | Server (PCC) if privacy allows | [11] |
| Battery state | Low Power Mode or critical battery | Server (PCC) or fail | [11] |
| Privacy policy | Data tagged as strictly local or sensitive | On-device only | [12] |

5.2 The Role of PrivateMLClientInferenceProviderService
When modelmanagerd determines that a request must be routed to the cloud, it does not open a direct HTTP connection. Instead, it delegates the request to the PrivateMLClientInferenceProviderService. [3]

This service handles the specific requirements of the PCC protocol:
- Attestation validation: It verifies the cryptographic attestation of the remote PCC node to ensure it is running signed, verifiable code. [3]
- Key wrapping: It encrypts the request payload with a transient key that can only be decrypted by the verified node. [3]
- Token exchange: It manages the exchange of anonymous access tokens to dissociate the user's identity (Apple ID) from the request content. [3]

This separation of concerns ensures that routing heuristics do not compromise the rigid security model. [3]

6. Privacy Architecture: Private Cloud Compute (PCC)
The Private Cloud Compute infrastructure is designed to resolve the tension between massive compute demand and absolute user privacy. It operates on a stateless computation paradigm. [11] [12]

6.1 Stateless Computation
The central promise of PCC is that user data exists in server memory only for the duration of the inference request:
- No persistence: There is no writable persistent storage for user data.
- No logging: The system prevents logging of prompt data or generated outputs.
- No inspection: Even Apple's SREs with administrative access cannot view active memory contents due to memory encryption anchored in secure hardware. [11] [12]

6.2 Verifiable Transparency
To foster trust, Apple has implemented a system of verifiable transparency. The software images running on PCC nodes are cryptographically signed, and these signatures are published to a public transparency log. Security researchers can inspect these logs and the provided software images in a Virtual Research Environment (VRE) to verify that the code running on the server matches the privacy promises. If a device detects a signature mismatch during the attestation phase, it will refuse to connect, treating the server as compromised. [12]

7. Thinking Modes: The Illusion of Reasoning
A critical aspect of the 2026 AI landscape is the debate surrounding "reasoning" models. While competitors have pushed Chain of Thought (CoT) as a path to general intelligence, Apple's research and implementation take a more skeptical, pragmatic stance. [13] [14]

7.1 "The Illusion of Thinking"
Apple's research paper, The Illusion of Thinking, challenges the efficacy of uncontrolled CoT. The research argues that what appears to be logical reasoning in LLMs is often sophisticated pattern matching. [13] [14]

- Fragility: Minor perturbations in logic puzzles (for example, changing names or constraints) can cause model performance to collapse, indicating that the model may be reciting learned templates rather than reasoning. [13]
- Scaling paradox: Increasing token budgets for reasoning can lead to diminishing returns or hallucinations on tasks that exceed the model's pattern-matching horizon. [13]

7.2 Developer Implications: Tools over Thoughts
Because of this skepticism, the Apple Intelligence framework discourages relying on the model for pure computation or logic. Instead, it prioritizes tool calling. [6]

- Deterministic vs. probabilistic: Instead of asking the model to calculate a math problem (probabilistic and error-prone), the system prompts the model to generate a call to a calculator function (deterministic and accurate).
- App Intents: Developers are encouraged to expose their app's logic via App Intents. The "thinking" of the model is restricted to understanding the user's intent and mapping it to the correct App Intent. The actual execution of the task is handled by the app's native code, not the LLM. [24]

7.3 Guided Chain of Thought
Despite the skepticism, the framework supports guided CoT for specific use cases where intermediate reasoning improves output structure. The FoundationModels framework allows developers to request structured output, encouraging the model to generate a reasoning trace before the final answer. This acts as a scratchpad, stabilizing the attention mechanism before it commits to a final token sequence. [6] [16]

8. Device Implications and Hardware Stratification
The unified brand of "Apple Intelligence" hides a significant stratification in hardware capabilities. The device landscape is divided into legacy AI devices and optimized AI devices.

8.1 The Optimized Tier: iPhone 17 (A19) and M5 Macs (Forward-looking)
The iPhone 17 lineup, powered by the A19 and A19 Pro chips, represents the hardware target for the mature Apple Intelligence experience.

- Neural Engine throughput: The A19 features a 16-core Neural Engine with improved TOPS compared to the A17 Pro, enabling near-instant local inference. [17] [18]
- Memory bandwidth: The A19 Pro includes enhanced memory bandwidth, a critical factor for LLM inference which is typically memory-bound. [17] [18]
- N1 chip: The inclusion of the Apple-designed N1 networking chip is expected to reduce PCC handoff latency. [18]
- Visual Intelligence: The iPhone 17 includes hardware buttons (Camera Control) and ray-tracing capabilities that integrate with Visual Intelligence for real-time environment analysis. [19]

8.2 The Legacy Tier: iPhone 15 Pro and 16 Series
While capable of running Apple Intelligence, these devices operate closer to their physical limits.

- Thermal constraints: Users may experience dimming screens or halted charging during prolonged AI sessions as modelmanagerd throttles performance. [11] [20]
- Battery impact: Intensive use of the Neural Engine on A17 Pro and A18 drains battery faster than newer nodes. [20]
- Feature gating: Advanced real-time features, particularly those involving video analysis or multi-modal concurrent processing, may be disabled or routed exclusively to PCC due to limited local resources.

8.3 Desktop and iPad: The M-Series Advantage
The Mac and iPad lineups (M1 and later) possess a distinct advantage: total memory capacity.

- Xcode predictive completion: This feature is exclusive to Macs with Apple Silicon and is smoother with 16GB+ of RAM. It runs a specialized coding model that is too large for the iPhone's memory footprint. [21] [22]
- Local RAG scale: A Mac with 64GB or 128GB of RAM can index and search significantly larger local datasets via Core Spotlight without performance degradation, enabling professional knowledge management workflows that are impractical on mobile. [9]

8.4 Summary of Device Capabilities

| Device class | Chipset | Context capability | Key constraints | Primary AI role |
| --- | --- | --- | --- | --- |
| iPhone 17 Pro | A19 Pro | 4096 (fast) | Heat (sustained) | Real-time agent, Visual Intelligence |
| iPhone 17 | A19 | 4096 (fast) | RAM (multitasking) | Everyday assistant, smart reply |
| iPhone 16 Pro | A18 Pro | 4096 (moderate) | Thermal throttling | Legacy support, photo editing |
| iPhone 15 Pro | A17 Pro | 4096 (slow) | Battery, heat | Entry-level AI, frequent PCC offload |
| Mac (Pro/Studio) | M1-M5 Max/Ultra | 4096+ (local LLMs) | None (high RAM) | Code gen, local training, large RAG |
| iPad Pro | M4/M5 | 4096 (fast) | OS limitations | Creative tools, image wand |

9. Developer Best Practices and Future Outlook
To succeed in this ecosystem, developers must adapt their architectures to the constraints and capabilities of the platform.

9.1 The "Agentic" Shift
The future of Apple Intelligence is not in building isolated chatbots but in building agentic apps:
- Expose intents: Developers must map their app's functionality to App Intents. This allows Siri to drive the app. [24]
- Donate to Spotlight: Data must be donated to the Semantic Index to be discoverable by the RAG layer. If it is not indexed, it is invisible to the intelligence layer. [8] [9]

9.2 Battery and Thermal Management
Developers must be cognizant of the "AI tax" on battery life:
- Batching: Avoid triggering inference on every keystroke. Use debounce timers or explicit user triggers (for example, a "Summarize" button) to spare the battery.
- Fallbacks: Implement fallback UI for when modelmanagerd denies access due to thermal pressure or low battery.

9.3 Conclusion
The Apple Intelligence architecture of 2026 is a masterclass in compromise. By accepting the hard limits of physics (memory bandwidth, heat, battery), Apple has built a system that is less "magical" in raw reasoning power than server-only competitors, but more practical for personal, private, and integrated use. The bifurcated model of on-device efficiency and private cloud power, governed by strict orchestration logic, sets the template for the next decade of mobile computing. For developers, the message is clear: optimize for the edge, trust the orchestration, and build tools, not just prompts.

Works cited
1. Apple Intelligence Foundation Language Models Tech Report 2025, https://machinelearning.apple.com/research/apple-foundation-models-tech-report-2025
2. Introducing Apple's On-Device and Server Foundation Models, https://machinelearning.apple.com/research/introducing-apple-foundation-models
3. Request Flow | Documentation - Apple Security Research, https://security.apple.com/documentation/private-cloud-compute/requestflow
4. Updates to Apple's On-Device and Server Foundation Language Models, https://machinelearning.apple.com/research/apple-foundation-models-2025-updates
5. TN3193: Managing the on-device foundation model's context window - Apple Developer, https://developer.apple.com/documentation/technotes/tn3193-managing-the-on-device-foundation-model-s-context-window
6. Generating content and performing tasks with Foundation Models - Apple Developer, https://developer.apple.com/documentation/FoundationModels/generating-content-and-performing-tasks-with-foundation-models
7. Context Tuning for Retrieval Augmented Generation - Apple Machine Learning Research, https://machinelearning.apple.com/research/context-tuning-retrieval
8. Adding your app's content to Spotlight indexes | Apple Developer Documentation, https://developer.apple.com/documentation/corespotlight/adding-your-app-s-content-to-spotlight-indexes
9. Core Spotlight | Apple Developer Documentation, https://developer.apple.com/documentation/corespotlight
10. Apple Intelligence but with multiple chats, RAG, and Web Search : r/LocalLLaMA, https://www.reddit.com/r/LocalLLaMA/comments/1mapwdm/apple_intelligence_but_with_multiple_chats_rag/
11. Private Cloud Compute: A new frontier for AI privacy in the cloud - Apple Security Research, https://security.apple.com/blog/private-cloud-compute/
12. Security research on Private Cloud Compute, https://security.apple.com/blog/pcc-security-research/
13. The Illusion of Thinking: Understanding the Strengths and Limitations of Reasoning Models via the Lens of Problem Complexity, https://ml-site.cdn-apple.com/papers/the-illusion-of-thinking.pdf
14. The Illusion of Thinking: Understanding the Strengths and Limitations of Reasoning Models via the Lens of Problem Complexity - Apple Machine Learning Research, https://machinelearning.apple.com/research/illusion-of-thinking
15. The Hidden Flaws in AI Reasoning Questions Uncovered by Apple's Latest Research, https://wowlabz.com/hidden-flaws-in-ai-reasoning/
16. Chain of Thought Prompting in LLMs - Dev-kit, https://dev-kit.io/blog/ai/chain-of-thought-prompting
17. iPhone 17 - Technical Specifications - Apple, https://www.apple.com/iphone-17/specs/
18. iPhone 17: Everything We Know | MacRumors, https://www.macrumors.com/roundup/iphone-17/
19. I took Apple Visual Intelligence to an art gallery to act as my tour guide - here's how it did, https://www.tomsguide.com/phones/iphones/i-took-apple-visual-intelligence-to-an-art-gallery-to-act-as-my-tour-guide-heres-how-it-did
20. Battery life with Apple Intelligence enabled vs disabled : r/ios18beta, https://www.reddit.com/r/ios18beta/comments/1fnh779/battery_life_with_apple_intelligence_enabled_vs/
21. Predictive Code Completion in Xcode - Lickability, https://lickability.com/blog/xcode-predictive-code-completion/
22. Xcode predictive code completion only works on Macs with 16GB memory : r/apple, https://www.reddit.com/r/apple/comments/1dd8i5j/xcode-predictive-code-completion_only_works_on/
23. WWDC on 9 June: What is (not) expected - Digitec, https://www.digitec.ch/en/page/wwdc-on-9-june-what-is-not-expected-38198
24. App Intents | Apple Developer Documentation, https://developer.apple.com/documentation/appintents
25. Apple's iOS 19 to Feature AI-Powered Battery Management | FMP - Financial Modeling Prep, https://site.financialmodelingprep.com/market-news/apples-ios--to-feature-aipowered-battery-management

"""#
        ),
    ]

    /// Total number of bundled sample documents, used for quota calculations.
    var sampleCount: Int { samples.count }

    /// Writes curated samples to disk and ingests them into the active RAG pipeline.
    /// Uses `.onboarding` context to prevent self-tuning rebuilds during initial setup.
    func importSamples(
        into ragService: RAGService,
        onProgress: ((Int, Int, String) -> Void)? = nil
    ) async throws {
        let urls = try writeSamplesToDocumentsDirectory()
        for (index, url) in urls.enumerated() {
            let filename = url.deletingPathExtension().lastPathComponent
            onProgress?(index + 1, urls.count, filename)
            try await ragService.addDocument(at: url, context: .onboarding)
            // DON'T delete - keep files so self-tuning rebuild can find them
        }
    }

    /// Persists each sample document in the app's Documents directory (permanent storage).
    /// Using Documents directory ensures files persist for self-tuning rebuilds.
    /// Files use stable names (no UUID suffix) to prevent duplicate imports.
    private func writeSamplesToDocumentsDirectory() throws -> [URL] {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let samplesDir = documentsDir.appendingPathComponent("SampleDocuments", isDirectory: true)

        // Create samples directory if needed
        try FileManager.default.createDirectory(at: samplesDir, withIntermediateDirectories: true)

        var urls: [URL] = []
        for sample in samples {
            let filename = sample.filename.replacingOccurrences(of: " ", with: "-")
            let fileURL = samplesDir
                .appendingPathComponent(filename)
                .appendingPathExtension(sample.extension)

            // Only write if file doesn't already exist (prevents duplicate ingestion)
            if !FileManager.default.fileExists(atPath: fileURL.path) { 
                try sample.body.write(to: fileURL, atomically: true, encoding: .utf8)
            }
            urls.append(fileURL)
        }
        return urls
    }
}
