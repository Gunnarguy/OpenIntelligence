//
//  ToolCallCounter.swift
//  OpenIntelligence
//
//  Lightweight global counter to track LLM tool calls during a single generation.
//  Increment this from tool handlers, and have the LLM service read-and-reset
//  at the end of a generation to populate LLMResponse.toolCallsMade.
//

import Foundation

final class ToolCallCounter {
    static let shared = ToolCallCounter()
    private init() {}

    private var count: Int = 0
    private let queue = DispatchQueue(label: "com.openintelligence.toolcallcounter")

    func increment() {
        queue.sync {
            count += 1
        }
    }

    func takeAndReset() -> Int {
        return queue.sync {
            let c = count
            count = 0
            return c
        }
    }
}
