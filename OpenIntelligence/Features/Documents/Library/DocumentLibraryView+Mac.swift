//
//  DocumentLibraryView+Mac.swift
//  OpenIntelligence
//
//  The Documents area's Mac chrome (5.8 Mac redesign): its actions in the window's toolbar, where a Mac app keeps them,
//  instead of round buttons inside the page; the selected document's details in the inspector beside the table instead
//  of a pushed page with a Back button; and the library actions chosen in the window's sidebar (`MacSidebar`).
//

#if os(macOS)
    import Combine
    import SwiftUI

    extension DocumentLibraryView {
        /// The toolbar, inspector and sidebar commands, around the area's content.
        func macDocumentsChrome<Content: View>(_ content: Content) -> some View {
            content
                .navigationSubtitle(macAreaIsActive ? macSubtitle : "")
                .toolbar {
                    if macAreaIsActive {
                        macDocumentToolbar
                    }
                }
                // Gated on the area being in front: the inspector is a column of the window, and it must not stay
                // open beside Chat.
                .inspector(
                    isPresented: Binding(
                        get: { macShowsInspector && macAreaIsActive && !filteredDocuments.isEmpty },
                        set: { show in
                            if show {
                                macShowsInspector = true
                                return
                            }
                            // Closed with another area already in front: the switch, not the person.
                            guard macAreaFlag.isActive else { return }
                            macShowsInspector = false
                            macInspectorClosedAt = Date()
                        })
                ) {
                    macInspectorContent
                        .inspectorColumnWidth(min: 300, ideal: 380, max: 560)
                }
                // A close that came with the switch to another area is undone: the inspector is the person's to close.
                .onChange(of: macAreaIsActive) { _, active in
                    macAreaFlag.isActive = active
                    if !active, let closed = macInspectorClosedAt, Date().timeIntervalSince(closed) < 1 {
                        macShowsInspector = true
                    }
                }
                // A link, Siri or the Atlas asked for a document: select it and show it beside the table.
                .onChange(of: openedDocumentID) { _, id in
                    guard let id else { return }
                    macSelection = [id]
                    macShowsInspector = true
                    openedDocumentID = nil
                }
                // Another library: keep only what is in it, so a document opened by a link into another library stays
                // selected whichever of the two changes is seen first.
                .onChange(of: containerService.activeContainerId) { _, _ in
                    let shown = Set(filteredDocuments.map(\.id))
                    macSelection = macSelection.filter { shown.contains($0) }
                }
                .onReceive(
                    macShellCommands.map { $0.$libraryCommand.eraseToAnyPublisher() } ?? Just(nil).eraseToAnyPublisher()
                ) { command in
                    guard let command else { return }
                    macShellCommands?.clear(\.libraryCommand)
                    takeMacLibraryCommand(command)
                }
        }

        /// The count of documents and passages, which the iPhone's footer under the cards shows.
        private var macSubtitle: String {
            let passages = filteredTotalChunks
            return "\(documentSectionSubtitle) \u{00B7} \(passages.formatted()) \(passages == 1 ? "passage" : "passages")"
        }

        @ViewBuilder
        private var macInspectorContent: some View {
            let selected = filteredDocuments.filter { macSelection.contains($0.id) }
            if selected.count == 1, let document = selected.first {
                NavigationStack {
                    DocumentDetailsView(
                        document: document,
                        embeddingProviderId: containerService.activeContainer?.embeddingProviderId)
                }
                .id(document.id)
            } else if selected.count > 1 {
                ContentUnavailableView(
                    "\(selected.count) Documents Selected",
                    systemImage: "doc.on.doc",
                    description: Text(
                        "\(selected.reduce(0) { $0 + $1.totalChunks }.formatted()) passages. Press Delete to remove them."))
            } else {
                ContentUnavailableView(
                    "No Document Selected",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Select a document to see how it was read, its passages and its pages."))
            }
        }

        @ToolbarContentBuilder
        private var macDocumentToolbar: some ToolbarContent {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Tour.used(.addDocument)
                    presentDocumentPickerOrUpgrade()
                } label: {
                    Label("Add Documents", systemImage: "plus")
                }
                .help(isGuideLibraryOpen ? "The guide library takes no files" : "Add Documents (Command-O)")
                .disabled(isGuideLibraryOpen)

                LibraryPasteButton { staged in
                    Tour.used(.paste)
                    importOpenedFiles(staged)
                } label: { isWorking in
                    Label("Paste into Library", systemImage: isWorking ? "hourglass" : "doc.on.clipboard")
                }
                .help("Paste a copied file, web address or text into this library")
                .disabled(isGuideLibraryOpen)

                Button {
                    Tour.used(.semanticSearch)
                    showingSemanticSearch = true
                } label: {
                    Label("Semantic Search", systemImage: "sparkle.magnifyingglass")
                }
                .help("Search by meaning (Command-F)")
                .disabled(ragService.documents.isEmpty)

                Button {
                    Tour.used(.librarySettings)
                    showingContainerSettings = true
                } label: {
                    Label("Library Settings", systemImage: "slider.horizontal.3")
                }
                .help("Library Settings")

                macMoreMenu

                Button {
                    macShowsInspector.toggle()
                } label: {
                    Label("Inspector", systemImage: "sidebar.trailing")
                }
                .help(macShowsInspector ? "Hide the document's details" : "Show the document's details")
            }
        }

        /// The library's less frequent actions: where it is kept, the watched folder, and the two destructive ones,
        /// which keep their confirmations (`documentHeader`).
        private var macMoreMenu: some View {
            Menu {
                if activeLibrary != nil, !isGuideLibraryOpen {
                    Picker("Keep This Library", selection: syncModeBinding) {
                        Text("On This Mac Only").tag(LibrarySyncMode.localOnly)
                        Text("In iCloud").tag(LibrarySyncMode.iCloudShared)
                    }
                    .pickerStyle(.inline)
                }
                if hasConfiguredICloudLibraries {
                    Button("Sync Now") { refreshSharedWorkspaceNow() }
                        .disabled(isRefreshingSharedWorkspace)
                }
                if !isGuideLibraryOpen {
                    Button("Watched Folder\u{2026}") {
                        Tour.used(.watchFolder)
                        showingWatchedFolder = true
                    }
                }
                if cachedDocumentCount > 0 {
                    Button("Cached Documents (\(cachedDocumentCount))\u{2026}") { showCachedDocs = true }
                }
                Divider()
                Button("New Library\u{2026}") { handleNewLibraryTapped() }
                if !isGuideLibraryOpen {
                    Button("Remove All Documents\u{2026}", role: .destructive) {
                        Tour.used(.removeAll)
                        showingClearAllConfirmation = true
                    }
                    .disabled(filteredDocuments.isEmpty)
                    if let activeLibrary, containerService.mayDelete(id: activeLibrary.id) {
                        Button("Delete \u{201C}\(activeLibrary.name)\u{201D}\u{2026}", role: .destructive) {
                            Tour.used(.deleteLibrary)
                            handleDeleteLibrary(activeLibrary)
                        }
                    }
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("More library actions")
        }

        /// A library action chosen in the window's sidebar. The sidebar has already opened that library.
        private func takeMacLibraryCommand(_ command: MacLibraryCommand) {
            switch command {
            case .newLibrary:
                handleNewLibraryTapped()
            case .settings(let id):
                if containerService.activeContainerId != id { containerService.setActive(id) }
                showingContainerSettings = true
            case .delete(let id):
                if let library = containerService.containers.first(where: { $0.id == id }) {
                    handleDeleteLibrary(library)
                }
            case .storage(let id, let mode):
                if let library = containerService.containers.first(where: { $0.id == id }) {
                    handleSetLibrarySyncMode(library, mode)
                }
            }
        }
    }
#endif
