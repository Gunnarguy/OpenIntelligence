import XCTest
@testable import OpenIntelligenceEngine

final class LLMModelTypeTests: XCTestCase {

    func testIsDeprecatedRawValue() {
        // Test deprecated values
        XCTAssertTrue(LLMModelType.isDeprecatedRawValue("gguf_local"))
        XCTAssertTrue(LLMModelType.isDeprecatedRawValue("coreml_local"))
        XCTAssertTrue(LLMModelType.isDeprecatedRawValue("mlx_local"))
        XCTAssertTrue(LLMModelType.isDeprecatedRawValue("chatgpt_extension"))
        XCTAssertTrue(LLMModelType.isDeprecatedRawValue("openai"))

        // Test current values
        XCTAssertFalse(LLMModelType.isDeprecatedRawValue("apple_intelligence"))
        XCTAssertFalse(LLMModelType.isDeprecatedRawValue("on_device_analysis"))

        // Test unknown/junk values
        XCTAssertFalse(LLMModelType.isDeprecatedRawValue("random_string"))
        XCTAssertFalse(LLMModelType.isDeprecatedRawValue(""))
    }

    func testMigrateFromDeprecated() {
        XCTAssertEqual(LLMModelType.migrate(from: "gguf_local"), .appleIntelligence)
        XCTAssertEqual(LLMModelType.migrate(from: "coreml_local"), .appleIntelligence)
        XCTAssertEqual(LLMModelType.migrate(from: "mlx_local"), .appleIntelligence)
        XCTAssertEqual(LLMModelType.migrate(from: "chatgpt_extension"), .appleIntelligence)
        XCTAssertEqual(LLMModelType.migrate(from: "openai"), .appleIntelligence)
    }

    func testMigrateFromCurrent() {
        XCTAssertEqual(LLMModelType.migrate(from: "apple_intelligence"), .appleIntelligence)
        XCTAssertEqual(LLMModelType.migrate(from: "on_device_analysis"), .onDeviceAnalysis)
    }

    func testMigrateFromUnknownFallback() {
        XCTAssertEqual(LLMModelType.migrate(from: "random_string"), .appleIntelligence)
        XCTAssertEqual(LLMModelType.migrate(from: ""), .appleIntelligence)
    }
}
