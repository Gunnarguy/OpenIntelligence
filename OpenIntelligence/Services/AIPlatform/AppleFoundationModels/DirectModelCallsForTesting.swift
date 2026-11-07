//
//  DirectModelCallsForTesting.swift
//  OpenIntelligence
//
//  Debug builds only: a switch the golden recorders (`StandardPipelineGoldenTests`, `ImportGoldenTests`, 2026-11-06)
//  turn on so the services that call Apple's on-device model directly, rather than through the engine's `llmService`,
//  behave as they do when the model is unavailable and take their fallbacks.
//
//  Why it exists: the recorders replace `llmService` with a stand-in so an answer is a fixed function of its prompt.
//  The services below ask `SystemLanguageModel.default` themselves, and in the iOS 27 Simulator the model answers, with
//  different words each time: on 2026-11-06 the route planner's plan, and so the prompt, differed between two passes of
//  the same question. With the switch on, those calls take the path an iPhone without Apple Intelligence takes. Off, the
//  default and the only state outside a recording, it changes nothing; in a Release build `isOn` is always false.
//
//  Read by: `QueryExecutionPlannerService`, `QueryRewriterService`, `SourceOnlyAnswerService`,
//  `IterativeRetrievalService`, `ConversationMemoryService`, `SuggestedQuestionsService.isSystemLLMAvailable`,
//  `ContentTaggingService` (a document's tags, which differed between two imports of one file) and
//  `DocumentSummaryService` (the overview passage, which then uses its extractive summary).
//

import Foundation

enum DirectModelCallsForTesting {
    #if DEBUG
        nonisolated(unsafe) static var disabled = false
    #endif

    /// True only in a Debug build while a recorder has turned the switch on.
    nonisolated static var isOn: Bool {
        #if DEBUG
            return disabled
        #else
            return false
        #endif
    }
}
