import Foundation

@MainActor
final class QueryRuntimeBridge {
    typealias ContinuedQueryRun = @MainActor () async -> Bool
    typealias ContinuedQueryExpiration = @MainActor () -> Void
    typealias ConfigureContinuedQueryHandler = (
        _ run: @escaping ContinuedQueryRun,
        _ expiration: @escaping ContinuedQueryExpiration
    ) -> Void
    typealias BeginUserInitiatedQueryHandler = (_ title: String, _ subtitle: String) -> Void
    typealias UpdateProgressHandler = (_ title: String, _ subtitle: String, _ fraction: Double) -> Void
    typealias CompleteUserInitiatedQueryHandler = (_ success: Bool) -> Void
    typealias BeginForegroundFallbackHandler = (_ reason: String) -> Void
    typealias VoidHandler = () -> Void

    static let shared = QueryRuntimeBridge()

    var configureContinuedQueryHandler: ConfigureContinuedQueryHandler?
    var beginUserInitiatedQueryHandler: BeginUserInitiatedQueryHandler?
    var updateContinuedQueryProgressHandler: UpdateProgressHandler?
    var completeUserInitiatedQueryHandler: CompleteUserInitiatedQueryHandler?
    var beginForegroundFallbackQueryHandler: BeginForegroundFallbackHandler?
    var endForegroundFallbackQueryHandler: VoidHandler?

    private init() {}

    func configureContinuedQuery(
        run: @escaping ContinuedQueryRun,
        expiration: @escaping ContinuedQueryExpiration
    ) {
        configureContinuedQueryHandler?(run, expiration)
    }

    func beginUserInitiatedQuery(title: String, subtitle: String) {
        beginUserInitiatedQueryHandler?(title, subtitle)
    }

    func updateContinuedQueryProgress(title: String, subtitle: String, fraction: Double) {
        updateContinuedQueryProgressHandler?(title, subtitle, fraction)
    }

    func completeUserInitiatedQuery(success: Bool) {
        completeUserInitiatedQueryHandler?(success)
    }

    func beginForegroundFallbackQueryExtensionIfNeeded(reason: String) {
        beginForegroundFallbackQueryHandler?(reason)
    }

    func endForegroundFallbackQueryExtension() {
        endForegroundFallbackQueryHandler?()
    }
}
