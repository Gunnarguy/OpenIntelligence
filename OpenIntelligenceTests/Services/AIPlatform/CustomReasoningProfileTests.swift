//
//  CustomReasoningProfileTests.swift
//  OpenIntelligenceTests
//
//  `AppleFoundationModelRoute.reasoningLevel` silently substitutes one value for another based on
//  a setting, which is the shape of change that is easy to get subtly wrong and impossible to see
//  from the outside. These pin what it substitutes and, more importantly, what it does not.
//

import XCTest

@testable import OpenIntelligence

#if canImport(FoundationModels)
    import FoundationModels

    @available(iOS 27.0, macOS 27.0, *)
    final class CustomReasoningProfileTests: XCTestCase {

        private let key = "customReasoningProfile"
        private var saved: Any?

        override func setUp() {
            super.setUp()
            saved = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }

        override func tearDown() {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
            super.tearDown()
        }

        // MARK: - With nothing written, nothing changes

        func testWithNoProfileTheNamedLevelsAreUnchanged() {
            // The property every existing install depends on: an absent key must leave Apple's
            // three named levels exactly as they were.
            XCTAssertEqual(AppleFoundationModelRoute.privateCloudCompute(reasoning: .light).reasoningLevel, .light)
            XCTAssertEqual(
                AppleFoundationModelRoute.privateCloudCompute(reasoning: .moderate).reasoningLevel, .moderate)
            XCTAssertEqual(AppleFoundationModelRoute.privateCloudCompute(reasoning: .deep).reasoningLevel, .deep)
        }

        func testWhitespaceOnlyIsNotAProfile() {
            // Someone opens the field, types a space, closes it. That is not a reasoning profile
            // and must not be sent to Apple as one.
            UserDefaults.standard.set("   \n  ", forKey: key)
            XCTAssertEqual(AppleFoundationModelRoute.privateCloudCompute(reasoning: .deep).reasoningLevel, .deep)
        }

        // MARK: - With a profile written, it replaces the level

        func testAWrittenProfileReplacesTheNamedLevel() {
            UserDefaults.standard.set("work backwards from the conclusion", forKey: key)
            XCTAssertEqual(
                AppleFoundationModelRoute.privateCloudCompute(reasoning: .deep).reasoningLevel,
                .custom("work backwards from the conclusion")
            )
        }

        func testTheProfileIsTrimmedBeforeBeingSent() {
            UserDefaults.standard.set("  check every number  \n", forKey: key)
            XCTAssertEqual(
                AppleFoundationModelRoute.privateCloudCompute(reasoning: .moderate).reasoningLevel,
                .custom("check every number")
            )
        }

        // MARK: - What it must NOT do

        func testAProfileDoesNotStartReasoningWhereThereWasNone() {
            // `.none` means this query type does not warrant reasoning spend at all. A custom
            // profile describes *how* to reason, not an instruction to begin, so it must not turn
            // a cheap lookup into a reasoning request and bill PCC quota for it.
            UserDefaults.standard.set("think very hard about everything", forKey: key)
            XCTAssertNil(AppleFoundationModelRoute.privateCloudCompute(reasoning: .none).reasoningLevel)
        }

        func testAProfileDoesNotLeakOntoTheOnDeviceRoute() {
            // Apple lists reasoning as unsupported on-device and `GenerationOptions` has no
            // equivalent knob, so an on-device route has no reasoning level to replace. If this
            // ever returns non-nil, the settings copy promising it changes nothing on-device
            // becomes a false claim.
            UserDefaults.standard.set("think very hard about everything", forKey: key)
            XCTAssertNil(AppleFoundationModelRoute.onDevice.reasoningLevel)
        }
    }
#endif
