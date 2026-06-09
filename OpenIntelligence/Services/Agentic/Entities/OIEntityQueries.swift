//
//  OIEntityQueries.swift
//  OpenIntelligence
//
//  Created by Gunnar Hostetler on 6/8/26.
//

import AppIntents
import Foundation

@available(iOS 16.0, macOS 13.0, *)
struct OIDocumentEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    func entities(for identifiers: [OIDocumentEntity.ID]) async throws -> [OIDocumentEntity] {
        let docs = loadAllDocuments()
        return docs.filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [OIDocumentEntity] {
        return loadAllDocuments()
    }
    
    func entities(matching displayName: String) async throws -> [OIDocumentEntity] {
        let docs = loadAllDocuments()
        return docs.filter { $0.filename.localizedCaseInsensitiveContains(displayName) }
    }
    
    func allEntities() async throws -> [OIDocumentEntity] {
        return loadAllDocuments()
    }
    
    private func loadAllDocuments() -> [OIDocumentEntity] {
        let url = AppSupportPaths.documentsMetadataURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let docs = try JSONDecoder().decode([Document].self, from: data)
            return docs.map { OIDocumentEntity(id: $0.id, filename: $0.filename, totalChunks: $0.totalChunks) }
        } catch {
            return []
        }
    }
}

@available(iOS 16.0, macOS 13.0, *)
struct OILibraryEntityQuery: EntityQuery, EntityStringQuery, EnumerableEntityQuery {
    func entities(for identifiers: [OILibraryEntity.ID]) async throws -> [OILibraryEntity] {
        let libs = loadAllLibraries()
        return libs.filter { identifiers.contains($0.id) }
    }
    
    func suggestedEntities() async throws -> [OILibraryEntity] {
        return loadAllLibraries()
    }
    
    func entities(matching displayName: String) async throws -> [OILibraryEntity] {
        let libs = loadAllLibraries()
        return libs.filter { $0.name.localizedCaseInsensitiveContains(displayName) }
    }
    
    func allEntities() async throws -> [OILibraryEntity] {
        return loadAllLibraries()
    }
    
    private func loadAllLibraries() -> [OILibraryEntity] {
        let url = AppSupportPaths.containersListURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let containers = try JSONDecoder().decode([KnowledgeContainer].self, from: data)
            return containers.map { OILibraryEntity(id: $0.id, name: $0.name, totalDocuments: $0.totalDocuments) }
        } catch {
            return []
        }
    }
}
