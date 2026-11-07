//
//  NetworkMonitor.swift
//  OpenIntelligence
//
//  Lightweight connectivity monitor for PCC routing decisions.
//

import Combine
import Foundation
import Network

final class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()

    @Published private(set) var isConnected: Bool = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "OpenIntelligence.NetworkMonitor")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let connected = path.status == .satisfied
            DispatchQueue.main.async {
                #if DEBUG
                    if self?.heldForTesting != nil { return }
                #endif
                self?.isConnected = connected
            }
        }
        monitor.start(queue: queue)
    }

    #if DEBUG
        /// Debug builds only: holds `isConnected` at `value`, ignoring the system's path updates, until called with
        /// nil. `StandardPipelineGoldenTests` asks the same questions twice and needs the same route both times; in the
        /// Simulator the path went from connected to not during one run (2026-11-06), and the route planner reads it
        /// (connected allowed the Private Cloud Compute window, which the Simulator reports as 0).
        private var heldForTesting: Bool?

        func holdForTesting(_ value: Bool?) {
            heldForTesting = value
            if let value { isConnected = value }
        }
    #endif
}
