//
//  SharedInbox.swift
//  OpenIntelligence
//
//  What the Share Sheet extension hands to the app (5.7).
//

import Foundation

/// A web address or text shared to OpenIntelligence from another app's share sheet, waiting in the app group's
/// `ShareInbox` folder until the app is next in front (5.7).
///
/// The extension (`OpenIntelligenceShare`) runs in a process of its own: it can't reach the app's files, and a share
/// extension can't open its app. So it writes each item here, and the app takes them when it becomes active
/// (`ContentView`, the active case) and adds them the way the Documents screen's Paste button adds a copied address or
/// text (`SharedInboxImport`). An item leaves the inbox only once it has been stored, or after `maxAttempts` tries that
/// failed, and the app then says it wasn't added. This file is compiled into the app and the extension, so it uses
/// Foundation only.
nonisolated enum SharedInbox {
    static let appGroup = "group.Gunndamental.OpenIntelligence"
    /// How many times the app tries to add an item before it says it couldn't and lets it go.
    static let maxAttempts = 3
    private static let claimPrefix = ".taking-"
    /// The extension of a claimed item's file while the app is storing it, so a run the app died in counts a try for
    /// that item and not for the ones waiting behind it.
    private static let tryingExtension = "trying"

    struct Item: Codable, Equatable, Sendable {
        enum Kind: String, Codable, Sendable {
            case link
            case text
        }

        let kind: Kind
        /// The web address, or the text.
        let value: String
        let sharedAt: Date
        /// The tries that failed so far (a page that couldn't be downloaded while offline, say).
        var attempts: Int? = nil
    }

    /// An item taken from the inbox, and the file that holds it while the app works on it.
    struct Claimed: Sendable {
        let item: Item
        let file: URL
    }

    /// What a call takes: the items to store, oldest first, and any item a run the app died in was trying for the last
    /// time, which is let go so the app can say so.
    struct Claim: Sendable {
        var items: [Claimed] = []
        var letGo: [Item] = []
    }

    /// The app group's inbox, or nil when there is no app group: a build whose App ID doesn't carry it, and the Mac,
    /// where the extension isn't built (its `SUPPORTED_PLATFORMS`), as for `WidgetSnapshot.defaultURL`.
    static var defaultFolder: URL? {
        #if os(iOS)
            FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
                .appendingPathComponent("ShareInbox", isDirectory: true)
        #else
            nil
        #endif
    }

    /// Writes each item to a file of its own. The write is atomic, so the app never reads half of one.
    static func save(_ items: [Item], in folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        for item in items {
            let stamp = Int64(item.sharedAt.timeIntervalSince1970 * 1000)
            let file = folder.appendingPathComponent("\(stamp)-\(UUID().uuidString).json")
            try encoder.encode(item).write(to: file, options: .atomic)
        }
    }

    /// Moves every waiting item into a folder of this call's own and returns them, oldest first. Nothing leaves for good
    /// until `finish(_:)` or `putBack(_:into:)`. Items a call left in its folder, because the app ended while it worked,
    /// go back into the inbox first: the one it was storing with that try counted, so an item that ends the app each
    /// time is let go after `maxAttempts`, and the ones waiting behind it as they were. The app takes items one call at
    /// a time (`SharedInboxImport`), so no other call's folder is in use then. A file that can't be read is removed: it
    /// won't become readable later.
    static func claimAll(from folder: URL) -> Claim {
        let fileManager = FileManager.default
        var claim = Claim()
        let entries = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for stale in entries where stale.lastPathComponent.hasPrefix(claimPrefix) {
            for file in (try? fileManager.contentsOfDirectory(at: stale, includingPropertiesForKeys: nil)) ?? [] {
                guard let item = read(file) else {
                    try? fileManager.removeItem(at: file)
                    continue
                }
                if file.pathExtension == tryingExtension {
                    if !putBack(Claimed(item: item, file: file), into: folder) { claim.letGo.append(item) }
                } else {
                    try? fileManager.moveItem(at: file, to: folder.appendingPathComponent(file.lastPathComponent))
                }
            }
            removeIfEmpty(stale)
        }

        let files =
            (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "json" } ?? []
        guard !files.isEmpty else { return claim }
        let mine = folder.appendingPathComponent(claimPrefix + UUID().uuidString, isDirectory: true)
        guard (try? fileManager.createDirectory(at: mine, withIntermediateDirectories: true)) != nil else {
            return claim
        }

        for file in files {
            let claimed = mine.appendingPathComponent(file.lastPathComponent)
            guard (try? fileManager.moveItem(at: file, to: claimed)) != nil else { continue }
            if let item = read(claimed) {
                claim.items.append(Claimed(item: item, file: claimed))
            } else {
                try? fileManager.removeItem(at: claimed)
            }
        }
        // The saved time is kept to the second; the file name starts with the millisecond, so it orders items shared in
        // the same second.
        claim.items.sort {
            ($0.item.sharedAt, $0.file.lastPathComponent) < ($1.item.sharedAt, $1.file.lastPathComponent)
        }
        removeIfEmpty(mine)
        return claim
    }

    /// Marks the item as the one being stored now, and returns it with its file's new address.
    static func beginTrying(_ claimed: Claimed) -> Claimed {
        let trying = claimed.file.appendingPathExtension(tryingExtension)
        guard (try? FileManager.default.moveItem(at: claimed.file, to: trying)) != nil else { return claimed }
        return Claimed(item: claimed.item, file: trying)
    }

    /// The item was stored: it leaves the inbox.
    static func finish(_ claimed: Claimed) {
        remove(claimed.file)
    }

    /// The item couldn't be stored. It goes back into the inbox with one more try counted, and true is returned, unless
    /// it has had `maxAttempts`; then it leaves and false is returned. When the counted copy can't be written, the item
    /// goes back as it was, so it is never lost on the way.
    @discardableResult
    static func putBack(_ claimed: Claimed, into folder: URL) -> Bool {
        var item = claimed.item
        item.attempts = (item.attempts ?? 0) + 1
        guard (item.attempts ?? 0) < maxAttempts else {
            remove(claimed.file)
            return false
        }
        let name =
            claimed.file.pathExtension == tryingExtension
            ? claimed.file.deletingPathExtension().lastPathComponent : claimed.file.lastPathComponent
        let destination = folder.appendingPathComponent(name)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(item), (try? data.write(to: destination, options: .atomic)) != nil {
            remove(claimed.file)
        } else if (try? FileManager.default.moveItem(at: claimed.file, to: destination)) != nil {
            remove(claimed.file)
        }
        return true
    }

    /// Whether anything is waiting, or was left half taken, without taking it.
    static func hasItems(in folder: URL) -> Bool {
        let fileManager = FileManager.default
        let names = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.contains { name in
            name.hasSuffix(".json")
                || (name.hasPrefix(claimPrefix)
                    && !((try? fileManager.contentsOfDirectory(atPath: folder.appendingPathComponent(name).path)) ?? [])
                        .isEmpty)
        }
    }

    private static func read(_ file: URL) -> Item? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? decoder.decode(Item.self, from: data)
    }

    /// Removes a claimed file, and its call's folder once that is empty.
    private static func remove(_ file: URL) {
        try? FileManager.default.removeItem(at: file)
        let claim = file.deletingLastPathComponent()
        if claim.lastPathComponent.hasPrefix(claimPrefix) { removeIfEmpty(claim) }
    }

    private static func removeIfEmpty(_ folder: URL) {
        if ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}
