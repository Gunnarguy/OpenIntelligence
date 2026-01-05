//
//  ProcessingModels.swift
//  OpenIntelligence
//
//  Shared enums and small UI helpers for ChatV2 processing state
//  Created by Cline on 10/28/25.
//

import SwiftUI

enum ChatExecutionLocation {
    case unknown
    case onDevice
    case privateCloudCompute
    case mlxLocal

    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .onDevice: return "iphone"
        case .privateCloudCompute: return "cloud.fill"
        case .mlxLocal: return "desktopcomputer"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return .gray
        case .onDevice: return .green
        case .privateCloudCompute: return .blue
        case .mlxLocal: return .indigo
        }
    }

    var displayName: String {
        switch self {
        case .unknown: return "Detecting..."
        case .onDevice: return "On-Device"
        case .privateCloudCompute: return "Private Cloud Compute"
        case .mlxLocal: return "MLX Local"
        }
    }
}

enum ChatProcessingStage: CaseIterable {
    case idle
    case embedding
    case searching
    case generating
    case complete

    var description: String {
        switch self {
        case .idle: return ""
        case .embedding: return "Embedding"
        case .searching: return "Searching"
        case .generating: return "Generating"
        case .complete: return "Complete"
        }
    }

    var icon: String {
        switch self {
        case .idle: return ""
        case .embedding: return "brain.head.profile"
        case .searching: return "magnifyingglass"
        case .generating: return "sparkles"
        case .complete: return "checkmark.circle.fill"
        }
    }
}
