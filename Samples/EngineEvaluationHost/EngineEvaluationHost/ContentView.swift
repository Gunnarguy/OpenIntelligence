import OpenIntelligenceEngine
import SwiftUI

struct ContentView: View {
    private let availability = OIEngine.availability()
    private let configuration = OIEngineConfiguration()

    var body: some View {
        NavigationStack {
            List {
                Section("Framework") {
                    LabeledContent("Module", value: "OpenIntelligenceEngine")
                    LabeledContent("Availability", value: availabilityLabel)
                    LabeledContent("Execution Context", value: configuration.executionContext.rawValue)
                    LabeledContent(
                        "Private Cloud Compute",
                        value: configuration.allowPrivateCloudCompute ? "Allowed" : "Disabled"
                    )
                }

                Section("Purpose") {
                    Text("This host app proves XCFramework import and a minimal public API touchpoint for founder evaluation.")
                }
            }
            .navigationTitle("Engine Eval Host")
        }
    }

    private var availabilityLabel: String {
        switch availability {
        case .available:
            return "available"
        case .simulatorUnsupported:
            return "simulatorUnsupported"
        case .unsupportedDevice:
            return "unsupportedDevice"
        case .appleIntelligenceDisabled:
            return "appleIntelligenceDisabled"
        case .modelPreparing:
            return "modelPreparing"
        case let .unavailable(message):
            return message
        }
    }
}
