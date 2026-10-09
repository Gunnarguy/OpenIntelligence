//
//  OIEntityQueries.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// Reads documents and libraries from the files the app keeps them in, so a shortcut can list and
/// pick them without the app's engine being built.
@available(iOS 16.0, macOS 13.0, *)
struct OIDocumentEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    func entities(for identifiers: [OIDocumentEntity.ID]) async throws -> [OIDocumentEntity] {
        let docs = Self.loadAllDocuments()
        return docs.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [OIDocumentEntity] {
        Self.loadAllDocuments()
    }

    func entities(matching displayName: String) async throws -> [OIDocumentEntity] {
        Self.loadAllDocuments().filter { $0.filename.localizedCaseInsensitiveContains(displayName) }
    }

    func allEntities() async throws -> [OIDocumentEntity] {
        Self.loadAllDocuments()
    }

    /// An enumerable query is what gives Shortcuts a "Find Documents" action: the system lists
    /// every document through `allEntities()` and filters and sorts on the item's properties.
    static var findIntentDescription: IntentDescription? {
        IntentDescription(
            "Finds documents in your libraries by name, type, library, date added, pages, words or passages.",
            categoryName: "Documents",
            searchKeywords: ["find", "filter", "documents"])
    }

    /// Every stored document, with its library's name joined in.
    static func loadAllDocuments() -> [OIDocumentEntity] {
        let libraryNames = Dictionary(
            OILibraryEntityQuery.loadContainers().map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return loadDocumentRecords().map { entity(for: $0, libraryNames: libraryNames) }
    }

    static func entity(for document: Document, libraryNames: [UUID: String]) -> OIDocumentEntity {
        OIDocumentEntity(
            id: document.id,
            filename: document.filename,
            totalChunks: document.totalChunks,
            kind: document.contentType.rawValue,
            addedAt: document.addedAt,
            pageCount: document.processingMetadata?.pagesProcessed,
            wordCount: document.processingMetadata?.totalWords,
            libraryName: document.containerId.flatMap { libraryNames[$0] }
        )
    }

    /// Where a document's file is stored. The entity carries no path, so this reads the record again.
    static func storedFileURL(for id: UUID) throws -> URL {
        guard let document = loadDocumentRecords().first(where: { $0.id == id }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let url = document.fileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: url.path])
        }
        return url
    }

    private static func loadDocumentRecords() -> [Document] {
        let url = AppSupportPaths.documentsMetadataURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([Document].self, from: data)
        } catch {
            return []
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct OILibraryEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    func entities(for identifiers: [OILibraryEntity.ID]) async throws -> [OILibraryEntity] {
        Self.loadAllLibraries().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [OILibraryEntity] {
        Self.loadAllLibraries()
    }

    func entities(matching displayName: String) async throws -> [OILibraryEntity] {
        Self.loadAllLibraries().filter { $0.name.localizedCaseInsensitiveContains(displayName) }
    }

    func allEntities() async throws -> [OILibraryEntity] {
        Self.loadAllLibraries()
    }

    static var findIntentDescription: IntentDescription? {
        IntentDescription(
            "Finds libraries by name, document count, passage count or date.",
            categoryName: "Libraries",
            searchKeywords: ["find", "filter", "libraries"])
    }

    static func loadAllLibraries() -> [OILibraryEntity] {
        loadContainers().map(entity(for:))
    }

    static func entity(for container: KnowledgeContainer) -> OILibraryEntity {
        OILibraryEntity(
            id: container.id,
            name: container.name,
            totalDocuments: container.totalDocuments,
            totalChunks: container.totalChunks,
            createdAt: container.createdAt,
            lastIndexedAt: container.lastIndexedAt
        )
    }

    static func loadContainers() -> [KnowledgeContainer] {
        let url = AppSupportPaths.containersListURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([KnowledgeContainer].self, from: data)
        } catch {
            return []
        }
    }
}
