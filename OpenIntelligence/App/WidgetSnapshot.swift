//
//  WidgetSnapshot.swift
//  OpenIntelligence
//
//  What the "Your Library" widget shows, written by the app for the widget extension to read (5.7).
//

import Foundation

#if canImport(WidgetKit)
    import WidgetKit
#endif

/// What the "Your Library" widget shows (5.7): the open library and its document count, and the last question in that
/// library with the start of its answer. The app writes it to the app group's container and the widget extension reads
/// it (`LibraryWidgetSnapshot` in `OpenIntelligenceLiveActivities/IngestionLiveActivityWidget.swift` decodes the fields
/// it shows). Without the app group, as in a build whose App ID doesn't carry it yet, there is no container: nothing is
/// written, and the widget asks to open the app.
///
/// The answer belongs to its library and its conversation. Opening another library drops it, and an answer from a
/// library that isn't open is not written. Clearing or deleting the conversation drops it (`ChatScreen.clearChat`,
/// `ThreadSidebarView`), so does hiding the answer (`MessageBubbleV2`), and so does sync removing the conversation
/// after it was deleted on another device (`ContentView`, `forgetAnswer(unlessConversationExists:)`). Only an answer
/// counts: an error or a notice in the chat is not written.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    var libraryId: UUID?
    var libraryName: String
    var documentCount: Int
    var question: String?
    var answerPreview: String?
    var answeredAt: Date?
    /// The conversation and the message the answer came from, so a deleted conversation or a hidden answer can take
    /// it off the widget.
    var threadId: UUID?
    var messageId: UUID?

    static let appGroup = "group.Gunndamental.OpenIntelligence"
    static let fileName = "widget_snapshot.json"
    static let widgetKind = "com.openintelligence.widget.library"

    /// The file in the app group's container, or nil when the build has no app group. Nil on the Mac too: the widget
    /// extension is built for iOS only (its `SUPPORTED_PLATFORMS`), so nothing there would read the file.
    static var defaultURL: URL? {
        #if os(iOS)
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
                .appendingPathComponent(fileName)
        #else
            nil
        #endif
    }

    static func read(from url: URL?) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Writes the snapshot when it differs from the one on disk and asks WidgetKit to redraw the widget. Returns
    /// whether it wrote.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot, to url: URL?) -> Bool {
        guard let url, read(from: url) != snapshot else { return false }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot), (try? data.write(to: url, options: .atomic)) != nil else {
            return false
        }
        #if canImport(WidgetKit)
            WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
        #endif
        return true
    }

    /// Sets the open library and its document count. Opening another library drops the last answer.
    static func recordLibrary(id: UUID, name: String, documentCount: Int, at url: URL? = defaultURL) {
        guard let url else { return }
        var snapshot = read(from: url) ?? WidgetSnapshot(libraryId: id, libraryName: name, documentCount: documentCount)
        if snapshot.libraryId != id { snapshot.dropAnswer() }
        snapshot.libraryId = id
        snapshot.libraryName = name
        snapshot.documentCount = documentCount
        write(snapshot, to: url)
    }

    /// Sets the last question and the opening of its answer, when the answer is from the open library.
    static func recordAnswer(
        question: String?, answer: String, libraryId: UUID, threadId: UUID? = nil, messageId: UUID? = nil,
        at url: URL? = defaultURL, now: Date = Date()
    ) {
        guard var snapshot = read(from: url), snapshot.libraryId == libraryId else { return }
        snapshot.question = question.map { preview(of: $0, limit: 90) }
        snapshot.answerPreview = preview(of: answer)
        snapshot.answeredAt = now
        snapshot.threadId = threadId
        snapshot.messageId = messageId
        write(snapshot, to: url)
    }

    /// Drops the last question and answer when they're from this library, as when its conversation is cleared or
    /// deleted.
    static func forgetAnswer(inLibrary libraryId: UUID, at url: URL? = defaultURL) {
        guard var snapshot = read(from: url), snapshot.libraryId == libraryId else { return }
        snapshot.dropAnswer()
        write(snapshot, to: url)
    }

    /// Drops the last question and answer when they're this message, as when the person hides it.
    static func forgetAnswer(messageId: UUID, at url: URL? = defaultURL) {
        guard var snapshot = read(from: url), snapshot.messageId == messageId else { return }
        snapshot.dropAnswer()
        write(snapshot, to: url)
    }

    /// Drops the last question and answer when the conversation they came from no longer exists, as when sync removed
    /// it after it was deleted on another device. `exists` gets the conversation's id and its library's id.
    static func forgetAnswer(unlessConversationExists exists: (UUID, UUID) -> Bool, at url: URL? = defaultURL) {
        guard var snapshot = read(from: url), snapshot.answerPreview != nil, let threadId = snapshot.threadId,
            let libraryId = snapshot.libraryId, !exists(threadId, libraryId)
        else { return }
        snapshot.dropAnswer()
        write(snapshot, to: url)
    }

    private mutating func dropAnswer() {
        question = nil
        answerPreview = nil
        answeredAt = nil
        threadId = nil
        messageId = nil
    }

    /// An answer's opening as the widget shows it: citation labels, Markdown marks and list bullets taken out, spaces
    /// folded, and cut on a word at `limit` characters.
    static func preview(of text: String, limit: Int = 160) -> String {
        var plain = text.replacingOccurrences(
            of: #"\[(?:S?\d+(?:\s*,\s*S?\d+)*)\]"#, with: "", options: .regularExpression)
        plain = plain.replacingOccurrences(of: #"(^|\s)#{1,6}\s"#, with: "$1", options: .regularExpression)
        // A list item's bullet or number at the start of a line ("- ", "• ", "2. "), which reads as stray punctuation
        // once the lines are joined.
        plain = plain.replacingOccurrences(
            of: #"(?m)^[ \t]*(?:[-•◦▪+*]|\d{1,3}[.)])[ \t]+"#, with: "", options: .regularExpression)
        plain = plain.replacingOccurrences(of: #"[*_`]+"#, with: "", options: .regularExpression)
        plain = plain.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        // A label taken out before punctuation leaves a space there.
        plain = plain.replacingOccurrences(of: #" +([.,;:!?])"#, with: "$1", options: .regularExpression)
        guard plain.count > limit else { return plain }
        let cut = plain.prefix(limit)
        let end = cut.lastIndex(of: " ") ?? cut.endIndex
        return String(cut[..<end]) + "…"
    }
}
