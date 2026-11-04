//
//  VerificationJournal.swift
//  OpenIntelligence
//
//  A structured record of what the app did, kept on the device in development builds so a check on an iPhone or
//  a Mac can be read off it instead of reported by hand (5.8).
//

import Foundation

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// One line of JSON per event in `Documents/verification_events.jsonl`, in development builds only (5.8).
///
/// Why: most roadmap rows close only when their behaviour is seen on a device, and the trace logged only the import
/// and answer pipeline, so a Siri action, a Live Activity, a widget tap or a background task left nothing to read and
/// the owner had to report each one (2026-11-03). `scripts/phone_evidence.py` copies this file off the device with
/// `devicectl` and checks each row's closing condition against it.
///
/// What a line holds: the time, the event name (`surface.what`), an outcome, a duration where one was measured, the
/// platform (`os`: `iOS` or `macOS`, so one checker reads the iPhone's journal and the Mac's), and fields. **Never document text, a question, an answer or a file name.** Libraries, documents and conversations
/// appear by `anon(_:)`, the first 8 characters of their id, which is enough to tie events together and names nothing.
/// Callers pass fields that describe the app's own state: a mode, a route, a count, a stage, an error's type.
///
/// In a Release build every call returns at once and nothing is written.
nonisolated enum VerificationJournal {
    enum Outcome: String, Sendable {
        case started, ok, failed, cancelled, info
    }

    /// Where the journal is written. Tests point it elsewhere, which turns the journal on in a test host
    /// (`fileURLIsReplaced`); a test that puts it back sets the flag false again.
    static var fileURL: () -> URL? {
        get { journalURL }
        set {
            journalURL = newValue
            fileURLIsReplaced = true
        }
    }

    nonisolated(unsafe) private static var journalURL: () -> URL? = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("verification_events.jsonl")
    }

    /// True once a test has pointed `fileURL` somewhere of its own. In a unit-test host the journal writes only
    /// then, so a test run never writes into the journal a device check reads.
    nonisolated(unsafe) static var fileURLIsReplaced = false

    /// Whether this process is a unit-test host (Xcode sets `XCTestConfigurationFilePath` for it).
    private static let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    /// A UI-test or screenshot launch: its lines carry `"host": "uitest"`, and `phone_evidence.py` drops them, so a
    /// robot's taps never close a row.
    private static let isUITestLaunch: Bool = {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--uitest-stand-in-model") || arguments.contains("--screenshot")
    }()

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

    /// The platform written on every line as `os`. An iPad reads `iOS` (its idiom is a main-actor read), and the
    /// Mac app reads `macOS`, which is what tells the two journals' events apart when they are checked together.
    static let platform: String = {
        #if os(macOS) || targetEnvironment(macCatalyst)
            return "macOS"
        #elseif os(visionOS)
            return "visionOS"
        #else
            return ProcessInfo.processInfo.isiOSAppOnMac ? "macOS" : "iOS"
        #endif
    }()

    /// When this process started recording: read once in `AppServices.init` (a static `let` is made on first read),
    /// so "was this answer written before this launch" is `timestamp < launchedAt`.
    static let launchedAt = Date()

    /// How many times this process went to the background (`ContentView` counts it on the main thread), so work that
    /// runs across a trip out of the app can say it did (`atlas.analyze`'s `leftFront`).
    @MainActor static var backgroundEntries = 0

    /// Whether VoiceOver is on, for rows that ask a flow to be used with it (5.8).
    @MainActor static var voiceOverOn: Bool {
        #if canImport(UIKit) && !os(watchOS)
            return UIAccessibility.isVoiceOverRunning
        #elseif canImport(AppKit)
            return NSWorkspace.shared.isVoiceOverEnabled
        #else
            return false
        #endif
    }

    /// A file's size in bytes, or 0 when it can't be read. A size only, never the name.
    static func fileBytes(_ url: URL) -> Int {
        guard isEnabled else { return 0 }
        return ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
    }

    /// The process's memory footprint in MB (`phys_footprint`, what iOS counts toward its memory limit), or 0 when
    /// the kernel doesn't answer. For a field on an import stage, not a per-passage call.
    static func footprintMB() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return Int(info.phys_footprint / 1_048_576)
    }

    static var isEnabled: Bool {
        #if DEBUG
            return !isTestHost || fileURLIsReplaced
        #else
            return false
        #endif
    }

    /// Records one event. `fields` values are written as given, so pass only the app's own state (see the type's note).
    /// `fields` and `durationMs` are autoclosures: when the journal is off (every Release build), neither is evaluated.
    static func record(
        _ event: String, _ outcome: Outcome = .info, durationMs: @autoclosure () -> Double? = nil,
        _ fields: @autoclosure () -> [String: String] = [:]
    ) {
        guard isEnabled else { return }
        let fields = fields()
        let durationMs = durationMs()
        let now = Date()
        var object: [String: Any] = [
            "t": timestamp.string(from: now),
            "e": event,
            "o": outcome.rawValue,
            "v": appVersion,
            "os": platform,
            "pid": Int(ProcessInfo.processInfo.processIdentifier),
        ]
        if isUITestLaunch { object["host"] = "uitest" }
        if let durationMs { object["ms"] = (durationMs * 10).rounded() / 10 }
        if !fields.isEmpty { object["f"] = fields }
        guard JSONSerialization.isValidJSONObject(object),
            var data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        else { return }
        data.append(0x0A)
        queue.async { append(data) }
    }

    /// Records an event that has no outcome of its own (`info`), with its fields.
    static func record(_ event: String, _ fields: @autoclosure () -> [String: String]) {
        guard isEnabled else { return }
        record(event, .info, durationMs: nil, fields())
    }

    /// Records `event` started, runs `body`, and records it ok, cancelled or failed with how long it took and the
    /// error's type. Runs `body` on the caller's actor.
    static func run<T>(
        _ event: String, _ fields: @autoclosure () -> [String: String] = [:],
        isolation: isolated (any Actor)? = #isolation, _ body: () async throws -> T
    ) async rethrows -> T {
        guard isEnabled else { return try await body() }
        let fields = fields()
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

        /// `fields` is evaluated only when the journal is on.
        init(_ event: String, _ fields: @autoclosure () -> [String: String] = [:]) {
            self.event = event
            self.fields = VerificationJournal.isEnabled ? fields() : [:]
            VerificationJournal.record(event, .started, self.fields)
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

        func end(_ extra: @autoclosure () -> [String: String] = [:]) {
            guard isOpen else { return }
            isOpen = false
            guard VerificationJournal.isEnabled else { return }
            VerificationJournal.record(event, .ok, durationMs: elapsedMs, fields.merging(extra()) { $1 })
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

/// Sends the main queue a ping every 100 ms and records each ping that comes back 250 ms or more late as
/// `mainThread.stall`, with how late it was and what the app was doing (`phase`), in development builds only (5.8).
/// A stall still in progress when a reader asks is not counted yet, and a stall shorter than the ping interval's
/// slack can read up to 100 ms short.
///
/// Why: several rows close on "the interface stayed responsive" (a 144k-passage library at launch, iCloud holding a
/// sync file, an import's whole-document passes), and that was read off Time Profiler or `sample` by hand. A timer on
/// a background queue sends the ping and measures how late it runs; 250 ms is Apple's hang threshold. Readers that need a yes or no (`launch.chatUsable`'s `stallFree`, an import's `responsive`) ask
/// `longestStall(since:)` for the window they care about.
///
/// Started once from `AppServices.init`. In a Release build `start()` does nothing.
nonisolated final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog()

    /// A main-thread delay at or above this is a stall: Apple's hang threshold.
    static let stallThresholdMs: Double = 250

    private let lock = NSLock()
    private let queue = DispatchQueue(label: "OpenIntelligence.MainThreadWatchdog", qos: .utility)
    private var timer: DispatchSourceTimer?
    private var pingInFlight = false
    private var stalls: [(endedAt: Date, ms: Double)] = []
    private var currentPhase = "launch"

    var isRunning: Bool { lock.withLock { timer != nil } }

    /// What the app is doing, written on each stall: `launch` until the chat first shows, then `chatOpen`,
    /// `firstQuestion` while the first answer is written, then `other`.
    var phase: String {
        get { lock.withLock { currentPhase } }
        set { lock.withLock { currentPhase = newValue } }
    }

    func start(interval: DispatchTimeInterval = .milliseconds(100)) {
        guard VerificationJournal.isEnabled else { return }
        lock.withLock {
            guard timer == nil else { return }
            let source = DispatchSource.makeTimerSource(queue: queue)
            source.schedule(deadline: .now() + interval, repeating: interval)
            source.setEventHandler { [weak self] in self?.tick() }
            timer = source
            source.resume()
        }
    }

    func stop() {
        lock.withLock {
            timer?.cancel()
            timer = nil
            pingInFlight = false
        }
    }

    /// The longest stall that ended at or after `date`, in ms; 0 when there was none.
    func longestStall(since date: Date) -> Double {
        lock.withLock { stalls.filter { $0.endedAt >= date }.map { $0.ms }.max() ?? 0 }
    }

    /// Whether the main thread answered within the threshold every time since `date`.
    func stallFree(since date: Date) -> Bool {
        longestStall(since: date) < Self.stallThresholdMs
    }

    private func tick() {
        let sent = Date()
        let send = lock.withLock { () -> Bool in
            guard timer != nil, !pingInFlight else { return false }
            pingInFlight = true
            return true
        }
        guard send else { return }
        DispatchQueue.main.async { [weak self] in
            let now = Date()
            self?.answered(lateMs: now.timeIntervalSince(sent) * 1000, at: now)
        }
    }

    private func answered(lateMs: Double, at now: Date) {
        let phase = lock.withLock { () -> String? in
            pingInFlight = false
            guard timer != nil, lateMs >= Self.stallThresholdMs else { return nil }
            stalls.append((now, lateMs))
            if stalls.count > 500 { stalls.removeFirst(stalls.count - 500) }
            return currentPhase
        }
        guard let phase else { return }
        VerificationJournal.record(
            "mainThread.stall", .info, durationMs: lateMs, ["ms": "\(Int(lateMs))", "phase": phase])
    }
}
