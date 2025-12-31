import Foundation

/// Lightweight helper for reading process launch arguments.
/// Used for DEBUG-only behaviors (e.g., deterministic screenshot capture).
enum LaunchArguments {
    static var all: [String] {
        ProcessInfo.processInfo.arguments
    }

    static func has(_ flag: String) -> Bool {
        if flag.hasPrefix("--") {
            let trimmed = String(flag.dropFirst(2))
            return all.contains(flag) || all.contains(trimmed) || all.contains("--\(trimmed)")
        }
        return all.contains(flag) || all.contains("--\(flag)")
    }

    /// Returns the value for `--key=value` if present.
    static func value(for key: String) -> String? {
        let prefix = "--\(key)="
        guard let arg = all.first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return String(arg.dropFirst(prefix.count))
    }

    /// Returns the value after `--key value` if present.
    static func value(after key: String) -> String? {
        let fullKey = key.hasPrefix("--") ? key : "--\(key)"
        guard let idx = all.firstIndex(of: fullKey) else { return nil }
        let next = all.index(after: idx)
        guard next < all.endIndex else { return nil }
        let v = all[next]
        if v.hasPrefix("--") { return nil }
        return v
    }

    /// Accepts either `--key=value` or `--key value`.
    static func valueEither(for key: String) -> String? {
        value(for: key) ?? value(after: key)
    }
}
