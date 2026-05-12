//
//  AppTips.swift
//  OpenIntelligence
//
//  Created by OpenIntelligence on 2/18/26.
//
//  TipKit integration — contextual tips for first-time users.
//  Tips automatically dismiss after the associated action is performed.
//

import SwiftUI
import TipKit

// MARK: - Tip Definitions

/// Tip shown on the Chat tab for first-time users who haven't asked a question yet.
struct FirstQueryTip: Tip {
    static let queryPerformed = Event(id: "queryPerformed")

    var title: Text {
        Text("Ask Your Documents")
    }

    var message: Text? {
        Text("Type a question to search your documents with AI.")
    }

    var image: Image? {
        Image(systemName: "bubble.left.and.text.bubble.right")
    }

    var rules: [Rule] {
        [
            #Rule(Self.queryPerformed) { event in
                event.donations.count == 0
            }
        ]
    }
}

/// Tip shown on the Documents tab to encourage first document ingestion.
struct IngestDocumentTip: Tip {
    static let documentIngested = Event(id: "documentIngested")

    var title: Text {
        Text("Add Your First Document")
    }

    var message: Text? {
        Text("Import PDFs, text, or Office docs to build your knowledge base.")
    }

    var image: Image? {
        Image(systemName: "doc.badge.plus")
    }

    var rules: [Rule] {
        [
            #Rule(Self.documentIngested) { event in
                event.donations.count == 0
            }
        ]
    }
}

/// Tip shown when a user first views a container/library.
struct ContainerTip: Tip {
    static let containerCreated = Event(id: "containerCreated")

    var title: Text {
        Text("Organize with Libraries")
    }

    var message: Text? {
        Text("Create libraries to organize documents by topic.")
    }

    var image: Image? {
        Image(systemName: "folder.badge.gearshape")
    }

    var rules: [Rule] {
        [
            #Rule(Self.containerCreated) { event in
                event.donations.count == 0
            }
        ]
    }
}

/// Tip shown in Settings to highlight model configuration.
struct ModelConfigTip: Tip {
    static let settingsVisited = Event(id: "settingsVisited")

    var title: Text {
        Text("Configure Your AI")
    }

    var message: Text? {
        Text("Tune retrieval depth, temperature, and context window.")
    }

    var image: Image? {
        Image(systemName: "slider.horizontal.3")
    }

    var rules: [Rule] {
        [
            #Rule(Self.settingsVisited) { event in
                event.donations.count == 0
            }
        ]
    }
}

/// Tip for the Atlas visualization feature.
struct AtlasTip: Tip {
    static let atlasViewed = Event(id: "atlasViewed")

    var title: Text {
        Text("Explore Your Knowledge")
    }

    var message: Text? {
        Text("Explore document clusters and embeddings interactively.")
    }

    var image: Image? {
        Image(systemName: "globe.americas")
    }

    var rules: [Rule] {
        [
            #Rule(Self.atlasViewed) { event in
                event.donations.count == 0
            }
        ]
    }
}

// MARK: - Compact Tip Style

/// A compact inline tip style that prevents text clipping and uses smaller fonts.
struct CompactTipViewStyle: TipViewStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .top, spacing: 10) {
            configuration.image?
                .font(.system(size: 20))
                .foregroundStyle(.tint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 3) {
                configuration.title
                    .font(.subheadline.weight(.semibold))

                configuration.message?
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Inline Tip Wrapper

/// A reusable view that renders a tip inline at the top of content,
/// properly sized so text is never clipped.
struct InlineTipView<T: Tip>: View {
    let tip: T

    var body: some View {
        TipView(tip)
            .tipViewStyle(CompactTipViewStyle())
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: 420)
            .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }
}

// MARK: - TipKit Configuration

/// Call once at app launch to configure TipKit.
enum AppTipConfiguration {
    static func configure() {
        try? Tips.configure([
            // Show tips immediately for new users; after reset, show tips again
            .displayFrequency(.immediate)
        ])
    }
}
