//
//  OIAnswerModeAppEnum.swift
//  OpenIntelligence
//

import AppIntents
import Foundation

/// The three answer modes as a menu in Shortcuts and Siri.
///
/// `RAGQualityMode` also carries four older names (fast, balanced, thorough, agentic) that map onto
/// these three. They stay out of the menu.
@available(iOS 16.0, macOS 13.0, *)
enum OIAnswerMode: String, AppEnum, CaseIterable, Sendable {
    case standard
    case deepThink
    case maximum

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Answer Mode")

    static var caseDisplayRepresentations: [OIAnswerMode: DisplayRepresentation] = [
        .standard: DisplayRepresentation(title: "Standard"),
        .deepThink: DisplayRepresentation(title: "Deep Think"),
        .maximum: DisplayRepresentation(title: "Maximum"),
    ]

    /// The engine's mode for this menu item.
    var qualityMode: RAGQualityMode {
        switch self {
        case .standard: return .standard
        case .deepThink: return .deepThink
        case .maximum: return .maximum
        }
    }

    /// The menu item for an engine mode, older names included.
    init(_ mode: RAGQualityMode) {
        switch mode.canonical {
        case .deepThink: self = .deepThink
        case .maximum: self = .maximum
        default: self = .standard
        }
    }
}
