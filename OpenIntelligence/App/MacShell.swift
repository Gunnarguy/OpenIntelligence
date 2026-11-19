//
//  MacShell.swift
//  OpenIntelligence
//
//  The Mac window's sidebar (5.8 Mac redesign). On a Mac the app was the iPhone's tab bar in a window: a pill of five
//  tabs in the title bar, Settings among them, the libraries as a row of chips repeated on three screens, and the
//  conversations in a panel that slid over the chat. Apple's guidance for the Mac (Human Interface Guidelines,
//  "Sidebars" and "Designing for macOS", read 2026-11-18) puts an app's areas and its top-level collections, like
//  folders, in a sidebar at most two levels deep, and Settings in a window of its own. This is that sidebar: the four
//  areas, the libraries, and the open library's conversations. iPhone and iPad keep the tab bar; nothing here is
//  compiled for them.
//

import SwiftUI

/// Whether this area of the Mac window is the one showing (5.8). Each area stays alive once built, as a tab does, so an
/// answer being written in Chat goes on while Documents is in front; a hidden area's toolbar items and title must not
/// reach the window's toolbar. Always true on iPhone and iPad, which never set it.
extension EnvironmentValues {
    @Entry var macAreaIsActive: Bool = true
}

extension EnvironmentValues {
    /// On a Mac, the title of the area in front, which every area's stack shows (5.8 Mac redesign). With the four
    /// areas' stacks side by side the window takes its title from the first one, Chat, whichever is in front; a title
    /// set around the split view is not used. Empty on iPhone and iPad.
    @Entry var macWindowTitle: String = ""
}

extension View {
    /// An area's title: its own on iPhone and iPad, the area in front's on a Mac (`macWindowTitle`).
    func areaNavigationTitle(_ title: String) -> some View {
        modifier(AreaNavigationTitle(title: title))
    }
}

private struct AreaNavigationTitle: ViewModifier {
    let title: String
    @Environment(\.macWindowTitle) private var macWindowTitle

    func body(content: Content) -> some View {
        content.navigationTitle(macWindowTitle.isEmpty ? title : macWindowTitle)
    }
}

