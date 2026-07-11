import XCTest
@testable import OpenIntelligenceEngine

final class LLMModelTypeTests: XCTestCase {

    func testIsDeprecatedRawValue() {
        XCTAssertTrue(LLMModelType.isDeprecatedRawValue("gguf_local"))
        XCTAssertTrue(LLMModelType.isDeprecatedRawValue("coreml_local"))
        XCTAssertTrue(LLMModelType.isDeprecatedRawValue("mlx_local"))
        XCTAssertTrue(LLMModelType.isDeprecatedRawValue("chatgpt_extension"))
        XCTAssertTrue(LLMModelType.isDeprecatedRawValue("openai"))

        XCTAssertFalse(LLMModelType.isDeprecatedRawValue("apple_intelligence"))
        XCTAssertFalse(LLMModelType.isDeprecatedRawValue("on_device_analysis"))
        XCTAssertFalse(LLMModelType.isDeprecatedRawValue("something_else"))
    }

    func testMigrateFromDeprecated() {
        XCTAssertEqual(LLMModelType.migrate(from: "gguf_local"), .appleIntelligence)
        XCTAssertEqual(LLMModelType.migrate(from: "coreml_local"), .appleIntelligence)
        XCTAssertEqual(LLMModelType.migrate(from: "mlx_local"), .appleIntelligence)
        XCTAssertEqual(LLMModelType.migrate(from: "chatgpt_extension"), .appleIntelligence)
        XCTAssertEqual(LLMModelType.migrate(from: "openai"), .appleIntelligence)
    }

    func testMigrateFromValid() {
        XCTAssertEqual(LLMModelType.migrate(from: "apple_intelligence"), .appleIntelligence)
        XCTAssertEqual(LLMModelType.migrate(from: "on_device_analysis"), .onDeviceAnalysis)
    }

    func testMigrateFromUnknown() {
        // Fallback should be .appleIntelligence for unknown string
        XCTAssertEqual(LLMModelType.migrate(from: "unknown_model_type"), .appleIntelligence)
    }
}
