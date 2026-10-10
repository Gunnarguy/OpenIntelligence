//
//  QuickActions.swift
//  OpenIntelligence
//

#if os(iOS)
    import UIKit

    /// The Home Screen quick actions: touch and hold the app's icon.
    ///
    /// Through 5.6 the icon offered only what the system adds. Each action posts a destination to
    /// `AppNavigationRequest`, the queue links and Shortcuts actions use.
    enum QuickAction: String, CaseIterable {
        case ask = "com.openintelligence.quick.ask"
        case addDocument = "com.openintelligence.quick.add-document"
        case scan = "com.openintelligence.quick.scan"

        var title: String {
            switch self {
            case .ask: return "Ask"
            case .addDocument: return "Add Document"
            case .scan: return "Scan Document"
            }
        }

        var symbol: String {
            switch self {
            case .ask: return "text.bubble"
            case .addDocument: return "doc.badge.plus"
            case .scan: return "camera.viewfinder"
            }
        }

        var destination: AppDestination {
            switch self {
            case .ask: return .chat
            case .addDocument: return .addDocument
            case .scan: return .scanDocument
            }
        }

        var item: UIApplicationShortcutItem {
            UIApplicationShortcutItem(
                type: rawValue,
                localizedTitle: title,
                localizedSubtitle: nil,
                icon: UIApplicationShortcutIcon(systemImageName: symbol)
            )
        }

        /// Sets the actions. They are set in code, so `Info.plist` does not list them.
        @MainActor
        static func install() {
            UIApplication.shared.shortcutItems = allCases.map(\.item)
        }

        /// Posts the destination for a quick action. Returns false for an item that is not ours.
        @MainActor
        @discardableResult
        static func handle(_ item: UIApplicationShortcutItem) -> Bool {
            guard let action = QuickAction(rawValue: item.type) else { return false }
            AppNavigationRequest.post(action.destination)
            return true
        }
    }

    /// Receives the quick action the app was launched with. SwiftUI has no API for it, so the app
    /// has a delegate for this and nothing else.
    final class OpenIntelligenceAppDelegate: NSObject, UIApplicationDelegate {
        func application(
            _ application: UIApplication,
            didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
        ) -> Bool {
            QuickAction.install()
            return true
        }

        func application(
            _ application: UIApplication,
            configurationForConnecting connectingSceneSession: UISceneSession,
            options: UIScene.ConnectionOptions
        ) -> UISceneConfiguration {
            if let item = options.shortcutItem {
                QuickAction.handle(item)
            }
            let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
            configuration.delegateClass = OpenIntelligenceSceneDelegate.self
            return configuration
        }
    }

    /// Receives a quick action chosen while the app is already running.
    final class OpenIntelligenceSceneDelegate: NSObject, UIWindowSceneDelegate {
        func windowScene(
            _ windowScene: UIWindowScene,
            performActionFor shortcutItem: UIApplicationShortcutItem,
            completionHandler: @escaping (Bool) -> Void
        ) {
            completionHandler(QuickAction.handle(shortcutItem))
        }
    }
#endif
