//
//  LocalComputePreference.swift
//  OpenIntelligence
//
//  Defines the user-facing toggle for how local inference workloads
//  (GGUF/Core ML) should utilize available compute units.
//

import Foundation

enum LocalComputePreference: String, CaseIterable, Identifiable {
    case automatic
    case gpuPreferred
    case cpuOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .gpuPreferred: return "GPU Preferred"
        case .cpuOnly: return "CPU Only"
        }
    }

    var detail: String {
        switch self {
        case .automatic:
            return "Let the runtime choose the best balance of GPU and CPU."
        case .gpuPreferred:
            return "Favor Metal acceleration for the highest throughput."
        case .cpuOnly:
            return "Disable GPU usage and keep execution on performance cores."
        }
    }

    var badgeText: String {
        switch self {
        case .automatic: return "Auto"
        case .gpuPreferred: return "GPU"
        case .cpuOnly: return "CPU"
        }
    }

    var iconName: String {
        switch self {
        case .automatic: return "sparkles"
        case .gpuPreferred: return "gpu"
        case .cpuOnly: return "cpu"
        }
    }

    static func load(from defaults: UserDefaults, key: String, fallback: LocalComputePreference = .automatic) -> LocalComputePreference {
        guard let raw = defaults.string(forKey: key), let value = LocalComputePreference(rawValue: raw) else {
            return fallback
        }
        return value
    }

    func persist(in defaults: UserDefaults, key: String) {
        defaults.set(rawValue, forKey: key)
    }
}
