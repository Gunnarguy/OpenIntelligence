//
//  LoggingConfiguration.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 10/19/25.
//

import Foundation

/// Global logging configuration for OpenIntelligence
/// Controls verbosity of console output across all services
enum LoggingConfiguration {
    
    /// Logging level for the application
    enum Level: Int, Comparable {
        case silent = 0      // No logs (production)
        case error = 1       // Only errors
        case warning = 2     // Errors + warnings
        case info = 3        // Errors + warnings + info
        case debug = 4       // All logs including debug
        case verbose = 5     // Maximum verbosity (development)
        
        static func < (lhs: Level, rhs: Level) -> Bool {
            return lhs.rawValue < rhs.rawValue
        }
    }
    
    /// Current logging level (can be changed at runtime)
    static var currentLevel: Level = {
        #if DEBUG
        return .info  // Default to info in debug builds
        #else
        return .error  // Only errors in release builds
        #endif
    }()
    
    /// Enable/disable specific logging categories
    static var enabledCategories: Set<Category> = {
        #if DEBUG
        return [.pipeline, .performance, .llm, .telemetry]  // Enable key categories in debug
        #else
        return []  // Minimal logging in release
        #endif
    }()
    
    /// Logging categories for fine-grained control
    enum Category {
        case initialization  // App/service startup
        case ingestion      // Document processing
        case embedding      // Embedding generation
        case vectorDB       // Vector database operations
        case retrieval      // Search/retrieval
        case llm            // LLM generation
        case pipeline       // RAG pipeline steps
        case performance    // Performance metrics
        case streaming      // Token streaming
        case telemetry      // Telemetry events
        case ui             // UI updates
    }
    
    /// Check if logging is enabled for a given level
    static func isEnabled(_ level: Level) -> Bool {
        return level <= currentLevel
    }
    
    /// Check if logging is enabled for a category
    static func isEnabled(_ category: Category) -> Bool {
        return enabledCategories.contains(category)
    }
    
    /// Log message with level check
    static func log(_ level: Level, category: Category? = nil, _ message: String) {
        guard isEnabled(level) else { return }
        if let category = category, !isEnabled(category) { return }
        
        let prefix: String
        switch level {
        case .silent: return
        case .error: prefix = "❌"
        case .warning: prefix = "⚠️ "
        case .info: prefix = "ℹ️ "
        case .debug: prefix = "🔍"
        case .verbose: prefix = "📝"
        }
        
        print("\(prefix) \(message)")
    }
    
    /// Convenience methods for common log levels
    static func error(_ message: String, category: Category? = nil) {
        log(.error, category: category, message)
    }
    
    static func warning(_ message: String, category: Category? = nil) {
        log(.warning, category: category, message)
    }
    
    static func info(_ message: String, category: Category? = nil) {
        log(.info, category: category, message)
    }
    
    static func debug(_ message: String, category: Category? = nil) {
        log(.debug, category: category, message)
    }
    
    static func verbose(_ message: String, category: Category? = nil) {
        log(.verbose, category: category, message)
    }
    
    /// Print a section header (respects level and category)
    static func section(_ title: String, level: Level = .info, category: Category? = nil) {
        guard isEnabled(level) else { return }
        if let category = category, !isEnabled(category) { return }
        let separator = String(repeating: "━", count: 60)
        print("\n\(separator)")
        print("  \(title)")
        print("\(separator)")
    }
    
    /// Print a boxed message (respects level and category)
    static func box(_ title: String, level: Level = .info, category: Category? = nil, content: [String] = []) {
        guard isEnabled(level) else { return }
        if let category = category, !isEnabled(category) { return }
        let width = 62
        print("\n╔" + String(repeating: "═", count: width) + "╗")
        print("║ \(title.padding(toLength: width - 2, withPad: " ", startingAt: 0)) ║")
        if !content.isEmpty {
            print("╠" + String(repeating: "═", count: width) + "╣")
            for line in content {
                print("║ \(line.padding(toLength: width - 2, withPad: " ", startingAt: 0)) ║")
            }
        }
        print("╚" + String(repeating: "═", count: width) + "╝")
    }
}

/// Convenience typealias for shorter code
typealias Log = LoggingConfiguration
