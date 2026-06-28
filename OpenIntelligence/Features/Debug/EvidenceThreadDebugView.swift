//
//  EvidenceThreadDebugView.swift
//  OpenIntelligence
//
//  Created by AI on 6/28/26.
//

import SwiftUI

/// A standalone diagnostic view for observing the EvidenceThreadStore.
/// It must be accessed manually by developers during Phase 1B (e.g. injected in a preview or temporary tap gesture).
struct EvidenceThreadDebugView: View {
    @StateObject private var service = EvidenceThreadDebugService()
    
    var body: some View {
        NavigationStack {
            List {
                if let error = service.errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
                
                Section(header: Text("Stored Threads")) {
                    if service.threads.isEmpty {
                        Text("No evidence threads found in the isolated local store.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(service.threads) { thread in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(thread.title)
                                    .font(.headline)
                                Text("ID: \(thread.id.uuidString.prefix(8))...")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("Messages: \(thread.messages.count)")
                                    .font(.caption2)
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    service.deleteThread(id: thread.id)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Evidence Debug (Phase 1B)")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: {
                        service.mockThread()
                    }) {
                        Label("Mock Thread", systemImage: "plus")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: {
                        service.loadThreads()
                    }) {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
            }
            .onAppear {
                service.loadThreads()
            }
        }
    }
}

#Preview {
    EvidenceThreadDebugView()
}
