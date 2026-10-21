//
//  SpotlightIndexService.swift
//  OpenIntelligence
//
//  CoreSpotlight integration — indexes ingested documents and containers
//  for Spotlight, Siri, and system-wide search discoverability.
//

import AppIntents
@preconcurrency import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

// MARK: - Spotlight Index Service

/// Indexes documents and containers into CoreSpotlight for system-wide search.
/// Documents become searchable from Spotlight, Siri, and Shortcuts.
@MainActor
final class SpotlightIndexService {

    // MARK: - Singleton

    static let shared = SpotlightIndexService()

    private let searchableIndex = CSSearchableIndex.default()
    private let domainIdentifier = "com.openintelligence.documents"

    private init() {}

    /// The Settings switch "Spotlight Indexing", on until the person turns it off.
    nonisolated static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "enableSpotlightIndexing") as? Bool ?? true
    }

    // MARK: - The Settings switch

    /// The last change of the switch, so an off and an on made quickly run in that order.
    private var switchChange: Task<Void, Never>?

    /// Turning "Spotlight Indexing" off removes every entry the app made, the document pages it
    /// offered to Spotlight and the libraries it suggested to Siri (5.7). Through 5.6 turning it
    /// off only stopped new entries: the ones made stayed searchable until they expired, and from
    /// 5.7 entries do not expire. Turning it on again lists every library and document, each
    /// document with its first lines, from what the app keeps; a document's passages are listed
    /// when it is imported again.
    func indexingSwitched(on isOn: Bool) {
        let previous = switchChange
        switchChange = Task {
            await previous?.value
            if isOn {
                await indexFromStoredRecords(documentIds: nil, libraryIds: nil, asUpdate: false)
                return
            }
            for writing in passageIndexing.values { writing.task.cancel() }
            do {
                try await searchableIndex.deleteAllSearchableItems()
                Log.info("[Spotlight] Indexing turned off: every entry removed", category: .initialization)
            } catch {
                Log.error(
                    "[Spotlight] Indexing turned off, and the entries could not be removed: \(error.localizedDescription)",
                    category: .initialization)
            }
            await NSUserActivity.deleteAllSavedUserActivities()
            _ = try? await IntentDonationManager.shared.deleteDonations(matching: .intentType(OpenLibraryIntent.self))
        }
    }

    // MARK: - Container Indexing

    /// Index a container (library) for Spotlight search
    func indexContainer(_ container: KnowledgeContainer) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .folder)
        attributeSet.title = container.name
        attributeSet.contentDescription = container.description ?? "Knowledge library with \(container.totalDocuments) documents"
        attributeSet.keywords = ["library", "knowledge base", "documents", container.name.lowercased()]
        attributeSet.thumbnailData = nil // Could generate from container icon
        attributeSet.containerTitle = "OpenIntelligence"
        attributeSet.containerDisplayName = "Libraries"

        let item = CSSearchableItem(
            uniqueIdentifier: "container-\(container.id.uuidString)",
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
        // Containers don't expire
        item.expirationDate = .distantFuture
        // The library's app item, so Siri can use the result and its Open action opens it (5.7).
        item.associateAppEntity(OILibraryEntityQuery.entity(for: container))

        HardwareTelemetryState.shared.pulse(.dataDecoding, intensity: 0.5, duration: 0.2)
        searchableIndex.indexSearchableItems([item]) { error in
            if let error = error {
                Log.error("[Spotlight] Failed to index container '\(container.name)': \(error.localizedDescription)", category: .initialization)
            } else {
                Log.debug("[Spotlight] Indexed container '\(container.name)'", category: .initialization)
                Task { @MainActor in DSHaptics.soft() }
            }
        }
    }

    /// Remove a container from Spotlight index
    func deindexContainer(id: UUID) {
        searchableIndex.deleteSearchableItems(withIdentifiers: ["container-\(id.uuidString)"]) { error in
            if let error = error {
                Log.error("[Spotlight] Failed to deindex container \(id): \(error.localizedDescription)", category: .initialization)
            }
        }
    }

    // MARK: - Document Indexing

    /// Index an ingested document for Spotlight search
    /// - Parameters:
    ///   - document: The ingested document metadata
    ///   - containerId: The container this document belongs to
    ///   - textPreview: First ~500 chars of document text for Spotlight preview
    func indexDocument(
        id: UUID,
        filename: String,
        containerId: UUID,
        containerName: String,
        textPreview: String,
        pageCount: Int? = nil,
        chunkCount: Int? = nil,
        fileSize: Int64? = nil,
        keywords: [String]? = nil,
        contentType: UTType = .plainText
    ) {
        let attributeSet = CSSearchableItemAttributeSet(contentType: contentType)
        attributeSet.title = filename
        attributeSet.contentDescription = String(textPreview.prefix(500))
        attributeSet.containerTitle = containerName
        attributeSet.containerDisplayName = "OpenIntelligence"

        // Rich metadata
        if let pageCount = pageCount {
            attributeSet.pageCount = pageCount as NSNumber
        }
        if let chunkCount = chunkCount {
            attributeSet.keywords = (keywords ?? []) + ["chunks: \(chunkCount)"]
        } else {
            attributeSet.keywords = keywords
        }

        // Document-specific attributes
        attributeSet.metadataModificationDate = Date()
        attributeSet.addedDate = Date()
        attributeSet.kind = "Ingested Document"

        let item = CSSearchableItem(
            uniqueIdentifier: "document-\(id.uuidString)",
            domainIdentifier: "\(domainIdentifier).\(containerId.uuidString)",
            attributeSet: attributeSet
        )
        // Through 5.6 a document's entry expired after 30 days and nothing indexed it again, so a
        // document imported a month ago could not be found from Spotlight. It stays until the
        // document is deleted (5.7), and it is the document's app item, whose Open action opens
        // the document's page.
        item.expirationDate = .distantFuture
        item.associateAppEntity(
            OIDocumentEntity(
                id: id, filename: filename, totalChunks: chunkCount ?? 0, pageCount: pageCount,
                libraryName: containerName))

        searchableIndex.indexSearchableItems([item]) { error in
            if let error = error {
                Log.error("[Spotlight] Failed to index document '\(filename)': \(error.localizedDescription)", category: .ingestion)
            } else {
                Log.debug("[Spotlight] Indexed document '\(filename)' in container '\(containerName)'", category: .ingestion)
            }
        }
        // Listed now, so an import that never finishes is removed at the next load, and kept
        // apart until its record is written, so a load during the import leaves it alone.
        importing.insert(id)
        updateKnownDocuments { $0[id] = containerId }
    }

    /// Remove a document from Spotlight index, with its passages when its library is known.
    ///
    /// Through 5.6 only the document's own entry was removed; its passages, in the domain
    /// `<root>.<library>.<document>`, stayed searchable until they expired. The domain delete is
    /// recursive (Apple's `deleteSearchableItems(withDomainIdentifiers:)`).
    func deindexDocument(id: UUID, containerId: UUID? = nil) {
        // Passages still being written are removed once they are (`indexDocumentChunks`).
        passageIndexing[id]?.task.cancel()
        importing.remove(id)
        let library = containerId ?? (knownDocuments ?? Self.readKnownDocuments())?[id]
        updateKnownDocuments { $0[id] = nil }
        searchableIndex.deleteSearchableItems(withIdentifiers: ["document-\(id.uuidString)"]) { error in
            if let error = error {
                Log.error("[Spotlight] Failed to deindex document \(id): \(error.localizedDescription)", category: .ingestion)
            }
        }
        guard let library else { return }
        searchableIndex.deleteSearchableItems(
            withDomainIdentifiers: ["\(domainIdentifier).\(library.uuidString).\(id.uuidString)"]
        ) { error in
            if let error = error {
                Log.error("[Spotlight] Failed to deindex the passages of \(id): \(error.localizedDescription)", category: .ingestion)
            }
        }
    }

    /// Remove all documents in a container from Spotlight index
    func deindexAllDocuments(in containerId: UUID) {
        for writing in passageIndexing.values where writing.library == containerId { writing.task.cancel() }
        updateKnownDocuments { known in known = known.filter { $0.value != containerId } }
        searchableIndex.deleteSearchableItems(withDomainIdentifiers: ["\(domainIdentifier).\(containerId.uuidString)"]) { error in
            if let error = error {
                Log.error("[Spotlight] Failed to deindex documents in container \(containerId): \(error.localizedDescription)", category: .ingestion)
            }
        }
    }

    // MARK: - Batch Operations

    /// Indexes every library and document again from the records the app keeps on disk, so it
    /// needs no screen and no engine: the background re-index task, the first launch of 5.7, and
    /// Spotlight itself on iOS and macOS 27 when it finds a problem with the app's index
    /// (`IndexedEntityQuery`).
    ///
    /// Through 5.6 `reindexAll` had no caller, and the background task only set a flag nothing
    /// read. Passages are not indexed again here: a document's are listed when it is imported.
    ///
    /// `asUpdate` marks each entry as an update (`CSSearchableItem.isUpdate`): the system changes
    /// an entry that exists, keeps the attributes this does not set, the text preview among them,
    /// and drops an entry that does not exist (CSSearchableItem.h, read 2026-10-14). The background
    /// task refreshes that way, for names that changed. Otherwise each entry is written whole, and
    /// a document's text preview, the first 500 characters its import listed, is read again from
    /// the full-text store.
    func reindexFromStoredRecords(
        documentIds: Set<UUID>? = nil, libraryIds: Set<UUID>? = nil, asUpdate: Bool = false
    ) async {
        guard Self.isEnabled else {
            Log.info("[Spotlight] Re-index skipped: Spotlight indexing is off", category: .initialization)
            return
        }
        await indexFromStoredRecords(documentIds: documentIds, libraryIds: libraryIds, asUpdate: asUpdate)
    }

    private func indexFromStoredRecords(documentIds: Set<UUID>?, libraryIds: Set<UUID>?, asUpdate: Bool) async {
        let entries = Self.itemsFromStoredRecords(
            domain: domainIdentifier, documentIds: documentIds, libraryIds: libraryIds)
        if !asUpdate {
            for (item, document) in entries where document != nil {
                guard let document, document.totalChunks <= Self.largestDocumentForAPreview else { continue }
                if let preview = await Self.textPreview(of: document.id) {
                    item.attributeSet.contentDescription = preview
                }
            }
        }
        let items = entries.map { $0.item }
        items.forEach { $0.isUpdate = asUpdate }
        for batch in stride(from: 0, to: items.count, by: 200) {
            // Turned off while this ran: the switch's own removal covers what was written.
            guard Self.isEnabled else { return }
            let slice = Array(items[batch..<min(batch + 200, items.count)])
            do {
                try await searchableIndex.indexSearchableItems(slice)
            } catch {
                Log.error("[Spotlight] Re-index failed: \(error.localizedDescription)", category: .initialization)
                return
            }
        }
        Log.info(
            "[Spotlight] \(asUpdate ? "Refreshed" : "Re-indexed") \(items.count) entries from stored records",
            category: .initialization)
    }

    /// A text preview reads the document's whole text from the full-text store and keeps 500
    /// characters, so a document of more passages than this gets none (about two million
    /// characters at the importer's passage sizes) [inferred from the chunk sizes, not measured].
    static let largestDocumentForAPreview = 2_000

    /// A document's first 500 characters, as its import listed them. None when the full-text
    /// store has no text for it.
    private static func textPreview(of documentId: UUID) async -> String? {
        guard let stored = await SQLiteFullTextService.shared.getContentPreview(documentId: documentId, maxLength: 500)
        else { return nil }
        return previewText(fromStored: stored)
    }

    /// The store marks a cut preview with a line of its own for its own screens, which an entry
    /// does not carry.
    nonisolated static func previewText(fromStored stored: String) -> String? {
        let text = (stored.components(separatedBy: "\n\n--- Preview truncated").first ?? stored)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Once, on the first launch of 5.7: entries made by 5.6 expire 30 days after they were made.
    /// Each library and document entry is written again whole, so it lasts and carries its app
    /// item. An update would keep the entry's attributes, and Apple's documentation does not say
    /// that it moves the expiry, so it is not used here.
    func refreshEntriesMadeBefore57() async {
        let key = "spotlightEntriesRefreshedFor57"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        await reindexFromStoredRecords(asUpdate: false)
        UserDefaults.standard.set(true, forKey: key)
    }

    /// One entry per library and per document, each document's with its record. The records are
    /// two small files (one record per library and per document, no passages), so they are read
    /// here, where they are decoded.
    private static func itemsFromStoredRecords(
        domain: String, documentIds: Set<UUID>?, libraryIds: Set<UUID>?
    ) -> [(item: CSSearchableItem, document: OIDocumentEntity?)] {
        let containers = OILibraryEntityQuery.loadContainers()
        var items: [(item: CSSearchableItem, document: OIDocumentEntity?)] = []
        for container in containers where libraryIds?.contains(container.id) ?? (documentIds == nil) {
            let attributes = CSSearchableItemAttributeSet(contentType: .folder)
            attributes.title = container.name
            attributes.contentDescription = container.description
                ?? "Knowledge library with \(container.totalDocuments) documents"
            attributes.containerTitle = "OpenIntelligence"
            attributes.containerDisplayName = "Libraries"
            let item = CSSearchableItem(
                uniqueIdentifier: "container-\(container.id.uuidString)", domainIdentifier: domain,
                attributeSet: attributes)
            item.expirationDate = .distantFuture
            item.associateAppEntity(OILibraryEntityQuery.entity(for: container))
            items.append((item, nil))
        }
        guard libraryIds == nil || documentIds != nil else { return items }
        let defaultLibrary = containers.first?.id
        let libraryNames = Dictionary(containers.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        for record in OIDocumentEntityQuery.loadDocumentRecords() where documentIds?.contains(record.id) ?? true {
            // A document stored before libraries existed has no library id and lives in the first one.
            guard let libraryId = record.containerId ?? defaultLibrary else { continue }
            let document = OIDocumentEntityQuery.entity(for: record, libraryNames: libraryNames)
            items.append((documentItem(document, domain: "\(domain).\(libraryId.uuidString)"), document))
        }
        return items
    }

    /// A document's entry, carrying the document as its app item so Siri and Apple Intelligence can
    /// use it. A tap on it in the Simulator ran an App Shortcut that takes a document (Ask About a
    /// Document) instead of `OpenDocumentIntent` [measured 2026-10-20]; dropping the app item would
    /// hand the tap to the app by identifier, but loses that link, so it is the owner's call.
    nonisolated static func documentItem(_ document: OIDocumentEntity, domain: String) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .plainText)
        attributes.title = document.filename
        // In an update a nil attribute is deleted (`isUpdate`), so one the record lacks is
        // left unset rather than set to nil.
        if let libraryName = document.libraryName { attributes.containerTitle = libraryName }
        attributes.containerDisplayName = "OpenIntelligence"
        if let pages = document.pageCount { attributes.pageCount = pages as NSNumber }
        if let added = document.addedAt { attributes.addedDate = added }
        attributes.kind = "Ingested Document"
        let item = CSSearchableItem(
            uniqueIdentifier: "document-\(document.id.uuidString)", domainIdentifier: domain,
            attributeSet: attributes)
        item.expirationDate = .distantFuture
        item.associateAppEntity(document)
        return item
    }

    // MARK: - Chunk Indexing

    /// Passage entries being written, by document. A delete that comes before they are written
    /// cancels the write, and one that comes while they are removes them once they are.
    private var passageIndexing: [UUID: (library: UUID, token: UUID, task: Task<Void, Never>)] = [:]

    /// Indexes a document's passages. The entries are built off the main actor (5.7): a document of
    /// a few thousand passages built them on it, one attribute set each, during the import.
    func indexDocumentChunks(
        documentId: UUID,
        documentName: String,
        chunks: [DocumentChunk],
        containerId: UUID,
        containerName: String
    ) {
        let domain = domainIdentifier
        let index = searchableIndex
        let passageDomain = "\(domain).\(containerId.uuidString).\(documentId.uuidString)"
        let token = UUID()
        let task = Task {
            defer {
                if passageIndexing[documentId]?.token == token { passageIndexing[documentId] = nil }
            }
            let items = await Self.passageItems(
                documentId: documentId, documentName: documentName, chunks: chunks,
                containerId: containerId, containerName: containerName, domain: domain)
            guard !Task.isCancelled, Self.isEnabled else { return }
            do {
                try await index.indexSearchableItems(items)
                Log.debug("[Spotlight] Indexed \(items.count) chunks of document '\(documentName)'", category: .ingestion)
            } catch {
                Log.error("[Spotlight] Failed to index \(items.count) chunks: \(error.localizedDescription)", category: .ingestion)
            }
            // The document was deleted, or the switch turned off, while the entries were written.
            if Task.isCancelled || !Self.isEnabled {
                try? await index.deleteSearchableItems(withDomainIdentifiers: [passageDomain])
            }
        }
        passageIndexing[documentId] = (containerId, token, task)
    }

    /// A passage's title in Spotlight: its document, and its page where it has one (5.7). It read
    /// "Juniper Flats Lease - Unit 4B.pdf — Page 3 [Chunk 13]", the passage's internal number in front of
    /// people, and "Page 1" for a text file, which has no pages (iOS 27 Simulator, 2026-10-20).
    nonisolated static func passageTitle(documentName: String, pageNumber: Int?) -> String {
        guard let pageNumber, pageNumber > 0 else { return documentName }
        return "\(documentName), page \(pageNumber)"
    }

    /// A passage's entry is named `passage-<document>-<passage>`, so a tap opens its document
    /// (`AppLink.destination(forSpotlightIdentifier:)`); through 5.6 it was `chunk-<passage>`,
    /// which opened nothing. It lasts as long as its document: `deindexDocument` removes the
    /// document's passage domain.
    @concurrent nonisolated private static func passageItems(
        documentId: UUID, documentName: String, chunks: [DocumentChunk], containerId: UUID,
        containerName: String, domain: String
    ) async -> sending [CSSearchableItem] {
        chunks.map { chunk -> CSSearchableItem in
            let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
            attributeSet.title = passageTitle(documentName: documentName, pageNumber: chunk.metadata.pageNumber)
            attributeSet.contentDescription = String(chunk.content.prefix(300))
            attributeSet.containerTitle = containerName
            attributeSet.containerDisplayName = "OpenIntelligence"

            var keys = ["chunk", "section", "excerpt", documentName.lowercased()]
            if let section = chunk.metadata.sectionTitle {
                keys.append(section.lowercased())
                attributeSet.headline = section
            }
            keys.append(contentsOf: chunk.metadata.keywords)
            attributeSet.keywords = keys

            if let page = chunk.metadata.pageNumber {
                attributeSet.pageCount = page as NSNumber
            }

            // No `relatedUniqueIdentifier`, which 5.6 set here: Apple documents it for activities
            // only (CSSearchableItemAttributeSet_General.h). The domain ties a passage to its
            // document for deletion, and the identifier for opening.
            let item = CSSearchableItem(
                uniqueIdentifier: "passage-\(documentId.uuidString)-\(chunk.id.uuidString)",
                domainIdentifier: "\(domain).\(containerId.uuidString).\(documentId.uuidString)",
                attributeSet: attributeSet
            )
            item.expirationDate = .distantFuture
            return item
        }
    }

    // MARK: - Entries of documents that are gone

    /// Every document this device knows, with its library: those read from disk at the last load
    /// and those an import here has listed since. Kept in the device's own folder, because each
    /// device has its own Spotlight index. Nil until it is first needed.
    private var knownDocuments: [UUID: UUID]?
    /// Documents an import on this device has listed whose record is not written yet.
    private var importing: Set<UUID> = []
    /// The last write of `knownDocuments`, so the writes land in order.
    private var knownDocumentsWrite: Task<Void, Never>?

    nonisolated private static var knownDocumentsURL: URL {
        AppSupportPaths.localCacheDir().appendingPathComponent("spotlight_documents.json")
    }

    /// The documents as read from disk (`RAGService.applyLoadedDocuments`), which is where a
    /// document deleted on another device arrives. From 5.7 entries do not expire, so the entries
    /// of a document that is gone, and of an import that stopped before its record was written,
    /// are removed here. A document this device has not listed, one imported on another device or
    /// while the switch was off, is listed from its record, without its passages.
    func documentsLoaded(_ documents: [Document], defaultLibraryId: UUID?) {
        var present: [UUID: UUID] = [:]
        for document in documents {
            guard let library = document.containerId ?? defaultLibraryId else { continue }
            present[document.id] = library
        }
        importing.subtract(present.keys)
        guard let known = knownDocuments ?? Self.readKnownDocuments() else {
            // The first load of 5.7 on this device: what is on disk is what it knows.
            knownDocuments = present
            writeKnownDocuments()
            return
        }
        let change = Self.change(known: known, present: present, importing: importing)
        knownDocuments = change.known
        guard change.known != known else { return }
        writeKnownDocuments()
        if !change.gone.isEmpty {
            searchableIndex.deleteSearchableItems(
                withIdentifiers: change.gone.keys.map { "document-\($0.uuidString)" }) { _ in }
            searchableIndex.deleteSearchableItems(
                withDomainIdentifiers: change.gone.map { "\(domainIdentifier).\($0.value.uuidString).\($0.key.uuidString)" }
            ) { _ in }
            Log.info(
                "[Spotlight] Removed the entries of \(change.gone.count) document(s) no longer in the libraries",
                category: .initialization)
        }
        if !change.arrived.isEmpty {
            Task { await reindexFromStoredRecords(documentIds: change.arrived) }
        }
    }

    /// What a load changes: the documents gone (not on disk and not being imported), the ones that
    /// arrived, and what is known afterwards.
    nonisolated static func change(
        known: [UUID: UUID], present: [UUID: UUID], importing: Set<UUID>
    ) -> (gone: [UUID: UUID], arrived: Set<UUID>, known: [UUID: UUID]) {
        let gone = known.filter { present[$0.key] == nil && !importing.contains($0.key) }
        let arrived = Set(present.keys.filter { known[$0] == nil })
        var next = present
        for id in importing { if let library = known[id] { next[id] = library } }
        return (gone, arrived, next)
    }

    private func updateKnownDocuments(_ change: (inout [UUID: UUID]) -> Void) {
        var known = knownDocuments ?? Self.readKnownDocuments() ?? [:]
        let before = known
        change(&known)
        knownDocuments = known
        if known != before { writeKnownDocuments() }
    }

    nonisolated private static func readKnownDocuments() -> [UUID: UUID]? {
        guard let data = try? Data(contentsOf: knownDocumentsURL),
            let stored = try? JSONDecoder().decode([String: String].self, from: data)
        else { return nil }
        var known: [UUID: UUID] = [:]
        for (document, library) in stored {
            if let document = UUID(uuidString: document), let library = UUID(uuidString: library) {
                known[document] = library
            }
        }
        return known
    }

    private func writeKnownDocuments() {
        guard let known = knownDocuments else { return }
        let stored = Dictionary(uniqueKeysWithValues: known.map { ($0.key.uuidString, $0.value.uuidString) })
        let previous = knownDocumentsWrite
        knownDocumentsWrite = Task.detached(priority: .utility) {
            await previous?.value
            do {
                try JSONEncoder().encode(stored).write(to: Self.knownDocumentsURL, options: .atomic)
            } catch {
                Log.warning("[Spotlight] The list of documents could not be saved: \(error.localizedDescription)", category: .initialization)
            }
        }
    }

    // MARK: - Search Continuation

    /// Handle a Spotlight search continuation — user tapped a result in Spotlight
    /// Returns the container ID and document ID to navigate to
    static func parseSpotlightIdentifier(_ identifier: String) -> (type: String, id: UUID)? {
        let parts = identifier.split(separator: "-", maxSplits: 1)
        guard parts.count == 2,
              let uuid = UUID(uuidString: String(parts[1]))
        else { return nil }

        return (type: String(parts[0]), id: uuid)
    }
}

