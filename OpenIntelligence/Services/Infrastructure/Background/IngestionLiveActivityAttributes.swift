import Foundation

#if canImport(ActivityKit)
import ActivityKit
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
        case .eco: return "Eco"
        case .balanced: return "Balanced"
        case .turbo: return "Turbo"
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
    static let ingestionQueueURL = URL(string: "openintelligence://documents/ingestion")!
    static let queryChatURL = URL(string: "openintelligence://chat/query")!
}

#if canImport(ActivityKit)
@available(iOS 17.0, *)
struct IngestionLiveActivityAttributes: ActivityAttributes {
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
struct QueryLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        let progress: Double
        let title: String
        let subtitle: String
    }

    let sessionID: UUID
}
#endif
