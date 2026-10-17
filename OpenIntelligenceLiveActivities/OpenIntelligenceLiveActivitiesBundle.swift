import SwiftUI
import WidgetKit

@main
struct OpenIntelligenceLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOSApplicationExtension 17.0, *) {
            IngestionLiveActivityWidget()
            QueryLiveActivityWidget()
            QuickActionsWidget()
            // Reads what the app writes to the app group (`WidgetSnapshot`), which the App IDs carry from 5.7.
            LibraryWidget()
        }
        if #available(iOSApplicationExtension 18.0, *) {
            AskControl()
            AddDocumentControl()
            ScanDocumentControl()
        }
    }
}