// MARK: - Documents and libraries as Spotlight's app items (5.7)

/// Documents and libraries are app items in Spotlight: their entries carry the item
/// (`associateAppEntity`), so Siri and Apple Intelligence can use a result and its Open action
/// opens it. These conformances live here, beside the index, because the engine package leaves
/// this folder out.
extension OIDocumentEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        var parts: [String] = []
        if let libraryName { parts.append("In \(libraryName)") }
        if let pageCount, pageCount > 0 { parts.append("\(pageCount) page\(pageCount == 1 ? "" : "s")") }
        parts.append("\(totalChunks) passage\(totalChunks == 1 ? "" : "s")")
        attributes.contentDescription = parts.joined(separator: ", ")
        attributes.addedDate = addedAt
        return attributes
    }
}

extension OILibraryEntity: IndexedEntity {
    var attributeSet: CSSearchableItemAttributeSet {
        let attributes = defaultAttributeSet
        attributes.contentDescription =
            "\(totalDocuments) document\(totalDocuments == 1 ? "" : "s"), \(totalChunks) passage\(totalChunks == 1 ? "" : "s")"
        return attributes
    }
}

/// On iOS and macOS 27 Spotlight asks the app to index its items again when it finds a problem
/// with the index.
@available(iOS 27.0, macOS 27.0, *)
extension OIDocumentEntityQuery: IndexedEntityQuery {
    func reindexEntities(for identifiers: [UUID], indexDescription _: CSSearchableIndexDescription) async throws {
        await SpotlightIndexService.shared.reindexFromStoredRecords(documentIds: Set(identifiers))
    }

    func reindexAllEntities(indexDescription _: CSSearchableIndexDescription) async throws {
        await SpotlightIndexService.shared.reindexFromStoredRecords()
    }
}

@available(iOS 27.0, macOS 27.0, *)
extension OILibraryEntityQuery: IndexedEntityQuery {
    func reindexEntities(for identifiers: [UUID], indexDescription _: CSSearchableIndexDescription) async throws {
        await SpotlightIndexService.shared.reindexFromStoredRecords(libraryIds: Set(identifiers))
    }

    func reindexAllEntities(indexDescription _: CSSearchableIndexDescription) async throws {
        await SpotlightIndexService.shared.reindexFromStoredRecords(libraryIds: Set(OILibraryEntityQuery.loadContainers().map(\.id)))
    }
}
