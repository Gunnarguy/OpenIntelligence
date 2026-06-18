//
//  BackgroundTaskService.swift
//  OpenIntelligence
//
//  Manages background processing tasks for index maintenance, Spotlight
//  re-indexing, and cache warmup using BGTaskScheduler.
//

#if os(iOS)
import BackgroundTasks
import Foundation

#if canImport(UIKit)
import UIKit
#endif

private enum ContinuedIngestionPhase: String, Codable, Sendable {
    case idle
    case submitted
    case foregroundFallback
    case running
    case submissionFailed
    case expired
    case completed
    case failed
}

private enum ContinuedQueryPhase: String, Codable, Sendable {
    case idle
    case submitted
    case foregroundFallback
    case running
    case submissionFailed
    case expired
    case completed
    case failed
    case cancelled
}

private enum ContinuedIngestionExecutionMode: String, Codable, Sendable {
    case efficiency
    case balanced
    case backgroundGPU
}

private struct ContinuedIngestionPolicySnapshot: Codable, Sendable {
    let deviceTier: String
    let chipName: String
    let formFactor: String
    let requestedGPUAccelerationLevel: Double
    let activeGPUAccelerationLevel: Double
    let backgroundGPUSupported: Bool
    let backgroundGPURequested: Bool
    let lowPowerModeEnabled: Bool
    let thermalState: String
    let memoryPressure: String
    let isCharging: Bool
    let batteryPercent: Int
    let submissionStrategy: String
    let executionMode: ContinuedIngestionExecutionMode
    let rationale: [String]
}

private struct ContinuedIngestionStatusSnapshot: Codable, Sendable {
    let phase: ContinuedIngestionPhase
    let title: String
    let subtitle: String
    let progressFraction: Double
    let updatedAt: Date
    let startedAt: Date?
    let completedAt: Date?
    let lastError: String?
    let policy: ContinuedIngestionPolicySnapshot?

    static let idle = ContinuedIngestionStatusSnapshot(
        phase: .idle,
        title: "",
        subtitle: "",
        progressFraction: 0,
        updatedAt: Date(),
        startedAt: nil,
        completedAt: nil,
        lastError: nil,
        policy: nil
    )
}

private struct ContinuedIngestionRequestContext: Sendable {
    let requestIdentifier: String
    let title: String
    let subtitle: String
    let policy: ContinuedIngestionPolicySnapshot
    let submittedAt: Date
}

private struct ContinuedQueryStatusSnapshot: Codable, Sendable {
    let phase: ContinuedQueryPhase
    let title: String
    let subtitle: String
    let progressFraction: Double
    let updatedAt: Date
    let startedAt: Date?
    let completedAt: Date?
    let lastError: String?
    let policy: ContinuedIngestionPolicySnapshot?

    static let idle = ContinuedQueryStatusSnapshot(
        phase: .idle,
        title: "",
        subtitle: "",
        progressFraction: 0,
        updatedAt: Date(),
        startedAt: nil,
        completedAt: nil,
        lastError: nil,
        policy: nil
    )
}

private struct ContinuedQueryRequestContext: Sendable {
    let requestIdentifier: String
    let title: String
    let subtitle: String
    let policy: ContinuedIngestionPolicySnapshot
    let submittedAt: Date
}

/// Handles background task execution for maintenance operations
final class BackgroundTaskService: Sendable {
    static let shared = BackgroundTaskService()

    // Task identifiers (must match Info.plist BGTaskSchedulerPermittedIdentifiers)
    static let indexMaintenanceIdentifier = "com.openintelligence.index-maintenance"
    static let spotlightReindexIdentifier = "com.openintelligence.spotlight-reindex"
    static let appRefreshIdentifier = "com.openintelligence.app-refresh"
    static let continuedIngestionIdentifier = "com.openintelligence.document-ingestion.*"
    static let continuedQueryIdentifier = "com.openintelligence.rag-query.*"
    private static let continuedIngestionIdentifierPrefix = "com.openintelligence.document-ingestion"
    private static let continuedQueryIdentifierPrefix = "com.openintelligence.rag-query"

    @MainActor private var continuedIngestionRunner: (@MainActor () async -> Bool)?
    @MainActor private var continuedIngestionExpirationHandler: (@MainActor () -> Void)?
#if !targetEnvironment(macCatalyst)
    @MainActor private var activeContinuedIngestionTask: BGContinuedProcessingTask?
#else
    @MainActor private var activeContinuedIngestionTask: BGTask?
#endif
    @MainActor private var activeContinuedIngestionWorker: Task<Void, Never>?
    @MainActor private var continuedIngestionRequestSubmitted = false
    @MainActor private var activeContinuedIngestionRequestContext: ContinuedIngestionRequestContext?
    @MainActor private var continuedIngestionStatus = ContinuedIngestionStatusSnapshot.idle
    @MainActor private var lastPersistedProgressBucket = -1
    @MainActor private var continuedQueryRunner: (@MainActor () async -> Bool)?
    @MainActor private var continuedQueryExpirationHandler: (@MainActor () -> Void)?
#if !targetEnvironment(macCatalyst)
    @MainActor private var activeContinuedQueryTask: BGContinuedProcessingTask?
#else
    @MainActor private var activeContinuedQueryTask: BGTask?
#endif
    @MainActor private var activeContinuedQueryWorker: Task<Void, Never>?
    @MainActor private var continuedQueryRequestSubmitted = false
    @MainActor private var activeContinuedQueryRequestContext: ContinuedQueryRequestContext?
    @MainActor private var continuedQueryStatus = ContinuedQueryStatusSnapshot.idle
    @MainActor private var lastPersistedQueryProgressBucket = -1

#if canImport(UIKit)
    @MainActor private var foregroundFallbackTaskID: UIBackgroundTaskIdentifier = .invalid
    @MainActor private var foregroundFallbackQueryTaskID: UIBackgroundTaskIdentifier = .invalid
#endif

    private init() {}

