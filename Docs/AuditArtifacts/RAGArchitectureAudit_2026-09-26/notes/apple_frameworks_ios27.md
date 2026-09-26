# Apple frameworks and models for on-device RAG: iOS/iPadOS/macOS 27 and Xcode 27 (state on 2026-09-26)

Method and tag conventions. The developer.apple.com reference pages were read on 2026-09-26 from the DocC JSON behind them (`https://developer.apple.com/tutorials/data/documentation/<path>.json`). I read about 150 pages this way, plus the Updates index (89 pages, each scanned for 2026 entries) and the iOS 27, iOS 27.2 beta 2, macOS 27, Xcode 26, Xcode 27 and Xcode 27.1 beta release notes. I also used WWDC video pages on developer.apple.com (transcript and code tabs), the developer news RSS, Apple's own GitHub repositories, and the AFM 3 Cloud model documentation PDF on developer.apple.com. Citations give the human-readable URL.

- **Where "availability" comes from.** "Availability" means the platform list in the DocC metadata. I did **not** read `@available` lines from an SDK, because this Linux host has no Xcode or SDK.
- **Blocked sources.** machinelearning.apple.com, support.apple.com and apple.com could not be fetched (egress blocked for both curl and WebFetch). Anything known only through search summaries or third-party sites is tagged `[inferred, URL]`.
- **Tag format.** `[documented, URL, fetched 2026-09-26]` marks developer.apple.com content. `[documented (Apple GitHub), URL, fetched 2026-09-26]` marks Apple-owned GitHub repositories.

## 1. Foundation Models framework in iOS/macOS 27: the new on-device model, APIs, and anything about retrieval or grounding

### Takeaway
Apple's own API names the iOS 27 on-device model "AFM 3". `SystemLanguageModel.Variant` has `core3` ("AFM 3 Core") and `coreAdvanced3` ("AFM 3 Core Advanced"). The developer docs publish no parameter count, quantization or language list for either variant. Third-party summaries of Apple's ML-research post say AFM 3 Core is a 3B dense model, and AFM 3 Core Advanced is a 20B sparse model with 1–4B active parameters.

In iOS 27, Foundation Models became a general LLM runtime:
- a `LanguageModel` protocol, so any on-device or server model can plug in;
- `PrivateCloudComputeLanguageModel` (32K context, three reasoning levels, daily per-user quota, managed entitlement);
- image attachments, `ToolCallingMode`, and dynamic profiles;
- `ContextOptions` with `ReasoningLevel`, and token usage accounting;
- system tools: Vision's `OCRTool` and `BarcodeReaderTool`, and Core Spotlight's `SpotlightSearchTool`. Apple explicitly presents `SpotlightSearchTool` as "fully local Retrieval-Augmented Generation (RAG)".

Custom adapters are effectively gone for iOS 27. The toolkit page says 26.0.0 is its last release and is incompatible with 27, and the adapter API reference pages now return 404.

### Cited Findings

