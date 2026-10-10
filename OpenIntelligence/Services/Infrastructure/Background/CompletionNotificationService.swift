//
//  CompletionNotificationService.swift
//  OpenIntelligence
//

import Foundation
import SwiftUI
import UserNotifications

#if canImport(UIKit)
    import UIKit
#elseif canImport(AppKit)
    import AppKit
#endif

/// When a finished import or answer earns a notification, and what it says.
///
/// Kept apart from the service so the rule can be tested without the notification centre. A
/// notification never carries the question or a file name: it can be read on a locked screen.
nonisolated enum CompletionNotificationPolicy {
    /// A question answered faster than this is not announced. The person asked it seconds ago and
    /// an answer that quick was not worth leaving the app for.
    static let minimumAnswerDuration: TimeInterval = 20

    enum Event: Equatable, Sendable {
        case importFinished(success: Bool)
        case answerFinished(success: Bool, duration: TimeInterval)
    }

    struct Content: Equatable, Sendable {
        let title: String
        let body: String
        /// Where a tap goes.
        let destination: AppDestination
    }

    /// nil when nothing should be shown: the switch is off, the app is in front, or the answer was
    /// quick.
    static func content(for event: Event, isEnabled: Bool, appIsActive: Bool) -> Content? {
        guard isEnabled, !appIsActive else { return nil }
        switch event {
        case .importFinished(let success):
            return success
                ? Content(
                    title: "Import finished", body: "Your documents are ready to ask about.",
                    destination: .documents)
                : Content(
                    title: "Import stopped",
                    body: "Some documents were not imported. Open OpenIntelligence to see which.",
                    destination: .importQueue)
        case .answerFinished(let success, let duration):
            guard duration >= minimumAnswerDuration else { return nil }
            return success
                ? Content(
                    title: "Your answer is ready", body: "OpenIntelligence finished the question you asked.",
                    destination: .chat)
                : Content(
                    title: "Your question did not finish", body: "Open OpenIntelligence to ask it again.",
                    destination: .chat)
        }
    }
}

/// Posts a local notification when an import or a long answer finishes while the app is not in front.
///
/// Off until the person turns it on in Settings, which is also when the system's permission prompt
/// appears. The app had no notifications of any kind through 5.6.
@MainActor
final class CompletionNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = CompletionNotificationService()

    /// The Settings switch. Read through `UserDefaults`, so `@AppStorage` sees the same value.
    nonisolated static let enabledKey = "notifyWhenFinished"
    private nonisolated static let linkKey = "link"

    private var answerStartedAt: Date?

    /// Call once at launch, so a tapped notification is routed.
    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    var isEnabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    /// Shows the system's permission prompt the first time. Returns whether notifications may be shown.
    func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    /// True when the person has refused notifications for the app in the system's settings.
    func isDeniedBySystem() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    func answerBegan(at date: Date = Date()) {
        answerStartedAt = date
    }

    func answerFinished(success: Bool, at date: Date = Date()) {
        guard let started = answerStartedAt else { return }
        answerStartedAt = nil
        post(.answerFinished(success: success, duration: date.timeIntervalSince(started)))
    }

    func importFinished(success: Bool) {
        post(.importFinished(success: success))
    }

    private func post(_ event: CompletionNotificationPolicy.Event) {
        guard
            let content = CompletionNotificationPolicy.content(
                for: event, isEnabled: isEnabled, appIsActive: Self.appIsActive)
        else { return }

        let notification = UNMutableNotificationContent()
        notification.title = content.title
        notification.body = content.body
        notification.sound = .default
        notification.userInfo = [Self.linkKey: AppLink.url(for: content.destination).absoluteString]
        let request = UNNotificationRequest(
            identifier: "completion-\(UUID().uuidString)", content: notification, trigger: nil)
        Task {
            do {
                try await UNUserNotificationCenter.current().add(request)
            } catch {
                Log.warning("[Notifications] Could not post: \(error.localizedDescription)", category: .initialization)
            }
        }
    }

    private static var appIsActive: Bool {
        #if canImport(UIKit)
            return UIApplication.shared.applicationState == .active
        #elseif canImport(AppKit)
            return NSApplication.shared.isActive
        #else
            return true
        #endif
    }

    // MARK: - UNUserNotificationCenterDelegate

    // `willPresent` is not implemented on purpose. Apple's header for it says a notification is not
    // presented while the app is in the foreground when the delegate does not implement the method,
    // which is the behaviour wanted here: the result is already on screen. (`content(for:)` also
    // posts nothing while the app is active.) Two attempts at implementing it, `async` and with a
    // completion handler, drew "nearly matches optional requirement" from the compiler, so neither
    // would have been called.

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let link = response.notification.request.content.userInfo[Self.linkKey] as? String,
            let url = URL(string: link), let destination = AppLink.destination(for: url)
        {
            Task { @MainActor in AppNavigationRequest.post(destination) }
        }
        completionHandler()
    }
}

/// The Notifications page in Settings: one switch, and what to do when the system has it off.
struct CompletionNotificationSettingsCard: View {
    @AppStorage(CompletionNotificationService.enabledKey) private var isEnabled = false
    @State private var deniedBySystem = false
    @State private var revertingSwitch = false

    var body: some View {
        // Built like the Apple Intelligence card in Settings: the same header, and a row with the
        // same icon column, type sizes and switch as that card's rows.
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.red)
                }
                Text("Notifications")
                    .font(.headline)
                Spacer()
            }
            .padding()

            Divider().padding(.horizontal)

            VStack(spacing: 2) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(.red)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Notify Me When It Finishes")
                            .font(.caption.weight(.medium))
                        Text(
                            "An import, or an answer that took more than "
                                + "\(Int(CompletionNotificationPolicy.minimumAnswerDuration)) seconds, "
                                + "while OpenIntelligence is not in front"
                        )
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    Spacer()
                    // The label is hidden on screen and is what VoiceOver reads for the switch.
                    Toggle("Notify Me When It Finishes", isOn: $isEnabled)
                        .labelsHidden()
                        .tint(.accentColor)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)

                if deniedBySystem {
                    noteRow(
                        icon: "exclamationmark.triangle.fill",
                        color: .orange,
                        text: "Notifications for OpenIntelligence are turned off in the system's Settings. "
                            + "Turn them on there, then turn this on.")
                }

                noteRow(
                    icon: "lock.fill",
                    color: .secondary,
                    text: "A notification never shows your question or a file name")
            }
            .padding(.vertical, 4)
            .onChange(of: isEnabled) { _, newValue in
                // The card turns the switch back off when the system says no. That is not a tap.
                if revertingSwitch {
                    revertingSwitch = false
                    return
                }
                DSHaptics.selection()
                guard newValue else { return }
                Task {
                    let allowed = await CompletionNotificationService.shared.requestPermission()
                    if allowed {
                        deniedBySystem = false
                    } else {
                        revertingSwitch = true
                        isEnabled = false
                        deniedBySystem = await CompletionNotificationService.shared.isDeniedBySystem()
                    }
                }
            }
        }
        .background(DSColors.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task {
            if isEnabled, await CompletionNotificationService.shared.isDeniedBySystem() {
                revertingSwitch = true
                isEnabled = false
                deniedBySystem = true
            }
        }
    }

    /// A line of small print in the card's row grid: the icon column, then the text.
    private func noteRow(icon: String, color: Color, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
                .frame(width: 16)
            Text(text)
                .font(.caption2)
                .foregroundColor(color)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
