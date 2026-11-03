//
//  WatchedFolderSection.swift
//  OpenIntelligence
//
//  Choosing a library's watched folder, in Library Settings (5.8).
//

import SwiftUI
import UniformTypeIdentifiers

/// A library's watched folder. Choosing one needs Pro or Lifetime; stopping never does.
struct WatchedFolderSection: View {
    let library: KnowledgeContainer?
    @ObservedObject var ragService: RAGService
    let hasAccess: Bool
    let showPlans: () -> Void

    @ObservedObject private var watcher = WatchedFolderService.shared
    @EnvironmentObject private var entitlementStore: EntitlementStore
    @State private var isChoosing = false
    @State private var problem: String?
    /// A folder large enough to ask about, with how many files it would import.
    @State private var large: (url: URL, count: Int)?

    /// Asked about from this many files, since an import of a large folder runs for a long time.
    private static let askFrom = 50

    private var folder: WatchedFolder? { watcher.folder(forLibrary: library?.id) }

    var body: some View {
        // Not for the guide library (5.8): it holds the app's guides only, and files are sent to the person's own.
        if !ragService.containerService.isGuideLibrary(library?.id) {
            watchedFolderSection
        }
    }

    private var watchedFolderSection: some View {
        Section {
            if let folder {
                LabeledContent("Folder", value: folder.name)
                if let checked = folder.lastCheckedAt {
                    LabeledContent("Last checked") {
                        Text(checked, style: .relative)
                    }
                }
                if let note = folder.note {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button("Check Now") {
                    Task { await watcher.check(engine: ragService) }
                }
                .disabled(watcher.isChecking || !hasAccess)
                Button("Stop Watching", role: .destructive) {
                    if let library { watcher.stopWatching(library: library.id) }
                }
            } else {
                Button("Watch a Folder") {
                    Tour.used(.watchFolder)
                    if hasAccess { isChoosing = true } else { showPlans() }
                }
                .tour(.watchFolder, in: Tour.librarySettings)
            }
            if let problem {
                Text(problem)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Watched Folder")
        } footer: {
            // Each claim is the service's (5.8): the walk takes subfolders (`FileManager.enumerator`), a Mac checks every
            // `WatchedFolderService.macCheckInterval` (300 s), iPhone and iPad on opening the app, and `settle` never
            // removes a document because its file left the folder.
            Text(
                "Pick a folder in Files, iCloud Drive included, and this library keeps up with it. Every file in it the app can read, subfolders too, is imported, and files you add later import by themselves. Change a file and the library swaps in the new version, so an older answer may not open the old one. Deleting a file from the folder leaves it in this library, and the app never changes or moves your files. A Mac checks every 5 minutes while the app is open; iPhone and iPad check each time you open the app, or when you tap Check Now. Pro and Lifetime."
            )
        }
        .fileImporter(isPresented: $isChoosing, allowedContentTypes: [.folder]) { result in
            switch result {
            case .success(let url):
                chosen(url)
            case .failure(let error):
                problem = error.localizedDescription
            }
        }
        .alert(
            "Import \(large?.count ?? 0) Files?",
            isPresented: Binding(get: { large != nil }, set: { if !$0 { large = nil } })
        ) {
            Button("Import") {
                if let large { start(large.url) }
                large = nil
            }
            Button("Cancel", role: .cancel) { large = nil }
        } message: {
            Text("This folder holds that many files the app can import. A large import can take a long time.")
        }
    }

    private func chosen(_ url: URL) {
        problem = nil
        Task {
            let scoped = url.startAccessingSecurityScopedResource()
            let count = await watcher.countOfFiles(in: url)
            if scoped { url.stopAccessingSecurityScopedResource() }
            if count >= Self.askFrom {
                large = (url, count)
            } else {
                start(url)
            }
        }
    }

    private func start(_ url: URL) {
        guard let library else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try watcher.watch(url, library: library.id)
            Task { await watcher.check(engine: ragService, documentLimit: entitlementStore.documentLimit) }
        } catch {
            problem = "This folder can't be watched: \(error.localizedDescription)"
        }
    }
}