    private static func continuedIngestionRequestIdentifier() -> String {
        "\(continuedIngestionIdentifierPrefix).\(UUID().uuidString)"
    }

    private static func continuedQueryRequestIdentifier() -> String {
        "\(continuedQueryIdentifierPrefix).\(UUID().uuidString)"
    }

    // MARK: - Task Scheduling

    /// Schedule index maintenance (runs when device is idle + charging)
    func scheduleIndexMaintenance() {
        let request = BGProcessingTaskRequest(identifier: Self.indexMaintenanceIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = true  // Only when charging
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600) // 4 hours from now

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.debug("[BackgroundTasks] Scheduled index maintenance", category: .initialization)
        } catch {
            Log.error("[BackgroundTasks] Failed to schedule index maintenance: \(error.localizedDescription)", category: .initialization)
        }
    }

    /// Schedule Spotlight re-indexing
    func scheduleSpotlightReindex() {
        let request = BGProcessingTaskRequest(identifier: Self.spotlightReindexIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 2 * 3600) // 2 hours from now

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.debug("[BackgroundTasks] Scheduled Spotlight reindex", category: .initialization)
        } catch {
            Log.error("[BackgroundTasks] Failed to schedule Spotlight reindex: \(error.localizedDescription)", category: .initialization)
        }
    }

    /// Schedule periodic app refresh (lightweight, runs frequently)
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: Self.appRefreshIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60) // 30 minutes from now

        do {
            try BGTaskScheduler.shared.submit(request)
            Log.debug("[BackgroundTasks] Scheduled app refresh", category: .initialization)
        } catch {
            Log.error("[BackgroundTasks] Failed to schedule app refresh: \(error.localizedDescription)", category: .initialization)
        }
    }

    @MainActor
    func configureContinuedIngestion(
        run: @escaping @MainActor () async -> Bool,
        expiration: @escaping @MainActor () -> Void
    ) {
        continuedIngestionRunner = run
        continuedIngestionExpirationHandler = expiration
    }

    @MainActor
    func configureContinuedQuery(
        run: @escaping @MainActor () async -> Bool,
        expiration: @escaping @MainActor () -> Void
    ) {
        continuedQueryRunner = run
        continuedQueryExpirationHandler = expiration
    }

    @MainActor
    func beginUserInitiatedIngestion(title: String, subtitle: String) {
#if targetEnvironment(macCatalyst)
        return
#else
        guard #available(iOS 26.0, *) else { return }
        guard activeContinuedIngestionTask == nil, activeContinuedIngestionWorker == nil, !continuedIngestionRequestSubmitted else {
            return
        }

        let displayTitle = tunedTitle(base: title)
        let displaySubtitle = tunedSubtitle(base: subtitle)
        let policy = continuedProcessingPolicy()
        let requestIdentifier = Self.continuedIngestionRequestIdentifier()
        activeContinuedIngestionRequestContext = ContinuedIngestionRequestContext(
            requestIdentifier: requestIdentifier,
            title: displayTitle,
            subtitle: displaySubtitle,
            policy: policy,
            submittedAt: Date()
        )

        let request = BGContinuedProcessingTaskRequest(
            identifier: requestIdentifier,
            title: displayTitle,
            subtitle: displaySubtitle
        )
        request.strategy = preferredSubmissionStrategy()
        if policy.backgroundGPURequested {
            request.requiredResources = .gpu
        }

        do {
            continuedIngestionRequestSubmitted = true
            try BGTaskScheduler.shared.submit(request)
            recordContinuedIngestionStatus(
                phase: .submitted,
                title: displayTitle,
                subtitle: displaySubtitle,
                fraction: 0,
                policy: policy,
                errorMessage: nil,
                startedAt: nil,
                completedAt: nil
            )
            TelemetryCenter.emit(
                .system,
                title: "Continued ingestion submitted",
                metadata: continuedIngestionTelemetryMetadata(
                    title: displayTitle,
                    subtitle: displaySubtitle,
                    policy: policy,
                    errorMessage: nil
                )
            )
            Log.info("[BackgroundTasks] Submitted continued ingestion task", category: .initialization)
        } catch {
            continuedIngestionRequestSubmitted = false
            recordContinuedIngestionStatus(
                phase: .submissionFailed,
                title: displayTitle,
                subtitle: displaySubtitle,
                fraction: 0,
                policy: policy,
                errorMessage: error.localizedDescription,
                startedAt: nil,
                completedAt: nil
            )
            TelemetryCenter.emit(
                .system,
                severity: .warning,
                title: "Continued ingestion submission failed",
                metadata: continuedIngestionTelemetryMetadata(
                    title: displayTitle,
                    subtitle: displaySubtitle,
                    policy: policy,
                    errorMessage: error.localizedDescription
                )
            )
            Log.warning("[BackgroundTasks] Failed to submit continued ingestion task: \(error.localizedDescription)", category: .initialization)
        }
#endif
    }

    @MainActor
    func beginUserInitiatedQuery(title: String, subtitle: String) {
#if targetEnvironment(macCatalyst)
        return
#else
        guard #available(iOS 26.0, *) else { return }
        guard activeContinuedQueryTask == nil, activeContinuedQueryWorker == nil, !continuedQueryRequestSubmitted else {
            return
        }

        let displayTitle = tunedTitle(base: title)
        let displaySubtitle = tunedSubtitle(base: subtitle)
        let policy = continuedProcessingPolicy()
        let requestIdentifier = Self.continuedQueryRequestIdentifier()
        activeContinuedQueryRequestContext = ContinuedQueryRequestContext(
            requestIdentifier: requestIdentifier,
            title: displayTitle,
            subtitle: displaySubtitle,
            policy: policy,
            submittedAt: Date()
        )

        let request = BGContinuedProcessingTaskRequest(
            identifier: requestIdentifier,
            title: displayTitle,
            subtitle: displaySubtitle
        )
        request.strategy = preferredSubmissionStrategy()
        if policy.backgroundGPURequested {
            request.requiredResources = .gpu
        }

        do {
            continuedQueryRequestSubmitted = true
            try BGTaskScheduler.shared.submit(request)
            recordContinuedQueryStatus(
                phase: .submitted,
                title: displayTitle,
                subtitle: displaySubtitle,
                fraction: 0,
                policy: policy,
                errorMessage: nil,
                startedAt: nil,
                completedAt: nil
            )
            TelemetryCenter.emit(
                .system,
                title: "Continued query submitted",
                metadata: continuedQueryTelemetryMetadata(
                    title: displayTitle,
                    subtitle: displaySubtitle,
                    policy: policy,
                    errorMessage: nil
                )
            )
            Log.info("[BackgroundTasks] Submitted continued query task", category: .initialization)
        } catch {
            continuedQueryRequestSubmitted = false
            recordContinuedQueryStatus(
                phase: .submissionFailed,
                title: displayTitle,
                subtitle: displaySubtitle,
                fraction: 0,
                policy: policy,
                errorMessage: error.localizedDescription,
                startedAt: nil,
                completedAt: nil
            )
            TelemetryCenter.emit(
                .system,
                severity: .warning,
                title: "Continued query submission failed",
                metadata: continuedQueryTelemetryMetadata(
                    title: displayTitle,
                    subtitle: displaySubtitle,
                    policy: policy,
                    errorMessage: error.localizedDescription
                )
            )
            Log.warning("[BackgroundTasks] Failed to submit continued query task: \(error.localizedDescription)", category: .initialization)
        }
#endif
    }

