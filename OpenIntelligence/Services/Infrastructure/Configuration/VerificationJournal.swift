//
//  VerificationJournal.swift
//  OpenIntelligence
//
//  A structured record of what the app did, kept on the device in development builds so a check on an iPhone or
//  a Mac can be read off it instead of reported by hand (5.8).
//

import Foundation

/// One line of JSON per event in `Documents/verification_events.jsonl`, in development builds only (5.8).
///
/// Why: most roadmap rows close only when their behaviour is seen on a device, and the trace logged only the import
/// and answer pipeline, so a Siri action, a Live Activity, a widget tap or a background task left nothing to read and
/// the owner had to report each one (2026-11-03). `scripts/phone_evidence.py` copies this file off the device with
/// `devicectl` and checks each row's closing condition against it.
///
/// What a line holds: the time, the event name (`surface.what`), an outcome, a duration where one was measured, and
/// fields. **Never document text, a question, an answer or a file name.** Libraries, documents and conversations
/// appear by `anon(_:)`, the first 8 characters of their id, which is enough to tie events together and names nothing.
/// Callers pass fields that describe the app's own state: a mode, a route, a count, a stage, an error's type.
///
/// In a Release build every call returns at once and nothing is written.
nonisolated enum VerificationJournal {
    enum Outcome: String, Sendable {
        case started, ok, failed, cancelled, info
    }

    /// Where the journal is written. Tests point it elsewhere.
    nonisolated(unsafe) static var fileURL: () -> URL? = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("verification_events.jsonl")
    }

    /// Rotated once at this size, so about twice it is kept: several days of ordinary use.
    static let maxFileSize: UInt64 = 10_000_000

    private static let queue = DispatchQueue(label: "OpenIntelligence.VerificationJournal", qos: .utility)

    private static let timestamp: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let appVersion: String = {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }()

    /// The first 8 characters of an id: ties events about one library or document together without naming it.
    static func anon(_ id: UUID?) -> String {
        guard let id else { return "none" }
        return String(id.uuidString.prefix(8))
    }

    static var isEnabled: Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }

    /// Records one event. `fields` values are written as given, so pass only the app's own state (see the type's note).
    static func record(
        _ event: String, _ outcome: Outcome = .info, durationMs: Double? = nil, _ fields: [String: String] = [:]
    ) {
        guard isEnabled else { return }
        let now = Date()
        var object: [String: Any] = [
            "t": timestamp.string(from: now),
            "e": event,
            "o": outcome.rawValue,
            "v": appVersion,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
        ]
        if let durationMs { object["ms"] = (durationMs * 10).rounded() / 10 }
        if !fields.isEmpty { object["f"] = fields }
        guard JSONSerialization.isValidJSONObject(object),
            var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { return }
        data.append(0x0A)
        queue.async { append(data) }
    }

    /// Records an event that has no outcome of its own (`info`), with its fields.
    static func record(_ event: String, _ fields: [String: String]) {
        record(event, .info, durationMs: nil, fields)
    }

    /// Records `event` started, runs `body`, and records it ok, cancelled or failed with how long it took and the
    /// error's type. Runs `body` on the caller's actor.
    static func run<T>(
        _ event: String, _ fields: [String: String] = [:], isolation: isolated (any Actor)? = #isolation,
        _ body: () async throws -> T
    ) async rethrows -> T {
        guard isEnabled else { return try await body() }
        let started = Date()
        record(event, .started, fields)
        do {
            let value = try await body()
            record(event, .ok, durationMs: Date().timeIntervalSince(started) * 1000, fields)
            return value
        } catch {
            var failed = fields
            failed["error"] = String(describing: type(of: error))
            let outcome: Outcome = error is CancellationError ? .cancelled : .failed
            record(event, outcome, durationMs: Date().timeIntervalSince(started) * 1000, failed)
            throw error
        }
    }

    /// An event with a start and an end, for code whose body can't be put in a closure (an App Intent's `perform`,
    /// whose opaque result type a generic closure would lose). Records `started` when made; `fail(_:)` records the
    /// error's type; `end()`, usually in a `defer`, records `ok` unless it already failed.
    final class Span: @unchecked Sendable {
        private let event: String
        private let fields: [String: String]
        private let started = Date()
        private var isOpen = true

        init(_ event: String, _ fields: [String: String] = [:]) {
            self.event = event
            self.fields = fields
            VerificationJournal.record(event, .started, fields)
        }

        private var elapsedMs: Double { Date().timeIntervalSince(started) * 1000 }

        func fail(_ error: Error) {
            guard isOpen else { return }
            isOpen = false
            var failed = fields
            failed["error"] = String(describing: type(of: error))
            VerificationJournal.record(
                event, error is CancellationError ? .cancelled : .failed, durationMs: elapsedMs, failed)
        }

        func end(_ extra: [String: String] = [:]) {
            guard isOpen else { return }
            isOpen = false
            VerificationJournal.record(event, .ok, durationMs: elapsedMs, fields.merging(extra) { $1 })
        }
    }

    /// Waits for every line recorded so far to be on disk. For tests and for a check that reads the file at once.
    static func flush() {
        queue.sync {}
    }

    private static func append(_ data: Data) {
        guard let url = fileURL() else { return }
        let fm = FileManager.default
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? UInt64, size > maxFileSize {
            let previous = url.deletingPathExtension().appendingPathExtension("prev.jsonl")
            try? fm.removeItem(at: previous)
            try? fm.moveItem(at: url, to: previous)
        }
        // O_APPEND, as the trace does: two processes (the app and an extension, or a relaunch) interleave between
        // lines, never inside one.
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return }
        defer { close(fd) }
        _ = data.withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
    }

    /// Every event in the live file, oldest first. For tests.
    static func readAll() -> [[String: Any]] {
        flush()
        guard let url = fileURL(), let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap {
            (try? JSONSerialization.jsonObject(with: Data($0.utf8))) as? [String: Any]
        }
    }
}
