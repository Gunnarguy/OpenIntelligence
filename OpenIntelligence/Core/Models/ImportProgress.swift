//
//  ImportProgress.swift
//  OpenIntelligence
//

import Foundation

/// How far an import has got, worked out in one place for everything that shows it (5.7): the
/// background task the system shows, the Live Activity and "Check Import Status", each given the
/// same list of documents (`RAGService.currentImportItems`). The Live Activity rounds the share to
/// a step that depends on the device.
///
/// Through the first 5.7 builds the background task and the Live Activity each worked it out. The
/// task's version took the document it had just been told about as the one in progress, so a
/// document that had just finished counted twice: with two documents, the end of the first read
/// 100%, and the bar went back to 50% when the second began.
nonisolated enum ImportProgress {
    /// The document the import is on: the first unfinished one that has started, or else the first
    /// one waiting.
    static func current(in items: [IngestionItem]) -> IngestionItem? {
        let pending = items.filter { !$0.stage.isTerminal }
        return pending.first { $0.stage != .queued } ?? pending.first
    }

    /// The share done, from 0 to 1. A document that finished, failed or was stopped counts whole;
    /// the one in progress counts its own progress, or else its stage's place among the stages.
    static func fraction(of items: [IngestionItem]) -> Double {
        guard !items.isEmpty else { return 0 }
        let finished = items.filter { $0.stage.isTerminal }.count
        var inProgress = 0.0
        if let current = current(in: items) {
            if let progress = current.progress {
                inProgress = min(max(progress, 0), 1)
            } else if let index = current.stage.pipelineIndex {
                inProgress = Double(index + 1) / Double(max(1, IngestionStage.pipelineStages.count))
            }
        }
        return min(1, (Double(finished) + inProgress) / Double(items.count))
    }

    /// The share done as a whole percentage, for a sentence, rounded as the Live Activity's own
    /// spoken label rounds it.
    static func percent(of items: [IngestionItem]) -> Int {
        Int((fraction(of: items) * 100).rounded())
    }
}
