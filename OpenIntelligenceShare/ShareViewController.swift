//
//  ShareViewController.swift
//  OpenIntelligenceShare
//
//  OpenIntelligence in another app's share sheet (5.7).
//

import Observation
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// OpenIntelligence's entry in the share sheet on iPhone and iPad (5.7): a web page from Safari, or text from any app.
/// It saves what was shared in the app group's inbox (`SharedInbox`), and the app adds it the next time it's in front,
/// the way its Paste button adds a copied address or text: a page is downloaded and saved and text is saved as a note,
/// in the library that is open, with the same plan check. A file is offered to the app with "Open in", so this entry
/// doesn't take files.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let model = ShareModel(context: extensionContext)
        let host = UIHostingController(rootView: ShareSheetView(model: model))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
        Task { await model.load() }
    }
}

/// What was shared, and whether it has been saved.
@Observable
final class ShareModel {
    enum State {
        case loading
        /// What will be saved, and whether some text was left out for being too long.
        case ready([SharedInbox.Item], leftOutText: Bool)
        case nothing
        case tooLong
        case saved
        case failed(String)
    }

    private(set) var state: State = .loading
    private weak var context: NSExtensionContext?

    init(context: NSExtensionContext?) {
        self.context = context
    }

    func load() async {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        var items: [SharedInbox.Item] = []
        var tooLong = false
        for provider in providers {
            if let url = await ShareLoading.webURL(from: provider) {
                items.append(SharedInbox.Item(kind: .link, value: url.absoluteString, sharedAt: Date()))
            } else {
                let text = await ShareLoading.text(from: provider)
                if let value = text.value {
                    items.append(SharedInbox.Item(kind: .text, value: value, sharedAt: Date()))
                }
                tooLong = tooLong || text.tooLong
            }
        }
        // Safari can hand over a page's address twice, as an address and as its text.
        var seen = Set<String>()
        items = items.filter { seen.insert($0.value).inserted }
        state = items.isEmpty ? (tooLong ? .tooLong : .nothing) : .ready(items, leftOutText: tooLong)
    }

    func add() {
        guard case .ready(let items, _) = state else { return }
        guard let folder = SharedInbox.defaultFolder else {
            state = .failed(
                "OpenIntelligence couldn't keep this for you. Copy it instead, then tap Paste on the app's Documents screen.")
            return
        }
        do {
            try SharedInbox.save(items, in: folder)
            state = .saved
            Task {
                try? await Task.sleep(for: .seconds(1.2))
                context?.completeRequest(returningItems: nil)
            }
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    func close() {
        if case .saved = state {
            context?.completeRequest(returningItems: nil)
        } else {
            context?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}

/// Reads what a provider holds. The callbacks come on a queue of the system's, so these are not on the main actor.
nonisolated enum ShareLoading {
    static func webURL(from provider: NSItemProvider) async -> URL? {
        guard provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
            !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        else { return nil }
        let url: URL? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// Text someone selected, up to `maxTextCharacters`. A text file handed over as a file is left to Open in: a provider
    /// with a file address or a file name is not read here. Text over the limit isn't kept, and `tooLong` says so.
    static func text(from provider: NSItemProvider) async -> (value: String?, tooLong: Bool) {
        guard provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
            !provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
            provider.suggestedName.map({ ($0 as NSString).pathExtension.isEmpty }) ?? true
        else { return (nil, false) }
        let text: String? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: String.self) { text, _ in continuation.resume(returning: text) }
        }
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.count > maxTextCharacters { return (nil, true) }
        return (trimmed.isEmpty ? nil : trimmed, false)
    }

    /// About 60 pages of text. More than this is a document, which Open in takes as a file.
    static let maxTextCharacters = 200_000
}

struct ShareSheetView: View {
    let model: ShareModel

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("OpenIntelligence")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(isSaved ? "Done" : "Cancel") { model.close() }
                    }
                    if case .ready = model.state {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Add") { model.add() }
                        }
                    }
                }
        }
    }

    private var isSaved: Bool {
        if case .saved = model.state { return true }
        return false
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            ProgressView()
        case .ready(let items, let leftOutText):
            List {
                Section {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        ShareItemRow(item: item)
                    }
                } footer: {
                    Text(
                        (leftOutText
                            ? "Some of the text was too long to share here and is left out. Copy it and use Paste instead. "
                            : "")
                            + "It's added the next time you open OpenIntelligence, to the library you have open there: a page "
                            + "is downloaded and saved, and text is saved as a note.")
                }
            }
        case .nothing:
            ContentUnavailableView(
                "Nothing to Add",
                systemImage: "square.and.arrow.down",
                description: Text(
                    "From here OpenIntelligence takes a web page or text. A file goes in with Open in, from the same share sheet."))
        case .tooLong:
            ContentUnavailableView(
                "Too Long to Share Here",
                systemImage: "text.badge.xmark",
                description: Text(
                    "The share sheet takes up to about 60 pages of text. Copy it and tap Paste on OpenIntelligence's Documents screen, or save it as a file and use Open in."))
        case .saved:
            ContentUnavailableView(
                "Saved for OpenIntelligence",
                systemImage: "checkmark.circle",
                description: Text("Open OpenIntelligence and it's added."))
        case .failed(let message):
            ContentUnavailableView(
                "Not Saved", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }
}

private struct ShareItemRow: View {
    let item: SharedInbox.Item

    var body: some View {
        switch item.kind {
        case .link:
            let url = URL(string: item.value)
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(url?.host() ?? item.value)
                        .font(.body.weight(.medium))
                    Text(item.value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            } icon: {
                Image(systemName: "globe")
            }
        case .text:
            Label {
                Text(item.value)
                    .lineLimit(6)
            } icon: {
                Image(systemName: "text.alignleft")
            }
        }
    }
}