#if canImport(UIKit)
    @MainActor
    func beginForegroundFallbackIngestionExtensionIfNeeded(reason: String) {
        guard foregroundFallbackTaskID == .invalid else { return }
        guard activeContinuedIngestionTask == nil else { return }

        let taskID = UIApplication.shared.beginBackgroundTask(withName: "DocumentIngestionHandoff") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let context = self.activeContinuedIngestionRequestContext
                self.continuedIngestionExpirationHandler?()
                self.recordContinuedIngestionStatus(
                    phase: .expired,
                    title: context?.title,
                    subtitle: context?.subtitle,
                    fraction: self.continuedIngestionStatus.progressFraction,
                    policy: context?.policy,
                    errorMessage: "Foreground background-time handoff expired before a continued task could take over.",
                    startedAt: self.continuedIngestionStatus.startedAt,
                    completedAt: Date()
                )
                TelemetryCenter.emit(
                    .system,
                    severity: .warning,
                    title: "Foreground ingestion handoff expired",
                    metadata: self.continuedIngestionTelemetryMetadata(
                        title: context?.title,
                        subtitle: context?.subtitle,
                        policy: context?.policy,
                        errorMessage: "fallback-expired"
                    )
                )
                self.endForegroundFallbackIngestionExtension()
                Log.warning("[BackgroundTasks] Foreground ingestion handoff expired", category: .initialization)
            }
        }

        guard taskID != .invalid else { return }
        foregroundFallbackTaskID = taskID
        recordContinuedIngestionStatus(
            phase: .foregroundFallback,
            title: activeContinuedIngestionRequestContext?.title,
            subtitle: activeContinuedIngestionRequestContext?.subtitle ?? tunedSubtitle(base: reason),
            fraction: continuedIngestionStatus.progressFraction,
            policy: activeContinuedIngestionRequestContext?.policy,
            errorMessage: nil,
            startedAt: continuedIngestionStatus.startedAt,
            completedAt: nil
        )
        TelemetryCenter.emit(
            .system,
            title: "Foreground ingestion handoff started",
            metadata: ["reason": reason]
        )
        Log.info("[BackgroundTasks] Started foreground ingestion handoff", category: .initialization)
    }

    @MainActor
    func beginForegroundFallbackQueryExtensionIfNeeded(reason: String) {
        guard foregroundFallbackQueryTaskID == .invalid else { return }
        guard activeContinuedQueryTask == nil else { return }

        let taskID = UIApplication.shared.beginBackgroundTask(withName: "RAGQueryHandoff") { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let context = self.activeContinuedQueryRequestContext
                self.continuedQueryExpirationHandler?()
                self.recordContinuedQueryStatus(
                    phase: .expired,
                    title: context?.title,
                    subtitle: context?.subtitle,
                    fraction: self.continuedQueryStatus.progressFraction,
                    policy: context?.policy,
                    errorMessage: "Foreground background-time handoff expired before a continued query task could take over.",
                    startedAt: self.continuedQueryStatus.startedAt,
                    completedAt: Date()
                )
                TelemetryCenter.emit(
                    .system,
                    severity: .warning,
                    title: "Foreground query handoff expired",
                    metadata: self.continuedQueryTelemetryMetadata(
                        title: context?.title,
                        subtitle: context?.subtitle,
                        policy: context?.policy,
                        errorMessage: "fallback-expired"
                    )
                )
                self.endForegroundFallbackQueryExtension()
                Log.warning("[BackgroundTasks] Foreground query handoff expired", category: .initialization)
            }
        }

        guard taskID != .invalid else { return }
        foregroundFallbackQueryTaskID = taskID
        recordContinuedQueryStatus(
            phase: .foregroundFallback,
            title: activeContinuedQueryRequestContext?.title,
            subtitle: activeContinuedQueryRequestContext?.subtitle ?? tunedSubtitle(base: reason),
            fraction: continuedQueryStatus.progressFraction,
            policy: activeContinuedQueryRequestContext?.policy,
            errorMessage: nil,
            startedAt: continuedQueryStatus.startedAt,
            completedAt: nil
        )
        TelemetryCenter.emit(
            .system,
            title: "Foreground query handoff started",
            metadata: ["reason": reason]
        )
        Log.info("[BackgroundTasks] Started foreground query handoff", category: .initialization)
    }

    @MainActor
    func endForegroundFallbackIngestionExtension() {
        guard foregroundFallbackTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(foregroundFallbackTaskID)
        foregroundFallbackTaskID = .invalid
    }

    @MainActor
    func endForegroundFallbackQueryExtension() {
        guard foregroundFallbackQueryTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(foregroundFallbackQueryTaskID)
        foregroundFallbackQueryTaskID = .invalid
    }
