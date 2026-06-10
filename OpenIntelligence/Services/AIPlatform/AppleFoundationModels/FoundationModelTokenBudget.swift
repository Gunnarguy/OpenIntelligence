//
//  FoundationModelTokenBudget.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Thread-safe helper that centralizes token budget, transcript token estimation,
/// character-to-token fallback ratios, and output reserve logic for on-device and cloud
/// foundation models conforming to WWDC26 Apple Intelligence specs.
public struct FoundationModelTokenBudget: Sendable {
    
    // MARK: - Constants
    
    /// Default token budget for context packing
    public nonisolated static let defaultTokenBudget = 3200
    
    /// Default context length window for standard model session
    public nonisolated static let baseContextLength = 4096
    
    /// Returns the context window size (tokens) based on execution mode/location.
    public nonisolated static func contextSize(isAppleFMOnDevice: Bool) -> Int {
        return isAppleFMOnDevice ? 8192 : 32768
    }
    
    /// Returns the dynamic token budget leaving a safety buffer.
    public nonisolated static func tokenBudget(isAppleFMOnDevice: Bool) -> Int {
        let size = contextSize(isAppleFMOnDevice: isAppleFMOnDevice)
        let safetyBuffer = isAppleFMOnDevice ? 800 : 2048
        return max(1000, size - safetyBuffer)
    }
    
    /// Empirically validated on-device Apple FM ratio: ~1.4 chars/token
    public nonisolated static let onDeviceCharsPerToken = 1.4
    
    /// Cloud fallback model ratio: ~2.5 chars/token
    public nonisolated static let cloudFallbackCharsPerToken = 2.5
    
    /// Estimated tokens per character for packing calculations (~0.71 tokens/char)
    public nonisolated static let tokensPerChar = 0.71
    
    // MARK: - Calculations
    
    /// Get the conservative characters-per-token ratio based on execution location.
    public nonisolated static func conservativeCharsPerToken(isAppleFMOnDevice: Bool) -> Double {
        return isAppleFMOnDevice ? onDeviceCharsPerToken : cloudFallbackCharsPerToken
    }
    
    /// Estimate token count conservatively for a given character count.
    public nonisolated static func estimateTokens(charsCount: Int, isAppleFMOnDevice: Bool) -> Int {
        let ratio = conservativeCharsPerToken(isAppleFMOnDevice: isAppleFMOnDevice)
        return max(1, Int(ceil(Double(charsCount) / ratio)))
    }
    
    /// Estimate token count conservatively for a given string.
    public nonisolated static func estimateTokens(for text: String, isAppleFMOnDevice: Bool) -> Int {
        return estimateTokens(charsCount: text.count, isAppleFMOnDevice: isAppleFMOnDevice)
    }
    
    /// ContextPacking-oriented character to token estimation (approx. 0.71 tokens/char).
    public nonisolated static func estimateTokensForCharCount(_ charsCount: Int) -> Int {
        return Int(ceil(Double(charsCount) * tokensPerChar))
    }
    
    // MARK: - Transcript Token Estimation
    
    #if canImport(FoundationModels)
    /// Estimate token count of a Transcript entry list for Apple Foundation Models.
    @available(iOS 26.0, macOS 16.0, *)
    public nonisolated static func estimateTranscriptTokens(_ transcript: Transcript) -> Int {
        var totalChars = 0
        for entry in transcript {
            switch entry {
            case let .instructions(inst):
                totalChars += String(describing: inst).count
            case let .prompt(prompt):
                totalChars += String(describing: prompt).count
            case let .response(resp):
                totalChars += String(describing: resp).count
            case let .toolCalls(calls):
                // Tool calls are typically compact JSON: ~100 chars per tool call average
                totalChars += calls.count * 100
            case let .toolOutput(output):
                totalChars += String(describing: output).count
            @unknown default:
                totalChars += 50 // Conservative estimate for unknown types
            }
        }
        return max(0, Int(ceil(Double(totalChars) / onDeviceCharsPerToken)))
    }
    #endif
}
