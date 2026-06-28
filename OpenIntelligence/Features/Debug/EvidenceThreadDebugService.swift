//
//  EvidenceThreadDebugService.swift
//  OpenIntelligence
//
//  Created by AI on 6/28/26.
//

import Foundation
import Combine

/// A debug-only service that exposes EvidenceThreadStore capabilities for visual diagnostics.
/// Not to be injected into production view hierarchies.
final class EvidenceThreadDebugService: ObservableObject {
    @Published var threads: [EvidenceThread] = []
    @Published var errorMessage: String? = nil
    
    private let store: EvidenceThreadStore
    private let defaultContainerId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    
    init(store: EvidenceThreadStore = EvidenceThreadStore()) {
        self.store = store
    }
    
    /// Loads all threads from the default container.
    func loadThreads() {
        do {
            threads = try store.listThreads(containerId: defaultContainerId)
            errorMessage = nil
        } catch {
            errorMessage = "Failed to load threads: \(error.localizedDescription)"
        }
    }
    
    /// Mocks a new thread and saves it.
    func mockThread() {
        let newThread = EvidenceThread(
            containerId: defaultContainerId,
            title: "Mock Thread \(Int.random(in: 100...999))",
            messages: [
                ChatMessage(role: .user, content: "Hello, this is a mock diagnostic thread."),
                ChatMessage(role: .assistant, content: "I am correctly isolated in the EvidenceThread store.")
            ]
        )
        do {
            try store.saveThread(newThread)
            loadThreads()
        } catch {
            errorMessage = "Failed to save mock thread: \(error.localizedDescription)"
        }
    }
    
    /// Deletes a specific thread.
    func deleteThread(id: UUID) {
        do {
            try store.deleteThread(id: id, containerId: defaultContainerId)
            loadThreads()
        } catch {
            errorMessage = "Failed to delete thread: \(error.localizedDescription)"
        }
    }
}
