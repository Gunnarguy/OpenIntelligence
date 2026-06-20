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
    func testCreateLibrary_success() throws {
        let libraryName = "TestLibrary123"

        let library = try engine.createLibrary(name: libraryName)

        XCTAssertEqual(library.name, libraryName)
        XCTAssertNotNil(library.id)

        let libraries = engine.listLibraries()
        XCTAssertTrue(libraries.contains(where: { $0.id == library.id }))
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

    @MainActor
    func testCreateLibrary_duplicateNameReturnsExisting() throws {
        let libraryName = "DuplicateTest"

        let library1 = try engine.createLibrary(name: libraryName)
        let library2 = try engine.createLibrary(name: libraryName)

        XCTAssertEqual(library1.id, library2.id)

        let libraries = engine.listLibraries()
        let matchingLibraries = libraries.filter { $0.name == libraryName }
        XCTAssertEqual(matchingLibraries.count, 1, "There should be only one library with this name")
    }
}
