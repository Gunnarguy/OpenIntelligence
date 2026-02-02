# Apple Intelligence Models & Specs

> **Scope**: Token limits, context rules, and integration constraints for iOS 26+ Foundation Models.
> **Source**: Official Apple Developer Documentation (iOS 26.0+)
> **Last Updated**: January 2026
> **Tech Note**: [TN3193: Managing the on-device foundation model's context window](https://developer.apple.com/documentation/Technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)

---

## Table of Contents

1. [Context Window Limit](#context-window-limit)
2. [Token Economics](#token-economics)
3. [LanguageModelSession](#languagemodelsession)
4. [Tool Calling](#tool-calling)
5. [Guided Generation (@Generable)](#guided-generation-generable)
6. [Content Tagging Use Case](#content-tagging-use-case)
7. [Safety & Guardrails](#safety--guardrails)
8. [Prompting Best Practices](#prompting-best-practices)
9. [RAG Integration (Apple's Recommendation)](#rag-integration-apples-recommendation)
10. [Performance Optimization](#performance-optimization)
11. [Error Handling](#error-handling)

---

## Context Window Limit

### The Hard Truth: 4096 Tokens

> **"Apple's on-device foundation model has a context window of 4096 tokens per language model session."**
> — TN3193

This is a **hard limit**. There is NO 65K extended context for PCC (Private Cloud Compute). The 4096 limit applies to:

- On-device execution
- PCC execution (same model, just faster inference)

### What Counts Toward the Limit

Everything in a session contributes to the 4096 token budget:

| Component                                    | Token Impact |
| -------------------------------------------- | ------------ |
| Instructions                                 | Yes          |
| All prompts (multi-turn)                     | Yes          |
| All model responses                          | Yes          |
| Tool schemas (name, description, parameters) | Yes          |
| Generable type schemas                       | Yes          |
| @Guide descriptions                          | Yes          |

### Character-to-Token Ratio

| Language                                  | Ratio            |
| ----------------------------------------- | ---------------- |
| English, Spanish, German (Latin alphabet) | ~3-4 chars/token |
| Chinese, Japanese, Korean                 | ~1 char/token    |

**Practical math for English**: 4096 tokens × 3.5 chars ≈ **14,336 characters max** for entire session.

---

## Token Economics

### Budget Allocation Strategy

Given 4096 tokens, allocate wisely:

```
┌─────────────────────────────────────────┐
│ Instructions:     ~200-400 tokens       │
│ Tool Schemas:     ~100-300 tokens (3-5) │
│ Generable Schema: ~50-100 tokens        │
│ User Prompt:      ~100-500 tokens       │
│ RAG Context:      ~1000-2000 tokens     │
│ Model Response:   ~500-1500 tokens      │
│ Buffer:           ~200 tokens           │
└─────────────────────────────────────────┘
```

### Token-Saving Strategies

1. **Short property names** in Generable types
2. **Minimal @Guide descriptions** - only where needed
3. **3-5 tools maximum** with brief descriptions
4. **1-3 paragraph instructions** max
5. **Split complex tasks** across multiple sessions

---

## LanguageModelSession

### Basic Usage

```swift
import FoundationModels

// Check availability first
let model = SystemLanguageModel.default
guard case .available = model.availability else {
    // Handle unavailable: .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady
    return
}

// Create session with instructions
let instructions = """
    You are a helpful assistant. Keep responses concise.
    """
let session = LanguageModelSession(instructions: instructions)

// Generate response
let response = try await session.respond(to: "Hello")
```

### Availability States

```swift
switch model.availability {
case .available:
    // Ready to use
case .unavailable(.deviceNotEligible):
    // Device doesn't support Apple Intelligence
case .unavailable(.appleIntelligenceNotEnabled):
    // User hasn't enabled Apple Intelligence in Settings
case .unavailable(.modelNotReady):
    // Model is downloading or system is busy
case .unavailable(let other):
    // Unknown reason
}
```

### Session Properties

| Property       | Description                             |
| -------------- | --------------------------------------- |
| `isResponding` | Bool - check before sending new request |
| `transcript`   | Full history of interactions            |

### Transcript Rehydration

Save and restore sessions:

```swift
// Save transcript
let savedTranscript = session.transcript

// Later: restore session from transcript
let restoredSession = LanguageModelSession(
    model: .default,
    tools: myTools,
    transcript: savedTranscript
)
```

### Prewarming for Performance

```swift
// Preload model and optionally cache prompt prefix
session.prewarm(promptPrefix: "Given the following context...")
```

---

## Tool Calling

### Tool Protocol

```swift
protocol Tool: Sendable {
    associatedtype Arguments: ConvertibleFromGeneratedContent
    associatedtype Output: PromptRepresentable

    var name: String { get }
    var description: String { get }

    func call(arguments: Arguments) async throws -> Output
}
```

### Example Tool Implementation

```swift
struct FindContacts: Tool {
    let name = "findContacts"
    let description = "Find contacts by count"  // Keep SHORT

    @Generable
    struct Arguments {
        @Guide(description: "Number of contacts", .range(1...10))
        let count: Int
    }

    func call(arguments: Arguments) async throws -> [String] {
        // Fetch contacts...
        return ["Alice", "Bob"]
    }
}
```

### Tool Best Practices

| Do                                       | Don't                              |
| ---------------------------------------- | ---------------------------------- |
| 3-5 tools maximum                        | 10+ tools                          |
| Short descriptions (one phrase)          | Long explanatory descriptions      |
| Simple argument types                    | Complex nested structures          |
| Run essential tools BEFORE calling model | Always rely on model to call tools |

### Creating Session with Tools

```swift
let session = LanguageModelSession(
    model: .default,
    tools: [FindContacts(), GetWeather(), SearchDatabase()],
    instructions: "You can search contacts and check weather."
)
```

---

## Guided Generation (@Generable)

### Basic Generable Struct

```swift
@Generable(description: "Profile information")
struct Profile {
    var name: String

    @Guide(description: "Age in years", .range(0...120))
    var age: Int

    @Guide(description: "One sentence bio")
    var bio: String
}
```

### Generating Typed Responses

```swift
let response = try await session.respond(
    to: "Generate a profile for a software engineer",
    generating: Profile.self
)
// response.content is Profile, not String!
```

### Supported Types

- `String`, `Bool`, `Int`, `Float`, `Double`, `Decimal`
- `Array<T>` where T is Generable
- Nested Generable structs
- Enums (with or without associated values)

### Enum for Constrained Output

```swift
@Generable
enum Sentiment {
    case positive
    case negative
    case neutral
}

// Forces model to pick from exactly these options
let response = try await session.respond(
    to: "What's the sentiment of: 'I love this!'",
    generating: Sentiment.self
)
```

### Generation Guides

```swift
@Guide(description: "...", .range(1...10))        // Numeric range
@Guide(description: "...", .maximumCount(5))      // Array max length
@Guide(description: "...", .minimumCount(1))      // Array min length
```

### Reasoning Field Pattern (IMPORTANT)

For complex tasks, add a reasoning field **FIRST**:

```swift
@Generable
struct ReasonedAnswer {
    // MUST be first - lets model think before answering
    var reasoningSteps: String

    @Guide(description: "The final answer only")
    var answer: String
}
```

Prompt pattern:

```swift
let instructions = """
    1. Begin with a plan to solve this question.
    2. Show your reasoning steps.
    3. Deliver the final answer in `answer`.
    """
```

### Dynamic Schema (Runtime)

```swift
let schema = DynamicGenerationSchema(
    name: "Menu",
    properties: [
        DynamicGenerationSchema.Property(
            name: "dailySoup",
            schema: DynamicGenerationSchema(
                name: "dailySoup",
                anyOf: ["Tomato", "Chicken Noodle", "Clam Chowder"]
            )
        )
    ]
)

let genSchema = try GenerationSchema(root: schema, dependencies: [])
let response = try await session.respond(to: prompt, schema: genSchema)
```

---

## Content Tagging Use Case

Specialized lighter model for categorization:

```swift
let model = SystemLanguageModel(useCase: .contentTagging)
let session = LanguageModelSession(
    model: model,
    instructions: "Provide two tags for main topics."
)

@Generable
struct ContentTags {
    @Guide(description: "Main topics", .maximumCount(2))
    let topics: [String]

    @Guide(description: "Emotions detected", .maximumCount(3))
    let emotions: [String]
}

let response = try await session.respond(
    to: "We had a lovely picnic at the beach!",
    generating: ContentTags.self
)
// topics: ["outdoor activity", "beach"]
// emotions: ["joy", "relaxation"]
```

---

## Safety & Guardrails

### Built-in Safety Layers

1. **Model Training**: Handles sensitive topics with care
2. **Guardrails**: Block harmful content (self-harm, violence, adult)

### Guardrail Violation Error

```swift
do {
    let response = try await session.respond(to: prompt)
} catch LanguageModelSession.GenerationError.guardrailViolation {
    // Input or output failed safety check
    // Show user-friendly message, offer to rephrase
}
```

### Model Refusal

For string responses, refusals start with "Sorry, I can't help with..."

For Generable responses:

```swift
do {
    let response = try await session.respond(to: prompt, generating: MyType.self)
} catch LanguageModelSession.GenerationError.refusal(let refusal, _) {
    if let message = try? await refusal.explanation {
        // Show explanation to user
    }
}
```

### Permissive Mode (For Sensitive Source Material)

```swift
// Allows reasoning about sensitive INPUT without triggering guardrails
let model = SystemLanguageModel(guardrails: .permissiveContentTransformations)
let session = LanguageModelSession(model: model)
```

**Note**: Only works for String responses, not Generable.

### App-Level Safety Strategies

1. **Fixed-choice prompts**: Safest - predefined options only
2. **Deny lists**: Block specific terms in input/output
3. **Instructions for safety**: "ALWAYS respond respectfully. If asked for harmful content, respond with 'Sorry, I can't do that.'"
4. **Output constraints**: Use Generable enums to limit possible outputs

---

## Prompting Best Practices

### Keep It Simple

| Do                                               | Don't                       |
| ------------------------------------------------ | --------------------------- |
| Single, well-defined goal                        | Multiple unrelated requests |
| Direct imperatives: "List", "Create", "Generate" | Passive voice, hedging      |
| 1-3 paragraphs max                               | Long rambling instructions  |
| "using three sentences"                          | Open-ended length           |

### Example: Good vs Bad

✅ **Good**:

```
Given a person's home-decor transactions, generate three relevant
categories starting with the most relevant.
```

❌ **Bad**:

```
The person's input contains their recent home-decor transaction history
along with their recent search history. The response should be a list of
existing categories of content the person might be interested in relevant
to their search and transactions, ordered so that the first categories in
the list are most relevant. For inspiration, the response should also
include new categories that spark creative ideas...
```

### Role & Persona

```swift
let instructions = """
    You are a senior software engineer who values mentoring.
    The person is a first-grade student.
    Respond in a friendly, encouraging tone.
    """
```

### Emphasis for Important Rules

Use UPPERCASE for critical instructions:

```swift
let instructions = """
    ALWAYS respond in a respectful way.
    You MUST decline harmful requests with 'Sorry, I can't do that.'
    NEVER include personal information in responses.
    """
```

### Conditional Logic: Code > Prompts

Instead of:

```
IF the guest is a bard, ask about music.
IF the guest is a soldier, ask about danger.
```

Do this:

```swift
let customGreeting = switch role {
case .bard: "Ask if they'll play music."
case .soldier: "Ask about recent dangers."
default: "Welcome the traveler."
}

let instructions = """
    You are an innkeeper. Greet the guest.
    \(customGreeting)
    """
```

### Few-Shot Prompting

Provide 2-15 simple examples:

```swift
let instructions = """
    Create an NPC customer. Examples:

    {name: "Thimblefoot", imageDescription: "A horse with rainbow mane",
     coffeeOrder: "Something refreshing and sweet."}
    {name: "Wise Fairy", imageDescription: "A blue glowing fairy",
     coffeeOrder: "Something simple and plant-based."}
    """
```

---

## RAG Integration (Apple's Recommendation)

> "Retrieval-Augmented Generation, or RAG, is a technique that combines a retrieval system (like a search engine or vector database) with a language model. If your use case has a large amount of information, notes, or documents you'd like the model to reference, you may have too much information to fit in the context window. Using RAG, you can dynamically fetch snippets of the relevant information when needed, and pass only the snippets to the model to stay within the context window."

### Apple's Recommended RAG Flow

1. **Chunking**: Split knowledge base into chunks
2. **Embedding**: Vectorize chunks (Apple suggests CoreML or NaturalLanguage framework)
3. **Storage**: Store in vector database
4. **Retrieval**: On query, vectorize query and find relevant chunks
5. **Generation**: Feed query + relevant chunks to model

### Key RAG Considerations

- **Chunk size**: Must fit within context budget (~1000-2000 tokens for RAG context)
- **Pre-retrieval**: Can run as tool call OR before calling model
- **Vectorization**: Can be heavy - consider pre-processing offline

---

## Performance Optimization

### Prewarming

```swift
// Load model into memory + optionally cache prompt prefix
session.prewarm(promptPrefix: "Based on the following documents...")
```

### Instruments Profiling

1. Xcode > Product > Profile
2. Select Blank template
3. Add "Foundation Models" instrument
4. Record and observe token consumption

### Response Time Factors

| Factor               | Impact               |
| -------------------- | -------------------- |
| Prompt length        | Longer = slower      |
| Response length      | Longer = slower      |
| Tool count           | More tools = slower  |
| Generable complexity | More fields = slower |

### Generation Options

```swift
let options = GenerationOptions(
    temperature: 1.0,        // Default. Higher = more creative
    maximumResponseTokens: 500  // Use sparingly - can cause truncation
)

let response = try await session.respond(
    to: prompt,
    options: options
)
```

---

## Error Handling

### Error Types

```swift
enum LanguageModelSession.GenerationError {
    case exceededContextWindowSize(ContextOverflowInfo)
    case guardrailViolation(GuardrailInfo)
    case refusal(Refusal, PartialContent?)
}
```

### Context Window Overflow

```swift
do {
    let response = try await session.respond(to: prompt)
} catch LanguageModelSession.GenerationError.exceededContextWindowSize(let info) {
    // Create new session
    // Shorten prompts
    // Split task across sessions
}
```

### Recovery Strategy for Overflow

```swift
func newContextualSession(with originalSession: LanguageModelSession) -> LanguageModelSession {
    let allEntries = originalSession.transcript
    // Keep first and last entries for context
    let condensed = [allEntries.first, allEntries.last].compactMap { $0 }
    let condensedTranscript = Transcript(entries: condensed)
    var newSession = LanguageModelSession(transcript: condensedTranscript)
    newSession.prewarm()
    return newSession
}
```

### Feedback to Apple

```swift
let feedbackData = session.logFeedbackAttachment(
    sentiment: .negative,
    issues: [.incorrectResponse],
    desiredResponseText: "Expected output here"
)
// Submit via Feedback Assistant
```

---

## OpenIntelligence Implementation Notes

### Current Architecture Alignment

| Apple Recommendation            | OpenIntelligence Implementation            |
| ------------------------------- | ------------------------------------------ |
| RAG for large knowledge bases   | ✅ VectorStoreRouter + HybridSearchService |
| 3-5 tools max                   | ⚠️ We have 12+ @Tool functions - OPTIMIZE  |
| Multi-session for complex tasks | ✅ Deep Think uses parallel sessions       |
| Chunking + embedding            | ✅ SemanticChunker + NLEmbedding           |
| Short instructions              | ⚠️ May need optimization                   |

### Optimization Opportunities

1. **Reduce tool count** - Consolidate or remove rarely-used tools
2. **Shorter @Guide descriptions** - Trim to essential phrases
3. **Add reasoning field** - First property in response structs
4. **Implement prewarm()** - For common prompt prefixes
5. **Use contentTagging** - For classification tasks (lighter model)

### Token Budget for RAG Context

With 4096 total tokens:

- ~500 tokens for instructions + tool schemas
- ~500 tokens for prompt
- ~1000-1500 tokens for model response
- **~1500-2000 tokens available for RAG context**

At 3.5 chars/token: **~5,250-7,000 characters for RAG snippets**

---

## References

- [Foundation Models Framework](https://developer.apple.com/documentation/foundationmodels)
- [TN3193: Managing Context Window](https://developer.apple.com/documentation/Technotes/tn3193-managing-the-on-device-foundation-model-s-context-window)
- [Generating Content Guide](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models)
- [Tool Protocol](https://developer.apple.com/documentation/foundationmodels/tool)
- [Guided Generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation)
- [Safety Guide](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output)
- [Prompting Guide](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model)
- [Content Tagging](https://developer.apple.com/documentation/foundationmodels/categorizing-and-organizing-data-with-content-tags)
- [WWDC25 Session 286: Meet the Foundation Models framework](https://developer.apple.com/videos/play/wwdc2025/286/)
