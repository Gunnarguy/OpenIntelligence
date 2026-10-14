//
//  MenuBarAsk.swift
//  OpenIntelligence
//

#if os(macOS)
    import AppKit
    import SwiftUI

    /// OpenIntelligence in the Mac's menu bar (5.7): a field that asks the open library, and the two
    /// things people most often open the app for, adding documents and searching them. A question is
    /// sent in the app's chat, which comes forward with it; with every window closed one is opened
    /// first (`MacServicesProvider.showWindowIfNoneIsOpen`). Settings, Appearance turns the item off.
    struct MenuBarAsk: View {
        /// The `UserDefaults` key the app and Settings share; the item shows until it is turned off.
        static let visibilityKey = "showMenuBarItem"

        @State private var question = ""
        @FocusState private var isFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("Ask your documents")
                    .font(.headline)
                TextField("What does the lease say about pets?", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFocused)
                    .onSubmit(ask)
                HStack {
                    Button("Add Documents…") { show(.addDocument, opening: .documents) }
                    Button("Search…") { show(.search, opening: .documents) }
                    Spacer()
                    Button("Ask", action: ask)
                        .keyboardShortcut(.defaultAction)
                        .disabled(Self.question(from: question) == nil)
                }
            }
            .padding(14)
            .frame(width: 360)
            .onAppear { isFocused = true }
        }

        private func ask() {
            guard let text = Self.question(from: question) else { return }
            question = ""
            show(.ask(text, sendsAtOnce: true), opening: .chat)
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
