//
//  PendingDocumentRemoval.swift
//  OpenIntelligence
//
//  A deletion made in the app can be undone for a few seconds (5.7). Through 5.6 a delete removed the
//  document's passages, text, Spotlight entries and file at once, and nothing could bring them back.
//

import Foundation

/// Documents deleted in the app and waiting out the seconds in which the deletion can be undone (5.7).
///
/// `RAGService.scheduleRemoval` takes the documents out of the list at once, so they leave the library on screen,
/// the app's searches (`RAGService.passagesFromKnownDocuments`) and the documents Shortcuts and Siri list
/// (`OIDocumentEntityQuery`), and removes them for good (`RAGService.removeDocument`) when the window ends, when
/// the app goes to the background, or, if the app ended first, at its next launch. Until then their passages,
/// text, Spotlight entries and file are untouched, so `RAGService.undoRemoval` puts them back as they were;
/// Spotlight still finds them in those seconds.
nonisolated struct PendingDocumentRemoval: Identifiable, Equatable, Sendable {
    let id: UUID
    /// The documents, in the order they had in the list.
    let documents: [Document]
    /// Where each document was in the list, so an undo puts it back there.
    let positions: [Int]
    /// When the removal runs.
    let deadline: Date

    /// How long a deletion can be undone.
    static let undoWindow: Duration = .seconds(6)

    /// What the Undo bar says.
    var summary: String {
        documents.count == 1 ? "Deleted “\(documents[0].filename)”" : "Deleted \(documents.count) documents"
    }
}

/// What `RAGService` keeps for a pending removal besides its record: the timer that runs it, what runs before
/// it, and the undo manager it is registered with, so the entry there goes when the removal runs.
@MainActor
final class PendingDocumentRemovalWork {
    /// What the undo manager's entry is registered against: one per removal.
    final class UndoTarget {}

    var timer: Task<Void, Never>?
    let beforeRemoving: (@MainActor (Document) async -> Void)?
    weak var undoManager: UndoManager?
    let undoTarget = UndoTarget()

    init(beforeRemoving: (@MainActor (Document) async -> Void)?, undoManager: UndoManager?) {
        self.beforeRemoving = beforeRemoving
        self.undoManager = undoManager
    }
}

/// The documents whose removal is scheduled and has not run, kept on disk by run of the app (5.7). A removal
/// the app did not live to run, because it was closed or ended in those seconds, still runs at the next
/// launch: its deletion was asked for and never undone. The file stays on this device; iCloud Sync copies
/// named files only.
nonisolated enum PendingDocumentRemovalLedger {
    /// This run of the app. Ids recorded under another run are removals no one is waiting on.
    static let thisRun = UUID().uuidString

    static var defaultURL: URL {
        AppSupportPaths.baseDir().appendingPathComponent("pending_document_removals.json")
    }

    /// Every id the file holds, of this run and of earlier ones.
    static func allIds(at url: URL = defaultURL) -> Set<UUID> {
        Set(read(url).values.flatMap { $0 }.compactMap(UUID.init(uuidString:)))
    }

    /// The ids earlier runs recorded and did not remove.
    static func earlierRunIds(at url: URL = defaultURL) -> Set<UUID> {
        Set(read(url).filter { $0.key != thisRun }.values.flatMap { $0 }.compactMap(UUID.init(uuidString:)))
    }

    /// Records these ids under this run. A write that fails leaves them out, so the next launch does not remove
    /// them: a document survives, which an undo can't fix, rather than one being removed that was put back.
    static func add(_ ids: Set<UUID>, at url: URL = defaultURL) {
        var runs = read(url)
        runs[thisRun] = Array(Set(runs[thisRun] ?? []).union(ids.map(\.uuidString))).sorted()
        _ = write(runs, to: url)
    }

    /// Forgets these ids under every run. When the file cannot be written, as on a full disk, it is deleted:
    /// an id left in it would hide a document that was put back, and the next launch would remove it.
    static func remove(
        _ ids: Set<UUID>, at url: URL = defaultURL,
        writer: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) {
        let gone = Set(ids.map(\.uuidString))
        let runs = read(url).mapValues { $0.filter { !gone.contains($0) } }.filter { !$0.value.isEmpty }
        if !write(runs, to: url, writer: writer) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private static func read(_ url: URL) -> [String: [String]] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: [String]].self, from: data)) ?? [:]
    }

    /// Writes the file, or deletes it when nothing is left. False when the write failed.
    private static func write(
        _ runs: [String: [String]], to url: URL,
        writer: (Data, URL) throws -> Void = { try $0.write(to: $1, options: .atomic) }
    ) -> Bool {
        if runs.isEmpty {
            try? FileManager.default.removeItem(at: url)
            return true
        }
        guard let data = try? JSONEncoder().encode(runs) else { return false }
        do {
            try writer(data, url)
            return true
        } catch {
            return false
        }
    }
}
