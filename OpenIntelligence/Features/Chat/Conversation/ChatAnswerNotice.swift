//
//  ChatAnswerNotice.swift
//  OpenIntelligence
//
//  Counts answers that finished while the Chat tab was not on screen, for the tab's badge.
//

import Combine
import SwiftUI

/// Counts answers that finished while the Chat tab was not on screen.
///
/// An answer keeps running when the person switches tab (`b87123d`, 5.0.1), but nothing said when
/// it finished: the only answer haptic fired as generation started, and the Chat tab looked the
/// same before and after. `ChatScreen` counts a finished answer here when it is not showing and
/// clears the count when it appears; `ContentView` badges the Chat tab with the count.
@MainActor
final class ChatAnswerNotice: ObservableObject {
    static let shared = ChatAnswerNotice()

    @Published private(set) var unseenAnswers = 0

    /// An answer finished, or stopped with something to read, while Chat was off screen.
    func answerFinishedOffScreen() {
        unseenAnswers += 1
        // Observed 2026-09-23: the badge showed on the iOS 27 simulator's tab bar and did not on
        // macOS, where the tabs sit in the toolbar. This line tells a Mac trace whether the count
        // moved, which separates "not counted" from "counted but not drawn".
        Log.info("[ChatAnswerNotice] Answer finished off screen; unseen=\(unseenAnswers)", category: .ui)
    }

    /// Chat is on screen, so every finished answer has been seen.
    func chatAppeared() {
        guard unseenAnswers != 0 else { return }
        unseenAnswers = 0
    }
}
