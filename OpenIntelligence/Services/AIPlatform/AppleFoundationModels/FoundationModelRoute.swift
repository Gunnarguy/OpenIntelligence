//
//  FoundationModelRoute.swift
//  OpenIntelligence
//

import Foundation

#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26.0, macOS 16.0, *)
public enum PCCReasoningLevel: String, Sendable, Equatable {
    case none
    case light
    case moderate
    case deep
}

@available(iOS 26.0, macOS 16.0, *)
public enum AppleFoundationModelRoute: Sendable, Equatable {
    case onDevice
    case privateCloudCompute(reasoning: PCCReasoningLevel)
    case automatic
}

#endif
