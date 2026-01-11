# Apple Framework API Reference

**Version**: 1.0
**Updated**: January 10, 2026
**Platform**: iOS 26.0+ / Apple Intelligence

Quick reference for Apple framework APIs used in OpenIntelligence.

---

## FoundationModels Framework (iOS 26+)

The FoundationModels framework provides access to Apple Intelligence's on-device LLM.

### Availability Check

```swift
import FoundationModels

// Check if Apple Intelligence is available
if LanguageModelSession.isAvailable {
    // Device supports on-device AI
}

// Detailed availability status
switch await LanguageModelSession.availabilityStatus {
case .available:
    // Ready to use
case .unavailable(.deviceNotSupported):
    // Device doesn't have Apple Intelligence
case .unavailable(.insufficientMemory):
    // Not enough RAM available
case .unavailable(.modelNotReady):
    // Model still downloading/preparing
}
```

### Basic Session Usage

```swift
import FoundationModels

// Create a session
let session = LanguageModelSession()

// Simple generation
let response = try await session.respond(to: "What is the capital of France?")
print(response.content)  // "The capital of France is Paris."

// Streaming generation
for try await chunk in session.streamResponse(to: prompt) {
    print(chunk.content, terminator: "")
}
```

### Context Window Limits

| Limit | Value | Notes |
|-------|-------|-------|
| Context Window | 4,096 tokens | Per session |
| Input Limit | ~3,000 tokens | Leave room for output |
| Output Limit | ~1,000 tokens | Typical response |

**Workaround for large context**: Chain multiple sessions (see AgenticOrchestrator)

### Guided Generation (@Generable)

```swift
import FoundationModels

@Generable
struct MovieReview {
    @Guide(description: "A score from 1-10")
    var rating: Int

    @Guide(description: "A brief summary of the review")
    var summary: String

    @Guide(description: "Key pros and cons")
    var prosAndCons: [String]
}

// Use it
let session = LanguageModelSession()
let review: MovieReview = try await session.respond(
    to: "Review the movie Inception",
    generating: MovieReview.self
)
print(review.rating)    // 9
print(review.summary)   // "A mind-bending thriller..."
```

### Tool Calling

```swift
import FoundationModels

struct SearchTool: Tool {
    static let name = "search_documents"
    static let description = "Search the knowledge base for relevant documents"

    @Generable
    struct Arguments {
        @Guide(description: "The search query")
        var query: String

        @Guide(description: "Maximum results to return")
        var maxResults: Int?
    }

    func call(arguments: Arguments) async throws -> ToolOutput {
        let results = await performSearch(query: arguments.query)
        return ToolOutput(content: results.description)
    }
}

// Register tools with session
let session = LanguageModelSession(tools: [SearchTool()])
let response = try await session.respond(to: "Find documents about machine learning")
// LLM may call SearchTool automatically
```

### Session Warming

```swift
// Pre-warm the model with common prompt prefix
try await session.prewarm(promptPrefix: """
You are a helpful assistant with access to a knowledge base.
When answering questions, cite your sources.
""")

// Subsequent generations are faster
let response = try await session.respond(to: userQuery)
```

### Transcript Persistence

```swift
// Save conversation state
let transcript = session.transcript
let data = try JSONEncoder().encode(transcript)
saveToStorage(data)

// Resume conversation
let savedData = loadFromStorage()
let transcript = try JSONDecoder().decode(Transcript.self, from: savedData)
let session = LanguageModelSession(transcript: transcript)
```

---

## NaturalLanguage Framework

### NLEmbedding (iOS 13+)

512-dimensional word and sentence embeddings.

```swift
import NaturalLanguage

// Get embedding model
guard let embedding = NLEmbedding.sentenceEmbedding(for: .english) else {
    throw EmbeddingError.modelNotAvailable
}

// Generate embedding vector
if let vector = embedding.vector(for: "Hello, world!") {
    // vector is [Double] with 512 dimensions
    print(vector.count)  // 512
}

// Compute similarity
let distance = embedding.distance(between: "cat", and: "dog")
// distance uses cosine similarity (0 = identical, 2 = opposite)
let similarity = 1.0 - (distance / 2.0)  // Convert to 0-1 similarity

// Check supported languages
let languages = NLEmbedding.supportedLanguages
// [.english, .french, .german, .spanish, .portuguese, .italian, ...]
```

### NLContextualEmbedding (iOS 17+)

BERT-like contextual embeddings that consider surrounding words.

```swift
import NaturalLanguage

// List available models
let models = NLContextualEmbedding.availableAssets
// Returns array of available embedding models

// Load contextual embedding
if let contextual = NLContextualEmbedding(language: .english) {
    // Process text
    let result = try await contextual.processString("The bank by the river")

    // Get embeddings for each token
    result.enumerateTokenVectors(in: result.string.startIndex..<result.string.endIndex) {
        token, vector in
        // token = "bank", vector = contextual embedding
        // Note: "bank" has different embedding than "I bank with Chase"
    }
}

// Supported languages (27+)
// .english, .french, .german, .spanish, .italian, .portuguese,
// .dutch, .polish, .russian, .japanese, .korean, .chinese, etc.
```

