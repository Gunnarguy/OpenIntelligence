#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import Foundation

@available(iOS 17.0, *)
@MainActor
final class IngestionLiveActivityService {
    static let shared = IngestionLiveActivityService()

    private var currentActivity: Activity<IngestionLiveActivityAttributes>?
    private var lastContentState: IngestionLiveActivityAttributes.ContentState?
    private var lastUpdateAt: Date = .distantPast
    private var activityOperationTask: Task<Void, Never>?
    private var activityStateObservationTask: Task<Void, Never>?

    private init() {
        currentActivity = restorableActivity()
        observeCurrentActivityIfNeeded()
    }

    func restoreExistingActivityIfNeeded() {
        discardInactiveActivityIfNeeded()
        if currentActivity == nil {
            currentActivity = restorableActivity()
            observeCurrentActivityIfNeeded()
        }
    }

    func sync(items: [IngestionItem], containerName: String?) {
        restoreExistingActivityIfNeeded()

        let relevantItems = items.sorted { lhs, rhs in
            sortOrder(for: lhs.stage) < sortOrder(for: rhs.stage)
        }

        guard !relevantItems.isEmpty else {
            endCurrentActivity(finalState: nil)
            return
        }

        guard shouldPresentLiveActivities else { return }
        guard let contentState = buildContentState(from: relevantItems) else { return }

        let shouldUpdate = lastContentState != contentState
        let enoughTimeElapsed = Date().timeIntervalSince(lastUpdateAt) >= minimumUpdateInterval
        guard shouldUpdate || currentActivity == nil else { return }
        guard currentActivity == nil || enoughTimeElapsed else { return }

        let trimmedContainerName = trimmed(containerName ?? "OpenIntelligence", maxLength: 24)
        let staleDate = Date().addingTimeInterval(max(60, minimumUpdateInterval * 8))
        let content = ActivityContent(state: contentState, staleDate: staleDate)

        if let currentActivity {
            let sessionID = currentActivity.attributes.sessionID
            activityOperationTask?.cancel()
            activityOperationTask = Task { [weak self] in
                guard !Task.isCancelled else { return }
                await currentActivity.update(content)
                guard !Task.isCancelled else { return }

                await MainActor.run { [weak self] in
                    guard let self else { return }
                    if self.currentActivity?.attributes.sessionID == sessionID {
                        self.lastContentState = contentState
                        self.lastUpdateAt = Date()
                    }
                    self.activityOperationTask = nil
                }
            }
        } else {
            guard activityOperationTask == nil else { return }
            do {
                let activity = try Activity.request(
                    attributes: IngestionLiveActivityAttributes(
                        sessionID: UUID(),
                        containerName: trimmedContainerName
                    ),
                    content: content,
                    pushType: nil
                )
                currentActivity = activity
                lastContentState = contentState
                lastUpdateAt = Date()
                observeCurrentActivityIfNeeded()
            } catch {
                Log.warning("[IngestionLiveActivity] Failed to start Live Activity: \(error.localizedDescription)", category: .ui)
            }
        }
    }

