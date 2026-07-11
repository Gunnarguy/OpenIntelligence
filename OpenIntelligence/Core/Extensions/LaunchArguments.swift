import Foundation

/// Lightweight helper for reading process launch arguments.
/// Used for DEBUG-only behaviors (e.g., deterministic screenshot capture).
enum LaunchArguments {
    static var all: [String] {
        ProcessInfo.processInfo.arguments
    }

    struct Parser {
        let arguments: [String]

        func has(_ flag: String) -> Bool {
            if flag.hasPrefix("--") {
                let trimmed = String(flag.dropFirst(2))
                return arguments.contains(flag) || arguments.contains(trimmed) || arguments.contains("--\(trimmed)")
            }
            return arguments.contains(flag) || arguments.contains("--\(flag)")
        }

        func value(for key: String) -> String? {
            let prefix = "--\(key)="
            guard let arg = arguments.first(where: { $0.hasPrefix(prefix) }) else { return nil }
            return String(arg.dropFirst(prefix.count))
        }

        func value(after key: String) -> String? {
            let fullKey = key.hasPrefix("--") ? key : "--\(key)"
            guard let idx = arguments.firstIndex(of: fullKey) else { return nil }
            let next = arguments.index(after: idx)
            guard next < arguments.endIndex else { return nil }
            let v = arguments[next]
            if v.hasPrefix("--") { return nil }
            return v
        }

        func valueEither(for key: String) -> String? {
            value(for: key) ?? value(after: key)
        }
    }

    static func has(_ flag: String) -> Bool {
        Parser(arguments: all).has(flag)
    }

    /// Returns the value for `--key=value` if present.
    static func value(for key: String) -> String? {
        Parser(arguments: all).value(for: key)
    }

    /// Returns the value after `--key value` if present.
    static func value(after key: String) -> String? {
        Parser(arguments: all).value(after: key)
    }

    /// Accepts either `--key=value` or `--key value`.
    static func valueEither(for key: String) -> String? {
        Parser(arguments: all).valueEither(for: key)
    }
}
