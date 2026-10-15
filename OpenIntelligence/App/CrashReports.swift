//
//  CrashReports.swift
//  OpenIntelligence
//

import Foundation

#if canImport(MetricKit)
    import MetricKit
#endif

/// Crash reports the person can send (5.7). MetricKit hands the app a crash diagnostic at the next
/// launch after it closed unexpectedly (iOS 27 and macOS 27); `MetricDiagnostics` saves each one here as
/// a file of its own, and the app offers it once, at that launch. Email Report opens a message to the
/// developer with a short summary in the person's own mail app, and Settings, About shares the whole
/// file. Nothing leaves the device unless the person sends it.
///
/// A saved report holds the app and system versions, the device model, how the app ended (termination
/// category and reason, exception type and code, signal), which of the app's states were running
/// (`AppStateReporting`) and the call stack, which names code, not content. It leaves out the message
/// text of an Objective-C exception and its arguments, which can carry strings the app was handling,
/// and the region format, process id and signposts. The newest ten are kept.
nonisolated enum CrashReports {
    /// Posted on the main thread when a report has been saved.
    static let didSave = Notification.Name("openIntelligence.crashReports.didSave")
    static let pendingKey = "crashReports.pending"
    static let keep = 10

    static func folder() -> URL {
        AppSupportPaths.localCacheDir().appendingPathComponent("CrashReports", isDirectory: true)
    }

    /// Saved reports, newest first.
    static func all(in folder: URL = folder()) -> [URL] {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return files.filter { $0.pathExtension == "json" }.sorted { $0.lastPathComponent > $1.lastPathComponent }
    }

    /// Writes one report, keeps the newest `keep`, and makes it the one the app offers next.
    @discardableResult
    static func save(
        _ fields: [String: Any], endedAt: Date, in folder: URL = folder(), defaults: UserDefaults = .standard
    ) throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "crash-\(formatter.string(from: endedAt))-\(UUID().uuidString.prefix(4)).json"
        let url = folder.appendingPathComponent(name)
        let data = try JSONSerialization.data(withJSONObject: fields, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
        for old in all(in: folder).dropFirst(keep) {
            try? FileManager.default.removeItem(at: old)
        }
        defaults.set(name, forKey: pendingKey)
        return url
    }

    /// The report not offered yet, if it is still on the device.
    static func pending(in folder: URL = folder(), defaults: UserDefaults = .standard) -> URL? {
        guard let name = defaults.string(forKey: pendingKey) else { return nil }
        let url = folder.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func markOffered(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: pendingKey)
    }

    /// The short summary written into the report when it was saved.
    static func summary(of report: URL) -> String? {
        guard let data = try? Data(contentsOf: report),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return object["summary"] as? String
    }

    /// A message to `address` with the report's summary in it. A mail link can't carry a file, so the
    /// whole report is shared from Settings, About.
    static func mailURL(for report: URL, to address: String) -> URL {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(
                name: "subject",
                value: "[OpenIntelligence Crash Report] \(report.deletingPathExtension().lastPathComponent)"),
            URLQueryItem(
                name: "body",
                value: (summary(of: report) ?? "")
                    + "\n\nThe whole report can be shared from OpenIntelligence, in Settings, About, Share the Last Crash Report.\n"),
        ]
        return components.url ?? URL(string: "mailto:\(address)")!
    }

    #if canImport(MetricKit)
        /// What is saved for a crash diagnostic: how the app ended, without the text of an exception's
        /// message or its arguments.
        @available(iOS 27.0, macOS 27.0, macCatalyst 27.0, *)
        static func fields(for report: MetricKit.DiagnosticReport, crash: MetricKit.CrashDiagnostic) -> [String: Any] {
            let environment = report.environment
            let dates = ISO8601DateFormatter()
            let app = "OpenIntelligence \(environment.applicationVersion) (\(environment.applicationBuildVersion))"
            let system = "\(environment.osVersion.platform) \(environment.osVersion.number) (\(environment.osVersion.buildNumber))"
            let device = "\(environment.deviceType), \(environment.platformArchitecture)"
            let states = environment.states.map { "\($0.domain) \($0.label)" }
            var ended: [String] = []
            var fields: [String: Any] = [
                "app": app,
                "system": system,
                "device": device,
                "testFlight": environment.isTestFlightApp,
                "from": dates.string(from: report.timeRange.start),
                "to": dates.string(from: report.timeRange.end),
                "states": states,
            ]
            if let value = crash.terminationCategory?.rawValue {
                fields["terminationCategory"] = value
                ended.append(value)
            }
            if let value = crash.terminationReason?.rawValue {
                fields["terminationReason"] = value
                ended.append(value)
            }
            if let value = crash.exceptionType {
                fields["exceptionType"] = value
                ended.append("exception type \(value)")
            }
            if let value = crash.exceptionCode {
                fields["exceptionCode"] = NSNumber(value: value)
                ended.append("code \(value)")
            }
            if let value = crash.signal {
                fields["signal"] = value
                ended.append("signal \(value)")
            }
            if let reason = crash.exceptionReason {
                fields["exceptionName"] = reason.exceptionName
                fields["exceptionClass"] = reason.className
                fields["exceptionKind"] = reason.exceptionType
                ended.append(reason.exceptionName)
            }
            if let value = crash.virtualMemoryRegionInfo {
                fields["virtualMemoryRegion"] = value
            }
            if let data = try? JSONEncoder().encode(crash.callStackTree),
                let tree = try? JSONSerialization.jsonObject(with: data)
            {
                fields["callStackTree"] = tree
            }
            let frames = MetricDiagnostics.extractTopFrames(from: crash.callStackTree, limit: 5)
            var summary = "\(app) on \(system), \(device)."
            if !ended.isEmpty { summary += "\nIt ended with: \(ended.joined(separator: ", "))." }
            if !states.isEmpty { summary += "\nRunning: \(states.joined(separator: ", "))." }
            if !frames.isEmpty { summary += "\nWhere: \(frames.joined(separator: "; "))." }
            fields["summary"] = summary
            return fields
        }
    #endif
}
