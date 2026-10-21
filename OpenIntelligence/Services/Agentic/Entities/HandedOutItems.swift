//
//  HandedOutItems.swift
//  OpenIntelligence
//
//  The answers and passages actions hand to Shortcuts, kept on this device for a day so the system
//  can look each one up by its id (5.7).
//

import Foundation

/// Answers and passages an action has handed out, by the id their items carry.
///
/// Through the first 5.7 builds an answer or a passage was handed out whole (`TransientAppEntity`), and
/// Shortcuts could not pass it to the next action: Copy to Clipboard's runner stopped on an assertion
/// ("All serialized item keys must have the prefix link.contentkit.", in
/// `-[WFContentItem additionalRepresentationsForSerialization]`) and the shortcut failed with "There was
/// a problem running the shortcut". A document, which the system passes by its id and looks up again,
/// went through the same step. Measured in the iOS 27.0 Simulator on 2026-10-20: Ask My Documents and
/// Find Passages followed by Copy to Clipboard failed, List Documents followed by it ran. So answers and
/// passages are looked up by id too, from this file.
///
/// The file is in the local cache folder, never in the iCloud workspace. It holds what was handed out in
/// the last day: at most `maxAnswers` answers with their passages, and `maxLoosePassages` passages that
/// belong to no kept answer (Find Passages'). An item older than a day is removed from the file whenever
/// it is read or written and each time the app loads its documents (`dropExpired`), and a passage whose
/// document is in no library any more is removed then too, with any answer that used it (`keepOnly`).
nonisolated enum HandedOutItems {
    struct Answer: Codable, Equatable, Sendable {
        let id: UUID
        let question: String
        let text: String
        let sourceList: String
        let mode: String
        let model: String
        let passageIds: [UUID]
        let createdAt: Date
    }

    struct Passage: Codable, Equatable, Sendable {
        let id: UUID
        /// The document the passage came from; nil only for one written without it.
        var documentId: UUID?
        let text: String
        let documentName: String
        let page: Int?
        let section: String?
        let score: Double
        let createdAt: Date
    }

    struct Contents: Codable, Equatable, Sendable {
        var answers: [Answer] = []
        var passages: [Passage] = []
    }

    static let keptFor: TimeInterval = 24 * 60 * 60
    static let maxAnswers = 100
    static let maxLoosePassages = 500

    private static let lock = NSLock()
    /// The file's contents as last read or written by this process, so an action doesn't read the file again.
    nonisolated(unsafe) private static var cached: Contents?

    /// Where the items are kept. Tests point this elsewhere and call `forgetCache()`.
    nonisolated(unsafe) static var fileURL: () -> URL = {
        AppSupportPaths.localCacheDir().appendingPathComponent("handed_out_items.json")
    }

    /// Keeps `answer`, if any, and `passages`, in one write.
    static func record(answer: Answer? = nil, passages: [Passage], now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        var contents = pruned(load(), now: now)
        let newPassageIds = Set(passages.map(\.id))
        contents.passages.removeAll { newPassageIds.contains($0.id) }
        contents.passages.append(contentsOf: passages)
        if let answer {
            contents.answers.removeAll { $0.id == answer.id }
            contents.answers.append(answer)
        }
        save(pruned(contents, now: now))
    }

    static func answers(_ ids: [UUID], now: Date = Date()) -> [Answer] {
        let kept = current(now: now).answers
        return ids.compactMap { id in kept.first { $0.id == id } }
    }

    static func passages(_ ids: [UUID], now: Date = Date()) -> [Passage] {
        let kept = current(now: now).passages
        return ids.compactMap { id in kept.first { $0.id == id } }
    }

    /// The answers handed out most recently, newest first.
    static func recentAnswers(limit: Int, now: Date = Date()) -> [Answer] {
        Array(current(now: now).answers.reversed().prefix(limit))
    }

    /// Removes what is older than a day from the file.
    static func dropExpired(now: Date = Date()) {
        _ = current(now: now)
    }

    /// Removes passages whose document is not in `documents`, and every answer that used one of them.
    static func keepOnly(documents: Set<UUID>, now: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        let contents = load()
        let gone = Set(
            contents.passages.filter { passage in passage.documentId.map { !documents.contains($0) } ?? false }
                .map(\.id))
        var kept = contents
        if !gone.isEmpty {
            kept.answers.removeAll { answer in answer.passageIds.contains { gone.contains($0) } }
            kept.passages.removeAll { gone.contains($0.id) }
        }
        kept = pruned(kept, now: now)
        if kept != contents { save(kept) }
    }

    /// Drops items older than a day, the oldest answers past `maxAnswers`, and the oldest passages that no kept
    /// answer uses past `maxLoosePassages`; a kept answer keeps its passages. Items are appended in the order
    /// they were handed out, so the oldest are at the front.
    static func pruned(_ contents: Contents, now: Date) -> Contents {
        let cutoff = now.addingTimeInterval(-keptFor)
        var kept = contents
        kept.answers.removeAll { $0.createdAt < cutoff }
        if kept.answers.count > maxAnswers { kept.answers.removeFirst(kept.answers.count - maxAnswers) }
        let usedByAnswers = Set(kept.answers.flatMap(\.passageIds))
        kept.passages.removeAll { $0.createdAt < cutoff }
        let loose = kept.passages.filter { !usedByAnswers.contains($0.id) }
        if loose.count > maxLoosePassages {
            let dropped = Set(loose.prefix(loose.count - maxLoosePassages).map(\.id))
            kept.passages.removeAll { dropped.contains($0.id) }
        }
        return kept
    }

    /// Forgets the copy in memory, so the next call reads the file. For tests.
    static func forgetCache() {
        lock.lock()
        defer { lock.unlock() }
        cached = nil
    }

    /// What is kept now, with anything expired removed from the file as well.
    private static func current(now: Date) -> Contents {
        lock.lock()
        defer { lock.unlock() }
        let contents = load()
        let kept = pruned(contents, now: now)
        if kept != contents { save(kept) }
        return kept
    }

    private static func load() -> Contents {
        if let cached { return cached }
        let read: Contents
        if let data = try? Data(contentsOf: fileURL()),
            let decoded = try? JSONDecoder().decode(Contents.self, from: data)
        {
            read = decoded
        } else {
            read = Contents()
        }
        cached = read
        return read
    }

    private static func save(_ contents: Contents) {
        cached = contents
        let url = fileURL()
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(contents).write(to: url, options: .atomic)
        } catch {
            Log.error(
                "[Shortcuts] Could not keep the handed-out items: \(error.localizedDescription)", category: .pipeline)
        }
    }
}