#else
    @MainActor
    func beginForegroundFallbackIngestionExtensionIfNeeded(reason _: String) {}

    @MainActor
    func endForegroundFallbackIngestionExtension() {}

    @MainActor
    func beginForegroundFallbackQueryExtensionIfNeeded(reason _: String) {}

    @MainActor
    func endForegroundFallbackQueryExtension() {}
#endif

    #if !targetEnvironment(macCatalyst)
    @MainActor
    @available(iOS 26.0, *)
    func handleContinuedIngestion(task: BGContinuedProcessingTask) {
        Log.info("[BackgroundTasks] Starting continued ingestion task", category: .initialization)

        let policy = activeContinuedIngestionRequestContext?.policy ?? continuedProcessingPolicy()
        applyIngestionExecutionProfile(policy: policy)

        endForegroundFallbackIngestionExtension()
        continuedIngestionRequestSubmitted = false
        activeContinuedIngestionTask = task
        task.progress.totalUnitCount = 1000
        task.progress.completedUnitCount = 0
        let context = activeContinuedIngestionRequestContext
        recordContinuedIngestionStatus(
            phase: .running,
            title: context?.title,
            subtitle: context?.subtitle,
            fraction: 0,
            policy: context?.policy,
            errorMessage: nil,
            startedAt: Date(),
            completedAt: nil
        )
        TelemetryCenter.emit(
            .system,
            title: "Continued ingestion started",
            metadata: continuedIngestionTelemetryMetadata(
                title: context?.title,
                subtitle: context?.subtitle,
                policy: context?.policy,
                errorMessage: nil
            )
        )

        task.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.activeContinuedIngestionWorker?.cancel()
                self.continuedIngestionExpirationHandler?()
                self.finishContinuedIngestion(
                    success: false,
                    phase: .expired,
                    errorMessage: "The system expired the continued ingestion task before completion."
                )
                Log.warning("[BackgroundTasks] Continued ingestion task expired", category: .initialization)
            }
        }

        activeContinuedIngestionWorker?.cancel()
        activeContinuedIngestionWorker = Task { @MainActor [weak self] in
            guard let self else { return }
            let success = await self.continuedIngestionRunner?() ?? false
            self.finishContinuedIngestion(
                success: success,
                phase: success ? .completed : .failed,
                errorMessage: success ? nil : "The ingestion pipeline reported failure while running under continued processing."
            )
        }
    }
    #endif

    @MainActor
    func shouldPauseForegroundIngestionForBackgroundHandoff() -> Bool {
        false
    }

    @MainActor
    func applyIngestionExecutionProfileForCurrentState() {
        #if targetEnvironment(macCatalyst)
            DeviceCapabilityService.shared.setIngestionExecutionProfile(.interactive)
        #else
            guard #available(iOS 26.0, *) else {
                DeviceCapabilityService.shared.setIngestionExecutionProfile(.interactive)
                return
            }

            let policy = activeContinuedIngestionRequestContext?.policy ?? continuedProcessingPolicy()
            applyIngestionExecutionProfile(policy: policy)
        #endif
    }

    @MainActor
    func clearIngestionExecutionProfile() {
        DeviceCapabilityService.shared.setIngestionExecutionProfile(.interactive)
    }

    @MainActor
    private func applyIngestionExecutionProfile(policy: ContinuedIngestionPolicySnapshot) {
        let profile: IngestionExecutionProfile = policy.backgroundGPURequested ? .continuedProcessingGPU : .continuedProcessingCPUOnly
        DeviceCapabilityService.shared.setIngestionExecutionProfile(profile)
    }

    #if !targetEnvironment(macCatalyst)
    @MainActor
    @available(iOS 26.0, *)
    func handleContinuedQuery(task: BGContinuedProcessingTask) {
        Log.info("[BackgroundTasks] Starting continued query task", category: .initialization)

        endForegroundFallbackQueryExtension()
        continuedQueryRequestSubmitted = false
        activeContinuedQueryTask = task
        task.progress.totalUnitCount = 1000
        task.progress.completedUnitCount = 0
        let context = activeContinuedQueryRequestContext
        recordContinuedQueryStatus(
            phase: .running,
            title: context?.title,
            subtitle: context?.subtitle,
            fraction: 0,
            policy: context?.policy,
            errorMessage: nil,
            startedAt: Date(),
            completedAt: nil
        )
        TelemetryCenter.emit(
            .system,
            title: "Continued query started",
            metadata: continuedQueryTelemetryMetadata(
                title: context?.title,
                subtitle: context?.subtitle,
                policy: context?.policy,
                errorMessage: nil
            )
        )

        task.expirationHandler = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.activeContinuedQueryWorker?.cancel()
                self.continuedQueryExpirationHandler?()
                self.finishContinuedQuery(
                    success: false,
                    phase: .expired,
                    errorMessage: "The system expired the continued query task before completion."
                )
                Log.warning("[BackgroundTasks] Continued query task expired", category: .initialization)
            }
        }

        activeContinuedQueryWorker?.cancel()
        activeContinuedQueryWorker = Task { @MainActor [weak self] in
            guard let self else { return }
            let success = await self.continuedQueryRunner?() ?? false
            self.finishContinuedQuery(
                success: success,
                phase: success ? .completed : .failed,
                errorMessage: success ? nil : "The RAG pipeline reported failure while running under continued processing."
            )
        }
    }
    #endif

    @MainActor
    func updateContinuedIngestionProgress(title: String, subtitle: String, fraction: Double) {
        #if targetEnvironment(macCatalyst)
            return
        #else
            guard #available(iOS 26.0, *), let task = activeContinuedIngestionTask else { return }
            let clampedFraction = max(0, min(1, fraction))
            let displayTitle = tunedTitle(base: title)
            let displaySubtitle = tunedSubtitle(base: subtitle)
            task.progress.totalUnitCount = 1000
            task.progress.completedUnitCount = Int64((clampedFraction * 1000).rounded())
            task.updateTitle(displayTitle, subtitle: displaySubtitle)
            persistContinuedIngestionProgress(
                title: displayTitle,
                subtitle: displaySubtitle,
                fraction: clampedFraction
            )
        #endif
    }

    @MainActor
    func updateContinuedQueryProgress(title: String, subtitle: String, fraction: Double) {
        #if targetEnvironment(macCatalyst)
            return
        #else
            guard #available(iOS 26.0, *), let task = activeContinuedQueryTask else { return }
            let clampedFraction = max(0, min(1, fraction))
            let displayTitle = tunedTitle(base: title)
            let displaySubtitle = tunedSubtitle(base: subtitle)
            task.progress.totalUnitCount = 1000
            task.progress.completedUnitCount = Int64((clampedFraction * 1000).rounded())
            task.updateTitle(displayTitle, subtitle: displaySubtitle)
            persistContinuedQueryProgress(
                title: displayTitle,
                subtitle: displaySubtitle,
                fraction: clampedFraction
            )
        #endif
    }

    @MainActor
    func completeUserInitiatedIngestion(success: Bool) {
        #if targetEnvironment(macCatalyst)
            _ = success
            activeContinuedIngestionWorker?.cancel()
            activeContinuedIngestionWorker = nil
            continuedIngestionRequestSubmitted = false
            clearIngestionExecutionProfile()
            activeContinuedIngestionRequestContext = nil
        #else
            guard #available(iOS 26.0, *) else { return }

            if activeContinuedIngestionTask != nil {
                finishContinuedIngestion(
                    success: success,
                    phase: success ? .completed : .failed,
                    errorMessage: success ? nil : "The ingestion pipeline completed with one or more failures."
                )
                return
            }

            endForegroundFallbackIngestionExtension()
            activeContinuedIngestionWorker?.cancel()
            activeContinuedIngestionWorker = nil
            continuedIngestionRequestSubmitted = false
            clearIngestionExecutionProfile()
            let context = activeContinuedIngestionRequestContext
            if let requestIdentifier = context?.requestIdentifier {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: requestIdentifier)
            }
            recordContinuedIngestionStatus(
                phase: success ? .completed : .failed,
                title: context?.title,
                subtitle: context?.subtitle,
                fraction: success ? 1 : continuedIngestionStatus.progressFraction,
                policy: context?.policy,
                errorMessage: success ? nil : "Document ingestion finished without continued background support.",
                startedAt: continuedIngestionStatus.startedAt,
                completedAt: Date()
            )
            activeContinuedIngestionRequestContext = nil
        #endif
    }

    @MainActor
    func completeUserInitiatedQuery(success: Bool) {
        #if targetEnvironment(macCatalyst)
            _ = success
            activeContinuedQueryWorker?.cancel()
            activeContinuedQueryWorker = nil
            continuedQueryRequestSubmitted = false
            activeContinuedQueryRequestContext = nil
        #else
            guard #available(iOS 26.0, *) else { return }

            if activeContinuedQueryTask != nil {
                finishContinuedQuery(
                    success: success,
                    phase: success ? .completed : .failed,
                    errorMessage: success ? nil : "The RAG pipeline completed with one or more failures."
                )
                return
            }

            endForegroundFallbackQueryExtension()
            activeContinuedQueryWorker?.cancel()
            activeContinuedQueryWorker = nil
            continuedQueryRequestSubmitted = false
            let context = activeContinuedQueryRequestContext
            if let requestIdentifier = context?.requestIdentifier {
                BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: requestIdentifier)
            }
            recordContinuedQueryStatus(
                phase: success ? .completed : .failed,
                title: context?.title,
                subtitle: context?.subtitle,
                fraction: success ? 1 : continuedQueryStatus.progressFraction,
                policy: context?.policy,
                errorMessage: success ? nil : "Question answering finished without continued background support.",
                startedAt: continuedQueryStatus.startedAt,
                completedAt: Date()
            )
            activeContinuedQueryRequestContext = nil
        #endif
    }

    #if !targetEnvironment(macCatalyst)
    @MainActor
    private func finishContinuedIngestion(
        success: Bool,
        phase: ContinuedIngestionPhase,
        errorMessage: String?
    ) {
        guard #available(iOS 26.0, *) else { return }
        guard let task = activeContinuedIngestionTask else { return }

        let context = activeContinuedIngestionRequestContext
        activeContinuedIngestionTask = nil
        activeContinuedIngestionWorker = nil
        continuedIngestionRequestSubmitted = false
        endForegroundFallbackIngestionExtension()
        task.expirationHandler = nil
        task.setTaskCompleted(success: success)
        recordContinuedIngestionStatus(
            phase: phase,
            title: context?.title,
            subtitle: context?.subtitle,
            fraction: success ? 1 : continuedIngestionStatus.progressFraction,
            policy: context?.policy,
            errorMessage: errorMessage,
            startedAt: continuedIngestionStatus.startedAt ?? context?.submittedAt,
            completedAt: Date()
        )
        TelemetryCenter.emit(
            .system,
            severity: success ? .info : .warning,
            title: success ? "Continued ingestion finished" : "Continued ingestion ended early",
            metadata: continuedIngestionTelemetryMetadata(
                title: context?.title,
                subtitle: context?.subtitle,
                policy: context?.policy,
                errorMessage: errorMessage
            )
        )
        clearIngestionExecutionProfile()
        activeContinuedIngestionRequestContext = nil
    }

    @MainActor
    private func finishContinuedQuery(
        success: Bool,
        phase: ContinuedQueryPhase,
        errorMessage: String?
    ) {
        guard #available(iOS 26.0, *) else { return }
        guard let task = activeContinuedQueryTask else { return }

        let context = activeContinuedQueryRequestContext
        activeContinuedQueryTask = nil
        activeContinuedQueryWorker = nil
        continuedQueryRequestSubmitted = false
        endForegroundFallbackQueryExtension()
        task.expirationHandler = nil
        task.setTaskCompleted(success: success)
        recordContinuedQueryStatus(
            phase: phase,
            title: context?.title,
            subtitle: context?.subtitle,
            fraction: success ? 1 : continuedQueryStatus.progressFraction,
            policy: context?.policy,
            errorMessage: errorMessage,
            startedAt: continuedQueryStatus.startedAt ?? context?.submittedAt,
            completedAt: Date()
        )
        TelemetryCenter.emit(
            .system,
            severity: success ? .info : .warning,
            title: success ? "Continued query finished" : "Continued query ended early",
            metadata: continuedQueryTelemetryMetadata(
                title: context?.title,
                subtitle: context?.subtitle,
                policy: context?.policy,
                errorMessage: errorMessage
            )
        )
        activeContinuedQueryRequestContext = nil
    }

    @MainActor
    @available(iOS 26.0, *)
    private func preferredSubmissionStrategy() -> BGContinuedProcessingTaskRequest.SubmissionStrategy {
        // Document ingestion should complete eventually after a user initiates it.
        // Prefer queueing over immediate failure when the system is resource constrained.
        .queue
    }

    @MainActor
    @available(iOS 26.0, *)
    private func continuedProcessingPolicy() -> ContinuedIngestionPolicySnapshot {
        let device = DeviceCapabilityService.shared
        let systemState = SystemStateMonitor.shared.currentState
        let backgroundGPUSupported = BGTaskScheduler.supportedResources.contains(.gpu)
        let requestedGPUAccelerationLevel = device.gpuAccelerationLevel
        let activeGPUAccelerationLevel = device.activeGPUAccelerationLevel
        let requiredGPUThreshold = requiredGPUThreshold(for: device)
        let minimumBatteryPercent = minimumBatteryPercentForBackgroundGPU(for: device)

        var rationale: [String] = []
        var backgroundGPURequested = true

        if !backgroundGPUSupported {
            backgroundGPURequested = false
            rationale.append("This device does not advertise background GPU support.")
        }

        if activeGPUAccelerationLevel < requiredGPUThreshold {
            backgroundGPURequested = false
            rationale.append("Requested GPU level stays below the safe background threshold for this device profile.")
        }

        if systemState.isLowPowerModeEnabled {
            backgroundGPURequested = false
            rationale.append("Low Power Mode is enabled, so background GPU escalation is disabled.")
        }

        if systemState.thermalState == .serious || systemState.thermalState == .critical {
            backgroundGPURequested = false
            rationale.append("Thermal pressure is above the safe continued-processing range.")
        }

        if systemState.memoryPressure == .critical {
            backgroundGPURequested = false
            rationale.append("Critical memory pressure requires the most conservative execution route.")
        }

        if device.formFactor == .iPhone,
           device.tier == .baseline,
           !systemState.isCharging {
            backgroundGPURequested = false
            rationale.append("Baseline iPhones only use background GPU when charging.")
        }

        if !systemState.isCharging,
           systemState.batteryPercent >= 0,
           systemState.batteryPercent < minimumBatteryPercent {
            backgroundGPURequested = false
            rationale.append("Battery reserve is below the device-specific threshold for sustained background GPU work.")
        }

        if backgroundGPURequested {
            rationale.append("Background GPU is safe enough for this device and current runtime state.")
        } else {
            rationale.append("Continue on CPU/ANE-first routing to maximize survivability under background constraints.")
        }

        let executionMode: ContinuedIngestionExecutionMode
        if backgroundGPURequested {
            executionMode = .backgroundGPU
        } else if activeGPUAccelerationLevel >= 0.3 {
            executionMode = .balanced
        } else {
            executionMode = .efficiency
        }

        return ContinuedIngestionPolicySnapshot(
            deviceTier: device.tier.rawValue,
            chipName: device.chipName,
            formFactor: device.formFactor.rawValue,
            requestedGPUAccelerationLevel: requestedGPUAccelerationLevel,
            activeGPUAccelerationLevel: activeGPUAccelerationLevel,
            backgroundGPUSupported: backgroundGPUSupported,
            backgroundGPURequested: backgroundGPURequested,
            lowPowerModeEnabled: systemState.isLowPowerModeEnabled,
            thermalState: systemState.thermalState.description,
            memoryPressure: systemState.memoryPressure.rawValue,
            isCharging: systemState.isCharging,
            batteryPercent: systemState.batteryPercent,
            submissionStrategy: "queue",
            executionMode: executionMode,
            rationale: rationale
        )
    }
    #endif

    @MainActor
    private func tunedTitle(base: String) -> String {
        trimmedDisplayText(base, maxLength: 22)
    }

    @MainActor
    private func tunedSubtitle(base: String) -> String {
        let normalized = base
            .replacingOccurrences(of: " • ", with: " · ")
            .replacingOccurrences(of: "  ", with: " ")

        if normalized.count <= 38 {
            return normalized
        }

        let segments = normalized
            .split(separator: "·", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        if segments.count >= 2 {
            let leading = trimmedDisplayText(String(segments[0]), maxLength: 14)
            let trailing = trimmedDisplayText(String(segments[1]), maxLength: 20)
            return "\(leading) · \(trailing)"
        }

        return trimmedDisplayText(normalized, maxLength: 38)
    }

    @MainActor
    private func trimmedDisplayText(_ text: String, maxLength: Int) -> String {
        let collapsed = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard collapsed.count > maxLength else { return collapsed }
        guard maxLength > 1 else { return String(collapsed.prefix(maxLength)) }
        return String(collapsed.prefix(maxLength - 1)) + "…"
    }

    @MainActor
    private func requiredGPUThreshold(for device: DeviceCapabilityService) -> Double {
        switch device.formFactor {
        case .iPhone:
            switch device.tier {
            case .baseline:
                return 0.85
            case .enhanced:
                return 0.75
            case .advanced, .ultraAdvanced:
                return 0.65
            case .unsupported:
                return 1.1
            }
        case .iPadMini:
            return 0.8
        case .iPadAir:
            return 0.7
        case .iPadPro, .mac:
            return 0.6
        case .unknown:
            return 1.1
        }
    }

    @MainActor
    private func minimumBatteryPercentForBackgroundGPU(for device: DeviceCapabilityService) -> Int {
        switch device.formFactor {
        case .iPhone:
            return device.tier == .baseline ? 50 : 35
        case .iPadMini:
            return 40
        case .iPadAir:
            return 30
        case .iPadPro:
            return 25
        case .mac:
            return -1
        case .unknown:
            return 50
        }
    }

    @MainActor
    private func persistContinuedIngestionProgress(title: String, subtitle: String, fraction: Double) {
        let progressBucket = Int((fraction * 100).rounded())
        let titleChanged = title != continuedIngestionStatus.title
        let subtitleChanged = subtitle != continuedIngestionStatus.subtitle

        guard progressBucket != lastPersistedProgressBucket || titleChanged || subtitleChanged else {
            return
        }

        lastPersistedProgressBucket = progressBucket
        recordContinuedIngestionStatus(
            phase: .running,
            title: title,
            subtitle: subtitle,
            fraction: fraction,
            policy: activeContinuedIngestionRequestContext?.policy ?? continuedIngestionStatus.policy,
            errorMessage: nil,
            startedAt: continuedIngestionStatus.startedAt,
            completedAt: nil
        )
    }

    @MainActor
    private func persistContinuedQueryProgress(title: String, subtitle: String, fraction: Double) {
        let progressBucket = Int((fraction * 100).rounded())
        let titleChanged = title != continuedQueryStatus.title
        let subtitleChanged = subtitle != continuedQueryStatus.subtitle

        guard progressBucket != lastPersistedQueryProgressBucket || titleChanged || subtitleChanged else {
            return
        }

        lastPersistedQueryProgressBucket = progressBucket
        recordContinuedQueryStatus(
            phase: .running,
            title: title,
            subtitle: subtitle,
            fraction: fraction,
            policy: activeContinuedQueryRequestContext?.policy ?? continuedQueryStatus.policy,
            errorMessage: nil,
            startedAt: continuedQueryStatus.startedAt,
            completedAt: nil
        )
    }

    @MainActor
    private func recordContinuedIngestionStatus(
        phase: ContinuedIngestionPhase,
        title: String?,
        subtitle: String?,
        fraction: Double,
        policy: ContinuedIngestionPolicySnapshot?,
        errorMessage: String?,
        startedAt: Date?,
        completedAt: Date?
    ) {
        let snapshot = ContinuedIngestionStatusSnapshot(
            phase: phase,
            title: title ?? continuedIngestionStatus.title,
            subtitle: subtitle ?? continuedIngestionStatus.subtitle,
            progressFraction: max(0, min(1, fraction)),
            updatedAt: Date(),
            startedAt: startedAt ?? continuedIngestionStatus.startedAt,
            completedAt: completedAt,
            lastError: errorMessage,
            policy: policy ?? continuedIngestionStatus.policy
        )

        continuedIngestionStatus = snapshot
        persistContinuedIngestionStatus(snapshot)
    }

    @MainActor
    private func recordContinuedQueryStatus(
        phase: ContinuedQueryPhase,
        title: String?,
        subtitle: String?,
        fraction: Double,
        policy: ContinuedIngestionPolicySnapshot?,
        errorMessage: String?,
        startedAt: Date?,
        completedAt: Date?
    ) {
        let snapshot = ContinuedQueryStatusSnapshot(
            phase: phase,
            title: title ?? continuedQueryStatus.title,
            subtitle: subtitle ?? continuedQueryStatus.subtitle,
            progressFraction: max(0, min(1, fraction)),
            updatedAt: Date(),
            startedAt: startedAt ?? continuedQueryStatus.startedAt,
            completedAt: completedAt,
            lastError: errorMessage,
            policy: policy ?? continuedQueryStatus.policy
        )

        continuedQueryStatus = snapshot
        persistContinuedQueryStatus(snapshot)
    }

    private func persistContinuedIngestionStatus(_ snapshot: ContinuedIngestionStatusSnapshot) {
        let url = AppSupportPaths.continuedIngestionStatusURL()

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.error("[BackgroundTasks] Failed to persist continued ingestion status: \(error.localizedDescription)", category: .initialization)
        }
    }

    private func persistContinuedQueryStatus(_ snapshot: ContinuedQueryStatusSnapshot) {
        let url = AppSupportPaths.continuedQueryStatusURL()

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.error("[BackgroundTasks] Failed to persist continued query status: \(error.localizedDescription)", category: .initialization)
        }
    }

    @MainActor
    private func continuedIngestionTelemetryMetadata(
        title: String?,
        subtitle: String?,
        policy: ContinuedIngestionPolicySnapshot?,
        errorMessage: String?
    ) -> [String: String] {
        var metadata: [String: String] = [:]

        if let title, !title.isEmpty {
            metadata["title"] = title
        }

        if let subtitle, !subtitle.isEmpty {
            metadata["subtitle"] = subtitle
        }

        if let errorMessage, !errorMessage.isEmpty {
            metadata["error"] = errorMessage
        }

        if let policy {
            metadata["chip"] = policy.chipName
            metadata["deviceTier"] = policy.deviceTier
            metadata["formFactor"] = policy.formFactor
            metadata["mode"] = policy.executionMode.rawValue
            metadata["backgroundGPU"] = policy.backgroundGPURequested ? "requested" : "disabled"
            metadata["thermal"] = policy.thermalState
            metadata["battery"] = "\(policy.batteryPercent)%"
            metadata["lowPowerMode"] = policy.lowPowerModeEnabled ? "on" : "off"
            metadata["rationale"] = policy.rationale.joined(separator: " | ")
        }

        return metadata
    }

    @MainActor
    private func continuedQueryTelemetryMetadata(
        title: String?,
        subtitle: String?,
        policy: ContinuedIngestionPolicySnapshot?,
        errorMessage: String?
    ) -> [String: String] {
        continuedIngestionTelemetryMetadata(
            title: title,
            subtitle: subtitle,
            policy: policy,
            errorMessage: errorMessage
        )
    }

    // MARK: - Task Handlers

    /// Handle index maintenance: compact vector databases, prune stale entity entries
    @MainActor
    func handleIndexMaintenance(task: BGProcessingTask) {
        Log.info("[BackgroundTasks] Starting index maintenance", category: .initialization)
        HardwareTelemetryReporter.pulse(.ragOrchestration, intensity: 0.6, duration: 0.5)

        // Schedule next occurrence
        scheduleIndexMaintenance()

        let maintenanceTask = Task {
            // 1. Entity index health check
            let entityService = EntityIndexService.shared
            let stats = await entityService.statistics()
            Log.info("[BackgroundTasks] Entity index: \(stats.totalEntities) entities, \(stats.totalIndexedChunks) chunks", category: .initialization)

            // 2. Gazetteer vocabulary health check
            let gazetteerTerms = await GazetteerService.shared.termCount
            let gazetteerLabels = await GazetteerService.shared.labelCount
            Log.info("[BackgroundTasks] Gazetteer: \(gazetteerTerms) terms across \(gazetteerLabels) labels", category: .initialization)

            // 3. Flag maintenance timestamp for diagnostics
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastIndexMaintenanceTimestamp")
            UserDefaults.standard.set(stats.totalEntities, forKey: "lastMaintenanceEntityCount")

            HardwareTelemetryReporter.reportCPUOperation()
            Log.info("[BackgroundTasks] Index maintenance completed", category: .initialization)
            task.setTaskCompleted(success: true)
        }

        // Handle task expiration
        task.expirationHandler = {
            maintenanceTask.cancel()
            Log.warning("[BackgroundTasks] Index maintenance expired", category: .initialization)
        }
    }

    /// Handle Spotlight re-indexing
    @MainActor
    func handleSpotlightReindex(task: BGProcessingTask) {
        Log.info("[BackgroundTasks] Starting Spotlight reindex", category: .initialization)
        HardwareTelemetryReporter.pulse(.dataDecoding, intensity: 0.5, duration: 0.3)

        scheduleSpotlightReindex()

        let reindexTask = Task {
            // Flag that a Spotlight reindex is needed on next foreground launch
            // Full reindex requires ContainerService data (only available in foreground)
            UserDefaults.standard.set(true, forKey: "spotlightReindexNeeded")
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastSpotlightReindexRequest")

            Log.info("[BackgroundTasks] Spotlight reindex flagged for next foreground launch", category: .initialization)
            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            reindexTask.cancel()
        }
    }

    /// Handle lightweight app refresh (cache warmup, prediction updates)
    @MainActor
    func handleAppRefresh(task: BGAppRefreshTask) {
        Log.debug("[BackgroundTasks] App refresh triggered", category: .initialization)

        scheduleAppRefresh()

        let refreshTask = Task {
            // 1. Warm Gazetteer vocabulary cache (forces lazy data to load)
            let termCount = await GazetteerService.shared.termCount
            Log.debug("[BackgroundTasks] Gazetteer warmed: \(termCount) terms", category: .initialization)

            // 2. Record refresh timestamp
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "lastAppRefreshTimestamp")

            task.setTaskCompleted(success: true)
        }

        task.expirationHandler = {
            refreshTask.cancel()
        }
    }
}
#else
import Foundation

