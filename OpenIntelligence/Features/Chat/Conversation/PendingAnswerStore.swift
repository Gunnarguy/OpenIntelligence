//
//  PendingAnswerStore.swift
//  OpenIntelligence
//
//  The question being answered, kept on this device so an answer the app lost can be asked again on its own (5.8).
//

import Foundation

/// The question whose answer is running, kept in this device's defaults, never synced: a synced record would have the
/// Mac answer the iPhone's question. On the owner's iPhone on 2026-11-05 a Deep Think answer existed only in memory;
/// iOS ended the app while it waited in the background, and the reopened chat showed the question and "This answer
/// didn't finish." (roadmap row `40f49a74d54f812dbdd8fd628b622299`). The chat now asks it again once, by itself, in the
/// mode it was asked in; a second loss shows Ask again as before.
@MainActor enum PendingAnswerStore {
    nonisolated struct Record: Codable, Equatable, Sendable {
        let messageId: UUID
        let question: String
        let mode: String
        let containerId: UUID?
        let askedAt: Date
        var resumed: Bool
    }

    /// How old a lost question may be and still be asked again by itself.
    nonisolated static let resumeWindow: TimeInterval = 24 * 60 * 60

    private static let key = "pendingAnswer.v1"

    /// Whether a question was asked in this process. A record found before any is from a process that ended with its
    /// answer unsaved; one found after is an answer still running here, which must not be asked twice.
    static private(set) var askedThisLaunch = false

    /// Set just before the chat asks a lost question again, so its record is marked as already asked again once.
    static var resumingNextSend = false

    static func record(messageId: UUID, question: String, mode: RAGQualityMode, containerId: UUID?, now: Date = Date()) {
        askedThisLaunch = true
        let resumed = resumingNextSend
        resumingNextSend = false
        save(
            Record(
                messageId: messageId, question: question, mode: mode.rawValue, containerId: containerId, askedAt: now,
                resumed: resumed))
    }

    static var current: Record? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    static func save(_ record: Record) {
        if let data = try? JSONEncoder().encode(record) { UserDefaults.standard.set(data, forKey: key) }
    }

    /// The record when the chat's last message is its question, unanswered, in the same library and mode, asked within
    /// the window, and not already asked again once. Nil otherwise.
    nonisolated static func resumable(
        _ record: Record?, lastMessageId: UUID?, lastMessageIsQuestion: Bool, containerId: UUID?, mode: RAGQualityMode,
        now: Date = Date()
    ) -> Record? {
        guard let record, !record.resumed, lastMessageIsQuestion, record.messageId == lastMessageId,
            record.containerId == containerId, record.mode == mode.rawValue,
            now.timeIntervalSince(record.askedAt) < resumeWindow
        else { return nil }
        return record
    }
}