### NLTagScheme for Named Entities

```swift
import NaturalLanguage

let tagger = NLTagger(tagSchemes: [.nameType, .lexicalClass])
tagger.string = "Apple is headquartered in Cupertino, California."

tagger.enumerateTags(in: text.startIndex..<text.endIndex,
                      unit: .word,
                      scheme: .nameType) { tag, range in
    if let tag = tag {
        print("\(text[range]): \(tag.rawValue)")
        // "Apple": OrganizationName
        // "Cupertino": PlaceName
        // "California": PlaceName
    }
    return true
}
```

---

## Core ML (Embedding & Reranking Models)

### Loading Bundled Models

```swift
import CoreML

// Load embedding model from bundle
let config = MLModelConfiguration()
config.computeUnits = .cpuAndGPU

let embeddingModel = try EmbeddingModel(configuration: config)

// Run inference
let input = EmbeddingModelInput(text: "Hello, world!")
let output = try embeddingModel.prediction(input: input)
let embedding = output.embeddingOutput  // MLMultiArray
```

### Model Specifications

**EmbeddingModel.mlpackage**
- Input: String (tokenized internally)
- Output: 512-dim float vector
- Vocabulary: `embedding_vocab.json`

**ReRankerModel.mlpackage**
- Input: Query + Document pair
- Output: Relevance score (0-1)
- Vocabulary: `reranker_vocab.json`

---

## Combine Integration

### Settings Debouncing

```swift
import Combine

// In SettingsStore.swift
private var cancellables = Set<AnyCancellable>()

// Debounce rapid setting changes
$enableHyDE
    .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
    .removeDuplicates()
    .sink { [weak self] value in
        self?.persistAll()
    }
    .store(in: &cancellables)
```

### Streaming Response Publishing

```swift
import Combine

// In LLMStreamingContext.swift
let tokenPublisher = PassthroughSubject<String, Never>()

// Publish tokens as they arrive
for try await chunk in session.streamResponse(to: prompt) {
    tokenPublisher.send(chunk.content)
}
tokenPublisher.send(completion: .finished)

// Subscribe in UI
tokenPublisher
    .receive(on: DispatchQueue.main)
    .sink { token in
        self.displayedText += token
    }
    .store(in: &cancellables)
```

---

## SwiftUI Integration

### Environment Objects

```swift
// App entry point
@main
struct OpenIntelligenceApp: App {
    @StateObject private var settings = SettingsStore()
    @StateObject private var ragService = RAGService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(ragService)
        }
    }
}

// In views
struct ChatScreen: View {
    @EnvironmentObject var settings: SettingsStore
    @EnvironmentObject var ragService: RAGService

    var body: some View {
        // Access settings.enableHyDE, ragService.messages, etc.
    }
}
```

### Task Cancellation Pattern

```swift
struct ChatScreen: View {
    @State private var currentTask: Task<Void, Never>?

    func sendMessage() {
        // Cancel any in-flight request
        currentTask?.cancel()

        currentTask = Task {
            defer { currentTask = nil }

            do {
                // Check for cancellation at key points
                try Task.checkCancellation()
                let embedding = await generateEmbedding()

                try Task.checkCancellation()
                let results = await search(embedding)

                try Task.checkCancellation()
                await generateResponse(results)

            } catch is CancellationError {
                // Silently ignore - user sent new query
            } catch {
                // Handle actual errors
            }
        }
    }
}
```

---

## Quick Reference Card

### Minimum iOS Versions

| Feature | iOS Version | Framework |
|---------|-------------|-----------|
| Apple Intelligence LLM | 26.0+ | FoundationModels |
| Tool Calling | 26.0+ | FoundationModels |
| @Generable | 26.0+ | FoundationModels |
| NLContextualEmbedding | 17.0+ | NaturalLanguage |
| NLEmbedding | 13.0+ | NaturalLanguage |
| Core ML | 11.0+ | CoreML |

### Import Statements

```swift
import FoundationModels  // Apple Intelligence
import NaturalLanguage   // Embeddings, NER, language detection
import CoreML            // Custom ML models
import Combine           // Reactive programming
import SwiftUI           // UI framework
```

### Key URLs

| Resource | URL |
|----------|-----|
| TN3193 - Context Window | https://developer.apple.com/documentation/technotes/tn3193 |
| LanguageModelSession | https://developer.apple.com/documentation/foundationmodels/languagemodelsession |
| Tool Protocol | https://developer.apple.com/documentation/foundationmodels/tool |
| NLEmbedding | https://developer.apple.com/documentation/naturallanguage/nlembedding |
| NLContextualEmbedding | https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding |
