//
//  ThreadSidebarView.swift
//  OpenIntelligence
//

import SwiftUI

@MainActor
struct ThreadSidebarView: View {
    @ObservedObject var ragService: RAGService
    @Binding var isPresented: Bool
    var onThreadSelected: (UUID) -> Void
    
    @State private var threads: [EvidenceThread] = []
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Evidence Threads")
                        .font(DSTypography.title)
                    Spacer()
                    Button {
                        let containerId = ragService.containerService.activeContainerId
                        ragService.createNewThread(for: containerId)
                        onThreadSelected(ragService.activeThreadId ?? UUID())
                        loadThreads()
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .imageScale(.large)
                            .foregroundColor(.accentColor)
                    }
                }
                .padding()
                .background(DSColors.surface)
                
                List {
                    ForEach(threads) { thread in
                        Button {
                            onThreadSelected(thread.id)
                        } label: {
                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                Text(thread.title)
                                    .font(.headline)
                                    .foregroundColor(DSColors.primaryText)
                                    .lineLimit(1)
                                Text(thread.updatedAt, style: .date)
                                    .font(DSTypography.caption)
                                    .foregroundColor(DSColors.secondaryText)
                            }
                            .padding(.vertical, DSSpacing.xs)
                        }
                        .listRowBackground(ragService.activeThreadId == thread.id ? DSColors.accent.opacity(0.1) : Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onDelete { indexSet in
                        let containerId = ragService.containerService.activeContainerId
                        for index in indexSet {
                            let thread = threads[index]
                            try? ragService.threadStore.deleteThread(id: thread.id, containerId: containerId)
                            if ragService.activeThreadId == thread.id {
                                ragService.createNewThread(for: containerId)
                                onThreadSelected(ragService.activeThreadId ?? UUID())
                            }
                        }
                        loadThreads()
                    }
                }
                .listStyle(.plain)
                .background(DSColors.surface)
            }
            .frame(width: 300)
            .background(DSColors.surface.ignoresSafeArea())
            .shadow(color: Color.black.opacity(0.15), radius: 10, x: 5, y: 0)
            
            // Tap outside to dismiss
            Color.black.opacity(0.001)
                .onTapGesture {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isPresented = false
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            loadThreads()
        }
        .onChange(of: ragService.containerService.activeContainerId) { _, _ in
            loadThreads()
        }
    }
    
    private func loadThreads() {
        let containerId = ragService.containerService.activeContainerId
        threads = ragService.listThreads(for: containerId)
    }
}