#### Framework scope and platforms
- **Platforms.** The framework page lists iOS 26.0, iPadOS 26.0, Mac Catalyst 26.0, macOS 26.0, visionOS 26.0 and watchOS 27.0 — [documented, [Foundation Models](https://developer.apple.com/documentation/foundationmodels), fetched 2026-09-26]
- **Scope.** The overview now reads: "provides access to any large language model, like the on-device and Private Cloud Compute models designed for Apple Intelligence." It also says: "When you need more reasoning capabilities and context size, use Private Cloud Compute or any server model provider." — [documented, [Foundation Models](https://developer.apple.com/documentation/foundationmodels), fetched 2026-09-26]
- **Retrieval example in the overview.** "the model can call a tool that searches a local or online database for information" — [documented, [Foundation Models](https://developer.apple.com/documentation/foundationmodels), fetched 2026-09-26]
- **On-device model is not on watchOS.** `SystemLanguageModel` is available on iOS/iPadOS/Mac Catalyst/macOS/visionOS 26.0, with no watchOS entry. `PrivateCloudComputeLanguageModel` adds watchOS 27.0. So on watchOS only PCC or other models are usable. — [documented, [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel); [PrivateCloudComputeLanguageModel](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel), fetched 2026-09-26]
- **Open source.** WWDC26 session 241: "The Foundation Models framework, including many of the brand new APIs that we're announcing today, is going open source!" The session also announced a "Foundation Models framework utilities" package "that will be updated between OS releases". — [documented, [WWDC26 241 transcript](https://developer.apple.com/videos/play/wwdc2026/241/), fetched 2026-09-26]

#### The on-device model ("AFM 3")
- **Variants and names.** `SystemLanguageModel.variant` (iOS 27.0; no watchOS) returns a `SystemLanguageModel.Variant`. The documented values are `core3` ("AFM 3 Core.") and `coreAdvanced3` ("AFM 3 Core Advanced."). `displayName` is "The user-facing name of the variant", for example `"AFM 3 Core"` or `"AFM 3 Core Advanced"`. — [documented, [Variant](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/variant-swift.struct); [displayName](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/variant-swift.struct/displayname), fetched 2026-09-26]
- **Three model versions so far.** "Apple periodically updates `SystemLanguageModel` in routine OS updates… Currently, there are 3 model versions that align with:
  - iOS, iPadOS, macOS, and visionOS 26.0 - 26.3;
  - 26.4;
  - 27.0."

  — [documented, [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), fetched 2026-09-26]
- **June 2026 update.** "Use the latest on-device `SystemLanguageModel` that follows instructions more accurately and produces better results… Because the model changes when a person updates to iOS 27… test your prompts with the new model." — [documented, [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels), fetched 2026-09-26]
- **February 2026 (26.4) update.** A new model "that improves instruction-following and tool-calling abilities", improved guardrails that "reduce the possibility of blocking benign content", `tokenCount(for:)`, and `contextSize`. — [documented, [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels), fetched 2026-09-26]
- **WWDC26 description.** "a new on-device model, rebuilt from the ground up, and better across the board. It's more intelligent; better at logic and tool calling." The same session adds that "the on-device model is also gaining Vision capabilities". — [documented, [WWDC26 241 transcript](https://developer.apple.com/videos/play/wwdc2026/241/), fetched 2026-09-26]
- **Old model not available after the update.** "Because the older model is only included as part of the beta program, it's essential to produce a record of what output your prompt produces with the prior model." — [documented, [Updating prompts for new model versions](https://developer.apple.com/documentation/foundationmodels/updating-prompts-for-new-model-versions), fetched 2026-09-26]
- **Model size, qualitative only.** "An on-device model has fewer parameters and a small context window… your input to the on-device model needs to be short and succinct." — [documented, [Prompting an on-device foundation model](https://developer.apple.com/documentation/foundationmodels/prompting-an-on-device-foundation-model), fetched 2026-09-26]
- **Parameter counts, only from secondary sources.**
  - AFM 3 Core is described as a 3-billion-parameter dense model.
  - AFM 3 Core Advanced is described as 20B parameters with a sparse architecture "activating just 1 to 4 billion parameters at a time", built on "Instruction-Following Pruning", with the full model stored in flash (NAND).
  - Neither figure appears on any developer.apple.com page I read.

  — [inferred, [9to5Mac, 2026-06-11](https://9to5mac.com/2026/06/11/apples-new-foundation-models-explained-on-device-ai-cloud-ai-and-everything-in-between/)]; [inferred, [TheNextWeb](https://thenextweb.com/news/apple-third-generation-foundation-models-afm)]; [inferred, search summary of the blocked [machinelearning.apple.com post](https://machinelearning.apple.com/research/introducing-third-generation-of-apple-foundation-models)]
- **Quantization.** A search summary mentions "2-bit Quantization-Aware Training" for on-device models and ASTC (~3.56 bits/weight) for server models. That wording matches Apple's 2025 report, and I could not confirm that it describes AFM 3. — [inferred, [search summary citing Apple ML Research 2025 updates](https://machinelearning.apple.com/research/apple-foundation-models-2025-updates)]
- **Which devices get Core Advanced.** Only iPhone 17 Pro, iPhone 17 Pro Max and iPhone Air (12GB RAM) reportedly run AFM 3 Core Advanced. — [inferred, [TechRadar](https://www.techradar.com/phones/ios/only-3-iphones-can-access-the-best-version-of-siri-ai-heres-which-features-are-exclusive-to-apples-most-powerful-on-device-model-afm-core-advanced)]; [inferred, [Tom's Guide](https://www.tomsguide.com/phones/iphones/only-the-iphone-17-pro-and-iphone-17-air-get-apples-most-powerful-on-device-apple-intelligence-model-heres-what-that-means)]
- **Languages: runtime APIs only.** `supportedLanguages` (a `Set<Locale.Language>`) and `supportsLocale(_:)` exist. The language article defers the list itself to Apple's support page "How to get Apple Intelligence", which is blocked here. — [documented, [supportedLanguages](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/supportedlanguages); [Supporting languages and locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models), fetched 2026-09-26]
- **Languages: third-party list.** English, Danish, Dutch, French, German, Italian, Norwegian, Portuguese, Spanish, Swedish, Turkish, Vietnamese, Chinese (simplified and traditional), Japanese and Korean. — [inferred, search summary citing [Wikipedia iOS 27](https://en.wikipedia.org/wiki/IOS_27) / [Macworld](https://www.macworld.com/article/2986799/ios-27-new-iphone-features-release-date-beta-compatiblity-apple-intelligence-siri.html)]
- **Guardrails depend on language.** "Guardrails for model input and output safety are only for supported languages and locales." — [documented, [Supporting languages and locales](https://developer.apple.com/documentation/foundationmodels/supporting-languages-and-locales-with-foundation-models), fetched 2026-09-26]
- **Documented strengths and limits of the on-device model.**
  - Good for: summarize, extract entities, understand text, refine or edit text, classify or judge text, compose creative writing, generate tags, game dialog.
  - "Capabilities to avoid": basic math, creating code, and logical reasoning.
  - For "tasks that require extensive world-knowledge", Apple points to guided generation and tool calling.

  — [documented, [Generating content and performing tasks](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models), fetched 2026-09-26]
- **Content tagging.** `SystemLanguageModel.UseCase` has `general` (the default) and `contentTagging`, which "always responds with tags". — [documented, [UseCase](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/usecase), fetched 2026-09-26]

#### Context size and token counting
- **`contextSize`.** Declared as `@backDeployed(before: iOS 26.4, macOS 26.4, visionOS 26.4) final var contextSize: Int { get }`, with platform list iOS 26.0+. It is "the total number of tokens that can be used in a single session, including both input prompts and generated responses". The page gives no number. — [documented, [SystemLanguageModel.contextSize](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize), fetched 2026-09-26]
- **`tokenCount(for:)`.** Five overloads, all iOS/macOS 26.4, all `async throws -> Int`, on `SystemLanguageModel` only (neither PCC nor the `LanguageModel` protocol lists one). They take:
  - `Instructions`
  - `some PromptRepresentable`
  - `GenerationSchema`
  - `[any Tool]`
  - `some Collection<Transcript.Entry>`

  — [documented, [tokenCount(for:)](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/tokencount(for:)), fetched 2026-09-26]
- **PCC context size.** `PrivateCloudComputeLanguageModel.contextSize` is `nonisolated(nonsending) final var contextSize: Int { get async throws }` (iOS 27.0). — [documented, [PCC contextSize](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel/contextsize), fetched 2026-09-26]
- **What the context window holds.** "every session interaction with the model consumes input and output tokens from this window. This includes all prompts, instructions, tool definitions and their input and output, generable type schemas, and all of the model's responses." One token is about 3–4 characters in Latin-alphabet languages and about one character in Chinese, Japanese, Korean and Vietnamese. — [documented, [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window), fetched 2026-09-26]
- **Budgeting guidance in the same article.**
  - "Reduce prompts to no more than three paragraphs in length."
  - "Provide no more than three to five tools per request."
  - "If the model always needs specific information, retrieve it directly and include it in your prompt rather than relying on tool calling."
  - On `contextSizeExceeded`: "trim the session history or create a new session".

  — [documented, [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window), fetched 2026-09-26]
- **Large inputs.** "If you need to process a large amount of data that won't fit in a single context window limit, break your data into smaller chunks, process each chunk in a separate session, and then combine the [results]." — [documented, [Generating content and performing tasks](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models), fetched 2026-09-26]
- **Usage accounting (iOS 27.0).** `LanguageModelSession.Response.usage` and `LanguageModelSession.usage` ("total accumulated usage… increases monotonically") are both `LanguageModelSession.Usage`. That type has:
  - `input` (`totalTokenCount`, `cachedTokenCount`)
  - `output` (`totalTokenCount`, `reasoningTokenCount`)
  - `metadata: [String : GeneratedContent]` ("Additional usage statistics that the language model encodes")
  - `totalTokenCount`

  — [documented, [Usage](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/usage-swift.struct); [Usage.Output](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/usage-swift.struct/output-swift.struct); [Usage.Input](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/usage-swift.struct/input-swift.struct), fetched 2026-09-26]
- **Usage in session code.** The WWDC26 241 code tab prints `response.usage.input.totalTokenCount`, `.input.cachedTokenCount`, `.output.totalTokenCount` and `.output.reasoningTokenCount`. — [documented, [WWDC26 241 code](https://developer.apple.com/videos/play/wwdc2026/241/), fetched 2026-09-26]

#### Session and prompt APIs: ContextOptions, ReasoningLevel, overloads
- **`ContextOptions`.** Available on iOS/iPadOS/Mac Catalyst/macOS/visionOS/watchOS 27.0. It has:
  - `init(includeSchemaInPrompt: Bool? = nil, reasoningLevel: ContextOptions.ReasoningLevel? = nil)`
  - properties `includeSchemaInPrompt: Bool?` ("Has no effect if there's no schema provided") and `reasoningLevel: ReasoningLevel?`

  — [documented, [ContextOptions](https://developer.apple.com/documentation/foundationmodels/contextoptions); [init](https://developer.apple.com/documentation/foundationmodels/contextoptions/init(includeschemainprompt:reasoninglevel:)); [includeSchemaInPrompt](https://developer.apple.com/documentation/foundationmodels/contextoptions/includeschemainprompt), fetched 2026-09-26]
- **`ContextOptions.ReasoningLevel`.** Cases are `light`, `moderate`, `deep` and `custom(String)` ("A custom level not represented by the other cases"). — [documented, [ReasoningLevel](https://developer.apple.com/documentation/foundationmodels/contextoptions/reasoninglevel-swift.enum); [custom(_:)](https://developer.apple.com/documentation/foundationmodels/contextoptions/reasoninglevel-swift.enum/custom(_:)), fetched 2026-09-26]
- **Overload families on `LanguageModelSession`.**
  - **iOS 26.0 families (12 overloads).** `respond(to:options:)`, `respond(to:generating:includeSchemaInPrompt:options:)`, `respond(to:schema:includeSchemaInPrompt:options:)`, the builder forms, and the matching `streamResponse` forms. These have **no** `contextOptions` parameter, and guided forms default `includeSchemaInPrompt: Bool = true`.
  - **iOS 27.0 "with metadata" families (12 overloads: 6 respond, 6 streamResponse).** These add `contextOptions:` and `metadata: [String : any ConvertibleToGeneratedContent] = [:]`.
  - **Defaults on the iOS 27 families.** Text forms default `contextOptions: ContextOptions = ContextOptions()`. Guided (`generating:` / `schema:`) forms default `contextOptions: ContextOptions = ContextOptions(includeSchemaInPrompt: true)`.

  — [documented, [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession), fetched 2026-09-26]
- **Response contents.** `LanguageModelSession.Response` exposes exactly `content`, `rawContent` (both iOS 26), `usage` (iOS 27) and `transcriptEntries` (iOS 26). — [documented, [Response](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/response), fetched 2026-09-26]
- **Other session additions in iOS 27.**
  - `init(profile:history:)`
  - `init(model: some LanguageModel = SystemLanguageModel.default, dynamicInstructions:history:)`
  - `properties: SessionPropertyValues`
  - `transcriptErrorHandlingPolicy`
  - `LanguageModelSession.Error`

  — [documented, [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession), fetched 2026-09-26]

#### Guided generation (`@Generable`, `@Guide`, `GenerationSchema`)
- **Decoding is constrained.** "The framework uses constrained sampling when generating output, which defines the rules on what the model can generate. Constrained sampling prevents the model from producing malformed output." Also: "The model generates `Generable` properties in the order they're declared." `DynamicGenerationSchema` builds schemas at runtime. — [documented, [Generating Swift data structures with guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation), fetched 2026-09-26]
- **Schema cost.** "The framework converts each type's structure into a JSON schema and sends that to the model", and `@Guide` descriptions consume tokens. — [documented, [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window), fetched 2026-09-26]
- **Unsupported guides on other models.** `LanguageModelError.unsupportedGenerationGuide` (iOS 27): "many models don't support certain guides". — [documented, [LanguageModelError](https://developer.apple.com/documentation/foundationmodels/languagemodelerror), fetched 2026-09-26]

#### Tools and tool-calling mode
- **`Tool` protocol (iOS 26).** `protocol Tool<Arguments, Output> : Sendable`, with `name`, `description`, `parameters: GenerationSchema`, `includesSchemaInInstructions` (default `true`; "should only be `false` if the model has been trained to have innate knowledge of this tool") and `@concurrent func call(arguments:) async throws -> Output`. Tools run concurrently, errors are wrapped in `LanguageModelSession.ToolCallError`, and `Tool.SessionProperty` was added in iOS 27. — [documented, [Tool](https://developer.apple.com/documentation/foundationmodels/tool), fetched 2026-09-26]
- **Grounding and parallel calls.** Tool calling lets the model "fetch up-to-date information, ground responses in sources of truth that you provide, and perform side effects". "The model can call a tool multiple times in parallel." — [documented, [Expanding generation with tool calling](https://developer.apple.com/documentation/foundationmodels/expanding-generation-with-tool-calling), fetched 2026-09-26]
- **Local database retrieval is named explicitly.** Custom tools can perform "additional actions like retrieving content from your local database". — [documented, [Generating content and performing tasks](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models), fetched 2026-09-26]
- **`GenerationOptions.ToolCallingMode` (iOS 27).** Values are `allowed` (the default), `required` ("must call one or more tools before it can respond"; you must define an exit condition) and `disallowed` ("responds using only its own knowledge"). It is set through `GenerationOptions.init(samplingMode:temperature:maximumResponseTokens:toolCallingMode:)`. — [documented, [ToolCallingMode](https://developer.apple.com/documentation/foundationmodels/generationoptions/toolcallingmode-swift.struct); [GenerationOptions](https://developer.apple.com/documentation/foundationmodels/generationoptions), fetched 2026-09-26]

#### Images in prompts
- **Image input is new in iOS 27.**
  - `Attachment<Content>` (iOS 27.0; includes watchOS) takes `CGImage`, `CIImage`, `CVPixelBuffer` or an image file URL, with a `label(_:)` "to help the model identify specific attachments when making tool calls".
  - "The framework performs the necessary scaling and color conversions."
  - Apple suggests using `PrivateCloudComputeLanguageModel` "If you determine that more reasoning or context is necessary".

  — [documented, [Attachment](https://developer.apple.com/documentation/foundationmodels/attachment); [ImageAttachmentContent](https://developer.apple.com/documentation/foundationmodels/imageattachmentcontent); [Analyzing images with multimodal prompting](https://developer.apple.com/documentation/foundationmodels/analyzing-images-with-multimodal-prompting), fetched 2026-09-26]
- **Image size and cost.** "The model supports images in any size and aspect ratio… larger images will consume more tokens and incur more latency." — [documented, [WWDC26 241 transcript](https://developer.apple.com/videos/play/wwdc2026/241/), fetched 2026-09-26]

#### LanguageModel protocol and custom providers
- **`LanguageModel` (iOS 27.0; includes watchOS).** "Implement this protocol to create a bridge between a model and the framework." It pairs with a `LanguageModelExecutor` (`respond(to:model:streamingInto:)`, `prewarm(model:transcript:)`). Apple suggests distributing implementations as Swift packages. — [documented, [LanguageModel](https://developer.apple.com/documentation/foundationmodels/languagemodel); [LanguageModelExecutor](https://developer.apple.com/documentation/foundationmodels/languagemodelexecutor), fetched 2026-09-26]
- **Capabilities.** `LanguageModelCapabilities.Capability` has `guidedGeneration`, `reasoning` ("reason, structurally separately from producing a response"), `toolCalling` and `vision`. If an app uses a capability the model lacks, "the system automatically throws an error for you". — [documented, [Capability](https://developer.apple.com/documentation/foundationmodels/languagemodelcapabilities/capability); [LanguageModel.capabilities](https://developer.apple.com/documentation/foundationmodels/languagemodel/capabilities), fetched 2026-09-26]
- **Open-source adapters.** `CoreAILanguageModel` (in `apple/coreai-models`) and `MLXLanguageModel` (in `ml-explore/mlx-swift-lm`) integrate on-device models. — [documented, [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels), fetched 2026-09-26]
- **Core AI models in a session.** Only the model passed into `init(model:tools:instructions:)` changes. Reasoning output from open-source reasoning models goes into `Transcript.Entry.reasoning(_:)`. It "requires macOS 27, iOS 27, and Xcode 27 or later." — [documented, [Running a Core AI model in a Foundation Models session](https://developer.apple.com/documentation/foundationmodels/running-a-core-ai-model-in-a-foundation-models-session), fetched 2026-09-26]
- **Utilities package.** `apple/foundation-models-utilities` adds:
  - `ChatCompletionsLanguageModel`, for any chat-completions REST server;
  - history-management profile modifiers `summarizeHistory`, `rollingWindow` and `droppingCompletedToolCalls`, to "prevent it from outgrowing the model's context window";
  - `Skills`, just-in-time instructions.

  It supports Apple platforms and some Linux distributions. — [documented (Apple GitHub), [foundation-models-utilities README](https://github.com/apple/foundation-models-utilities), fetched 2026-09-26]

#### Dynamic profiles, session properties, transcripts
- **Three composable layers (iOS 27).**
  - Dynamic instructions "Re-evaluate before every model request and supply the instructions and tools needed at that time".
  - Profiles bind instructions to session-level configuration such as the model and reasoning level.
  - Dynamic profiles orchestrate transitions and keep one active profile at a time.

  — [documented, [Composing dynamic sessions with instructions and profiles](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles), fetched 2026-09-26]
- **`Profile` modifiers.** Include `.temperature(...)`, `.reasoningLevel(...)` and life-cycle hooks such as `onToolOutput(perform:)`. — [documented, [Profile](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/profile), fetched 2026-09-26]
- **`Transcript.Reasoning` (iOS 27).** Has `segments` and `signature`. When `signature` is non-nil, "segments may represent a partial summary or be empty". iOS 27 also adds `Transcript.AttachmentSegment` and `Transcript.ImageAttachment`. — [documented, [Transcript.Reasoning](https://developer.apple.com/documentation/foundationmodels/transcript/reasoning); [Transcript](https://developer.apple.com/documentation/foundationmodels/transcript), fetched 2026-09-26]

#### Streaming, prewarming and KV caching
- **Streaming.** `streamResponse` overloads exist in both the iOS 26 and iOS 27 families and return `LanguageModelSession.ResponseStream<Content>`. — [documented, [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession), fetched 2026-09-26]
- **Prewarming.** `prewarm(promptPrefix:)` (iOS 26.0, watchOS 27.0): "only use prewarm when you have a window of at least 1 second before the call to a respond method". It is not guaranteed to load immediately "if your app is running in the background or the system is under load". — [documented, [prewarm(promptPrefix:)](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/prewarm(promptprefix:)), fetched 2026-09-26]
- **KV cache.** A session's token order is instructions, then tool definitions, then transcript entries. "Appending new content at the end of the sequence… is a cache-friendly operation." "A change to the instructions… invalidates the cache for the tool definitions and the entire transcript." — [documented, [Optimizing key-value caching](https://developer.apple.com/documentation/foundationmodels/optimizing-key-value-caching-in-language-model-sessions), fetched 2026-09-26]

#### Guardrails, errors and availability
- **Guardrails.** `SystemLanguageModel.Guardrails` has `default` (all guardrails on) and `permissiveContentTransformations`, which "lets the model handle potentially unsafe content, such as summarizing a news article" when generating `String` output. Violations throw `LanguageModelError.guardrailViolation(_:)` (iOS 27). — [documented, [Guardrails](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/guardrails); [Improving the safety of generative model output](https://developer.apple.com/documentation/foundationmodels/improving-the-safety-of-generative-model-output), fetched 2026-09-26]
- **iOS 27 errors.**
  - `LanguageModelError` cases: `contextSizeExceeded`, `rateLimited`, `refusal`, `timeout`, `guardrailViolation`, `unsupportedCapability`, `unsupportedTranscriptContent`, `unsupportedGenerationGuide`, `unsupportedLanguageOrLocale`.
  - `SystemLanguageModel.Error.assetsUnavailable`.

  — [documented, [LanguageModelError](https://developer.apple.com/documentation/foundationmodels/languagemodelerror); [SystemLanguageModel.Error](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/error), fetched 2026-09-26]
- **Availability reasons.** `appleIntelligenceNotEnabled`, `deviceNotEligible`, `modelNotReady`. "It can take some time for the model to download and become available when a person turns on Apple Intelligence." — [documented, [UnavailableReason](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/availability-swift.enum/unavailablereason); [Generating content and performing tasks](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models), fetched 2026-09-26]

#### Adapters and the adapter training toolkit
- **Toolkit end of life.** The adapter toolkit page says: "Version 26.0.0 is the last release of this toolkit and is not compatible with macOS, iOS, iPadOS, or visionOS 27 and later." It also states "Each adapter is compatible with a single specific system model version." — [documented, [Foundation Models adapter training](https://developer.apple.com/apple-intelligence/foundation-models-adapter/), fetched 2026-09-26]
- **Reference pages removed.** These return HTTP 404 on 2026-09-26, and the Foundation Models root, `SystemLanguageModel` and Updates pages no longer reference any adapter symbol:
  - `foundationmodels/systemlanguagemodel/adapter`
  - `…/adapter-swift.struct`
  - `…/init(adapter:guardrails:)`
  - the article `loading-and-using-a-custom-adapter-with-foundation-models`
  - the entitlement page `com.apple.developer.foundation-model-adapter`

  — [documented (by absence), [SystemLanguageModel topics](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), fetched 2026-09-26]
- **Third-party reading.** Some write-ups still describe adapters as version-locked rather than removed. — [inferred, [blakecrosley.com](https://blakecrosley.com/blog/foundation-models-custom-adapters)]; [inferred, [apfel issue #362, "DEFERRED to macOS 27"](https://github.com/Arthur-Ficial/apfel/issues/362)]

#### Private Cloud Compute (`PrivateCloudComputeLanguageModel`)
- **Capability table.** Rows compare `SystemLanguageModel` against PCC:
  - Preserves privacy: ✅ vs ✅
  - Works offline: ✅ vs 🚫
  - Usage limits: "Unlimited" vs "Limit per day"
  - Reasoning: "Not supported" vs "Multiple levels"
  - Context size: "4K" vs "32K"

  — [documented, [Adding server-side intelligence with Private Cloud Compute](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), fetched 2026-09-26]
- **Integration.**
  - Switching to PCC is one line: `LanguageModelSession(model: PrivateCloudComputeLanguageModel())`.
  - It is available on iOS, macOS, watchOS and visionOS 27.
  - On a network failure, "retry the request using the on-device model".
  - Apple advises: "Start with the on-device model and evaluate it with the `Evaluations` framework."

  — [documented, [PCC article](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), fetched 2026-09-26]
- **Quota.**
  - `QuotaUsage` exposes `isLimitReached`, `status` (below, approaching or exceeded), `resetDate` and `limitIncreaseSuggestion`. Quotas are "orthogonal to a model's availability".
  - Errors are `quotaLimitReached`, `networkFailure` and `serviceUnavailable`.
  - Xcode scheme options can simulate "Approaching Quota Usage Limit" and "Quota Usage Limit Reached".

  — [documented, [QuotaUsage](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel/quotausage-swift.struct); [PCC Error](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel/error); [PCC article](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), fetched 2026-09-26]
- **Daily limit.** It is per user and "counted with your user's iCloud account", and iCloud+ raises it. No numeric limit is published. — [documented, [WWDC26 319 transcript](https://developer.apple.com/videos/play/wwdc2026/319/), fetched 2026-09-26]; the search summaries I found also report no published number — [inferred, [MacObserver](https://www.macobserver.com/news/apple-intelligence-daily-limits-confirmed-fee-not-priced/)]
- **Eligibility.**
  - Developers must be enrolled in the App Store Small Business Program.
  - They must have fewer than 2 million first-time app downloads across their apps.
  - They must have the PCC entitlement assigned.
  - PCC then comes "with no cloud API cost". TestFlight and ad hoc installs do not count.
  - Developers who exceed the threshold "must migrate to an alternative solution within 6 months".

  — [documented, [Accessing Private Cloud Compute](https://developer.apple.com/private-cloud-compute/), fetched 2026-09-26]
- **Entitlement key.** `com.apple.developer.private-cloud-compute` is a Boolean, default NO, on iOS, iPadOS, macOS, visionOS and watchOS 27.0. — [documented, [entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.private-cloud-compute), fetched 2026-09-26]
- **The PCC model: AFM 3 Cloud.** Apple's model documentation form (dated September 14, 2026) states:
  - release date September 14, 2026;
  - "general-purpose multimodal model based on a Parallel-Track Mixture-of-Experts (PT-MoE) architecture";
  - inputs text, images and video; output text;
  - total size "500B-1T" parameters;
  - distributed only through the Foundation Models API to apps with the PCC entitlement;
  - requires iOS/iPadOS/macOS/watchOS/visionOS 27 or later.

  — [documented, [AFM 3 Cloud Model Documentation Form (PDF)](https://developer.apple.com/download/files/AFM-3-Cloud-Model-Documentation-Form.pdf), fetched 2026-09-26]
- **WWDC26 description of the PCC model.** "the very same one that powers many of the Apple Intelligence features… a much bigger model than the on-device models, and has a 32,000 token context window". — [documented, [WWDC26 241 transcript](https://developer.apple.com/videos/play/wwdc2026/241/), fetched 2026-09-26]

#### Retrieval, grounding, "knowledge", citations and search through tool calling
- **SpotlightSearchTool.** Core Spotlight ships `SpotlightSearchTool` (iOS/iPadOS/Mac Catalyst/macOS/visionOS 27.0). It "gives models a way to search your app's content and use the results to answer prompts… The model uses the results as additional context." Full details are in Key Question 4. — [documented, [Making your indexed content available to Foundation Models](https://developer.apple.com/documentation/corespotlight/making-your-indexed-content-available-to-foundation-models), fetched 2026-09-26]
- **Apple calls it local RAG.** WWDC26 241 chapter text: "a Spotlight-powered search tool enabling fully local Retrieval-Augmented Generation (RAG)". — [documented, [WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/), fetched 2026-09-26]
- **WWDC26 246.** "Level up basic search into a retrieval-augmented system using SpotlightSearchTool and LanguageModelSession." It has a chapter "Grounding answers with Spotlight tool-calling". — [documented, [WWDC26 246](https://developer.apple.com/videos/play/wwdc2026/246/), fetched 2026-09-26]
- **Vision tools (iOS 27).** `OCRTool` "returns a string containing all recognized text from the image", on iOS/iPadOS/Mac Catalyst/macOS/visionOS 27 and not in Simulator. `BarcodeReaderTool` covers the same platforms plus watchOS 27 and is not in Simulator. — [documented, [OCRTool](https://developer.apple.com/documentation/vision/ocrtool); [BarcodeReaderTool](https://developer.apple.com/documentation/vision/barcodereadertool), fetched 2026-09-26]

#### Beta-only items, and changes between the June betas and release
- **Beta-only (27.2 beta).** These are marked Beta in the docs: `Transcript.DataAttachment` (platform "iOS 27.2 BETA"), `DataAttachmentRepresentable`, `DataEntryRepresentable`, `LanguageModel.supportsDataAttachmentType(_:)`, `supportsDataEntryType(_:)` and `Attachment.init(_:)` (data content). — [documented, [Foundation Models](https://developer.apple.com/documentation/foundationmodels); [Transcript](https://developer.apple.com/documentation/foundationmodels/transcript); [LanguageModel](https://developer.apple.com/documentation/foundationmodels/languagemodel); [Attachment](https://developer.apple.com/documentation/foundationmodels/attachment), fetched 2026-09-26]
- **Fixed by release (iOS 27 release notes).**
  - "Private Cloud Compute might not work when you use simulators"
  - on-device model calling tools "excessively" with tool calling plus guided generation
  - "`PrivateCloudComputeLanguageModel` always uses greedy decoding"
  - `onPrompt` and `Profile` issues
  - a `GenerationError` deprecation warning on `@Generable` enums

  — [documented, [iOS & iPadOS 27 Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes), fetched 2026-09-26]
- **Release dates.**
  - Xcode 27 RC: 2026-09-09.
  - AFM 3 Cloud release date: September 14, 2026. iOS 27 public release is reported as 2026-09-14 [inferred, [MacDailyNews](https://macdailynews.com/2026/09/14/apple-releases-ios-27-ipados-27-macos-27-watchos-27-visionos-27-and-tvos-27/)].
  - 27.2 betas: 2026-09-16.
  - iOS 27.1 ships with iPhone Duo on October 23.

  — [documented, [news 2026-09-09](https://developer.apple.com/news/?id=k1mtkt1k); [news 2026-09-16](https://developer.apple.com/news/?id=rfb1rooi); [AFM 3 Cloud form](https://developer.apple.com/download/files/AFM-3-Cloud-Model-Documentation-Form.pdf), fetched 2026-09-26]

### Inferences
- The "AFM 3" name the owner uses is Apple's own. It is a family of two on-device variants, and a device gets one or the other. Which one a device gets is reported to depend on RAM (12GB for Core Advanced), not on API choice [inferred from the TechRadar and Tom's Guide sources above]. `SystemLanguageModel.variant` is the documented way to tell at runtime.
- **Two architectural signals for a RAG app.**
  - Apple now ships a system retrieval tool (`SpotlightSearchTool`) inside the same session API. Apple also documents both retrieval patterns: tool-driven, and "retrieve it directly and include it in your prompt".
  - Apple treats any model, whether PCC, a Core AI export, MLX or a chat-completions server, as interchangeable behind `LanguageModel`. So the same retrieval and prompt code can target several backends, differing in context size, reasoning support and capabilities.
- Adapters are unusable on iOS 27. Evidence: the toolkit is incompatible with 27, and every adapter reference page is gone. This is strong evidence, but I could not confirm it against the iOS 27 SDK swiftinterface from this host.

### Gaps
- **Model specifics missing from developer docs.** No developer.apple.com page gives parameter counts, quantization or bit-width for AFM 3 Core or AFM 3 Core Advanced. The only primary source with figures, the Apple ML Research post, was blocked, so those figures are [inferred]. There is also no on-device "Model Documentation Form" analogous to the AFM 3 Cloud PDF: guessed filenames returned 404, and search found none.
- **Language list.** The official Apple Intelligence language list (support.apple.com) was unreachable.
- **Doc inconsistencies I could not resolve.**
  - The `ToolCallingMode.required` discussion mentions `LanguageModelSession.Manifest`, which appears nowhere else in the reference.
  - The documented declaration of `init(model:tools:instructions:)` shows `model: SystemLanguageModel = .default`, while the PCC article says PCC can be passed to that same initializer.
  - Both are probably beta-era renames or overload-rendering artifacts, and need an SDK check.
- **Streaming internals.** I did not read `ResponseStream` in depth (snapshot semantics).

## 2. Settling the contradiction: "the on-device model has a 32K context window"

### Takeaway
No Apple source says the on-device model has a 32K context window. 32K (32,768 tokens) is the Private Cloud Compute model.

Apple's written documentation still says 4K / 4,096 tokens on-device. That appears in the PCC capability table, in "Managing the context window", in "Generating content…", and in the Updates page's `#Playground` note.

Apple's own WWDC26 code, however, shows `SystemLanguageModel().contextSize` returning **8192 on iOS 27.0 on newer devices** (4096 on 26.0). And the WWDC26 "What's new" session tells developers to use `contextSize` "to adapt your app to the hardware it's running on".

So the precise answer: on-device is 4,096 tokens per the written docs and on older hardware or OS versions, and 8,192 on iOS 27 on newer devices per WWDC26 code comments. The runtime `contextSize` property is the authority. "Reasoning not supported" on-device is still what the PCC table says.

### Cited Findings
- **PCC capability table.** "Context size | 4K | | 32K" and "Reasoning | Not supported | | Multiple levels" (`SystemLanguageModel` vs `PrivateCloudComputeLanguageModel`). The same article says PCC "provides a larger 32K-token context size and stronger reasoning". — [documented, [Adding server-side intelligence with PCC](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute), fetched 2026-09-26]
- **"Managing the context window".** "Apple's on-device foundation model has a context window of 4096 tokens per session." — [documented, [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window), fetched 2026-09-26]
- **"Generating content…".** "the system model supports up to 4,096 tokens." — [documented, [Generating content and performing tasks](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models), fetched 2026-09-26]
- **Updates page (February 2026 entry).** "Use the `#Playground` macro in Xcode to view an estimate of the usage of 4,096 tokens in the available context window." — [documented, [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels), fetched 2026-09-26]
- **API reference.** `SystemLanguageModel.contextSize` and `PrivateCloudComputeLanguageModel.contextSize` document no numeric value. — [documented, [contextSize](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize); [PCC contextSize](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel/contextsize), fetched 2026-09-26]
- **WWDC26 319 ("Build with the new Apple Foundation Model on Private Cloud Compute").**
  - Transcript: "The on-device model offers 4k, and with PCC you get 32K. And the PCC model supports reasoning."
  - Code tab at 5:58: `SystemLanguageModel().contextSize // 4096 on 26.0 // 8192 on 27.0 (newer devices)` and `PrivateCloudComputeLanguageModel().contextSize // 32768`.

  — [documented, [WWDC26 319](https://developer.apple.com/videos/play/wwdc2026/319/), fetched 2026-09-26]
- **WWDC26 241 ("What's new in the Foundation Models framework").**
  - Transcript: "In iOS 26.4, we released new APIs for inspecting the model's context size and counting the tokens… You'll want to use these going forward to adapt your app to the hardware it's running on." PCC "has a 32,000 token context window".
  - Code tab at 2:46: `let model = SystemLanguageModel(); print(model.contextSize) // 8192`.
  - Chapter text: "Private Cloud Compute… a 32K context window with reasoning levels".

  — [documented, [WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/), fetched 2026-09-26]
- **Third-party summary.** One says "the on-device model works inside a 4K-token budget… iOS 27 expands it from the iOS 26 window of 4,096 tokens, but the new number hasn't been published". This is partly contradicted by Apple's WWDC26 code comment (8192). — [inferred, search summary citing [byteiota](https://byteiota.com/ios27-foundation-models-on-device-ai/) and [ChatForest](https://chatforest.com/builders-log/apple-foundation-models-ios-27-on-device-llm-api-builder-guide/)]
- **Where "32K on-device" comes from.** In the one search I ran for this phrase, every result attributed the 32K figure to the PCC model, e.g. "PrivateCloudComputeLanguageModel, which offers a 32K context window". None attributed it to the on-device model. — [inferred, [dev.to WWDC26 summary](https://dev.to/hariharanjagan/whats-new-in-apples-foundation-models-framework-at-wwdc-2026-5227)]; the primary source is [documented, [WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/), fetched 2026-09-26]

### Inferences
- The "32K on-device" claim looks like a conflation of the PCC model's 32K window with the on-device model.
- The repository's "4K on-device vs 32K PCC" matches today's documented table. As a runtime fact it is incomplete: the WWDC26 code comment says 8192 on iOS 27 on newer devices.
- **Possible link to the model variant.** "Newer devices" plausibly means devices that run AFM 3 Core Advanced, which reportedly require 12GB RAM. That would make context size variant-dependent. Apple does not document a variant-to-context-size mapping, so treat this link as unverified.
- **Reasoning on-device.** Documented as "Not supported" in the PCC table. The protocol-level `LanguageModelCapabilities.reasoning` flag plus "the system automatically throws an error" suggests a reasoning request to a model without that capability throws, likely `unsupportedCapability`. This behaviour is not documented specifically for `SystemLanguageModel`.

### Gaps
- No Apple reference page states the on-device value for iOS 27 as a number. The 8192 figure appears only in WWDC26 code comments (sessions 241 and 319), not in API docs or articles.
- Unknown:
  - which devices count as "newer devices";
  - whether AFM 3 Core on older Apple Intelligence devices stays at 4096;
  - whether `contextSize` varies by variant or by RAM.

  Confirming this needs `contextSize` logged on physical devices of each class. Note that WWDC 241 printed 8192 with no qualifier.

## 3. Re-verification of repository facts (repo verified 2026-09-10) against today's documentation

### Takeaway
Most repository facts stand. One is wrong as worded: `ContextOptions` is **not** on every `respond`/`streamResponse` overload. It is a defaulted argument only on the 12 new iOS 27 "with metadata" overloads, and the 12 iOS 26 overloads have no `contextOptions` parameter. The iOS 27 overloads also add a `metadata:` parameter.

The context-size fact is confirmed as documented but is incomplete (see Key Question 2). The device-requirements fact cannot be verified from developer.apple.com, because Apple's docs defer to blocked apple.com and support.apple.com pages. It is consistent with third-party sources.

### Cited Findings

| # | Repository fact (2026-09-10) | Status on 2026-09-26 | Evidence |
|---|---|---|---|
| 1 | `ContextOptions` is `@available(iOS 27.0, macOS 27.0)` | **Confirmed.** DocC platforms: iOS, iPadOS, Mac Catalyst, macOS, visionOS, **and watchOS** 27.0 | [documented, [ContextOptions](https://developer.apple.com/documentation/foundationmodels/contextoptions), fetched 2026-09-26] |
| 2 | `ReasoningLevel` cases `.light`, `.moderate`, `.deep`, `.custom(String)` | **Confirmed.** `case custom(String)` | [documented, [ReasoningLevel](https://developer.apple.com/documentation/foundationmodels/contextoptions/reasoninglevel-swift.enum); [custom(_:)](https://developer.apple.com/documentation/foundationmodels/contextoptions/reasoninglevel-swift.enum/custom(_:)), fetched 2026-09-26] |
| 3 | `ContextOptions` is a defaulted argument on every respond/streamResponse overload | **Changed / inaccurate as worded.** Only the 12 iOS 27 overloads (`respond(options:contextOptions:metadata:prompt:)`, `respond(to:options:contextOptions:metadata:)`, `respond(to:generating:options:contextOptions:metadata:)`, `respond(to:schema:…)`, and the same for `streamResponse`) carry `contextOptions`. Defaults are `ContextOptions()` for text and `ContextOptions(includeSchemaInPrompt: true)` for guided. The 12 iOS 26.0 overloads have no `contextOptions` parameter. All iOS 27 overloads also add `metadata: [String : any ConvertibleToGeneratedContent] = [:]`. | [documented, [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession), fetched 2026-09-26] |
| 4 | Guided-generation overloads default `includeSchemaInPrompt` to `true` | **Confirmed, with nuance.** iOS 26 guided overloads: `includeSchemaInPrompt: Bool = true`. iOS 27 guided overloads carry the flag inside `contextOptions: ContextOptions = ContextOptions(includeSchemaInPrompt: true)`. `ContextOptions.init` itself defaults `includeSchemaInPrompt: Bool? = nil`, and the property "Has no effect if there's no schema provided". | [documented, [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession); [ContextOptions init](https://developer.apple.com/documentation/foundationmodels/contextoptions/init(includeschemainprompt:reasoninglevel:)); [includeSchemaInPrompt](https://developer.apple.com/documentation/foundationmodels/contextoptions/includeschemainprompt), fetched 2026-09-26] |
| 5 | `Response` carries `content`, `rawContent`, `transcriptEntries`, `usage`, and nothing names the backend model | **Confirmed for `Response`.** Exactly those four members. Nuance: iOS 27 adds `SystemLanguageModel.variant` / `Variant.displayName` ("AFM 3 Core" / "AFM 3 Core Advanced") on the **model** object, not the response. `Usage.metadata: [String : GeneratedContent]` is an open dictionary whose keys are undocumented. | [documented, [Response](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/response); [variant](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/variant-swift.property); [Usage](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/usage-swift.struct), fetched 2026-09-26] |
| 6 | `Response.usage` is new in iOS 27 and carries `reasoningTokenCount` | **Confirmed, path clarified.** `response.usage.output.reasoningTokenCount` (nested in `Usage.Output`). Also `usage.input.cachedTokenCount`, `usage.totalTokenCount`, and the session-level `LanguageModelSession.usage` (accumulating). All iOS 27.0. | [documented, [Usage.Output](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/usage-swift.struct/output-swift.struct); [session usage](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/usage-swift.property), fetched 2026-09-26] |
| 7 | Apple replaced the on-device model in iOS 27 and tells developers to re-test prompts | **Confirmed.** The June 2026 Updates entry, and `SystemLanguageModel` lists 3 model versions (26.0–26.3, 26.4, 27.0). The model was also replaced in 26.4 (February 2026 entry). | [documented, [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels); [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel), fetched 2026-09-26] |
| 8 | iOS 27 added the `LanguageModel` protocol, images in prompts, `toolCallingMode`, dynamic profiles, and an updated Foundation Models Instruments template | **Confirmed.** `LanguageModel`, `Attachment`, `ToolCallingMode`, `DynamicProfile` / `Profile` are all iOS 27.0. The Foundation Models instrument was **introduced in Xcode 26** ("The Foundation Models instrument is a new tool…") and updated in Xcode 27 ("quick inspection of instructions, prompts, responses, token usage, and inference performance", 164223804). | [documented, [LanguageModel](https://developer.apple.com/documentation/foundationmodels/languagemodel); [Attachment](https://developer.apple.com/documentation/foundationmodels/attachment); [ToolCallingMode](https://developer.apple.com/documentation/foundationmodels/generationoptions/toolcallingmode-swift.struct); [Xcode 26 RN](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes); [Xcode 27 RN](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes), fetched 2026-09-26] |
| 9 | Apple Intelligence requires iPhone 15 Pro or later, iPad with M1/A17 Pro or later, or an Apple silicon Mac | **Unverifiable from developer.apple.com.** Every Foundation Models page defers to apple.com/apple-intelligence and support.apple.com/121115, and both are blocked. Third-party sources agree: iPhone 15 Pro / Pro Max, all iPhone 16 and 17 models including iPhone Air, 16e and 17e; iPad with M1 or later plus iPad mini (A17 Pro); Mac with M1 or later. Related documented fact: "macOS 27 will be Apple silicon only". | [inferred, [MacRumors 2026-09-14](https://www.macrumors.com/2026/09/14/ios-27-compatible-iphones/)]; [inferred, [TechPP](https://techpp.com/2026/06/09/ios-27-supported-devices-list/)]; [inferred, search summary of [support.apple.com 121115](https://support.apple.com/en-in/121115)]; [documented, [news 2026-09-09](https://developer.apple.com/news/?id=k1mtkt1k), fetched 2026-09-26] |
| 10 | 4K on-device vs 32K on PCC; reasoning not supported on-device (from the PCC article table) | **Confirmed as documented, but incomplete.** The table is unchanged today. WWDC26 code shows `contextSize` 8192 on iOS 27.0 on newer devices (see Key Question 2). | [documented, [PCC article](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute); [WWDC26 319](https://developer.apple.com/videos/play/wwdc2026/319/), fetched 2026-09-26] |
| 11 | Context-size and token-counting APIs added in iOS 26.4 (listed as "reportedly") | **Confirmed.** Five `tokenCount(for:)` overloads are iOS/macOS 26.4. `contextSize` was announced in February 2026 (26.4) and is `@backDeployed(before: iOS 26.4…)` with iOS 26.0 availability. WWDC26 241: "In iOS 26.4, we released new APIs for inspecting the model's context size and counting the tokens". | [documented, [tokenCount(for:)](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/tokencount(for:)); [contextSize](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize); [WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/), fetched 2026-09-26] |

- **Toolchain.** The released toolchain is Xcode 27 with "Swift 6.4 and SDKs for iOS 27, iPadOS 27, tvOS 27, watchOS 27, macOS 27, and visionOS 27". It "requires a Mac running macOS Tahoe 26.6 or later." The repository's fact came from build 27A5194q, an earlier Xcode 27 build; the repository records the release as 27A266a. — [documented, [Xcode 27 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes), fetched 2026-09-26]

### Inferences
- Row 3 matters for code that assumes every `respond` call can take `contextOptions`. Only the iOS 27 overload family accepts it, so iOS 26-compatible call sites cannot pass reasoning levels.
- Row 5 still holds for "which backend answered". `Response` has no model identity field, but the session's model object (and, for on-device, `variant`) does.

### Gaps
- Availability was read from DocC platform metadata, not from the iOS 27 SDK's `@available` lines. The swiftinterface cannot be read on this Linux host.
- The device list (row 9) could not be read from any Apple-controlled page reachable from this environment.

## 4. Embeddings and search that Apple provides (NaturalLanguage, Core Spotlight, App Intents, Core AI, Core ML)

### Takeaway
Apple added no new text-embedding API in iOS 26 or 27. NaturalLanguage has no Updates page. `NLEmbedding` (word embeddings since iOS 13, sentence embeddings since iOS 14) and `NLContextualEmbedding` (BERT, iOS 17 / macOS 14) are unchanged, and Apple does not publish their dimensions or maximum lengths as numbers; both are runtime properties.

The big 2026 search addition is **Core Spotlight's `SpotlightSearchTool`** (iOS 27). It is a Foundation Models `Tool` that lets a model query the app's Spotlight index or indexed files through a multi-stage pipeline:
- source configuration, guidance levels and content domains;
- a compact output format and custom stages;
- a result stream for the app's own UI.

That pipeline sits on top of the on-device semantic search Spotlight has had since iOS 18. Its default configuration is sized for PCC and, per the iOS 27 release notes, **overflows the on-device model's context** unless a `focused` guide is used.

**Core AI** (iOS 27, all platforms) is the new framework for running modern neural models (`.aimodel`) on CPU, GPU and Neural Engine. Core ML is now pointed at non-neural models. Core AI can run arbitrary converted PyTorch models; Apple's recipe catalog has no dedicated sentence-embedding recipe today.

### Cited Findings

#### NaturalLanguage
- **Sentence embeddings for retrieval.** `NLEmbedding.sentenceEmbedding(for:)` and `sentenceEmbedding(for:revision:)` are available from iOS 14 / macOS 11; word embeddings from iOS 13 / macOS 10.15. The API offers `vector(for:) -> [Double]?`, `distance(between:and:distanceType:)` and `neighbors(for:maximumCount:distanceType:)` (default `.cosine`), plus `dimension`, `revision` and `supportedSentenceEmbeddingRevisions(for:)`. — [documented, [NLEmbedding](https://developer.apple.com/documentation/naturallanguage/nlembedding), fetched 2026-09-26]
- **Apple's guidance.** "To calculate the distance between phrases, use a sentence embedding. You might use it to measure similarity between sentences for tasks like text retrieval." — [documented, [Finding similarities between pieces of text](https://developer.apple.com/documentation/naturallanguage/finding-similarities-between-pieces-of-text), fetched 2026-09-26]
- **`NLContextualEmbedding` (iOS 17 / macOS 14).**
  - It provides "a dense vector representation… using models trained with contextualized language understanding".
  - Assets download over the air: call `requestAssets`, then `load()`.
  - Properties include `modelIdentifier`, `revision` ("use the same model revision you used during development"), `dimension` and `maximumSequenceLength`.
  - Apple's own note: "For semantic similarity tasks, consider using `NLEmbedding`."

  — [documented, [NLContextualEmbedding](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding), fetched 2026-09-26]
- **Contextual embedding languages.** "Starting in iOS 17 and macOS 14, the framework supports 27 languages across three models": Latin (20 languages listed), Cyrillic (4) and Chinese/Japanese/Korean. iOS 18 / macOS 15 added three models: Arabic; Indic (Bangla, Gujarati, Hindi, Kannada, Malayalam, Marathi, Punjabi, Tamil, Telugu, Urdu); and Thai. — [documented, [languages](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding/languages), fetched 2026-09-26]
- **Maximum length.** "Inputs longer than the token limit will be truncated, and only the first `maximumSequenceLength` tokens will be processed… works best with text snippets at the sentence or paragraph level." No number is given. — [documented, [maximumSequenceLength](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding/maximumsequencelength), fetched 2026-09-26]
- **Output is per subword token.** `NLContextualEmbeddingResult` "returns embeddings at the subword level… If you need… single representations for entire text inputs, pool or combine subword vectors." — [documented, [NLContextualEmbeddingResult](https://developer.apple.com/documentation/naturallanguage/nlcontextualembeddingresult), fetched 2026-09-26]
- **Architecture (WWDC23).** "transformer-based contextual embeddings. Specifically, these are BERT embeddings". — [documented, [WWDC23 10042](https://developer.apple.com/videos/play/wwdc2023/10042/), fetched 2026-09-26]
- **No 2025–2026 changes documented.** `updates/naturallanguage` returns 404, and NaturalLanguage is not among the Updates pages with 2026 sections. — [documented (by absence), [Updates index](https://developer.apple.com/documentation/updates), fetched 2026-09-26]

#### Core Spotlight: semantic search (iOS 18+) and `SpotlightSearchTool` (iOS 27)
- **Semantic search since iOS 18.** "In iOS 18 and macOS 15 and later, Spotlight also supports semantic searches of your content, in addition to lexical matching." `CSUserQuery` (class since iOS 16) performs "lexical and semantic searches". `CSUserQueryContext.disableSemanticSearch` turns it off, and `enableRankedResults` and `maxRankedResultCount` control ranking. — [documented, [Building a search interface for your app](https://developer.apple.com/documentation/corespotlight/building-a-search-interface-for-your-app); [CSUserQuery](https://developer.apple.com/documentation/corespotlight/csuserquery); [CSUserQueryContext](https://developer.apple.com/documentation/corespotlight/csuserquerycontext), fetched 2026-09-26]
- **How the semantic index works (WWDC24).** "Semantic search requires machine learning models that must be downloaded to the device, and will be run in your app's process." Set `title` and `textContent`, which "will be processed in the semantic index". Semantic search "works best on text or media assets". — [documented, [WWDC24 10131](https://developer.apple.com/videos/play/wwdc2024/10131/), fetched 2026-09-26]
- **Index stays local.** "The indexes you create using Core Spotlight remain on device, and are private to the owner of the device." — [documented, [Core Spotlight](https://developer.apple.com/documentation/corespotlight), fetched 2026-09-26]
- **2026 changes.**
  - June 2026: `SpotlightSearchTool` ("Make your app's indexed content available to Foundation models") and `CSSearchableIndexDescription` (iOS 27).
  - July 2026: the "Searching indexed content with natural language" sample.

  — [documented, [Core Spotlight updates](https://developer.apple.com/documentation/updates/corespotlight), fetched 2026-09-26]
- **`SpotlightSearchTool` basics.** A `struct` on iOS/iPadOS/Mac Catalyst/macOS/visionOS 27.0 (no watchOS). `init(configuration: SpotlightSearchTool.Configuration = Configuration(sources: [.coreSpotlight]))`. It conforms to `Tool`: `parameters`, `includesSchemaInInstructions`, `name`, `description`. `Arguments = GeneratedContent`, and the doc text mentions a native schema "(FullArguments or RAGSearchArguments)". — [documented, [SpotlightSearchTool](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool), fetched 2026-09-26]
- **`Configuration`.** `init(sources:guide:contactResolver:customStages:maximumResponseSize:)`. `maximumResponseSize` is "The maximum number of UTF-8 characters of rendered tool output the search tool sends back to the model on a single call"; if `nil`, it defaults based on the guide. — [documented, [Configuration](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool/configuration-swift.struct), fetched 2026-09-26]
- **Sources.**
  - `CoreSpotlightSource` searches the app's Spotlight index. It returns item identifiers plus `fetchAttributes`. An optional `CSSearchableIndexDelegate` can "generate that data dynamically", with `maximumResultCount` and `sourceOptions`.
  - `FileSource` searches "previously indexed files" in given `scopes` (directories).
  - The tool "searches each source separately and then combines the results".

  — [documented, [CoreSpotlightSource](https://developer.apple.com/documentation/corespotlight/corespotlightsource); [FileSource](https://developer.apple.com/documentation/corespotlight/filesource); [Making your indexed content available to Foundation Models](https://developer.apple.com/documentation/corespotlight/making-your-indexed-content-available-to-foundation-models), fetched 2026-09-26]
- **Guidance and format.**
  - `GuidanceLevel` values: `complete` (all techniques; the default; "works best with Private Cloud Compute"), `focused(_:)` (content domains) and `dynamic(_:)` (chosen techniques via `GuidanceProfile`).
  - `ContentDomain` values: `audio`, `calendar`, `communications`, `documents` ("Documents, notes, and text-heavy content"), `items` and `visualMedia`, each with custom attribute mapping.
  - `FormatLevel` values: `.structured` ("highest fidelity, highest token cost") and `.compact` ("Best for models with limited context").

  — [documented, [GuidanceLevel](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool/guidancelevel); [ContentDomain](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool/contentdomain); [FormatLevel](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool/formatlevel), fetched 2026-09-26]
- **On-device limit (documented).** "if you configure it to use the on-device language model without providing a `focused(_:)` guide, Spotlight search exceeds the context window of the model and can't return results." — [documented, [Making your indexed content available to Foundation Models](https://developer.apple.com/documentation/corespotlight/making-your-indexed-content-available-to-foundation-models), fetched 2026-09-26]
- **Known issue in the iOS 27 and macOS 27 release notes (183770678).** "Creating a SpotlightSearchTool without a configuration and using it with a LanguageModelSession backed by the on-device system language model fails… the tool's description and parameter schema alone exceed the on-device model's context window before any prompt is added." Workaround: `.focused(.documents)` and the like. — [documented, [iOS & iPadOS 27 Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes); [macOS 27 Release Notes](https://developer.apple.com/documentation/macos-release-notes/macos-27-release-notes), fetched 2026-09-26]
- **Pipeline and custom stages.**
  - "For each query, the model builds a pipeline of work", with stages such as retrieve, count and score.
  - `CustomStage` (a `Generable` protocol) has `execute` methods over items, scored items, text, count, grouped items, tables and statistics.
  - `ScoredSearchableItem` is "a searchable item paired with a caller-assigned relevance score".
  - Result types include `SearchTextResult` ("LLM-generated text summary"), `SearchCount`, `SearchStatistic` and `SearchResultsTable`.

  — [documented, [CustomStage](https://developer.apple.com/documentation/corespotlight/customstage); [Spotlight search tool collection](https://developer.apple.com/documentation/corespotlight/spotlight-search-tool), fetched 2026-09-26]
- **Results for the app's UI.** `searchResults: some AsyncSequence<SpotlightSearchTool.SearchReply, Never>` delivers "results of a search to your app for processing". `SearchReply` has `content`, `label` ("short, LLM-generated description"), `status`, `queryToken` and `stageToken`. — [documented, [SpotlightSearchTool](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool); [SearchReply](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool/searchreply), fetched 2026-09-26]
- **Contacts.** `ContactResolver` / `ResolvedContact` help the model resolve "I" and "me". — [documented, [Making your indexed content available…](https://developer.apple.com/documentation/corespotlight/making-your-indexed-content-available-to-foundation-models), fetched 2026-09-26]
- **Sample app.** It requires "a device that supports Apple Intelligence, running iOS 27 or later". It defaults to the on-device model and states "For best search performance… route searches to Private Cloud Compute". It is tied to WWDC26 session 246, "LLM search using Core Spotlight". — [documented, [Searching indexed content with natural language](https://developer.apple.com/documentation/corespotlight/searching-indexed-content-with-natural-language), fetched 2026-09-26]
- **Platforms (WWDC26 246).** "SpotlightSearchTool is available on iOS, iPadOS, macOS, and visionOS." — [documented, [WWDC26 246](https://developer.apple.com/videos/play/wwdc2026/246/), fetched 2026-09-26]

#### App Intents
- **`IndexedEntity` (iOS 18 / macOS 15).** "Adding entities to Spotlight makes them discoverable by Apple Intelligence." It has `attributeSet`, `defaultAttributeSet` and `hideInSpotlight`. June 2025 added `@Property(indexingKey:)` / `@ComputedProperty(indexingKey:)`. June 2026 added `IndexedEntityQuery` ("retrieve indexed entities by identifier from the Spotlight index") and `EntityCollection`. — [documented, [IndexedEntity](https://developer.apple.com/documentation/appintents/indexedentity); [App Intents updates](https://developer.apple.com/documentation/updates/appintents), fetched 2026-09-26]

#### Core AI (new in iOS 27)
- **What it is.** "Run AI models in your app on Apple silicon." It is available on iOS, iPadOS, Mac Catalyst, macOS, tvOS, visionOS and watchOS 27.0.
  - "allows your app to use the latest model architectures and inference techniques across the CPU, GPU, and Neural Engine."
  - Tooling: Core AI Optimization, Core AI PyTorch Extensions (`.aimodel` conversion), the Evaluations framework, the Core AI Debugger, the `coreai-build` ahead-of-time compiler, and an Instruments instrument and debug gauge.
  - "If your app uses model types other than neural networks, such as decision trees or tabular feature engineering, see Core ML."

  — [documented, [Core AI](https://developer.apple.com/documentation/coreai), fetched 2026-09-26]
- **Core ML now points to Core AI.** "If your app integrates AI models using the latest architectures and inference techniques, see Core AI." The Core ML Updates page's latest entry is June 2024 (`MLTensor`, `MLState` stateful predictions, multifunction models, Core ML Tools 8 compression). — [documented, [Core ML](https://developer.apple.com/documentation/coreml); [Core ML updates](https://developer.apple.com/documentation/updates/coreml), fetched 2026-09-26]
- **Integration.**
  - "Inference happens on device… there is no per-inference cost."
  - The model is bundled or downloaded as `.aimodel`; Xcode needs the Metal Toolchain component or builds fail.
  - "Core AI specializes the model for the current device… specialization can take a significant amount of time."
  - Language models can run through `LanguageModelSession`.

  — [documented, [Integrating on-device AI models in your app with Core AI](https://developer.apple.com/documentation/coreai/integrating-on-device-ai-models-in-your-app-with-core-ai), fetched 2026-09-26]
- **Specialization, caching and compute units.** Specialization output is cached (`AIModelCache`). `SpecializationOptions` can restrict to `.cpuOnly` or prefer a compute unit. `ComputeUnitKind` values are `cpu`, `gpu` and `neuralEngine`. — [documented, [Managing model specialization and caching](https://developer.apple.com/documentation/coreai/managing-model-specialization-and-caching); [ComputeUnitKind](https://developer.apple.com/documentation/coreai/computeunitkind), fetched 2026-09-26]
- **Neural Engine changes (iOS 27 release notes).**
  - Neural Engine improvements for Apple Intelligence capable devices.
  - "restricts background access to the Neural Engine"; background use requires `com.apple.developer.background-tasks.continued-processing.inference`.
  - "Large model loading (over 1 GB) performance is improved".
  - Neural Engine memory is "attributed to your app process".
  - Several fixes, including crashes for "linear-attention LLMs such as Qwen3.5/3.6" and FP8, palettized and sparse configurations that "may not run on the Neural Engine".

  — [documented, [iOS & iPadOS 27 Release Notes](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes), fetched 2026-09-26]
- **KV cache as state (WWDC26 324).** The KV cache is implemented as model state: "States are inputs to the model which are both read, and updated in-place during inference". — [documented, [WWDC26 324 "Meet Core AI"](https://developer.apple.com/videos/play/wwdc2026/324/), fetched 2026-09-26]
- **Apple's model catalog (`apple/coreai-models`).**
  - LLMs: Gemma 3, GPT-OSS, Mistral, Mixtral, Muse Glimmer, Phi, Qwen2.5, Qwen3, Qwen3 MoE.
  - VLM: Qwen3-VL.
  - Vision: CLIP and others.
  - Audio: Whisper, Parakeet, Wav2Vec 2.0, CLAP.
  - Text: RoBERTa (125M, export with dynamic sequence 1–512) and T5.
  - The registry lists no dedicated sentence-embedding model (no BGE, E5, GTE or MiniLM).
  - iOS LLM exports "require a fixed context length at export time". The default iOS compression is `4bit_weight_palettized_group32`.
  - Requirements: "macOS and iOS 27.0+", "Xcode 27.0+".

  — [documented (Apple GitHub), [coreai-models README](https://github.com/apple/coreai-models); [models/README.md](https://github.com/apple/coreai-models/blob/main/models/README.md); [roberta](https://github.com/apple/coreai-models/tree/main/models/roberta), fetched 2026-09-26]

### Inferences
- For a local-first RAG app, Apple now offers three distinct retrieval substrates:
  - NaturalLanguage embeddings: vectors the app stores and searches itself.
  - Core Spotlight: the system's own on-device lexical and semantic index. The app gets ranked items, not vectors.
  - `SpotlightSearchTool`: model-driven retrieval over that index, returning compact text into the session context.
- Of these, only NaturalLanguage exposes raw vectors. Core Spotlight never documents exposing embeddings.
- Core AI makes running a third-party embedding model technically possible: any PyTorch model converted to `.aimodel`, e.g. the RoBERTa encoder recipe. Apple provides no ready-made sentence-embedding export. This is based on the catalog contents, not an Apple statement.

### Gaps
- **Embedding sizes.** Apple does not publish `NLContextualEmbedding.dimension` or `maximumSequenceLength` values. A search summary claiming "512 dimensions / 256 tokens" appeared to echo the query terms and has no primary source, so it is unverified.
- **No embedding access in Spotlight.** No Apple page documents a public API to read Spotlight's semantic embeddings, or to use Spotlight's semantic model as an embedding function.
- **Core AI embedding recipe.** Not verified whether any Core AI recipe outputs pooled sentence embeddings; the RoBERTa recipe README does not describe pooling.

## 5. Ingestion-related APIs (Vision documents, DataDetection, VisionKit, PDFKit, Speech)

### Takeaway
- **Vision.** `RecognizeDocumentsRequest` (iOS/macOS/tvOS/visionOS 26) returns a hierarchical `DocumentObservation`: containers with a title, paragraphs, lines, words, lists, tables (rows, columns, cells), barcodes and data-detector matches. Apple states it recognizes text in 26 languages. iOS 27 added no new Vision document request, but did add `OCRTool` and `BarcodeReaderTool` for Foundation Models sessions.
- **Speech.** `SpeechAnalyzer` and `SpeechTranscriber` (iOS 26) give on-device long-form transcription. iOS 27 added file and asset input providers.
- **Other ingestion APIs.** DataDetection, the VisionKit document camera and PDFKit have no 2025–2026 changes in Apple's Updates index.

### Cited Findings
- **`RecognizeDocumentsRequest`.** Available on iOS 26.0, macOS 26.0, tvOS 26.0 and visionOS 26.0. It "scans a document and extracts different groups of text and barcodes… receipts, nutritional labels, textbook pages, forms". It "allows you to access your chosen document's structure grouped by words, lines, or paragraphs. You can also access tables and lists." Options are `textRecognitionOptions` (languages), `barcodeDetectionOptions` and `supportedRecognitionLanguages`. — [documented, [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest), fetched 2026-09-26]
- **`DocumentObservation`.** Has `uuid`, `confidence` (normalized 0–1), `document: Container` and `timeRange` (for video frames). `Container` has:
  - `text`, `title`, `paragraphs`, `lists`, `tables`, `barcodes`, and `DataDetectorMatch` ("emails, phone numbers, addresses")
  - `Container.Text`: `transcript`, `lines`, `words`, `detectedData`, `boundingRegion`, `textAlignment`
  - `Table`: `rows`, `columns`, `cell(row:col:)`, `boundingRegion`
  - `List`: `items`, `Marker`

  — [documented, [DocumentObservation](https://developer.apple.com/documentation/vision/documentobservation); [Container](https://developer.apple.com/documentation/vision/documentobservation/container); [Container.Text](https://developer.apple.com/documentation/vision/documentobservation/container/text-swift.struct); [Table](https://developer.apple.com/documentation/vision/documentobservation/container/table); [List](https://developer.apple.com/documentation/vision/documentobservation/container/list), fetched 2026-09-26]
- **Structure and languages (WWDC25 272).**
  - "recognize text in 26 languages… detect structures such as tables and lists, group lines of text into paragraphs, detect machine-readable codes… and identify important information like email addresses, phone numbers, or URLs."
  - "Vision will return one document observation per image."
  - Table "cells are automatically grouped into rows".

  — [documented, [WWDC25 272 "Read documents using the Vision framework"](https://developer.apple.com/videos/play/wwdc2025/272/), fetched 2026-09-26]
- **Vision Updates page.** The latest entries are June 2025 (`RecognizeDocumentsRequest`, `DetectLensSmudgeRequest`); there are no 2026 entries. The 2026 Vision additions (`OCRTool`, `BarcodeReaderTool`) are listed on the Foundation Models Updates page instead. — [documented, [Vision updates](https://developer.apple.com/documentation/updates/vision); [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels), fetched 2026-09-26]
- **`OCRTool` and `BarcodeReaderTool` (iOS 27).** Session tools. `OCRTool` "returns a string containing all recognized text"; both allow a custom `name` and `description`, and neither is available in Simulator. WWDC26 241: "the OCRTool allows the model to extract structured text from images." — [documented, [OCRTool](https://developer.apple.com/documentation/vision/ocrtool); [BarcodeReaderTool](https://developer.apple.com/documentation/vision/barcodereadertool); [WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/), fetched 2026-09-26]
- **DataDetection (iOS 15, macOS 12, visionOS 1, watchOS 8).** `DDMatch` subclasses cover calendar events, email addresses, flight numbers, links, money amounts, phone numbers, postal addresses and shipment tracking numbers. The `DataDetector` string extension scans strings. — [documented, [DataDetection](https://developer.apple.com/documentation/datadetection), fetched 2026-09-26]
- **VisionKit.**
  - `VNDocumentCameraViewController` (iOS 13, Mac Catalyst 13.1, visionOS 1.0): "The results of a scan include images, by page number… export the scanned images to PDF."
  - `DataScannerViewController` (iOS 16, visionOS 1.0) scans live video for text, data in text and machine-readable codes.
  - `updates/visionkit` returns 404; there is no VisionKit Updates page.

  — [documented, [VNDocumentCameraViewController](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller); [DataScannerViewController](https://developer.apple.com/documentation/visionkit/datascannerviewcontroller), fetched 2026-09-26]
- **PDFKit.** `updates/pdfkit` returns 404, and PDFKit is not among the 20 Updates pages with 2026 sections: AVKit, App Intents, AppKit, Bundle Resources, Core Spotlight, EnergyKit, FSKit, Foundation Models, HealthKit, MetricKit, Network Extension, PaperKit, PencilKit, Sensitive Content Analysis, Speech, SwiftData, SwiftUI, UIKit, Visual Intelligence and Xcode. — [documented, [Updates index](https://developer.apple.com/documentation/updates), fetched 2026-09-26]
- **`SpeechAnalyzer`.** An actor on iOS/iPadOS/Mac Catalyst/macOS/tvOS/visionOS 26.0. "The analyzer can only analyze one input sequence at a time." Assets are managed through `AssetInventory`. — [documented, [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer), fetched 2026-09-26]
- **`SpeechTranscriber` and `DictationTranscriber`.** Check `SpeechTranscriber.isAvailable` / `supportedLocales`: "If it does not, consider… using `DictationTranscriber` instead". `DictationTranscriber` (iOS 26) is "compatible with older devices" and uses the same models as system dictation. — [documented, [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber); [DictationTranscriber](https://developer.apple.com/documentation/speech/dictationtranscriber), fetched 2026-09-26]
- **Speech in June 2026 (iOS 27).** `AssetInputSequenceProvider` ("Reads from an audio file or asset") and `CaptureInputSequenceProvider` (microphone), plus `AnalyzerInputConverter`. — [documented, [Speech updates](https://developer.apple.com/documentation/updates/speech); [AssetInputSequenceProvider](https://developer.apple.com/documentation/speech/assetinputsequenceprovider), fetched 2026-09-26]
- **Speech model (WWDC25 277).** The new model is "good for long-form and distant audio", with "volatile" (fast, rough) versus finalized results. — [documented, [WWDC25 277](https://developer.apple.com/videos/play/wwdc2025/277/), fetched 2026-09-26]

### Inferences
- `RecognizeDocumentsRequest` output gives structural boundaries (title, paragraph, list item, table row and cell). A chunker can use these instead of fixed-size text windows. The API exists on all of the app's platforms from iOS/macOS 26.
- `OCRTool` is a model-invoked tool that returns plain text into the session context. It suits a question about one image in a chat turn. It is a different ingestion path from batch document indexing, and returns no structure.

### Gaps
- **Reading order.** Apple's pages do not use the phrase "reading order" or define the ordering of `paragraphs` or containers for multi-column layouts. I found no documentation that guarantees reading order.
- **Unreachable sample.** The Vision sample "Recognizing tables within a document" JSON was not reachable at the path I tried.
- **Languages.** The Vision language list is a runtime property (`supportedRecognitionLanguages`). The "26 languages" figure is from the WWDC25 session, not the reference page.
- **Speech limits.** `SpeechTranscriber` device requirements and locale list are runtime-only (`isAvailable`, `supportedLocales`); no device list is published on the pages read.
- **PDFKit symbols.** I did not audit PDFKit symbol by symbol for 26 or 27 additions; the absence claim rests on the Updates index only.

## 6. Evaluation and observability (Evaluations framework, Instruments)

### Takeaway
Apple shipped an **Evaluations framework** in iOS/macOS 27 and Xcode 27 for grading model output. It supports:
- datasets, subjects, code-based evaluators and model-judge evaluators;
- tool-call trajectory evaluators and synthetic dataset generation;
- Swift Testing integration and reports in Xcode's Report navigator.

It "works with any model available through Foundation Models, including on-device, Private Cloud Compute, and other models". So the owner's roadmap row names a real, shipping framework.

The Foundation Models Instruments instrument was introduced in Xcode 26 and updated in Xcode 27 to show instructions, prompts, responses, token usage (including cached tokens) and inference performance.

### Cited Findings
- **Evaluations framework.** Available on iOS, iPadOS, Mac Catalyst, macOS, visionOS and watchOS 27.0, and Xcode 27.0. "Measure the quality of your app's intelligence-powered features… Define datasets, generate model responses, apply metrics, and aggregate results… from simple pass or fail checks to detailed scoring with model-judge patterns… works with any model available through Foundation Models." — [documented, [Evaluations](https://developer.apple.com/documentation/evaluations), fetched 2026-09-26]
- **Symbols.**
  - Core: `Evaluation`, `ModelSample`, `Loader`, `SampleGenerator` (synthetic datasets), `Metric`, `Evaluator`, `MetricsAggregator`, `EvaluationResult` (summary, detailed and grouped views).
  - Model judge: `ModelJudgeEvaluator`, `ModelJudgePrompt`, `ScoreDimension`.
  - Tool calls: `ToolCallEvaluator`, `TrajectoryExpectation`, `ArgumentMatcher`.
  - Swift Testing: `EvaluationTrait`, `EvaluationContext`.

  — [documented, [Evaluations](https://developer.apple.com/documentation/evaluations), fetched 2026-09-26]
- **Workflow.**
  - "Provide input as a dataset of samples with expected outputs; Define the subject…; Add evaluators…; Aggregate…"
  - Evaluators return `passing(rationale:)`, `failing(rationale:)` or `scoring(_:rationale:)`.
  - Run with `@Test(.evaluates(...))`. Results appear under "the Evaluations item beneath the test run" in the Report navigator.

  — [documented, [Evaluating language model responses](https://developer.apple.com/documentation/evaluations/evaluating-language-model-responses), fetched 2026-09-26]
- **Model judge.** `ModelJudgeEvaluator` "sends the query, response, and optional reference data to a model judge, which returns scores for one or more dimensions". — [documented, [ModelJudgeEvaluator](https://developer.apple.com/documentation/evaluations/modeljudgeevaluator), fetched 2026-09-26]
- **Grounding criterion.** Apple's criteria article includes an example target row, "Output is factually grounded. | Claims are supported by provided context. | Score 1–4 on factual scale", and the advice "Use code when you can… Use humans to calibrate, not to score at scale." — [documented, [Designing specific, measurable criteria](https://developer.apple.com/documentation/evaluations/designing-evaluation-criteria), fetched 2026-09-26]
- **Measurement approaches.** The Foundation Models article lists "Comparison to ground truth", "Semantic similarity" ("By converting text to embeddings…") and "Model-based judgment" ("verify the judging model's assessment align with human judgment"). — [documented, [Evaluating prompts to measure performance](https://developer.apple.com/documentation/foundationmodels/evaluating-prompts-to-measure-performance-and-improve-model-responses), fetched 2026-09-26]
- **Evaluations with Core AI.** Evaluations can compare Core AI models against the default on-device model ("Evaluating a Core AI model"). — [documented, [Evaluations](https://developer.apple.com/documentation/evaluations); [Integrating on-device AI models… with Core AI](https://developer.apple.com/documentation/coreai/integrating-on-device-ai-models-in-your-app-with-core-ai), fetched 2026-09-26]
- **Related WWDC26 sessions.** 298 "Meet the Evaluations framework", 299 "Create robust evaluations for agentic apps", 335 "Improve your prompts by hill-climbing with Evaluations", 243 "Debug and profile agentic app experiences with Instruments". — [documented, [WWDC26 session list](https://developer.apple.com/videos/wwdc2026/), fetched 2026-09-26]
- **Instruments, introduced in Xcode 26.** "The Foundation Models instrument is a new tool designed to help developers profile their app's usage of the FoundationModels framework… asset loading, prompt processing, and inference details." — [documented, [Xcode 26 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-26-release-notes), fetched 2026-09-26]
- **Instruments, updated in Xcode 27.** "Foundation Models Instrument now helps you trace and debug Foundation Models usage in your app with quick inspection of instructions, prompts, responses, token usage, and inference performance. (164223804)" — [documented, [Xcode 27 Release Notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes), fetched 2026-09-26]
- **Instrument details.**
  - It surfaces prompts, tool calls, latency and token consumption, including "Cached Tokens".
  - "Because a recording captures and stores all Foundation Models prompts and responses in an unencrypted form, Instruments presents an alert."
  - To use it: "Select the Foundation Models template".

  — [documented, [Analyzing the runtime performance of your Foundation Models app](https://developer.apple.com/documentation/foundationmodels/analyzing-the-runtime-performance-of-your-foundation-models-app); [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window), fetched 2026-09-26]
- **Foundation Models SDK for Python (March 2026).** Runs on macOS 26.0+ with Python 3.10+. It can "Evaluate Swift Foundation Models app features by running batch inference and analyzing results from Python" and "Process transcripts exported from Swift apps for quality analysis". — [documented, [Foundation Models updates](https://developer.apple.com/documentation/updates/foundationmodels), fetched 2026-09-26]; [documented (Apple GitHub), [python-apple-fm-sdk README](https://github.com/apple/python-apple-fm-sdk), fetched 2026-09-26]
- **Feedback.** `LanguageModelSession.logFeedbackAttachment(...)` (iOS 26; three overloads) produces feedback `Data`. — [documented, [LanguageModelSession](https://developer.apple.com/documentation/foundationmodels/languagemodelsession), fetched 2026-09-26]

### Inferences
- The Evaluations framework runs as Swift Testing tests under Xcode 27. Its platform list includes iOS, so evaluation code can target device builds.
- The framework's documented building blocks map directly onto answer-quality grading for RAG:
  - reference data passed to a judge;
  - a groundedness dimension, "Claims are supported by provided context";
  - tool-call trajectory checks, for example whether a retrieval tool was called.

### Gaps
- **Judge model choice.** I did not find guidance on which model to use as judge. The model-judge design article did not return matching passages for "Private Cloud Compute", "on-device" or "larger model".
- **Where evaluations run.** Whether evaluations can run on a physical iOS device (versus Mac or Simulator during `xcodebuild test`) is not stated in the pages read.

## 7. Capability matrix: OS availability, device requirements, documented limits, and what each enables for a local-first RAG app

### Takeaway
Everything Apple added for RAG in 2026 needs iOS/macOS 27. That covers PCC, ContextOptions and reasoning, usage accounting, images, the LanguageModel protocol, SpotlightSearchTool, OCRTool, Core AI and Evaluations. Token counting and `contextSize` date from 26.4, back-deployed for `contextSize`. Document OCR structure (`RecognizeDocumentsRequest`) and SpeechAnalyzer date from 26.0. Embeddings (NaturalLanguage) date from iOS 13, 14 or 17.

Device gating falls into three groups:
- **Needs an Apple Intelligence device:** the on-device model, PCC, and SpotlightSearchTool's sample.
- **Needs a managed entitlement and business eligibility:** PCC.
- **Hardware-independent APIs:** Core AI, NaturalLanguage, Vision, Speech. Speech checks `isAvailable` at runtime.

### Cited Findings

| Capability | OS availability (DocC) | Device / entitlement requirements | Documented limits | What it enables in a local-first RAG app (factual) | Source |
|---|---|---|---|---|---|
| `SystemLanguageModel` (AFM 3 on 27.0) | iOS/iPadOS/Mac Catalyst/macOS/visionOS 26.0; no watchOS | Apple Intelligence device and region; model download (`modelNotReady`) | 4,096-token window per written docs; 8192 on 27.0 on newer devices per WWDC26 code; reasoning "Not supported"; avoid math, code and logical reasoning | Answers generated fully on device, offline, with no usage limit | [documented, [SystemLanguageModel](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel); [PCC article](https://developer.apple.com/documentation/foundationmodels/adding-server-side-intelligence-with-private-cloud-compute); [WWDC26 319](https://developer.apple.com/videos/play/wwdc2026/319/), fetched 2026-09-26] |
| `SystemLanguageModel.variant` | iOS 27.0; no watchOS | Same as above | Values `core3` and `coreAdvanced3` only | Lets the app read at runtime which AFM 3 variant is answering | [documented, [Variant](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/variant-swift.struct), fetched 2026-09-26] |
| `contextSize` / `tokenCount(for:)` | `contextSize` iOS 26.0 (back-deployed before 26.4); `tokenCount` iOS/macOS 26.4 | Same as above | `tokenCount` exists on `SystemLanguageModel` only | Lets retrieval code measure instructions, prompts, schemas, tools and transcript against the real per-device budget | [documented, [contextSize](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/contextsize); [tokenCount(for:)](https://developer.apple.com/documentation/foundationmodels/systemlanguagemodel/tokencount(for:)), fetched 2026-09-26] |
| `PrivateCloudComputeLanguageModel` (AFM 3 Cloud) | iOS/iPadOS/Mac Catalyst/macOS/visionOS/watchOS 27.0 | Apple Intelligence device; network; PCC entitlement (Small Business Program, under 2M first-time downloads); per-user daily quota tied to iCloud, raised by iCloud+ | 32K (32,768) context; three reasoning levels; 500B–1T PT-MoE; no published quota number | Longer retrieved context and multi-level reasoning without API keys or per-token cost to the developer | [documented, [PCC model](https://developer.apple.com/documentation/foundationmodels/privatecloudcomputelanguagemodel); [Accessing PCC](https://developer.apple.com/private-cloud-compute/); [AFM 3 Cloud form](https://developer.apple.com/download/files/AFM-3-Cloud-Model-Documentation-Form.pdf), fetched 2026-09-26] |
| `ContextOptions` / `ReasoningLevel` | 27.0, all six platforms | Reasoning needs a model with the `.reasoning` capability | Only on the iOS 27 overload family | Per-request reasoning depth and schema-in-prompt control | [documented, [ContextOptions](https://developer.apple.com/documentation/foundationmodels/contextoptions), fetched 2026-09-26] |
| `Response.usage` / session `usage` | 27.0 | None | None stated | Per-answer input, cached, output and reasoning token counts for telemetry | [documented, [Usage](https://developer.apple.com/documentation/foundationmodels/languagemodelsession/usage-swift.struct), fetched 2026-09-26] |
| Guided generation | iOS 26.0 (watchOS 27) | None beyond the model | Schema consumes context; other models may reject guides | Structured answers, e.g. answer plus cited chunk IDs, produced by constrained sampling | [documented, [Guided generation](https://developer.apple.com/documentation/foundationmodels/generating-swift-data-structures-with-guided-generation), fetched 2026-09-26] |
| `Tool` + `ToolCallingMode` | `Tool` iOS 26.0; `ToolCallingMode` 27.0 | None beyond the model | Apple advises 3–5 tools per request; tool definitions consume tokens | Model-invoked retrieval over the app's own store, with the option to force (`required`) or forbid (`disallowed`) tool use | [documented, [Tool](https://developer.apple.com/documentation/foundationmodels/tool); [ToolCallingMode](https://developer.apple.com/documentation/foundationmodels/generationoptions/toolcallingmode-swift.struct); [Managing the context window](https://developer.apple.com/documentation/foundationmodels/managing-the-context-window), fetched 2026-09-26] |
| Image attachments | 27.0 | Model must support `.vision` | Larger images use more tokens | Questions over page images or photos alongside text chunks | [documented, [Attachment](https://developer.apple.com/documentation/foundationmodels/attachment); [WWDC26 241](https://developer.apple.com/videos/play/wwdc2026/241/), fetched 2026-09-26] |
| `LanguageModel` protocol (Core AI, MLX, chat-completions) | 27.0 | Depends on the provider | Capability errors are thrown automatically | Swaps the answering model (on-device open model or server) without changing session, retrieval or prompt code | [documented, [LanguageModel](https://developer.apple.com/documentation/foundationmodels/languagemodel), fetched 2026-09-26] |
| Dynamic profiles | 27.0 | None | None stated | Switches instructions, tools, model and reasoning per step (e.g. retrieve, then answer) within one session | [documented, [Composing dynamic sessions](https://developer.apple.com/documentation/foundationmodels/composing-dynamic-sessions-with-instructions-and-profiles), fetched 2026-09-26] |
| Custom adapters | Toolkit 26.0.0 is the last release; "not compatible with… 27 and later"; API pages 404 | Previously an adapter entitlement | Not usable on 27 per the toolkit page | None on iOS 27 | [documented, [adapter toolkit](https://developer.apple.com/apple-intelligence/foundation-models-adapter/), fetched 2026-09-26] |
| `SpotlightSearchTool` | iOS/iPadOS/Mac Catalyst/macOS/visionOS 27.0 | Apple Intelligence device for the model; content must be indexed | Default config overflows the on-device context (known issue 183770678); use `focused(_:)` and `.compact`; `maximumResponseSize` in UTF-8 characters | System-provided retrieval over Spotlight-indexed items or files, returned into the session and streamed to the UI | [documented, [SpotlightSearchTool](https://developer.apple.com/documentation/corespotlight/spotlightsearchtool); [iOS 27 RN](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes), fetched 2026-09-26] |
| Core Spotlight semantic search (`CSUserQuery`) | Semantic from iOS 18 / macOS 15 | ML models downloaded, run in the app process | Works best on text and media; no vector access | On-device lexical plus semantic ranked search over the app's own items | [documented, [Building a search interface](https://developer.apple.com/documentation/corespotlight/building-a-search-interface-for-your-app); [WWDC24 10131](https://developer.apple.com/videos/play/wwdc2024/10131/), fetched 2026-09-26] |
| `NLEmbedding` (sentence) | iOS 14 / macOS 11 | Per-language availability (`nil` if unavailable) | Revisioned models | App-owned sentence vectors with cosine distance and neighbor search | [documented, [NLEmbedding](https://developer.apple.com/documentation/naturallanguage/nlembedding), fetched 2026-09-26] |
| `NLContextualEmbedding` | iOS 17 / macOS 14 | Assets downloaded over the air | Truncates at `maximumSequenceLength` (value unpublished); subword vectors need pooling | Multilingual BERT token vectors across 27+ languages and 6 script models | [documented, [NLContextualEmbedding](https://developer.apple.com/documentation/naturallanguage/nlcontextualembedding), fetched 2026-09-26] |
| Core AI | iOS/iPadOS/Mac Catalyst/macOS/tvOS/visionOS/watchOS 27.0 | Metal Toolchain in Xcode; background Neural Engine use needs an entitlement | Specialization time; iOS LLMs need a fixed context length | Runs converted open models on CPU, GPU or Neural Engine, as a `LanguageModel` or as raw inference functions | [documented, [Core AI](https://developer.apple.com/documentation/coreai); [iOS 27 RN](https://developer.apple.com/documentation/ios-ipados-release-notes/ios-ipados-27-release-notes), fetched 2026-09-26]; [documented (Apple GitHub), [coreai-models](https://github.com/apple/coreai-models), fetched 2026-09-26] |
| `RecognizeDocumentsRequest` | iOS/macOS/tvOS/visionOS 26.0 | None stated | One observation per image; 26 languages (WWDC25) | Structured OCR (paragraphs, lists, tables, title) as ingestion input | [documented, [RecognizeDocumentsRequest](https://developer.apple.com/documentation/vision/recognizedocumentsrequest); [WWDC25 272](https://developer.apple.com/videos/play/wwdc2025/272/), fetched 2026-09-26] |
| `OCRTool` / `BarcodeReaderTool` | 27.0 (`BarcodeReaderTool` also watchOS) | Not in Simulator | `OCRTool` returns a single string | Model-invoked text extraction from an attached image during a chat turn | [documented, [OCRTool](https://developer.apple.com/documentation/vision/ocrtool); [BarcodeReaderTool](https://developer.apple.com/documentation/vision/barcodereadertool), fetched 2026-09-26] |
| DataDetection | iOS 15 / macOS 12 | None | Fixed set of 8 match types | Typed entity metadata (dates, addresses, links and so on) for chunks | [documented, [DataDetection](https://developer.apple.com/documentation/datadetection), fetched 2026-09-26] |
| `VNDocumentCameraViewController` | iOS 13 | Camera | None stated | Page-image capture of paper documents for ingestion | [documented, [VNDocumentCameraViewController](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller), fetched 2026-09-26] |
| `SpeechAnalyzer` / `SpeechTranscriber` | iOS/macOS 26.0 (input providers 27.0) | `SpeechTranscriber.isAvailable`; `DictationTranscriber` for older devices | One input sequence at a time | On-device transcription of audio files into indexable text | [documented, [SpeechAnalyzer](https://developer.apple.com/documentation/speech/speechanalyzer); [SpeechTranscriber](https://developer.apple.com/documentation/speech/speechtranscriber), fetched 2026-09-26] |
| Evaluations | 27.0 plus Xcode 27.0 | None stated | None stated | Repeatable scoring of answers (including a "claims are supported by provided context" dimension) across prompts and models | [documented, [Evaluations](https://developer.apple.com/documentation/evaluations), fetched 2026-09-26] |
| Foundation Models instrument | Xcode 26 (introduced), Xcode 27 (updated) | None | Recordings store prompts and responses unencrypted | Token and latency breakdown per request, including cached tokens | [documented, [Xcode 27 RN](https://developer.apple.com/documentation/xcode-release-notes/xcode-27-release-notes), fetched 2026-09-26] |

- **Device requirements (search-only).** Apple Intelligence runs on iPhone 15 Pro and later (including the iPhone 16 and 17 lines, Air, 16e and 17e), iPads with M1 or later plus iPad mini (A17 Pro), and Macs with M1 or later. AFM 3 Core Advanced is limited to 12GB-RAM devices. — [inferred, [MacRumors](https://www.macrumors.com/2026/09/14/ios-27-compatible-iphones/)]; [inferred, [TechRadar](https://www.techradar.com/phones/ios/only-3-iphones-can-access-the-best-version-of-siri-ai-heres-which-features-are-exclusive-to-apples-most-powerful-on-device-model-afm-core-advanced)]

### Inferences
- An app that must keep a pre-27 deployment target can only use the 26.x subset: on-device model, guided generation, `Tool`, token counting from 26.4, `RecognizeDocumentsRequest`, `SpeechAnalyzer` and NaturalLanguage embeddings. The rest needs `#available(iOS 27…)` checks.
- Because the on-device window differs by OS and apparently by hardware (4,096 vs 8,192), a fixed token budget fails to use the larger window on newer devices. It also risks exceeding the window on older ones. Apple's own guidance is to read `contextSize` at runtime.

### Gaps
- **Device list.** No developer.apple.com page reachable here lists the Apple Intelligence device models; the rows above rely on [inferred] sources.
- **Quota numbers.** Neither the PCC daily quota nor its iCloud+ tiers are published anywhere I could reach.
- **Variant-to-context mapping.** No page maps AFM 3 variants to devices or to context sizes.
