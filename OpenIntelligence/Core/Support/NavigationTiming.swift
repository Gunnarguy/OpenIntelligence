import Foundation

/// Wall-clock timing for navigation, so "this screen feels slow" becomes a number.
///
/// Written after five failed attempts at the Documents tab. Each attempt instrumented
/// one suspected culprit, measured it, found it fast, and moved on: the tab-appear task
/// runs in 21ms, `reloadWorkspaceData` in about 20ms, its `NSFileCoordinator` read in
/// 6 to 14ms, and 26 vector store loads total 269ms across a whole session. Every
/// individual number was small and the tab still felt slow, because nothing was
/// measuring the interval the user actually experiences — from the tap to the screen
/// being usable.
///
/// The device console carries no timestamps, so the gap cannot be recovered from a
/// capture after the fact. It has to be measured at the source.
///
/// Deliberately a plain clock rather than signposts: the point is a line in the shared
/// trace that anyone can read, not an Instruments session someone has to run.
@MainActor
enum NavigationTiming {
    private static var markers: [String: Date] = [:]

    /// Records the moment an interaction began, keyed by destination.
    static func begin(_ destination: String) {
        markers[destination] = Date()
    }

    /// Milliseconds since `begin` for this destination, consuming the marker.
    ///
    /// Returns nil when no marker exists — a screen appearing for a reason other than
    /// the navigation being measured, such as the app returning to the foreground.
    /// Reporting a made-up number there would be worse than reporting nothing.
    static func elapsedMilliseconds(_ destination: String) -> Double? {
        guard let started = markers.removeValue(forKey: destination) else { return nil }
        return Date().timeIntervalSince(started) * 1000
    }

    /// Formats the interval for a log line, or a marker that says it is unknown.
    static func describe(_ destination: String) -> String {
        guard let ms = elapsedMilliseconds(destination) else { return "sinceTap=n/a" }
        return "sinceTap=\(String(format: "%.0f", ms))ms"
    }
}
