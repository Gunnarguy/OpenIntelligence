//
//  SiriPhraseTip.swift
//  OpenIntelligence
//

import AppIntents
import SwiftUI

/// Apple's tip for one of the app's Siri phrases, shown until the person closes it: asking a question on
/// the empty Chat screen, and finding passages under the Documents screen's list (5.7).
///
/// `SiriTipView` reads the phrase Siri has registered for the action, in the person's language, so
/// the words on screen cannot drift from `RAGAppShortcutsProvider`. Through 5.6 the phrases were
/// listed in Settings only. iPhone and iPad: `SiriTipView` does not exist on the Mac. The Documents
/// screen's tip is Find Passages and not adding a file: the phrase for adding a file is "Add this
/// document to OpenIntelligence", which needs a document open to mean anything, and a tip with it was
/// taken out on 2026-10-09 for reading wrong there.
struct SiriPhraseTip: View {
    /// Which phrase the tip shows. Each keeps its own closed state.
    enum Action: String {
        case ask
        case findPassages
    }

    private let action: Action
    @AppStorage private var isVisible: Bool

    init(_ action: Action = .ask) {
        self.action = action
        _isVisible = AppStorage(wrappedValue: true, "siriPhraseTipVisible.\(action.rawValue)")
    }

    var body: some View {
        #if os(iOS)
            if isVisible {
                switch action {
                case .ask:
                    SiriTipView(intent: QueryDocumentsIntent(), isVisible: $isVisible)
                case .findPassages:
                    SiriTipView(intent: SearchPassagesIntent(), isVisible: $isVisible)
                }
            }
        #else
            EmptyView()
        #endif
    }
}