    func endCurrentActivity(finalState: IngestionLiveActivityAttributes.ContentState?) {
        guard let currentActivity else { return }

        activityOperationTask?.cancel()
        activityOperationTask = nil
        activityStateObservationTask?.cancel()
        activityStateObservationTask = nil
        self.currentActivity = nil
        lastContentState = nil
        lastUpdateAt = .distantPast

        activityOperationTask = Task { [weak self] in
            if let finalState {
                await currentActivity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .after(.now + 600)
                )
            } else {
                await currentActivity.end(nil, dismissalPolicy: .immediate)
            }

            await MainActor.run { [weak self] in
                self?.activityOperationTask = nil
            }
        }
    }

    func finish(items: [IngestionItem], containerName _: String?) {
        guard !items.isEmpty else {
            endCurrentActivity(finalState: nil)
            return
        }

        let device = DeviceCapabilityService.shared
        let completedCount = items.filter { $0.stage == .complete }.count
        let failedCount = items.filter { $0.stage == .failed }.count
        let totalCount = items.count
        let progress = totalCount == 0 ? 1.0 : Double(completedCount) / Double(totalCount)
        let stageLabel = failedCount > 0 ? "Finished with issues" : "Complete"
        let headline: String
        if failedCount > 0 {
            headline = "\(completedCount) imported, \(failedCount) failed"
        } else {
            headline = totalCount == 1 ? "Import complete" : "\(completedCount) documents ready"
        }

        let finalState = IngestionLiveActivityAttributes.ContentState(
            progress: progress,
            processedCount: completedCount,
            totalCount: totalCount,
            activeCount: 0,
            currentFilename: headline,
            currentStage: stageLabel,
            remainingDocuments: [],
            deviceSummary: trimmed(deviceSummary(for: device), maxLength: 32),
            performanceSummary: failedCount > 0 ? "Review failed imports in Documents" : "Knowledge base updated",
            presentationProfile: presentationProfile(for: device),
            processingMode: processingMode(for: device),
            thermalBucket: IngestionLiveActivityThermalBucket(processInfoState: ProcessInfo.processInfo.thermalState)
        )

        endCurrentActivity(finalState: finalState)
    }

    private func restorableActivity() -> Activity<IngestionLiveActivityAttributes>? {
        Activity<IngestionLiveActivityAttributes>.activities.first(where: { $0.activityState == .active })
    }

    private func discardInactiveActivityIfNeeded() {
        guard let currentActivity, currentActivity.activityState != .active else { return }
        activityStateObservationTask?.cancel()
        activityStateObservationTask = nil
        self.currentActivity = nil
        lastContentState = nil
        lastUpdateAt = .distantPast
    }

    private func observeCurrentActivityIfNeeded() {
        guard let currentActivity else {
            activityStateObservationTask?.cancel()
            activityStateObservationTask = nil
            return
        }

        let sessionID = currentActivity.attributes.sessionID
        activityStateObservationTask?.cancel()
        activityStateObservationTask = Task { [weak self] in
            for await state in currentActivity.activityStateUpdates {
                guard !Task.isCancelled else { return }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    guard self.currentActivity?.attributes.sessionID == sessionID else { return }

                    if state != .active {
                        self.currentActivity = nil
                        self.lastContentState = nil
                        self.lastUpdateAt = .distantPast
                        self.activityStateObservationTask?.cancel()
                        self.activityStateObservationTask = nil
                    }
                }
            }
        }
    }

    private var shouldPresentLiveActivities: Bool {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
        guard !ProcessInfo.processInfo.isiOSAppOnMac else { return false }
        return true
    }

    private var minimumUpdateInterval: TimeInterval {
        let device = DeviceCapabilityService.shared
        if device.isMac {
            return 1.0
        }

        switch device.tier {
        case .unsupported:
            return 4.0
        case .baseline:
            return 2.5
        case .enhanced:
            return 1.75
        case .advanced:
            return 1.25
        case .ultraAdvanced:
            return 1.0
        }
    }

    private func buildContentState(from items: [IngestionItem]) -> IngestionLiveActivityAttributes.ContentState? {
        guard let currentItem = items.first(where: { !$0.stage.isTerminal }) ?? items.first else {
            return nil
        }

        let device = DeviceCapabilityService.shared
        let activeCount = items.filter { !$0.stage.isTerminal }.count
        let processedCount = items.filter { $0.stage == .complete }.count
        let totalCount = items.count
        let rawProgress = overallProgress(for: items, currentItem: currentItem)
        let quantizedProgress = quantize(rawProgress, step: progressQuantum(for: device))
        let remainingDocuments = items
            .filter { !$0.stage.isTerminal }
            .prefix(3)
            .map { trimmed($0.filename, maxLength: filenameLimit(for: device)) }

        let thermalBucket = IngestionLiveActivityThermalBucket(processInfoState: ProcessInfo.processInfo.thermalState)

        return IngestionLiveActivityAttributes.ContentState(
            progress: quantizedProgress,
            processedCount: processedCount,
            totalCount: totalCount,
            activeCount: activeCount,
            currentFilename: trimmed(currentItem.filename, maxLength: filenameLimit(for: device)),
            currentStage: currentItem.stage.displayName,
            remainingDocuments: remainingDocuments,
            deviceSummary: trimmed(deviceSummary(for: device), maxLength: 32),
            performanceSummary: trimmed(performanceSummary(for: device, thermalBucket: thermalBucket), maxLength: 40),
            presentationProfile: presentationProfile(for: device),
            processingMode: processingMode(for: device),
            thermalBucket: thermalBucket
        )
    }

    private func overallProgress(for items: [IngestionItem], currentItem: IngestionItem) -> Double {
        guard !items.isEmpty else { return 0 }

        let completedCount = items.filter { $0.stage == .complete }.count
        let activeContribution: Double
        if let explicitProgress = currentItem.progress {
            activeContribution = explicitProgress
        } else if let pipelineIndex = currentItem.stage.pipelineIndex {
            activeContribution = Double(pipelineIndex + 1) / Double(max(1, IngestionStage.pipelineStages.count))
        } else {
            activeContribution = currentItem.stage.isTerminal ? 1 : 0
        }

        return min(1, (Double(completedCount) + activeContribution) / Double(items.count))
    }

    private func progressQuantum(for device: DeviceCapabilityService) -> Double {
        if device.isMac {
            return 0.01
        }

        switch device.tier {
        case .unsupported:
            return 0.10
        case .baseline:
            return 0.05
        case .enhanced:
            return 0.03
        case .advanced, .ultraAdvanced:
            return 0.02
        }
    }

    private func filenameLimit(for device: DeviceCapabilityService) -> Int {
        switch presentationProfile(for: device) {
        case .compactPhone:
            return 20
        case .standardPhone:
            return 24
        case .tablet, .desktopCompanion:
            return 32
        }
    }

    private func presentationProfile(for device: DeviceCapabilityService) -> IngestionLiveActivityPresentationProfile {
        if device.isMac {
            return .desktopCompanion
        }

        switch device.formFactor {
        case .iPadMini, .iPadAir, .iPadPro:
            return .tablet
        case .iPhone:
            return device.tier == .baseline ? .compactPhone : .standardPhone
        case .mac:
            return .desktopCompanion
        case .unknown:
            return .compactPhone
        }
    }

    private func processingMode(for device: DeviceCapabilityService) -> IngestionLiveActivityProcessingMode {
        let level = device.activeGPUAccelerationLevel
        if level > 0.7 {
            return .turbo
        }
        if level >= 0.3 {
            return .balanced
        }
        return .eco
    }

    private func deviceSummary(for device: DeviceCapabilityService) -> String {
        switch presentationProfile(for: device) {
        case .compactPhone:
            return device.chipName
        case .standardPhone:
            return "\(device.chipName) • \(device.visionParsingConcurrency)x Vision"
        case .tablet:
            return "\(device.chipName) • \(device.pdfRenderingConcurrency)x Render"
        case .desktopCompanion:
            return "\(device.chipName) • \(device.embeddingConcurrency)x Embed"
        }
    }

    private func performanceSummary(
        for device: DeviceCapabilityService,
        thermalBucket: IngestionLiveActivityThermalBucket
    ) -> String {
        let mode = processingMode(for: device).displayName
        if thermalBucket == .serious || thermalBucket == .critical {
            return "\(mode) • thermal management active"
        }
        return "\(mode) • \(device.gpuConcurrency)x GPU • \(device.ocrExtractionConcurrency)x OCR"
    }

    private func trimmed(_ text: String, maxLength: Int) -> String {
        guard text.count > maxLength else { return text }
        return String(text.prefix(max(1, maxLength - 1))) + "…"
    }

    private func quantize(_ value: Double, step: Double) -> Double {
        guard step > 0 else { return value }
        return min(1, max(0, (value / step).rounded() * step))
    }

    private func sortOrder(for stage: IngestionStage) -> Int {
        switch stage {
        case .queued:
            return 1
        case .complete, .failed:
            return 2
        default:
            return 0
        }
    }
}
#endif

#if !canImport(ActivityKit) || targetEnvironment(macCatalyst)
import Foundation

@MainActor
final class IngestionLiveActivityService {
    static let shared = IngestionLiveActivityService()

    private init() {}

    func restoreExistingActivityIfNeeded() {}
    func sync(items _: [IngestionItem], containerName _: String?) {}
    func endCurrentActivity(finalState _: Any? = nil) {}
    func finish(items _: [IngestionItem], containerName _: String?) {}
}
#endif
