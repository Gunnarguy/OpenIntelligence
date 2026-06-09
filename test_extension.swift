import Foundation
import FoundationModels

public struct ContextOptions {
    public enum ReasoningLevel: String {
        case none
        case light
        case moderate
        case deep
    }
    public var reasoningLevel: ReasoningLevel
    public init(reasoningLevel: ReasoningLevel) {
        self.reasoningLevel = reasoningLevel
    }
}

@available(macOS 15.0, *)
extension LanguageModelSession {
    public func streamResponse(to prompt: String, options: GenerationOptions, contextOptions: ContextOptions?) -> LanguageModelSession.ResponseStream<String> {
        return self.streamResponse(to: prompt, options: options)
    }
}
