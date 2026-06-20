import XCTest
@testable import OpenIntelligenceEngine

final class OpenIntelligenceEngineTests: XCTestCase {

    var engine: OIEngine!
    var tempURL: URL!

    @MainActor
    override func setUp() async throws {
        // Set up temporary base directory for AppSupportPaths
        tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempURL, withIntermediateDirectories: true)

        let config = OIEngineConfiguration(storageURL: tempURL)
        self.engine = OIEngine(configuration: config)
    }

    @MainActor
    override func tearDown() async throws {
        if let tempURL = tempURL {
            try? FileManager.default.removeItem(at: tempURL)
        }
        self.engine = nil
    }

    @MainActor
    func testCreateLibrary_emptyNameThrows() throws {
        XCTAssertThrowsError(try engine.createLibrary(name: "   ")) { error in
            if case OpenIntelligenceEngineError.invalidRequest(let message) = error {
                XCTAssertEqual(message, "Library name must not be empty.")
            } else {
                XCTFail("Expected invalidRequest error but got \(error)")
            }
        }
    }

}
