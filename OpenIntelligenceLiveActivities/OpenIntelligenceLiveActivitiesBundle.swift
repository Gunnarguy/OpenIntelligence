import SwiftUI
import WidgetKit

@main
struct OpenIntelligenceLiveActivitiesBundle: WidgetBundle {
    var body: some Widget {
        if #available(iOSApplicationExtension 17.0, *) {
            IngestionLiveActivityWidget()
            QueryLiveActivityWidget()
        }
        if #available(iOSApplicationExtension 18.0, *) {
            AskControl()
            AddDocumentControl()
            ScanDocumentControl()
        }
    }
}