final class BackgroundTaskService: Sendable {
    static let shared = BackgroundTaskService()

    static let indexMaintenanceIdentifier = "com.openintelligence.index-maintenance"
    static let spotlightReindexIdentifier = "com.openintelligence.spotlight-reindex"
    static let appRefreshIdentifier = "com.openintelligence.app-refresh"
    static let continuedIngestionIdentifier = "com.openintelligence.document-ingestion.*"
    static let continuedQueryIdentifier = "com.openintelligence.rag-query.*"

    private init() {}

    func scheduleIndexMaintenance() {}
    func scheduleSpotlightReindex() {}
    func scheduleAppRefresh() {}

    @MainActor
    func configureContinuedIngestion(
        run: @escaping @MainActor () async -> Bool,
        expiration: @escaping @MainActor () -> Void
    ) {}

    @MainActor
    func configureContinuedQuery(
        run: @escaping @MainActor () async -> Bool,
        expiration: @escaping @MainActor () -> Void
    ) {}

    @MainActor
    func beginUserInitiatedIngestion(title: String, subtitle: String) {}

    @MainActor
    func beginUserInitiatedQuery(title: String, subtitle: String) {}

    @MainActor
    func beginForegroundFallbackIngestionExtensionIfNeeded(reason: String) {}

    @MainActor
    func endForegroundFallbackIngestionExtension() {}

    @MainActor
    func beginForegroundFallbackQueryExtensionIfNeeded(reason: String) {}

    @MainActor
    func endForegroundFallbackQueryExtension() {}

    @MainActor
    func shouldPauseForegroundIngestionForBackgroundHandoff() -> Bool {
        false
    }

    @MainActor
    func applyIngestionExecutionProfileForCurrentState() {}

    @MainActor
    func clearIngestionExecutionProfile() {}

    @MainActor
    func updateContinuedIngestionProgress(title: String, subtitle: String, fraction: Double) {}

    @MainActor
    func updateContinuedQueryProgress(title: String, subtitle: String, fraction: Double) {}

    @MainActor
    func completeUserInitiatedIngestion(success: Bool) {}

    @MainActor
    func completeUserInitiatedQuery(success: Bool) {}
}
#endif
