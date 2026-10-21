//
//  PlanlessRouteTests.swift
//  OpenIntelligenceTests
//
//  A request with no `ModelExecutionPlan` never reaches the consent sheet
//  (`RAGService.ensureCloudConsentIfNeeded` returns at once without a plan), so it must never
//  reach Private Cloud Compute either. Before 5.7 the planless branch of
//  `FoundationModelRoutePolicy.determineRoute` sent one there under Hybrid when the prompt was
//  over the device window, and every time with Private Cloud Compute picked in the model picker.
//

import XCTest

@testable import OpenIntelligence

#if canImport(FoundationModels)
    import FoundationModels

    @available(iOS 26.0, macOS 26.0, *)
    final class PlanlessRouteTests: XCTestCase {

        private let queryTypes: [FoundationModelRoutePolicy.QueryType] = [
            .exactLookup, .standard, .deepThink, .maximum,
        ]

        private func assertOnDevice(
            _ config: InferenceConfig,
            estimatedTokens: Int,
            file: StaticString = #filePath,
            line: UInt = #line
        ) {
            for queryType in queryTypes {
                let route = FoundationModelRoutePolicy.determineRoute(
                    queryType: queryType,
                    estimatedContextTokens: estimatedTokens,
                    config: config
                )
                guard case .onDevice = route else {
                    XCTFail("\(queryType) with no plan routed to \(route)", file: file, line: line)
                    continue
                }
            }
        }

        func testPrivateCloudComputePickedInTheModelPickerStaysOnDeviceWithoutAPlan() {
            var config = InferenceConfig()
            config.fmPreference = .privateCloudCompute
            config.allowPrivateCloudCompute = true
            assertOnDevice(config, estimatedTokens: 100)
        }

        func testPrivateCloudComputePickedWithDontAllowStaysOnDeviceWithoutAPlan() {
            var config = InferenceConfig()
            config.fmPreference = .privateCloudCompute
            config.allowPrivateCloudCompute = false
            assertOnDevice(config, estimatedTokens: 100)
        }

        // Before 5.7 this case also needed Private Cloud Compute to be available, which it never is in the
        // Simulator, so here it pins the new rule without telling the old code apart. The two picker tests do.
        func testHybridPromptOverTheDeviceWindowStaysOnDeviceWithoutAPlan() {
            var config = InferenceConfig()
            config.fmPreference = .automatic
            config.allowPrivateCloudCompute = true
            assertOnDevice(config, estimatedTokens: 1_000_000)
        }
    }
#endif
