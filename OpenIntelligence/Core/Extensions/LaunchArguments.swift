import Foundation

/// Lightweight helper for reading process launch arguments.
/// Used for DEBUG-only behaviors (e.g., deterministic screenshot capture).
enum LaunchArguments {
    static var all: [String] {
        ProcessInfo.processInfo.arguments
    }

    static func has(_ flag: String, in arguments: [String] = all) -> Bool {
        if flag.hasPrefix("--") {
            let trimmed = String(flag.dropFirst(2))
            return arguments.contains(flag) || arguments.contains(trimmed) || arguments.contains("--\(trimmed)")
        }
        return arguments.contains(flag) || arguments.contains("--\(flag)")
    }

    /// Returns the value for `--key=value` if present.
    static func value(for key: String, in arguments: [String] = all) -> String? {
        let prefix = "--\(key)="
        guard let arg = arguments.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return String(arg.dropFirst(prefix.count))
    }

    /// Returns the value after `--key value` if present.
    static func value(after key: String, in arguments: [String] = all) -> String? {
        let fullKey = key.hasPrefix("--") ? key : "--\(key)"
        guard let idx = arguments.firstIndex(of: fullKey) else { return nil }
        let next = arguments.index(after: idx)
        guard next < arguments.endIndex else { return nil }
        let v = arguments[next]
        if v.hasPrefix("--") { return nil }
        return v
    }

    /// Accepts either `--key=value` or `--key value`.
    static func valueEither(for key: String, in arguments: [String] = all) -> String? {
        value(for: key, in: arguments) ?? value(after: key, in: arguments)
    }
}
