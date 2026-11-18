//
//  MenuBarAsk.swift
//  OpenIntelligence
//

#if os(macOS)
    import AppKit
    import SwiftUI

    /// OpenIntelligence in the Mac's menu bar (5.7): a field that asks a library, the open one unless another is
    /// picked (5.8), and the two
    /// things people most often open the app for, adding documents and searching them. A question is
    /// sent in the app's chat, which comes forward with it; with every window closed one is opened
    /// first (`MacServicesProvider.showWindowIfNoneIsOpen`). Settings, Appearance turns the item off.
    struct MenuBarAsk: View {
        /// The `UserDefaults` key the app and Settings share; the item shows until it is turned off.
        static let visibilityKey = "showMenuBarItem"

        @State private var question = ""
        @FocusState private var isFocused: Bool
        /// The libraries as last saved, read each time the panel opens, and the one the question goes to.
        @State private var libraries: [KnowledgeContainer] = []
        @State private var libraryId: UUID?

        /// The app's own icon at the menu bar's size, in its colours (5.8). It was the system's
        /// `sparkle.magnifyingglass`, which says "search" and not which app.
        static let icon: NSImage = {
            let image = (NSApplication.shared.applicationIconImage.copy() as? NSImage) ?? NSImage()
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = false
            return image
        }()

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Ask your documents")
                        .font(.headline)
                    Spacer()
                    if libraries.count > 1 {
                        Picker("Library", selection: $libraryId) {
                            ForEach(libraries) { library in
                                Text(library.name).tag(Optional(library.id))
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityLabel("Library to ask")
                    }
                }
                TextField("What does the lease say about pets?", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(ask)
                HStack {
                    Button("Add Documents…") {
                        if let libraryId { AppNavigationRequest.post(.library(libraryId)) }
                        show(.addDocument, opening: .documents)
                    }
                    Button("Search…") { show(.search, opening: .documents) }
                    Spacer()
                    Button("Ask", action: ask)
                        .keyboardShortcut(.defaultAction)
                        .disabled(Self.question(from: question) == nil)
                }
            }
            .padding(14)
            .frame(width: 360)
            .onAppear {
                isFocused = true
                let saved = ContainerService.savedLibraries()
                // The guide library first, as in the app's library rows (2026-11-18).
                let guide = UserDefaults.standard.string(forKey: ContainerService.guideLibraryIdKey).flatMap(UUID.init(uuidString:))
                let order = ContainerService.guideFirst(saved.libraries.map(\.id), guide: guide)
                libraries = order.compactMap { id in saved.libraries.first { $0.id == id } }
                if libraryId == nil || !saved.libraries.contains(where: { $0.id == libraryId }) {
                    libraryId = saved.openId ?? saved.libraries.first?.id
                }
            }
        }

        private func ask() {
            guard let text = Self.question(from: question) else { return }
            question = ""
            VerificationJournal.record(
                "menuBar.ask",
                [
                    "windowOpen": "\(NSApplication.shared.windows.contains { $0.isVisible && $0.canBecomeMain })",
                    "library": libraryId.map(VerificationJournal.anon) ?? "open",
                ])
            show(.ask(text, sendsAtOnce: true, libraryId: libraryId), opening: .chat)
        }

        /// The app comes forward, with a window if none is open, and takes the request.
        private func show(_ destination: AppDestination, opening screen: AppDestination) {
            NSApplication.shared.activate()
            MacServicesProvider.showWindowIfNoneIsOpen(link: AppLink.url(for: screen))
            AppNavigationRequest.post(destination)
        }

        /// The text to send, or nil when there is nothing but space.
        nonisolated static func question(from text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }
#endif
