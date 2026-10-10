//
//  AppCommands.swift
//  OpenIntelligence
//

import SwiftUI

/// Menu and keyboard commands: the menu bar on the Mac, and the same shortcuts on an iPad with a
/// keyboard. Through 5.6 the app had none of its own, so a new conversation, an import and each tab
/// could be reached only by pointer or touch.
///
/// Every command posts a destination to `AppNavigationRequest`, the same queue links and actions
/// use, so a command can do nothing a link cannot.
struct OpenIntelligenceCommands: Commands {
    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Conversation") {
                AppNavigationRequest.post(.newConversation(libraryId: nil))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Add Documents\u{2026}") {
                AppNavigationRequest.post(.addDocument)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings\u{2026}") {
                AppNavigationRequest.post(.settings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("Go") {
            Button("Chat") {
                AppNavigationRequest.post(.chat)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Documents") {
                AppNavigationRequest.post(.documents)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Import Queue") {
                AppNavigationRequest.post(.importQueue)
            }
            .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Find in Library\u{2026}") {
                AppNavigationRequest.post(.search)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Next Library") {
                LibrarySwitching.post(step: 1)
            }
            .keyboardShortcut("]", modifiers: .command)

            Button("Previous Library") {
                LibrarySwitching.post(step: -1)
            }
            .keyboardShortcut("[", modifiers: .command)
        }
    }
}

/// Which library "Next Library" and "Previous Library" go to: the list in the order the app keeps
/// it, wrapping at both ends. With one library, or none active, there is nowhere to go.
enum LibrarySwitching {
    nonisolated static func target(from active: UUID, in libraries: [UUID], step: Int) -> UUID? {
        guard libraries.count > 1, let index = libraries.firstIndex(of: active) else { return nil }
        let count = libraries.count
        return libraries[((index + step) % count + count) % count]
    }

    @MainActor
    static func post(step: Int) {
        let libraries = IntentSupport.libraries()
        guard let target = target(from: libraries.activeContainerId, in: libraries.containers.map(\.id), step: step)
        else { return }
        AppNavigationRequest.post(.library(target))
    }
}
