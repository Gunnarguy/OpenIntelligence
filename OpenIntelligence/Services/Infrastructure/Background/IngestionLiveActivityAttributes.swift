import Foundation

#if os(iOS) && canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import AppIntents
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
