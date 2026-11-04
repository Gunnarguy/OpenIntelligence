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
                MenuCommandJournal.record("newConversation")
                AppNavigationRequest.post(.newConversation(libraryId: nil))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Button("Add Documents\u{2026}") {
                MenuCommandJournal.record("addDocuments")
                AppNavigationRequest.post(.addDocument)
            }
            .keyboardShortcut("o", modifiers: .command)
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings\u{2026}") {
                MenuCommandJournal.record("settings")
                AppNavigationRequest.post(.settings)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("Go") {
            Button("Chat") {
                MenuCommandJournal.record("chat")
                AppNavigationRequest.post(.chat)
            }
            .keyboardShortcut("1", modifiers: .command)

            Button("Documents") {
                MenuCommandJournal.record("documents")
                AppNavigationRequest.post(.documents)
            }
            .keyboardShortcut("2", modifiers: .command)

            Button("Import Queue") {
                MenuCommandJournal.record("importQueue")
                AppNavigationRequest.post(.importQueue)
            }
            .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Find in Library\u{2026}") {
                MenuCommandJournal.record("findInLibrary")
                AppNavigationRequest.post(.search)
            }
            .keyboardShortcut("f", modifiers: .command)

            Button("Next Library") {
                MenuCommandJournal.record("nextLibrary")
                LibrarySwitching.post(step: 1)
            }
            .keyboardShortcut("]", modifiers: .command)

            Button("Previous Library") {
                MenuCommandJournal.record("previousLibrary")
                LibrarySwitching.post(step: -1)
            }
            .keyboardShortcut("[", modifiers: .command)
        }
    }
}

/// The menu or keyboard command that ran (5.8 journal, `menu.command`). A click and its shortcut run the same action,
/// so the journal can't say which was used.
enum MenuCommandJournal {
    static func record(_ command: String) {
        VerificationJournal.record("menu.command", ["command": command])
    }
}

/// Which library "Next Library" and "Previous Library" go to: the list in the order the app keeps
/// it, wrapping at both ends, without the libraries a Focus filter hides (5.7). With one library,
/// or none active, there is nowhere to go.
enum LibrarySwitching {
    nonisolated static func target(from active: UUID, in libraries: [UUID], step: Int) -> UUID? {
        guard libraries.count > 1, let index = libraries.firstIndex(of: active) else { return nil }
        let count = libraries.count
        return libraries[((index + step) % count + count) % count]
    }

    @MainActor
    static func post(step: Int) {
        let libraries = IntentSupport.libraries()
        guard let target = target(from: libraries.activeContainerId, in: libraries.pickableContainers.map(\.id), step: step)
        else { return }
        AppNavigationRequest.post(.library(target))
    }
}
