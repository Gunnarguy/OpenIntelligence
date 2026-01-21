//
//  ToolCallCounter.swift
//  OpenIntelligence
//
//  Lightweight global counter to track LLM tool calls during a single generation.
//  Increment this from tool handlers, and have the LLM service read-and-reset
//  at the end of a generation to populate LLMResponse.toolCallsMade.
//

import Foundation

/// Actor-based counter to avoid "unsafeForcedSync called from Swift Concurrent context" warnings.
/// Using an actor instead of DispatchQueue.sync ensures proper Swift concurrency integration.
actor ToolCallCounter { 
    static let shared = ToolCallCounter()

    private var count: Int = 0

    func increment() { 
        count += 1
    }

    func takeAndReset() -> Int { 
        let c = count
        count = 0
        return c
    }
}
