//
//  IngestionLiveActivityStageText.swift
//  OpenIntelligence
//

import Foundation

/// The one line of status an import's Live Activity shows under the file's name, on the Lock
/// Screen and in the Dynamic Island.
///
/// Through 5.6 it was the stage's name. Two cases say more than that from 5.7. A file imported in
/// pieces stays in one stage for the whole import, so the line gives the piece ("Part 12 of 45").
/// And an import the system stopped when background time ran out is not "Queued" in any sense a
/// person would guess: it is waiting for the app to be opened, and the line says that.
enum IngestionLiveActivityStageText {
    static let pausedInBackground = "Paused. Open to continue"

    static func text(for item: IngestionItem) -> String {
        text(stage: item.stage, detail: item.detail)
    }

    static func text(stage: IngestionStage, detail: String) -> String {
        if stage == .queued, detail == IngestionItem.queuedForResumeDetail {
            return pausedInBackground
        }
        // "Part 12 of 45: embedding 960 of 3,850 passages" is the queue's line for a piece.
        if !stage.isTerminal, detail.hasPrefix("Part "), let colon = detail.firstIndex(of: ":") {
            return String(detail[..<colon])
        }
        return stage.displayName
    }
}
