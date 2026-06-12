import Foundation

@MainActor
final class IngestionRuntimeBridge {
    typealias ContinuedIngestionRun = @MainActor () async -> Bool
    typealias ContinuedIngestionExpiration = @MainActor () -> Void
    typealias ConfigureContinuedIngestionHandler = (
        _ run: @escaping ContinuedIngestionRun,
        _ expiration: @escaping ContinuedIngestionExpiration
    ) -> Void
    typealias BeginUserInitiatedIngestionHandler = (_ title: String, _ subtitle: String) -> Void
    typealias UpdateProgressHandler = (_ title: String, _ subtitle: String, _ fraction: Double) -> Void
    typealias CompleteUserInitiatedIngestionHandler = (_ success: Bool) -> Void
    typealias LiveActivityItemsHandler = (_ items: [IngestionItem], _ containerName: String?) -> Void
    typealias IngestionFallbackHandler = (_ reason: String) -> Void
    typealias VoidHandler = () -> Void

    static let shared = IngestionRuntimeBridge()

    var configureContinuedIngestionHandler: ConfigureContinuedIngestionHandler?
    var beginUserInitiatedIngestionHandler: BeginUserInitiatedIngestionHandler?
    var updateContinuedIngestionProgressHandler: UpdateProgressHandler?
    var completeUserInitiatedIngestionHandler: CompleteUserInitiatedIngestionHandler?
    var beginForegroundFallbackIngestionHandler: IngestionFallbackHandler?
    var endForegroundFallbackIngestionHandler: VoidHandler?
    var restoreLiveActivityHandler: VoidHandler?
    var syncLiveActivityHandler: LiveActivityItemsHandler?
    var finishLiveActivityHandler: LiveActivityItemsHandler?
    var endLiveActivityHandler: VoidHandler?

    private init() {}

    func configureContinuedIngestion(
        run: @escaping ContinuedIngestionRun,
        defaultValue: Bool = false, // unused, keep matching signature if any
        expiration: @escaping ContinuedIngestionExpiration
    ) {
        configureContinuedIngestionHandler?(run, expiration)
    }

    func beginUserInitiatedIngestion(title: String, subtitle: String) {
        beginUserInitiatedIngestionHandler?(title, subtitle)
    }

    func updateContinuedIngestionProgress(title: String, subtitle: String, fraction: Double) {
        updateContinuedIngestionProgressHandler?(title, subtitle, fraction)
    }

    func completeUserInitiatedIngestion(success: Bool) {
        completeUserInitiatedIngestionHandler?(success)
    }

    func beginForegroundFallbackIngestion(reason: String) {
        beginForegroundFallbackIngestionHandler?(reason)
    }

    func endForegroundFallbackIngestion() {
        endForegroundFallbackIngestionHandler?()
    }

    func restoreLiveActivityIfNeeded() {
        restoreLiveActivityHandler?()
    }

    func syncLiveActivity(items: [IngestionItem], containerName: String?) {
        syncLiveActivityHandler?(items, containerName)
    }

    func finishLiveActivity(items: [IngestionItem], containerName: String?) {
        finishLiveActivityHandler?(items, containerName)
    }

    func endLiveActivity() {
        endLiveActivityHandler?()
    }
}
