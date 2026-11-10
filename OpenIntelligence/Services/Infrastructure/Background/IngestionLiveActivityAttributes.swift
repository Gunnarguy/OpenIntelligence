import Foundation

#if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import AppIntents
import SwiftUI
import UIKit
import WidgetKit
#endif

enum IngestionLiveActivityPresentationProfile: String, Codable, Hashable, Sendable {
    case compactPhone
    case standardPhone
    case tablet
    case desktopCompanion
}

enum IngestionLiveActivityProcessingMode: String, Codable, Hashable, Sendable {
    case eco
    case balanced
    case turbo

    var displayName: String {
        switch self {
        case .eco: return "Efficiency"
        case .balanced: return "Balanced"
        case .turbo: return "Performance"
        }
    }
}

enum IngestionLiveActivityThermalBucket: String, Codable, Hashable, Sendable {
    case nominal
    case fair
    case serious
    case critical

    init(processInfoState: ProcessInfo.ThermalState) {
        switch processInfoState {
        case .nominal: self = .nominal
        case .fair: self = .fair
        case .serious: self = .serious
        case .critical: self = .critical
        @unknown default: self = .fair
        }
    }

    var displayName: String {
        rawValue.capitalized
    }
}

enum OpenIntelligenceDeepLink {
    static let scheme = "openintelligence"
    static let documentsURL = URL(string: "openintelligence://documents")!
    static let ingestionQueueURL = URL(string: "openintelligence://documents/ingestion")!
    static let queryChatURL = URL(string: "openintelligence://chat//query")!
}

#if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
/// The color every Live Activity and widget is drawn in: the accent the person picked in Settings, Appearance (5.8).
/// Until 5.8 an answer's Live Activity and the widgets were purple and an import's was green, cyan or orange by its
/// processing mode, whatever the app's color. The app shares the color in the app group's defaults (`share(chosen:)`)
/// and puts it in each Live Activity state it sends (`tintHex`), so a change shows at the next update.
nonisolated enum LiveActivityTint {
    /// The app's default accent (`AccentColor` in the app's asset catalog, light appearance), for a state without one.
    static let fallback = Color(red: 0.000, green: 0.361, blue: 0.859)

    static func color(hex: String?) -> Color {
        guard var text = hex?.trimmingCharacters(in: .whitespacesAndNewlines) else { return fallback }
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let rgb = UInt64(text, radix: 16) else { return fallback }
        return Color(
            red: Double((rgb >> 16) & 0xFF) / 255, green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255)
    }

    static let appGroup = "group.Gunndamental.OpenIntelligence"
    private static let sharedKey = "appAccentColorHex"

    /// In a widget: the color the app last shared.
    static var shared: Color { color(hex: UserDefaults(suiteName: appGroup)?.string(forKey: sharedKey)) }

    /// In the app: shares the person's accent (`SettingsStore.appAccentColorHex`; nil for the default, the app's
    /// `AccentColor`) with the widgets, and redraws them when it changed.
    static func share(chosen: String?) {
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        let hex = (chosen?.isEmpty == false ? chosen : nil) ?? defaultHex()
        guard defaults.string(forKey: sharedKey) != hex else { return }
        defaults.set(hex, forKey: sharedKey)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// In the app: the color for a Live Activity state, the shared one, else the app's `AccentColor`.
    static func currentHex() -> String? {
        UserDefaults(suiteName: appGroup)?.string(forKey: sharedKey) ?? defaultHex()
    }

    private static func defaultHex() -> String? {
        guard let accent = UIColor(named: "AccentColor") else { return nil }
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        guard accent.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

@available(iOS 17.0, *)
nonisolated struct IngestionLiveActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let progress: Double
        let processedCount: Int
        let totalCount: Int
        let activeCount: Int
        let currentFilename: String
        let currentStage: String
        let remainingDocuments: [String]
        let deviceSummary: String
        let performanceSummary: String
        let presentationProfile: IngestionLiveActivityPresentationProfile
        let processingMode: IngestionLiveActivityProcessingMode
        let thermalBucket: IngestionLiveActivityThermalBucket
        /// The app's accent color as "#RRGGBB" (5.8), see `LiveActivityTint`. Optional so a state written without it
        /// still decodes.
        var tintHex: String? = nil
    }

    let sessionID: UUID
    let containerName: String
}

@available(iOS 17.0, *)
nonisolated struct QueryLiveActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        let progress: Double
        let title: String
        let subtitle: String
        /// True once the answer has ended ("Answer ready" or "Stopped"), so the Stop button goes.
        /// Optional so a state written without it still decodes.
        var finished: Bool? = nil
        /// True when this Live Activity is the reranker's first setup after an update, not an answer (5.8): no Stop
        /// button, a search symbol. Optional so a state written without it still decodes.
        var isSetup: Bool? = nil
        /// The app's accent color as "#RRGGBB" (5.8), see `LiveActivityTint`.
        var tintHex: String? = nil
    }

    let sessionID: UUID
}

/// The Stop button on a long answer's Live Activity (5.7). The system runs `perform()` in the app,
/// which stops the answer the way the chat's own stop button does (`ChatScreen.stopGeneration`),
/// keeping the text already written. The chat stops only when `sessionID` is the Live Activity of
/// the answer still running (`QueryLiveActivityService.isRunningActivity`), so a Stop tapped on an
/// ended one stops nothing. The widget extension compiles this type to draw the button. Through
/// 5.6 there was no Live Activity for an answer, and stopping one meant opening the app.
@available(iOS 17.0, *)
nonisolated struct StopLongAnswerIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Stop Answering"
    static let isDiscoverable = false

    @Parameter(title: "Answer")
    var sessionID: String

    init() {}

    init(sessionID: UUID) {
        self.sessionID = sessionID.uuidString
    }

    func perform() async throws -> some IntentResult {
        let sessionID = sessionID
        await MainActor.run {
            NotificationCenter.default.post(
                name: .stopLongAnswer, object: nil, userInfo: ["sessionID": sessionID])
        }
        return .result()
    }
}
#endif

extension Notification.Name {
    /// Posted by `StopLongAnswerIntent` with the Live Activity's `sessionID` in `userInfo`; the chat
    /// that is answering stops. Declared on every platform so the chat can listen without a
    /// platform check; only iPhone and iPad post it.
    nonisolated static let stopLongAnswer = Notification.Name("OpenIntelligence.stopLongAnswer")
}
