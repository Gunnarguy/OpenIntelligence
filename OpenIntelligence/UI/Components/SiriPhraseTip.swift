//
//  SiriPhraseTip.swift
//  OpenIntelligence
//

import AppIntents
import SwiftUI

/// Apple's tip for the app's Siri phrase for asking a question, shown on the empty Chat screen until
/// the person closes it.
///
/// `SiriTipView` reads the phrase Siri has registered for the action, in the person's language, so
/// the words on screen cannot drift from `RAGAppShortcutsProvider`. Through 5.6 the phrases were
/// listed in Settings only. iPhone and iPad: `SiriTipView` does not exist on the Mac. There is no
/// tip on the empty Documents screen: the phrase for adding a file is "Add this document to
/// OpenIntelligence", which needs a document on screen to mean anything.
struct SiriPhraseTip: View {
    @AppStorage("siriPhraseTipVisible.ask") private var isVisible = true

    var body: some View {
        #if os(iOS)
            if isVisible {
                SiriTipView(intent: QueryDocumentsIntent(), isVisible: $isVisible)
            }
        #else
            EmptyView()
        #endif
    }
}