#if os(macOS)
    import Combine

    /// Whether an area is in front, read when a binding's setter runs rather than when it was made. An inspector's
    /// binding made while its area was in front can be written false as the area goes behind, which is not the person
    /// closing it.
    final class MacAreaFlag {
        var isActive = true
    }

    /// A row of the Mac sidebar.
    enum MacSidebarItem: Hashable {
        case area(ContentView.Tab)
        case library(UUID)
        case thread(UUID)
    }

    /// What a sidebar row asks a screen to do. The screen may not exist yet (each area is built the first time it is
    /// shown), so the request waits here and the screen takes it when it appears: a `@Published` value is delivered to
    /// a new subscriber at once.
    enum MacLibraryCommand {
        case newLibrary
        case settings(UUID)
        case delete(UUID)
        case storage(UUID, LibrarySyncMode)
    }

    /// An answer's details for the inspector: what `ChatResponseDetailsView` shows, and the library's documents so a
    /// source can open its page.
    struct MacAnswerDetails: Identifiable {
        let id = UUID()
        let metadata: ResponseMetadata
        let retrievedChunks: [RetrievedChunk]
        let structuredAnswer: StructuredAnswer?
        let lookup: LibraryDocumentLookup?
    }

    /// One per window (5.8): with File > New Window, a request made in one window's sidebar must reach that window's
    /// screens only. `ContentView` owns it, puts it in the window's environment (`macShellCommands`) and makes it the
    /// focused scene's object, so the menu bar's commands reach the window in front.
    ///
    /// A screen that takes a request clears it with `clear(_:)`, on the next turn of the main loop: a `@Published`
    /// value is sent to subscribers before it is stored, so setting it to nil inside the subscriber is overwritten by
    /// the store that follows, and the request would wait there for the next screen to subscribe.
    @MainActor
    final class MacShellCommands: ObservableObject {
        func clear<Value>(_ keyPath: ReferenceWritableKeyPath<MacShellCommands, Value?>) {
            DispatchQueue.main.async { [weak self] in self?[keyPath: keyPath] = nil }
        }
        /// For the Documents screen: a library action chosen in the sidebar.
        @Published var libraryCommand: MacLibraryCommand?
        /// For the Chat screen: the conversation chosen in the sidebar.
        @Published var threadToOpen: UUID?
        /// For the window: the area a menu command asks for (Go > Atlas, Go > Database).
        @Published var areaRequest: ContentView.Tab?
        /// For the Chat screen: the answer whose details show in the window's inspector (5.8), where the iPhone shows
        /// them in a sheet over the chat.
        @Published var answerDetails: MacAnswerDetails?
    }

    extension EnvironmentValues {
        /// The window's `MacShellCommands`; nil outside a main window (the Settings and Atlas windows).
        @Entry var macShellCommands: MacShellCommands? = nil
    }

    struct MacSidebar: View {
        @Binding var selection: MacSidebarItem?
        let commands: MacShellCommands
        @ObservedObject var ragService: RAGService
        @ObservedObject var containerService: ContainerService
        let unseenAnswers: Int

        @State private var threads: [EvidenceThread] = []
        @State private var threadError: String?

        var body: some View {
            List(selection: $selection) {
                Section {
                    // The badge goes inside the tag: a `.badge` around the `.tag` hid the tag from the List, so the
                    // Chat row could not be selected or clicked (2026-11-19).
                    area("Chat", symbol: "bubble.left.and.bubble.right", .chat, badge: unseenAnswers)
                    area("Documents", symbol: "doc.text.magnifyingglass", .documents)
                    area("Atlas", symbol: "globe.americas", .visualizations)
                    area("Database", symbol: "cylinder.split.1x2", .database)
                }

                Section("Libraries") {
                    ForEach(containerService.pickableContainers) { library in
                        libraryRow(library)
                    }
                    // Dragged into another order, as the chips are on iPhone and iPad (`LibraryReordering`).
                    .onMove { indices, destination in
                        let libraries = containerService.pickableContainers
                        let ids = indices.map { libraries[$0].id }
                        let target = destination < libraries.count ? libraries[destination].id : nil
                        containerService.move(ids, before: target)
                    }
                    Button {
                        commands.libraryCommand = .newLibrary
                        selection = .area(.documents)
                    } label: {
                        Label("New Library", systemImage: "plus")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Section {
                    if threads.isEmpty {
                        Text("No evidence threads in this library yet")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .selectionDisabled()
                    }
                    ForEach(threads) { thread in
                        threadRow(thread)
                    }
                } header: {
                    Text("Evidence Threads")
                }
            }
            .listStyle(.sidebar)
            .onAppear(perform: loadThreads)
            .onChange(of: containerService.activeContainerId) { _, _ in loadThreads() }
            .onReceive(ragService.$activeThreadId) { _ in loadThreads() }
            // A conversation's title and date change when an answer is saved.
            .onReceive(ragService.$chatHistories.debounce(for: .milliseconds(400), scheduler: RunLoop.main)) { _ in
                loadThreads()
            }
            .alert(
                "Thread Limit Reached",
                isPresented: Binding(get: { threadError != nil }, set: { if !$0 { threadError = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(threadError ?? "")
            }
        }

        private func area(_ title: String, symbol: String, _ tab: ContentView.Tab, badge: Int = 0) -> some View {
            Label(title, systemImage: symbol)
                .badge(badge)
                .tag(MacSidebarItem.area(tab))
        }

        private func libraryRow(_ library: KnowledgeContainer) -> some View {
            let isActive = containerService.activeContainerId == library.id
            let count = containerService.documentCount(for: library.id)
            return Label {
                HStack(spacing: DSSpacing.xs) {
                    Text(library.name)
                        .fontWeight(isActive ? .semibold : .regular)
                        .lineLimit(1)
                    if library.syncMode == .iCloudShared {
                        Image(systemName: "icloud")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("Syncs with iCloud")
                    }
                }
            } icon: {
                Image(systemName: library.icon)
                    .foregroundStyle(Color(hex: library.colorHex) ?? .accentColor)
            }
            .badge(count)
            .tag(MacSidebarItem.library(library.id))
            .accessibilityValue(isActive ? "Open library" : "")
            .contextMenu {
                Button("Library Settings\u{2026}") {
                    commands.libraryCommand = .settings(library.id)
                    selection = .library(library.id)
                }
                Button("New Library\u{2026}") {
                    commands.libraryCommand = .newLibrary
                    selection = .area(.documents)
                }
                if !containerService.isGuideLibrary(library.id) {
                    Divider()
                    Button(library.syncMode == .localOnly ? "Local Only (Current)" : "Make Local Only") {
                        commands.libraryCommand = .storage(library.id, .localOnly)
                        selection = .library(library.id)
                    }
                    .disabled(library.syncMode == .localOnly)
                    Button(library.syncMode == .iCloudShared ? "iCloud Sync (Current)" : "Make iCloud Sync") {
                        commands.libraryCommand = .storage(library.id, .iCloudShared)
                        selection = .library(library.id)
                    }
                    .disabled(library.syncMode == .iCloudShared)
                }
                if containerService.mayDelete(id: library.id) {
                    Divider()
                    Button("Delete Library\u{2026}", role: .destructive) {
                        commands.libraryCommand = .delete(library.id)
                        selection = .library(library.id)
                    }
                }
            }
        }

        private func threadRow(_ thread: EvidenceThread) -> some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(thread.title)
                    .lineLimit(1)
                Text(thread.updatedAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .tag(MacSidebarItem.thread(thread.id))
            .contextMenu {
                Button("Delete Evidence Thread", role: .destructive) {
                    delete(thread)
                }
            }
        }

        private func loadThreads() {
            threads = ragService.listThreads(for: containerService.activeContainerId)
        }

        /// As the iPhone's conversation list deletes one (`ThreadSidebarView`): the open one is replaced by a new one.
        private func delete(_ thread: EvidenceThread) {
            let containerId = containerService.activeContainerId
            try? ragService.threadStore.deleteThread(id: thread.id, containerId: containerId)
            if ragService.activeThreadId == thread.id {
                do {
                    try ragService.createNewThread(for: containerId)
                    if let fresh = ragService.activeThreadId {
                        commands.threadToOpen = fresh
                    }
                } catch let quotaError as EvidenceThreadQuotaError {
                    threadError = quotaError.localizedDescription
                } catch {
                    Log.error("[MacSidebar] Failed to create thread: \(error.localizedDescription)", category: .ui)
                }
            }
            WidgetSnapshot.forgetAnswer(inLibrary: containerId)
            loadThreads()
        }
    }
#endif
